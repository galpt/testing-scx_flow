#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Targeted validation for scx_flow lifecycle hooks and task-creation paths.

set -euo pipefail

SCHEDULER_BIN="${SCHEDULER_BIN:-$(command -v scx_flow || true)}"
MONITOR_INTERVAL="0.2"
MONITOR_SECONDS=6
BURST_ROUNDS=20
BURST_WIDTH=64
STRICT=0

MONITOR_PID=""
MONITOR_FILE=""

usage() {
    cat <<EOF
Usage: sudo ./validate_lifecycle_scx_flow.sh [options]

Options:
  --strict                 Exit non-zero if init_task activity stays at zero
  --monitor-seconds N      Monitor capture window in seconds (default: 6)
  --burst-rounds N         Number of short-lived task bursts (default: 20)
  --burst-width N          Tasks per burst (default: 64)
  --scheduler-bin PATH     Path to scx_flow binary (default: command -v scx_flow)
  -h, --help               Show this help
EOF
}

cleanup() {
    if [ -n "${MONITOR_PID:-}" ]; then
        kill "$MONITOR_PID" 2>/dev/null || true
        wait "$MONITOR_PID" 2>/dev/null || true
    fi
    rm -f "${MONITOR_FILE:-}"
}

trap cleanup EXIT INT TERM

while [ "$#" -gt 0 ]; do
    case "$1" in
        --strict)
            STRICT=1
            shift
            ;;
        --monitor-seconds)
            MONITOR_SECONDS="$2"
            shift 2
            ;;
        --burst-rounds)
            BURST_ROUNDS="$2"
            shift 2
            ;;
        --burst-width)
            BURST_WIDTH="$2"
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

start_monitor_capture() {
    local outfile="$1"

    timeout "${MONITOR_SECONDS}s" "$SCHEDULER_BIN" --monitor "$MONITOR_INTERVAL" \
        > "$outfile" 2>/dev/null &
    MONITOR_PID="$!"
}

run_lifecycle_burst() {
    local round width idx

    for round in $(seq 1 "$BURST_ROUNDS"); do
        for idx in $(seq 1 "$BURST_WIDTH"); do
            bash -c 'exit 0' &
        done
        wait
        for idx in $(seq 1 "$BURST_WIDTH"); do
            sh -c 'true' &
        done
        wait
        sleep 0.05
    done
}

MONITOR_FILE="$(mktemp)"

echo "========================================"
echo "Validating scx_flow lifecycle coverage"
echo "Current time: $(date)"
echo "Scheduler: $CURRENT_SCHED"
echo "Binary: $SCHEDULER_BIN"
echo "========================================"
echo ""

start_monitor_capture "$MONITOR_FILE"
sleep 0.2
run_lifecycle_burst
wait "$MONITOR_PID" 2>/dev/null || true
MONITOR_PID=""

INIT_TASK_MAX="$(max_counter_from_monitor "init_task" "$MONITOR_FILE")"
ENABLE_MAX="$(max_counter_from_monitor "enable" "$MONITOR_FILE")"
EXIT_TASK_MAX="$(max_counter_from_monitor "exit_task" "$MONITOR_FILE")"

echo "Max init_task() activity seen in one monitor window: $INIT_TASK_MAX"
echo "Max enable() activity seen in one monitor window: $ENABLE_MAX"
echo "Max exit_task() activity seen in one monitor window: $EXIT_TASK_MAX"
print_monitor_excerpt "$MONITOR_FILE"
echo ""

echo "========================================"
echo "Validation summary"
echo "========================================"
echo "init_task() max activity: $INIT_TASK_MAX"
echo "enable() max activity: $ENABLE_MAX"
echo "exit_task() max activity: $EXIT_TASK_MAX"

if [ "$INIT_TASK_MAX" -le 0 ]; then
    echo "init_task() did not trigger under task-creation bursts." >&2
    if [ "$STRICT" -eq 1 ]; then
        exit 1
    fi
    echo "This should be investigated before treating lifecycle coverage as complete."
    exit 0
fi

if [ "$ENABLE_MAX" -le 0 ] || [ "$EXIT_TASK_MAX" -le 0 ]; then
    echo "Lifecycle note: init_task() is active, but enable()/exit_task() remained zero."
    echo "That usually means these hooks are optional or not exercised in the current kernel/workload path."
    echo "This is acceptable as long as correctness does not depend on them."
else
    echo "Lifecycle validation looks good."
fi
