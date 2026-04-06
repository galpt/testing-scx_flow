#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Fork/thread throughput + cache-miss benchmark for the active scheduler.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_LOG="${BENCHMARK_LOG:-$SCRIPT_DIR/fork_thread_benchmark_$(date +%Y%m%d_%H%M%S).log}"
SUMMARY_FILE=""
EXPECTED_SCHEDULER="scx_flow"
BENCHMARK_LABEL=""
MSG_GROUPS=24
NR_LOOPS=6000
USE_PIPE=0
USE_THREAD=0

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

usage() {
    cat <<EOF
Usage: sudo ./fork_thread_benchmark.sh [options]

Options:
  --log-file PATH             Write the benchmark log to PATH
  --summary-file PATH         Write machine-readable summary metrics to PATH
  --expected-scheduler NAME   Expected active scheduler, 'none', or 'any'
  --label TEXT                Optional benchmark label written into the log
  --groups N                  perf bench sched messaging groups (default: ${MSG_GROUPS})
  --nr-loops N                perf bench sched messaging loops (default: ${NR_LOOPS})
  --pipe                      Use pipe() instead of socketpair()
  --thread                    Use threads instead of processes
  -h, --help                  Show this help
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --log-file) BENCHMARK_LOG="$2"; shift 2 ;;
        --summary-file) SUMMARY_FILE="$2"; shift 2 ;;
        --expected-scheduler) EXPECTED_SCHEDULER="$2"; shift 2 ;;
        --label) BENCHMARK_LABEL="$2"; shift 2 ;;
        --groups) MSG_GROUPS="$2"; shift 2 ;;
        --nr-loops) NR_LOOPS="$2"; shift 2 ;;
        --pipe) USE_PIPE=1; shift ;;
        --thread) USE_THREAD=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [ "$EUID" -ne 0 ]; then
    log "Please run with sudo: sudo $0"
    exit 1
fi

have_cmd perf || { echo "perf is required for fork_thread_benchmark.sh" >&2; exit 1; }
have_cmd awk || { echo "awk is required for fork_thread_benchmark.sh" >&2; exit 1; }

mkdir -p "$(dirname "$BENCHMARK_LOG")"
echo "=== Fork/Thread Benchmark Log ===" > "$BENCHMARK_LOG"
log "Fork/thread benchmark started at $(date)"
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

header "Benchmark Configuration"
log "Groups: ${MSG_GROUPS}"
log "Loops: ${NR_LOOPS}"
log "Pipe mode: ${USE_PIPE}"
log "Thread mode: ${USE_THREAD}"

BENCH_OUT="$(mktemp)"
PERF_OUT="$(mktemp)"
PERSISTENT_BENCH_OUT="$BENCH_OUT"
PERSISTENT_PERF_OUT="$PERF_OUT"
trap 'rm -f "$BENCH_OUT" "$PERF_OUT"' EXIT INT TERM

CMD=(perf stat -x, -e instructions,cycles,cache-misses,cache-references -- perf bench sched messaging -g "$MSG_GROUPS" -l "$NR_LOOPS")
if [ "$USE_PIPE" -eq 1 ]; then
    CMD+=(-p)
fi
if [ "$USE_THREAD" -eq 1 ]; then
    CMD+=(-t)
fi

header "perf bench sched messaging"
"${CMD[@]}" >"$BENCH_OUT" 2>"$PERF_OUT"
cat "$BENCH_OUT" | tee -a "$BENCHMARK_LOG"
cat "$PERF_OUT" | tee -a "$BENCHMARK_LOG"

FORK_THREAD_TIME_SEC="$(awk '/Total time:/ {print $(NF-1); exit}' "$BENCH_OUT")"
FORK_THREAD_INSTRUCTIONS="$(awk -F, '$3 ~ /^instructions/ {print $1; exit}' "$PERF_OUT")"
FORK_THREAD_CYCLES="$(awk -F, '$3 ~ /^cycles/ {print $1; exit}' "$PERF_OUT")"
FORK_THREAD_CACHE_MISSES="$(awk -F, '$3 ~ /^cache-misses/ {print $1; exit}' "$PERF_OUT")"
FORK_THREAD_CACHE_REFERENCES="$(awk -F, '$3 ~ /^cache-references/ {print $1; exit}' "$PERF_OUT")"
FORK_THREAD_IPC="$(awk -v i="$FORK_THREAD_INSTRUCTIONS" -v c="$FORK_THREAD_CYCLES" 'BEGIN { if (c > 0) printf "%.3f", i / c; else printf "" }')"

header "Fork/Thread Summary"
log "Total time: ${FORK_THREAD_TIME_SEC}s"
log "Instructions: ${FORK_THREAD_INSTRUCTIONS}"
log "Cycles: ${FORK_THREAD_CYCLES}"
log "IPC: ${FORK_THREAD_IPC}"
log "Cache misses: ${FORK_THREAD_CACHE_MISSES}"
log "Cache references: ${FORK_THREAD_CACHE_REFERENCES}"

if [ -n "$SUMMARY_FILE" ]; then
    mkdir -p "$(dirname "$SUMMARY_FILE")"
    PERSISTENT_BENCH_OUT="${SUMMARY_FILE}.perf_bench.out"
    PERSISTENT_PERF_OUT="${SUMMARY_FILE}.perf_stat.csv"
    cp "$BENCH_OUT" "$PERSISTENT_BENCH_OUT"
    cp "$PERF_OUT" "$PERSISTENT_PERF_OUT"
    cat > "$SUMMARY_FILE" <<EOF
BENCHMARK_LABEL=${BENCHMARK_LABEL}
EXPECTED_SCHEDULER=${EXPECTED_SCHEDULER}
KERNEL_RELEASE=$(uname -r)
SCHED_EXT_STATE=${SCHED_EXT_STATE}
CURRENT_SCHEDULER=${CURRENT_SCHED}
FORK_THREAD_GROUPS=${MSG_GROUPS}
FORK_THREAD_NR_LOOPS=${NR_LOOPS}
FORK_THREAD_USE_PIPE=${USE_PIPE}
FORK_THREAD_USE_THREAD=${USE_THREAD}
FORK_THREAD_TIME_SEC=${FORK_THREAD_TIME_SEC}
FORK_THREAD_INSTRUCTIONS=${FORK_THREAD_INSTRUCTIONS}
FORK_THREAD_CYCLES=${FORK_THREAD_CYCLES}
FORK_THREAD_IPC=${FORK_THREAD_IPC}
FORK_THREAD_CACHE_MISSES=${FORK_THREAD_CACHE_MISSES}
FORK_THREAD_CACHE_REFERENCES=${FORK_THREAD_CACHE_REFERENCES}
LOG_PATH=${BENCHMARK_LOG}
PERF_STDOUT_PATH=${PERSISTENT_BENCH_OUT}
PERF_STAT_PATH=${PERSISTENT_PERF_OUT}
EOF
fi

trap - EXIT INT TERM
