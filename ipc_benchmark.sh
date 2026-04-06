#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# IPC round-trip ping-pong benchmark for the active scheduler.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_SCRIPT="$SCRIPT_DIR/ipc_probe.py"
SCHEDULER_BIN="${SCHEDULER_BIN:-$(command -v scx_flow || true)}"
BENCHMARK_LOG="${BENCHMARK_LOG:-$SCRIPT_DIR/ipc_benchmark_$(date +%Y%m%d_%H%M%S).log}"
SUMMARY_FILE=""
EXPECTED_SCHEDULER="scx_flow"
BENCHMARK_LABEL=""
DURATION_SECONDS=20
WORKERS=2
MESSAGE_BYTES=64
LATE_THRESHOLD_US=500
CPU_HOGS=""
CPU_LOAD=85
MONITOR_INTERVAL="0.2"
MONITOR_FILE=""
MONITOR_PID=""

WORKLOAD_PIDS=()

log() {
    echo -e "$1"
    echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g' >> "$BENCHMARK_LOG"
}

header() {
    log ""
    log "=========================================="
    log "$1"
    log "=========================================="
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

start_monitor_capture() {
    if [ -z "$MONITOR_FILE" ] || [ -z "$SCHEDULER_BIN" ] || [ ! -x "$SCHEDULER_BIN" ]; then
        return
    fi
    "$SCHEDULER_BIN" --monitor "$MONITOR_INTERVAL" >"$MONITOR_FILE" 2>/dev/null &
    MONITOR_PID="$!"
}

stop_monitor_capture() {
    if [ -n "$MONITOR_PID" ]; then
        kill "$MONITOR_PID" 2>/dev/null || true
        wait "$MONITOR_PID" 2>/dev/null || true
        MONITOR_PID=""
    fi
}

max_counter_from_monitor() {
    local key="$1"
    local file="$2"

    if [ ! -s "$file" ]; then
        printf '0\n'
        return
    fi

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

cleanup() {
    local pid
    stop_monitor_capture
    for pid in "${WORKLOAD_PIDS[@]:-}"; do
        kill "$pid" >/dev/null 2>&1 || true
        wait "$pid" >/dev/null 2>&1 || true
    done
}

trap cleanup EXIT INT TERM

is_expected_scheduler_match() {
    case "$EXPECTED_SCHEDULER" in
        any) return 0 ;;
        none) [ -z "$1" ] || [ "$1" = "none" ] || [ "$1" = "unknown" ] ;;
        *)
            case "$1" in
                "$EXPECTED_SCHEDULER"|"$EXPECTED_SCHEDULER"_*) return 0 ;;
                "${EXPECTED_SCHEDULER#scx_}"|"${EXPECTED_SCHEDULER#scx_}"_*) return 0 ;;
                *) return 1 ;;
            esac
            ;;
    esac
}

default_worker_count() {
    local cpus
    cpus="$(nproc)"
    if [ "$cpus" -lt 4 ]; then
        printf '1\n'
    else
        printf '2\n'
    fi
}

usage() {
    cat <<EOF
Usage: sudo ./ipc_benchmark.sh [options]

Options:
  --log-file PATH             Write the benchmark log to PATH
  --summary-file PATH         Write machine-readable summary metrics to PATH
  --expected-scheduler NAME   Expected active scheduler, 'none', or 'any'
  --label TEXT                Optional benchmark label written into the log
  --duration-seconds N        Benchmark duration in seconds (default: ${DURATION_SECONDS})
  --workers N                 Number of IPC worker pairs (default: auto, up to 2)
  --message-bytes N           Ping-pong payload size in bytes (default: ${MESSAGE_BYTES})
  --late-threshold-us N       Soft round-trip threshold in microseconds (default: ${LATE_THRESHOLD_US})
  --cpu-hogs N                Number of stress-ng CPU hogs (default: same as workers)
  --cpu-load N                stress-ng CPU load percentage (default: ${CPU_LOAD})
  -h, --help                  Show this help
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --log-file) BENCHMARK_LOG="$2"; shift 2 ;;
        --summary-file) SUMMARY_FILE="$2"; shift 2 ;;
        --expected-scheduler) EXPECTED_SCHEDULER="$2"; shift 2 ;;
        --label) BENCHMARK_LABEL="$2"; shift 2 ;;
        --duration-seconds) DURATION_SECONDS="$2"; shift 2 ;;
        --workers) WORKERS="$2"; shift 2 ;;
        --message-bytes) MESSAGE_BYTES="$2"; shift 2 ;;
        --late-threshold-us) LATE_THRESHOLD_US="$2"; shift 2 ;;
        --cpu-hogs) CPU_HOGS="$2"; shift 2 ;;
        --cpu-load) CPU_LOAD="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [ "$EUID" -ne 0 ]; then
    log "Please run with sudo: sudo $0"
    exit 1
fi

if [ ! -x "$PROBE_SCRIPT" ]; then
    echo "Missing IPC probe helper: $PROBE_SCRIPT" >&2
    exit 1
fi

if ! have_cmd python3; then
    echo "python3 is required for ipc_benchmark.sh" >&2
    exit 1
fi

if [ -z "$WORKERS" ]; then
    WORKERS="$(default_worker_count)"
fi

if [ -z "$CPU_HOGS" ]; then
    CPU_HOGS="$WORKERS"
fi

if [ -n "$SUMMARY_FILE" ]; then
    mkdir -p "$(dirname "$SUMMARY_FILE")"
    if [ "$EXPECTED_SCHEDULER" = "scx_flow" ]; then
        MONITOR_FILE="${SUMMARY_FILE}.monitor.log"
    fi
elif [ "$EXPECTED_SCHEDULER" = "scx_flow" ]; then
    MONITOR_FILE="${BENCHMARK_LOG}.monitor.log"
fi

mkdir -p "$(dirname "$BENCHMARK_LOG")"
echo "=== IPC Benchmark Log ===" > "$BENCHMARK_LOG"
log "IPC benchmark started at $(date)"
if [ -n "$BENCHMARK_LABEL" ]; then
    log "Benchmark label: $BENCHMARK_LABEL"
fi

header "System Information"
log "Kernel: $(uname -r)"
log "CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
log "CPU Cores: $(nproc)"

header "Scheduler Status"
SCHED_EXT_STATE="$(cat /sys/kernel/sched_ext/state 2>/dev/null || echo "unknown")"
CURRENT_SCHED="$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || true)"
[ -n "$CURRENT_SCHED" ] || CURRENT_SCHED="none"
log "sched_ext state: $SCHED_EXT_STATE"
log "Current scheduler: $CURRENT_SCHED"
log "Expected scheduler: $EXPECTED_SCHEDULER"
if ! is_expected_scheduler_match "$CURRENT_SCHED"; then
    log "Warning: expected scheduler '$EXPECTED_SCHEDULER' is not currently active."
fi

header "IPC Probe Configuration"
log "Duration: ${DURATION_SECONDS}s"
log "Worker pairs: ${WORKERS}"
log "Message bytes: ${MESSAGE_BYTES}"
log "Soft RTT threshold: ${LATE_THRESHOLD_US}us"
log "CPU hogs: ${CPU_HOGS}"
log "CPU load: ${CPU_LOAD}%"

if have_cmd stress-ng && [ "$CPU_HOGS" -gt 0 ]; then
    header "Background Load"
    log "Starting ${CPU_HOGS} stress-ng CPU hogs for ${DURATION_SECONDS}s"
    stress-ng --cpu "$CPU_HOGS" --cpu-load "$CPU_LOAD" --timeout "${DURATION_SECONDS}s" --metrics-brief \
        >>"$BENCHMARK_LOG" 2>&1 &
    WORKLOAD_PIDS+=("$!")
else
    header "Background Load"
    if ! have_cmd stress-ng; then
        log "stress-ng not found; running IPC probe without synthetic CPU load."
    else
        log "CPU hog count set to 0; running without synthetic CPU load."
    fi
fi

header "IPC Probe"
PROBE_JSON="${SUMMARY_FILE:-$BENCHMARK_LOG}.ipc_probe.json"
PROBE_ENV_TMP="$(mktemp)"
start_monitor_capture
python3 "$PROBE_SCRIPT" \
    --duration-seconds "$DURATION_SECONDS" \
    --workers "$WORKERS" \
    --message-bytes "$MESSAGE_BYTES" \
    --late-threshold-us "$LATE_THRESHOLD_US" \
    --output-json "$PROBE_JSON" \
    | tee "$PROBE_ENV_TMP" \
    | tee -a "$BENCHMARK_LOG"

stop_monitor_capture
wait >/dev/null 2>&1 || true
cleanup
trap - EXIT INT TERM

# shellcheck disable=SC1090
. "$PROBE_ENV_TMP"
rm -f "$PROBE_ENV_TMP"

header "IPC Summary"
log "Samples: ${IPC_SAMPLES}"
log "Over ${IPC_LATE_THRESHOLD_US}us ratio: ${IPC_OVER_THRESHOLD_RATIO_PCT}%"
log "Mean RTT: ${IPC_MEAN_RTT_US}us"
log "p95 RTT: ${IPC_P95_RTT_US}us"
log "p99 RTT: ${IPC_P99_RTT_US}us"
log "Max RTT: ${IPC_MAX_RTT_US}us"

IPC_MONITOR_WAKE_MAX=0
IPC_MONITOR_LOCAL_MAX=0
IPC_MONITOR_RAISE_MAX=0
IPC_MONITOR_BOOST_MAX=0
IPC_MONITOR_ARM_MAX=0
IPC_MONITOR_CAND_MAX=0
IPC_MONITOR_CONSUME_MAX=0
IPC_MONITOR_PREEMPT_MAX=0
if [ -n "$MONITOR_FILE" ] && [ -f "$MONITOR_FILE" ]; then
    IPC_MONITOR_WAKE_MAX="$(max_counter_from_monitor "ipc_wake" "$MONITOR_FILE")"
    IPC_MONITOR_LOCAL_MAX="$(max_counter_from_monitor "ipc_local" "$MONITOR_FILE")"
    IPC_MONITOR_RAISE_MAX="$(max_counter_from_monitor "ipc_raise" "$MONITOR_FILE")"
    IPC_MONITOR_BOOST_MAX="$(max_counter_from_monitor "ipc_boost" "$MONITOR_FILE")"
    IPC_MONITOR_ARM_MAX="$(max_counter_from_monitor "ipc_arm" "$MONITOR_FILE")"
    IPC_MONITOR_CAND_MAX="$(max_counter_from_monitor "ipc_cand" "$MONITOR_FILE")"
    IPC_MONITOR_CONSUME_MAX="$(max_counter_from_monitor "ipc_consume" "$MONITOR_FILE")"
    IPC_MONITOR_PREEMPT_MAX="$(max_counter_from_monitor "ipc_preempt" "$MONITOR_FILE")"

    if [ "$IPC_MONITOR_WAKE_MAX" = "0" ] && [ "$IPC_MONITOR_CAND_MAX" != "0" ]; then
        IPC_MONITOR_WAKE_MAX="$IPC_MONITOR_CAND_MAX"
    fi
    if [ "$IPC_MONITOR_RAISE_MAX" = "0" ] && [ "$IPC_MONITOR_ARM_MAX" != "0" ]; then
        IPC_MONITOR_RAISE_MAX="$IPC_MONITOR_ARM_MAX"
    fi
    if [ "$IPC_MONITOR_BOOST_MAX" = "0" ] && [ "$IPC_MONITOR_CONSUME_MAX" != "0" ]; then
        IPC_MONITOR_BOOST_MAX="$IPC_MONITOR_CONSUME_MAX"
    fi
fi

if [ -n "$SUMMARY_FILE" ]; then
    mkdir -p "$(dirname "$SUMMARY_FILE")"
    cat > "$SUMMARY_FILE" <<EOF
BENCHMARK_LABEL=${BENCHMARK_LABEL}
EXPECTED_SCHEDULER=${EXPECTED_SCHEDULER}
KERNEL_RELEASE=$(uname -r)
SCHED_EXT_STATE=${SCHED_EXT_STATE}
CURRENT_SCHEDULER=${CURRENT_SCHED}
IPC_DURATION_SECONDS=${IPC_DURATION_SECONDS}
IPC_WORKERS=${IPC_WORKERS}
IPC_CPUS=${IPC_CPUS}
IPC_MESSAGE_BYTES=${IPC_MESSAGE_BYTES}
IPC_SAMPLES=${IPC_SAMPLES}
IPC_MEAN_RTT_US=${IPC_MEAN_RTT_US}
IPC_P95_RTT_US=${IPC_P95_RTT_US}
IPC_P99_RTT_US=${IPC_P99_RTT_US}
IPC_MAX_RTT_US=${IPC_MAX_RTT_US}
IPC_LATE_THRESHOLD_US=${IPC_LATE_THRESHOLD_US}
IPC_OVER_THRESHOLD_COUNT=${IPC_OVER_THRESHOLD_COUNT}
IPC_OVER_THRESHOLD_RATIO_PCT=${IPC_OVER_THRESHOLD_RATIO_PCT}
CPU_HOGS=${CPU_HOGS}
CPU_LOAD=${CPU_LOAD}
LOG_PATH=${BENCHMARK_LOG}
RAW_JSON_PATH=${PROBE_JSON}
MONITOR_PATH=${MONITOR_FILE}
IPC_MONITOR_WAKE_MAX=${IPC_MONITOR_WAKE_MAX}
IPC_MONITOR_LOCAL_MAX=${IPC_MONITOR_LOCAL_MAX}
IPC_MONITOR_RAISE_MAX=${IPC_MONITOR_RAISE_MAX}
IPC_MONITOR_BOOST_MAX=${IPC_MONITOR_BOOST_MAX}
IPC_MONITOR_ARM_MAX=${IPC_MONITOR_ARM_MAX}
IPC_MONITOR_CAND_MAX=${IPC_MONITOR_CAND_MAX}
IPC_MONITOR_CONSUME_MAX=${IPC_MONITOR_CONSUME_MAX}
IPC_MONITOR_PREEMPT_MAX=${IPC_MONITOR_PREEMPT_MAX}
EOF
fi
