#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Sudden load-spike tail latency benchmark for the active scheduler.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_SCRIPT="$SCRIPT_DIR/burst_probe.py"
SCHEDULER_BIN="${SCHEDULER_BIN:-$(command -v scx_flow || true)}"
BENCHMARK_LOG="${BENCHMARK_LOG:-$SCRIPT_DIR/burst_benchmark_$(date +%Y%m%d_%H%M%S).log}"
SUMMARY_FILE=""
EXPECTED_SCHEDULER="scx_flow"
BENCHMARK_LABEL=""
DURATION_SECONDS=20
STRICT_DURATION_SECONDS=30
PERIOD_US=1000
WORKERS=""
LATE_THRESHOLD_US=1000
SETTLE_SECONDS=2
BURST_INTERVAL_MS=1000
BURST_DURATION_MS=200
STRICT_MODE=0
DURATION_SET=0
SETTLE_SET=0
MONITOR_INTERVAL="0.2"
MONITOR_FILE=""
MONITOR_PID=""

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

cleanup() {
    stop_monitor_capture
}

trap cleanup EXIT INT TERM

default_worker_count() {
    local cpus
    cpus="$(nproc)"
    if [ "$cpus" -lt 4 ]; then
        printf '%s\n' "$cpus"
    else
        printf '4\n'
    fi
}

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

usage() {
    cat <<EOF
Usage: sudo ./burst_benchmark.sh [options]

Options:
  --log-file PATH             Write the benchmark log to PATH
  --summary-file PATH         Write machine-readable summary metrics to PATH
  --expected-scheduler NAME   Expected active scheduler, 'none', or 'any'
  --label TEXT                Optional benchmark label written into the log
  --duration-seconds N        Benchmark duration in seconds (default: ${DURATION_SECONDS})
  --strict                    Use the long-run strict preset for very low miss-ratio measurement
                              (currently: ${STRICT_DURATION_SECONDS}s duration, ${SETTLE_SECONDS}s or explicit settle)
  --period-us N               Probe wake period in microseconds (default: ${PERIOD_US})
  --workers N                 Number of probe workers (default: auto, up to 4)
  --late-threshold-us N       Soft lateness threshold in microseconds (default: ${LATE_THRESHOLD_US})
  --settle-seconds N          Initial quiet period before bursts (default: ${SETTLE_SECONDS})
  --burst-interval-ms N       Time between burst starts (default: ${BURST_INTERVAL_MS})
  --burst-duration-ms N       Each burst duration (default: ${BURST_DURATION_MS})
  -h, --help                  Show this help
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --log-file)
            BENCHMARK_LOG="$2"
            shift 2
            ;;
        --summary-file)
            SUMMARY_FILE="$2"
            shift 2
            ;;
        --expected-scheduler)
            EXPECTED_SCHEDULER="$2"
            shift 2
            ;;
        --label)
            BENCHMARK_LABEL="$2"
            shift 2
            ;;
        --duration-seconds)
            DURATION_SECONDS="$2"
            DURATION_SET=1
            shift 2
            ;;
        --strict)
            STRICT_MODE=1
            shift
            ;;
        --period-us)
            PERIOD_US="$2"
            shift 2
            ;;
        --workers)
            WORKERS="$2"
            shift 2
            ;;
        --late-threshold-us)
            LATE_THRESHOLD_US="$2"
            shift 2
            ;;
        --settle-seconds)
            SETTLE_SECONDS="$2"
            SETTLE_SET=1
            shift 2
            ;;
        --burst-interval-ms)
            BURST_INTERVAL_MS="$2"
            shift 2
            ;;
        --burst-duration-ms)
            BURST_DURATION_MS="$2"
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

if [ "$STRICT_MODE" -eq 1 ]; then
    if [ "$DURATION_SET" -eq 0 ]; then
        DURATION_SECONDS="$STRICT_DURATION_SECONDS"
    fi
    if [ "$SETTLE_SET" -eq 0 ]; then
        SETTLE_SECONDS=5
    fi
fi

if [ "$EUID" -ne 0 ]; then
    log "Please run with sudo: sudo $0"
    exit 1
fi

if [ ! -x "$PROBE_SCRIPT" ]; then
    echo "Missing burst probe helper: $PROBE_SCRIPT" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required for burst_benchmark.sh" >&2
    exit 1
fi

if [ -z "$WORKERS" ]; then
    WORKERS="$(default_worker_count)"
fi

if [ -n "$SUMMARY_FILE" ]; then
    mkdir -p "$(dirname "$SUMMARY_FILE")"
    MONITOR_FILE="${SUMMARY_FILE}.monitor.log"
elif [ "$EXPECTED_SCHEDULER" = "scx_flow" ]; then
    MONITOR_FILE="${BENCHMARK_LOG}.monitor.log"
fi

mkdir -p "$(dirname "$BENCHMARK_LOG")"
echo "=== Burst Benchmark Log ===" > "$BENCHMARK_LOG"
log "Burst benchmark started at $(date)"
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

header "Burst Probe Configuration"
log "Duration: ${DURATION_SECONDS}s"
log "Strict mode: $( [ "$STRICT_MODE" -eq 1 ] && printf yes || printf no )"
log "Probe wake period: ${PERIOD_US}us"
log "Workers: ${WORKERS}"
log "Soft lateness threshold: ${LATE_THRESHOLD_US}us"
log "Initial settle: ${SETTLE_SECONDS}s"
log "Burst interval: ${BURST_INTERVAL_MS}ms"
log "Burst duration: ${BURST_DURATION_MS}ms"

if [ -n "$MONITOR_FILE" ] && [ "$EXPECTED_SCHEDULER" = "scx_flow" ]; then
    : > "$MONITOR_FILE"
    header "Scheduler Monitor"
    log "Capturing scx_flow --monitor to: ${MONITOR_FILE}"
    start_monitor_capture
fi

header "Burst Probe"
PROBE_JSON="${SUMMARY_FILE:-$BENCHMARK_LOG}.burst_probe.json"
PROBE_ENV_TMP="$(mktemp)"
python3 "$PROBE_SCRIPT" \
    --duration-seconds "$DURATION_SECONDS" \
    --period-us "$PERIOD_US" \
    --workers "$WORKERS" \
    --late-threshold-us "$LATE_THRESHOLD_US" \
    --settle-seconds "$SETTLE_SECONDS" \
    --burst-interval-ms "$BURST_INTERVAL_MS" \
    --burst-duration-ms "$BURST_DURATION_MS" \
    --output-json "$PROBE_JSON" \
    | tee "$PROBE_ENV_TMP" \
    | tee -a "$BENCHMARK_LOG"

# shellcheck disable=SC1090
. "$PROBE_ENV_TMP"
rm -f "$PROBE_ENV_TMP"

header "Burst Summary"
log "Active burst samples: ${BURST_ACTIVE_SAMPLES}"
log "Burst p95 late: ${BURST_LATENCY_P95_US}us"
log "Burst p99 late: ${BURST_LATENCY_P99_US}us"
log "Burst max late: ${BURST_LATENCY_MAX_US}us"
log "Burst miss ratio: ${BURST_MISS_RATIO_PCT}%"
log "Burst miss ratio resolution: ${BURST_MISS_RATIO_RESOLUTION_PCT}%"
log "Burst late >${BURST_LATE_THRESHOLD_US}us ratio: ${BURST_LATE_OVER_THRESHOLD_RATIO_PCT}%"
log "Idle p99 late: ${IDLE_LATENCY_P99_US}us"

stop_monitor_capture

MONITOR_BURST_WAKE_MAX="$(max_counter_from_monitor "burst_wake" "$MONITOR_FILE")"
MONITOR_BURST_PREEMPT_MAX="$(max_counter_from_monitor "burst_preempt" "$MONITOR_FILE")"
MONITOR_BURST_RAISE_MAX="$(max_counter_from_monitor "burst_raise" "$MONITOR_FILE")"
MONITOR_DIRECT_LOCAL_MAX="$(max_counter_from_monitor "direct_local" "$MONITOR_FILE")"
MONITOR_DIRECT_CAND_MAX="$(max_counter_from_monitor "direct_cand" "$MONITOR_FILE")"

if [ -n "$MONITOR_FILE" ] && [ -s "$MONITOR_FILE" ]; then
    header "Monitor Summary"
    log "burst_wake max: ${MONITOR_BURST_WAKE_MAX}"
    log "burst_preempt max: ${MONITOR_BURST_PREEMPT_MAX}"
    log "burst_raise max: ${MONITOR_BURST_RAISE_MAX}"
    log "direct_local max: ${MONITOR_DIRECT_LOCAL_MAX}"
    log "direct_cand max: ${MONITOR_DIRECT_CAND_MAX}"
fi

if [ -n "$SUMMARY_FILE" ]; then
    mkdir -p "$(dirname "$SUMMARY_FILE")"
    cat > "$SUMMARY_FILE" <<EOF
BENCHMARK_LABEL=${BENCHMARK_LABEL}
EXPECTED_SCHEDULER=${EXPECTED_SCHEDULER}
KERNEL_RELEASE=$(uname -r)
SCHED_EXT_STATE=${SCHED_EXT_STATE}
CURRENT_SCHEDULER=${CURRENT_SCHED}
BURST_DURATION_SECONDS=${BURST_DURATION_SECONDS}
BURST_PERIOD_US=${BURST_PERIOD_US}
BURST_WORKERS=${BURST_WORKERS}
BURST_CPUS=${BURST_CPUS}
BURST_BURNER_CPUS=${BURST_BURNER_CPUS}
BURST_SETTLE_SECONDS=${BURST_SETTLE_SECONDS}
BURST_INTERVAL_MS=${BURST_INTERVAL_MS}
BURST_WINDOW_MS=${BURST_WINDOW_MS}
BURST_WINDOW_COUNT=${BURST_WINDOW_COUNT}
BURST_LATE_THRESHOLD_US=${BURST_LATE_THRESHOLD_US}
BURST_TOTAL_SAMPLES=${BURST_TOTAL_SAMPLES}
BURST_ACTIVE_SAMPLES=${BURST_ACTIVE_SAMPLES}
BURST_IDLE_SAMPLES=${BURST_IDLE_SAMPLES}
OVERALL_LATENCY_P95_US=${OVERALL_LATENCY_P95_US}
OVERALL_LATENCY_P99_US=${OVERALL_LATENCY_P99_US}
OVERALL_LATENCY_MAX_US=${OVERALL_LATENCY_MAX_US}
BURST_LATENCY_P95_US=${BURST_LATENCY_P95_US}
BURST_LATENCY_P99_US=${BURST_LATENCY_P99_US}
BURST_LATENCY_MAX_US=${BURST_LATENCY_MAX_US}
BURST_MEAN_LATE_US=${BURST_MEAN_LATE_US}
BURST_MISS_COUNT=${BURST_MISS_COUNT}
BURST_MISS_RATIO_PCT=${BURST_MISS_RATIO_PCT}
BURST_MISS_RATIO_RESOLUTION_PCT=${BURST_MISS_RATIO_RESOLUTION_PCT}
BURST_LATE_OVER_THRESHOLD_COUNT=${BURST_LATE_OVER_THRESHOLD_COUNT}
BURST_LATE_OVER_THRESHOLD_RATIO_PCT=${BURST_LATE_OVER_THRESHOLD_RATIO_PCT}
IDLE_LATENCY_P95_US=${IDLE_LATENCY_P95_US}
IDLE_LATENCY_P99_US=${IDLE_LATENCY_P99_US}
IDLE_LATENCY_MAX_US=${IDLE_LATENCY_MAX_US}
MONITOR_PATH=${MONITOR_FILE}
BURST_MONITOR_WAKE_MAX=${MONITOR_BURST_WAKE_MAX}
BURST_MONITOR_PREEMPT_MAX=${MONITOR_BURST_PREEMPT_MAX}
BURST_MONITOR_RAISE_MAX=${MONITOR_BURST_RAISE_MAX}
BURST_MONITOR_DIRECT_LOCAL_MAX=${MONITOR_DIRECT_LOCAL_MAX}
BURST_MONITOR_DIRECT_CAND_MAX=${MONITOR_DIRECT_CAND_MAX}
LOG_PATH=${BENCHMARK_LOG}
RAW_JSON_PATH=${PROBE_JSON}
EOF
fi

log ""
log "Benchmark complete."
log "Results saved to: ${BENCHMARK_LOG}"
if [ -n "$SUMMARY_FILE" ]; then
    log "Summary saved to: ${SUMMARY_FILE}"
fi
