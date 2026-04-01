#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Targeted validation for scx_flow v2 hog-containment behavior. This script
# keeps the same worker tasks alive across an abusive phase and a recovery
# phase so we can see whether containment and recovery counters actually move.

set -euo pipefail

SCHEDULER_BIN="${SCHEDULER_BIN:-$(command -v scx_flow || true)}"
MONITOR_INTERVAL="0.2"
WORKERS=8
CONTAIN_SECONDS=6
RECOVER_SECONDS=6
CONTAIN_SLEEP_SEC="0.003"
CONTAIN_BUSY_SEC="0.020"
RECOVER_SLEEP_SEC="0.020"
RECOVER_BUSY_SEC="0.001"
STRICT=0

MONITOR_PID=""
MONITOR_FILE=""
WORKLOAD_PIDS=()

usage() {
    cat <<EOF
Usage: sudo ./validate_containment_scx_flow.sh [options]

Options:
  --strict                 Exit non-zero if containment stays at zero
  --workers N              Number of long-lived burst workers (default: 8)
  --contain-seconds N      Duration of the abusive phase (default: 6)
  --recover-seconds N      Duration of the recovery phase (default: 6)
  --scheduler-bin PATH     Path to scx_flow binary (default: command -v scx_flow)
  -h, --help               Show this help
EOF
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
    rm -f "${MONITOR_FILE:-}"
}

trap cleanup EXIT INT TERM

while [ "$#" -gt 0 ]; do
    case "$1" in
        --strict)
            STRICT=1
            shift
            ;;
        --workers)
            WORKERS="$2"
            shift 2
            ;;
        --contain-seconds)
            CONTAIN_SECONDS="$2"
            shift 2
            ;;
        --recover-seconds)
            RECOVER_SECONDS="$2"
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

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required for validate_containment_scx_flow.sh." >&2
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
        tail -n 8 "$file"
    else
        echo "(no monitor output captured)"
    fi
}

start_monitor_capture() {
    local outfile="$1"
    local total_seconds

    total_seconds=$((CONTAIN_SECONDS + RECOVER_SECONDS + 3))
    timeout "${total_seconds}s" "$SCHEDULER_BIN" --monitor "$MONITOR_INTERVAL" \
        > "$outfile" 2>/dev/null &
    MONITOR_PID="$!"
}

start_burst_workers() {
    local idx

    for idx in $(seq 1 "$WORKERS"); do
        python3 - <<PY &
import time

contain_deadline = time.perf_counter() + float(${CONTAIN_SECONDS})
recover_deadline = contain_deadline + float(${RECOVER_SECONDS})
contain_sleep = float(${CONTAIN_SLEEP_SEC})
contain_busy = float(${CONTAIN_BUSY_SEC})
recover_sleep = float(${RECOVER_SLEEP_SEC})
recover_busy = float(${RECOVER_BUSY_SEC})

def busy_spin(seconds: float) -> None:
    end = time.perf_counter() + seconds
    while time.perf_counter() < end:
        pass

while True:
    now = time.perf_counter()
    if now >= recover_deadline:
        break
    if now < contain_deadline:
        time.sleep(contain_sleep)
        busy_spin(contain_busy)
    else:
        time.sleep(recover_sleep)
        busy_spin(recover_busy)
PY
        WORKLOAD_PIDS+=("$!")
    done
}

MONITOR_FILE="$(mktemp)"

echo "========================================"
echo "Validating scx_flow hog containment"
echo "Current time: $(date)"
echo "Scheduler: $CURRENT_SCHED"
echo "Binary: $SCHEDULER_BIN"
echo "Workers: $WORKERS"
echo "Contain phase: ${CONTAIN_SECONDS}s (sleep ${CONTAIN_SLEEP_SEC}s / busy ${CONTAIN_BUSY_SEC}s)"
echo "Recover phase: ${RECOVER_SECONDS}s (sleep ${RECOVER_SLEEP_SEC}s / busy ${RECOVER_BUSY_SEC}s)"
echo "========================================"
echo ""

start_monitor_capture "$MONITOR_FILE"
sleep 0.2
start_burst_workers
wait "${WORKLOAD_PIDS[@]}"
WORKLOAD_PIDS=()
wait "$MONITOR_PID" 2>/dev/null || true
MONITOR_PID=""

HOG_CONTAIN_MAX="$(max_counter_from_monitor "hog_contain" "$MONITOR_FILE")"
HOG_RECOVER_MAX="$(max_counter_from_monitor "hog_recover" "$MONITOR_FILE")"
EXHAUST_MAX="$(max_counter_from_monitor "exhaust" "$MONITOR_FILE")"
POS_WAKE_MAX="$(max_counter_from_monitor "pos_wake" "$MONITOR_FILE")"
LATENCY_ENQ_MAX="$(max_counter_from_monitor "latency_enq" "$MONITOR_FILE")"

echo "Max hog_contain seen in one monitor window: $HOG_CONTAIN_MAX"
echo "Max hog_recover seen in one monitor window: $HOG_RECOVER_MAX"
echo "Max budget exhaustions seen in one monitor window: $EXHAUST_MAX"
echo "Max positive-budget wakeups seen in one monitor window: $POS_WAKE_MAX"
echo "Max latency-lane enqueues seen in one monitor window: $LATENCY_ENQ_MAX"
print_monitor_excerpt "$MONITOR_FILE"
echo ""

echo "========================================"
echo "Validation summary"
echo "========================================"
echo "hog_contain max activity: $HOG_CONTAIN_MAX"
echo "hog_recover max activity: $HOG_RECOVER_MAX"
echo "budget exhaustion max activity: $EXHAUST_MAX"
echo "positive-budget wake max activity: $POS_WAKE_MAX"
echo "latency lane max activity: $LATENCY_ENQ_MAX"

if [ "$HOG_CONTAIN_MAX" -le 0 ]; then
    echo "Containment did not trigger under the targeted burst-hog workload." >&2
    if [ "$STRICT" -eq 1 ]; then
        exit 1
    fi
    echo "This means the current v2 containment logic is likely too conservative or the workload still does not match the trigger shape."
    exit 0
fi

if [ "$HOG_RECOVER_MAX" -le 0 ]; then
    echo "Containment triggered, but recovery stayed at zero in this run."
    echo "That can mean the recovery phase was too short or the decay thresholds are still conservative."
    exit 0
fi

echo "Containment validation looks good."
