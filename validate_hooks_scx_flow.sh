#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Targeted validation for scx_flow hook activity that broad benchmarks may not
# naturally exercise enough.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEDULER_BIN="${SCHEDULER_BIN:-$(command -v scx_flow || true)}"
MONITOR_INTERVAL="0.2"
WAKE_WORKERS=8
WAKE_ITERATIONS=500
WAKE_SLEEP_SEC="0.002"
RT_CPU=0
RT_PRESSURE_SECONDS=2
MONITOR_SECONDS=6
STRICT=0

WORKLOAD_PIDS=()
MONITOR_PID=""
WAKE_MONITOR_FILE=""
CPU_RELEASE_MONITOR_FILE=""

usage() {
    cat <<EOF
Usage: sudo ./validate_hooks_scx_flow.sh [options]

Options:
  --strict                 Exit non-zero if cpu_release activity stays at zero
  --rt-cpu N               CPU to target for cpu_release pressure test (default: 0)
  --monitor-seconds N      Monitor capture window in seconds (default: 6)
  --scheduler-bin PATH     Path to scx_flow binary (default: command -v scx_flow)
  -h, --help               Show this help
EOF
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

cleanup() {
    local pid

    for pid in "${WORKLOAD_PIDS[@]:-}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait "${WORKLOAD_PIDS[@]:-}" 2>/dev/null || true
    if [ -n "${MONITOR_PID:-}" ]; then
        kill "$MONITOR_PID" 2>/dev/null || true
        wait "$MONITOR_PID" 2>/dev/null || true
    fi
    rm -f "${WAKE_MONITOR_FILE:-}" "${CPU_RELEASE_MONITOR_FILE:-}"
}

trap cleanup EXIT INT TERM

while [ "$#" -gt 0 ]; do
    case "$1" in
        --strict)
            STRICT=1
            shift
            ;;
        --rt-cpu)
            RT_CPU="$2"
            shift 2
            ;;
        --monitor-seconds)
            MONITOR_SECONDS="$2"
            shift 2
            ;;
        --scheduler-bin)
            SCHEDULER_BIN="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo $0" >&2
    exit 1
fi

if [ -z "$SCHEDULER_BIN" ] || [ ! -x "$SCHEDULER_BIN" ]; then
    echo "Could not find executable scx_flow binary. Use --scheduler-bin PATH." >&2
    exit 1
fi

CURRENT_SCHED="$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || true)"
case "$CURRENT_SCHED" in
    scx_flow|scx_flow_*) ;;
    *)
        echo "scx_flow is not the active scheduler right now: ${CURRENT_SCHED:-none}" >&2
        echo "Activate scx_flow first, then rerun this validation." >&2
        exit 1
        ;;
esac

start_monitor_capture() {
    local outfile="$1"

    timeout "${MONITOR_SECONDS}s" "$SCHEDULER_BIN" --monitor "$MONITOR_INTERVAL" \
        > "$outfile" 2>/dev/null &
    MONITOR_PID="$!"
}

max_counter_from_monitor() {
    local key="$1"
    local file="$2"

    awk -v key="$key" '
    BEGIN { max = 0 }
    {
        for (i = 1; i <= NF; i++) {
            if ($i ~ ("^" key "=")) {
                split($i, parts, "=")
                value = parts[2] + 0
                if (value > max) {
                    max = value
                }
            }
        }
    }
    END { print max }
    ' "$file"
}

print_monitor_excerpt() {
    local file="$1"

    if [ -s "$file" ]; then
        tail -n 5 "$file"
    else
        echo "(no monitor output captured)"
    fi
}

run_wakeup_test() {
    local monitor_file="$1"
    local i

    start_monitor_capture "$monitor_file"
    sleep 0.2

    for i in $(seq 1 "$WAKE_WORKERS"); do
        bash -c '
            iters="$1"
            delay="$2"
            for ((j = 0; j < iters; j++)); do
                : >/dev/null
                sleep "$delay"
            done
        ' _ "$WAKE_ITERATIONS" "$WAKE_SLEEP_SEC" &
        WORKLOAD_PIDS+=("$!")
    done

    wait "${WORKLOAD_PIDS[@]}"
    WORKLOAD_PIDS=()
    wait "$MONITOR_PID" || true
    MONITOR_PID=""
}

run_cpu_release_test() {
    local monitor_file="$1"
    local i

    if ! have_cmd taskset || ! have_cmd chrt || ! have_cmd timeout; then
        echo "Skipping cpu_release pressure test: need taskset, chrt, and timeout." >&2
        return 2
    fi

    start_monitor_capture "$monitor_file"
    sleep 0.2

    for i in 1 2 3; do
        taskset -c "$RT_CPU" timeout "$((MONITOR_SECONDS - 1))s" \
            bash -c 'while :; do :; done' &
        WORKLOAD_PIDS+=("$!")
    done

    sleep 0.5
    taskset -c "$RT_CPU" chrt -f 10 timeout "${RT_PRESSURE_SECONDS}s" \
        bash -c 'while :; do :; done' || true

    wait "${WORKLOAD_PIDS[@]}" 2>/dev/null || true
    WORKLOAD_PIDS=()
    wait "$MONITOR_PID" || true
    MONITOR_PID=""
}

WAKE_MONITOR_FILE="$(mktemp)"
CPU_RELEASE_MONITOR_FILE="$(mktemp)"

echo "========================================"
echo "Validating scx_flow hook coverage"
echo "Current time: $(date)"
echo "Scheduler: $CURRENT_SCHED"
echo "Binary: $SCHEDULER_BIN"
echo "========================================"
echo ""

echo ">>> Step 1: Wake-heavy runnable() validation..."
run_wakeup_test "$WAKE_MONITOR_FILE"
RUNNABLE_MAX="$(max_counter_from_monitor "runnable" "$WAKE_MONITOR_FILE")"
echo "Max runnable() wakeups seen in one monitor window: $RUNNABLE_MAX"
print_monitor_excerpt "$WAKE_MONITOR_FILE"
echo ""

if [ "$RUNNABLE_MAX" -le 0 ]; then
    echo "runnable() validation did not observe wake activity. That should be investigated." >&2
    exit 1
fi

echo ">>> Step 2: cpu_release() rescue validation..."
CPU_RELEASE_STATUS=0
run_cpu_release_test "$CPU_RELEASE_MONITOR_FILE" || CPU_RELEASE_STATUS=$?
if [ "$CPU_RELEASE_STATUS" -eq 2 ]; then
    CPU_RELEASE_MAX=0
    echo "cpu_release() validation was skipped due to missing system tools."
else
    CPU_RELEASE_MAX="$(max_counter_from_monitor "cpu_release" "$CPU_RELEASE_MONITOR_FILE")"
    echo "Max cpu_release() rescues seen in one monitor window: $CPU_RELEASE_MAX"
    print_monitor_excerpt "$CPU_RELEASE_MONITOR_FILE"
fi
echo ""

echo "========================================"
echo "Validation summary"
echo "========================================"
echo "runnable() max activity: $RUNNABLE_MAX"
echo "cpu_release() max activity: ${CPU_RELEASE_MAX:-skipped}"

if [ "${CPU_RELEASE_MAX:-0}" -le 0 ] && [ "$CPU_RELEASE_STATUS" -ne 2 ]; then
    if [ "$STRICT" -eq 1 ]; then
        echo "cpu_release() did not trigger under targeted pressure." >&2
        exit 1
    fi
    echo "cpu_release() stayed at zero in this run. That can happen depending on CPU pressure timing."
    echo "If you want a stricter check, rerun with --strict or increase the RT pressure duration."
else
    echo "Hook validation looks good."
fi
