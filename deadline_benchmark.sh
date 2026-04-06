#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Periodic frame-target deadline benchmark for the active scheduler.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_SCRIPT="$SCRIPT_DIR/deadline_probe.py"
BENCHMARK_LOG="${BENCHMARK_LOG:-$SCRIPT_DIR/deadline_benchmark_$(date +%Y%m%d_%H%M%S).log}"
SUMMARY_FILE=""
EXPECTED_SCHEDULER="scx_flow"
BENCHMARK_LABEL=""
DURATION_SECONDS=30
PERIOD_US=16666
WORKERS=4
LATE_THRESHOLD_US=1000
CPU_HOGS=""
CPU_LOAD=85

WORKLOAD_PIDS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

cleanup() {
    local pid
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
        printf '%s\n' "$cpus"
    else
        printf '4\n'
    fi
}

usage() {
    cat <<EOF
Usage: sudo ./deadline_benchmark.sh [options]

Options:
  --log-file PATH             Write the benchmark log to PATH
  --summary-file PATH         Write machine-readable summary metrics to PATH
  --expected-scheduler NAME   Expected active scheduler, 'none', or 'any'
  --label TEXT                Optional benchmark label written into the log
  --duration-seconds N        Benchmark duration in seconds (default: ${DURATION_SECONDS})
  --period-us N               Periodic frame target in microseconds (default: ${PERIOD_US})
  --workers N                 Number of probe workers (default: auto, up to 4)
  --late-threshold-us N       Soft lateness threshold in microseconds (default: ${LATE_THRESHOLD_US})
  --cpu-hogs N                Number of stress-ng CPU hogs (default: same as workers)
  --cpu-load N                stress-ng CPU load percentage (default: ${CPU_LOAD})
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
            shift 2
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
        --cpu-hogs)
            CPU_HOGS="$2"
            shift 2
            ;;
        --cpu-load)
            CPU_LOAD="$2"
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
    log "${RED}Please run with sudo: sudo $0${NC}"
    exit 1
fi

if [ ! -x "$PROBE_SCRIPT" ]; then
    echo "Missing deadline probe helper: $PROBE_SCRIPT" >&2
    exit 1
fi

if ! have_cmd python3; then
    echo "python3 is required for deadline_benchmark.sh" >&2
    exit 1
fi

if [ -z "$WORKERS" ]; then
    WORKERS="$(default_worker_count)"
fi

if [ -z "$CPU_HOGS" ]; then
    CPU_HOGS="$WORKERS"
fi

mkdir -p "$(dirname "$BENCHMARK_LOG")"
echo "=== Deadline Benchmark Log ===" > "$BENCHMARK_LOG"
log "Deadline benchmark started at $(date)"
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
    log "${YELLOW}Warning: expected scheduler '$EXPECTED_SCHEDULER' is not currently active.${NC}"
fi

header "Deadline Probe Configuration"
log "Duration: ${DURATION_SECONDS}s"
log "Frame target period: ${PERIOD_US}us"
log "Target FPS: $(awk "BEGIN { printf \"%.2f\", 1000000 / ${PERIOD_US} }")"
log "Workers: ${WORKERS}"
log "Soft lateness threshold: ${LATE_THRESHOLD_US}us"
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
        log "${YELLOW}stress-ng not found; running deadline probe without synthetic CPU load.${NC}"
    else
        log "${YELLOW}CPU hog count set to 0; running without synthetic CPU load.${NC}"
    fi
fi

header "Deadline Probe"
PROBE_JSON="${SUMMARY_FILE:-$BENCHMARK_LOG}.deadline_probe.json"
PROBE_ENV_TMP="$(mktemp)"
python3 "$PROBE_SCRIPT" \
    --duration-seconds "$DURATION_SECONDS" \
    --period-us "$PERIOD_US" \
    --workers "$WORKERS" \
    --late-threshold-us "$LATE_THRESHOLD_US" \
    --output-json "$PROBE_JSON" \
    | tee "$PROBE_ENV_TMP" \
    | tee -a "$BENCHMARK_LOG"

wait >/dev/null 2>&1 || true
cleanup
trap - EXIT INT TERM

# shellcheck disable=SC1090
. "$PROBE_ENV_TMP"
rm -f "$PROBE_ENV_TMP"

header "Deadline Summary"
log "Samples: ${DEADLINE_SAMPLES}"
log "Miss ratio: ${DEADLINE_MISS_RATIO_PCT}%"
log "Late >${DEADLINE_LATE_THRESHOLD_US}us ratio: ${DEADLINE_LATE_OVER_THRESHOLD_RATIO_PCT}%"
log "p95 late: ${DEADLINE_P95_LATE_US}us"
log "p99 late: ${DEADLINE_P99_LATE_US}us"
log "Max late: ${DEADLINE_MAX_LATE_US}us"
log "Jitter samples: ${DEADLINE_JITTER_SAMPLES}"
log "p95 jitter: ${DEADLINE_P95_JITTER_US}us"
log "p99 jitter: ${DEADLINE_P99_JITTER_US}us"
log "Max jitter: ${DEADLINE_MAX_JITTER_US}us"

if [ -n "$SUMMARY_FILE" ]; then
    mkdir -p "$(dirname "$SUMMARY_FILE")"
    cat > "$SUMMARY_FILE" <<EOF
BENCHMARK_LABEL=${BENCHMARK_LABEL}
EXPECTED_SCHEDULER=${EXPECTED_SCHEDULER}
KERNEL_RELEASE=$(uname -r)
SCHED_EXT_STATE=${SCHED_EXT_STATE}
CURRENT_SCHEDULER=${CURRENT_SCHED}
DEADLINE_DURATION_SECONDS=${DEADLINE_DURATION_SECONDS}
DEADLINE_PERIOD_US=${DEADLINE_PERIOD_US}
DEADLINE_TARGET_FPS=${DEADLINE_TARGET_FPS}
DEADLINE_WORKERS=${DEADLINE_WORKERS}
DEADLINE_CPUS=${DEADLINE_CPUS}
DEADLINE_SAMPLES=${DEADLINE_SAMPLES}
DEADLINE_MEAN_LATE_US=${DEADLINE_MEAN_LATE_US}
DEADLINE_P95_LATE_US=${DEADLINE_P95_LATE_US}
DEADLINE_P99_LATE_US=${DEADLINE_P99_LATE_US}
DEADLINE_MAX_LATE_US=${DEADLINE_MAX_LATE_US}
DEADLINE_JITTER_SAMPLES=${DEADLINE_JITTER_SAMPLES}
DEADLINE_MEAN_JITTER_US=${DEADLINE_MEAN_JITTER_US}
DEADLINE_P95_JITTER_US=${DEADLINE_P95_JITTER_US}
DEADLINE_P99_JITTER_US=${DEADLINE_P99_JITTER_US}
DEADLINE_MAX_JITTER_US=${DEADLINE_MAX_JITTER_US}
DEADLINE_MISS_COUNT=${DEADLINE_MISS_COUNT}
DEADLINE_MISS_RATIO_PCT=${DEADLINE_MISS_RATIO_PCT}
DEADLINE_LATE_THRESHOLD_US=${DEADLINE_LATE_THRESHOLD_US}
DEADLINE_LATE_OVER_THRESHOLD_COUNT=${DEADLINE_LATE_OVER_THRESHOLD_COUNT}
DEADLINE_LATE_OVER_THRESHOLD_RATIO_PCT=${DEADLINE_LATE_OVER_THRESHOLD_RATIO_PCT}
CPU_HOGS=${CPU_HOGS}
CPU_LOAD=${CPU_LOAD}
LOG_PATH=${BENCHMARK_LOG}
RAW_JSON_PATH=${PROBE_JSON}
EOF
fi
