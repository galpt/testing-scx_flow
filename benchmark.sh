#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Benchmark script for scx_flow
# Runs latency, throughput, and stress tests to validate scheduler performance

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_LOG="${BENCHMARK_LOG:-$SCRIPT_DIR/benchmark_results_$(date +%Y%m%d_%H%M%S).log}"
SUMMARY_FILE=""
EXPECTED_SCHEDULER="scx_flow"
BENCHMARK_LABEL=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

scheduler_short_name() {
    case "$1" in
        scx_*) printf '%s\n' "${1#scx_}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

capture_scheduler_monitor_line() {
    local scheduler_bin="$1"
    local output=""

    if ! have_cmd "$scheduler_bin"; then
        return 0
    fi

    if ! "$scheduler_bin" --help 2>/dev/null | grep -q -- "--monitor"; then
        return 0
    fi

    if have_cmd timeout; then
        output=$(timeout 2s "$scheduler_bin" --monitor 0.2 2>/dev/null | awk '/^\[scx_/ { print; exit }' || true)
    else
        output=$("$scheduler_bin" --monitor 0.2 2>/dev/null | awk '/^\[scx_/ { print; exit }' || true)
    fi

    printf '%s\n' "$output"
}

is_expected_scheduler_match() {
    local current="$1"
    local short_name=""

    case "$EXPECTED_SCHEDULER" in
        any) return 0 ;;
        none) [ -z "$current" ] || [ "$current" = "none" ] || [ "$current" = "unknown" ] ;;
        *)
            short_name="$(scheduler_short_name "$EXPECTED_SCHEDULER")"
            case "$current" in
                "$EXPECTED_SCHEDULER"|"$EXPECTED_SCHEDULER"_*|"$short_name"|"$short_name"_*) return 0 ;;
                *) return 1 ;;
            esac
            ;;
    esac
}

usage() {
    cat <<EOF
Usage: sudo ./benchmark.sh [options]

Options:
  --log-file PATH             Write the benchmark log to PATH
  --summary-file PATH         Write machine-readable summary metrics to PATH
  --expected-scheduler NAME   Expected active scheduler, 'none', or 'any'
  --label TEXT                Optional benchmark label written into the log
  --hard-rt                  Enable hard real-time cyclictest mode (FIFO prio 99,
                             SMP, 200us interval, histogram up to 20us)
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
        --hard-rt)
            HARD_RT="1"
            shift
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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log "${RED}Please run with sudo: sudo $0${NC}"
    exit 1
fi

mkdir -p "$(dirname "$BENCHMARK_LOG")"
echo "=== Benchmark Log ===" > "$BENCHMARK_LOG"
log "Benchmark started at $(date)"
if [ -n "$BENCHMARK_LABEL" ]; then
    log "Benchmark label: $BENCHMARK_LABEL"
fi

header "System Information"
log "Kernel: $(uname -r)"
log "CPU: $(cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d: -f2 | xargs)"
log "CPU Cores: $(nproc)"

header "Scheduler Status"
SCHED_EXT_STATE=$(cat /sys/kernel/sched_ext/state 2>/dev/null || echo "unknown")
CURRENT_SCHED=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || true)
[ -n "$CURRENT_SCHED" ] || CURRENT_SCHED="none"
log "sched_ext state: $SCHED_EXT_STATE"
log "Current scheduler: $CURRENT_SCHED"
log "Expected scheduler: $EXPECTED_SCHEDULER"

if ! is_expected_scheduler_match "$CURRENT_SCHED"; then
    log "${YELLOW}Warning: expected scheduler '$EXPECTED_SCHEDULER' is not currently active.${NC}"
fi

header "Benchmark Tool Check"
for tool in cyclictest stress-ng perf sysbench hackbench; do
    if have_cmd "$tool"; then
        log "${GREEN}Found:${NC} $tool"
    else
        log "${YELLOW}Missing:${NC} $tool"
    fi
done
log ""
log "If required tools are missing, run: sudo ./install_benchmark_deps.sh"

HARD_RT="${HARD_RT:-}"
LATENCY_MAX_US=""
LATENCY_SPIKES_OVER_100US=""
LATENCY_SAMPLES=""
LATENCY_OVER_20US=""
LATENCY_TOTAL_SAMPLES=""
THROUGHPUT_BENCHMARK="none"
HACKBENCH_MEAN_SECONDS=""
SYSBENCH_EVENTS_PER_SEC=""
SYSBENCH_AVG_LATENCY_MS=""
STRESSNG_BOGO_OPS_PER_SEC=""
SCHEDULER_MONITOR_LINE=""

header "1. Cyclictest (Latency Benchmark)"
log "Running cyclictest for latency measurement..."
log "This measures wakeup latency in microseconds."
log ""

# Cyclictest parameters
CYCLICTEST_DURATION=30
CYCLICTEST_THREADS=4
CYCLICTEST_AFFINITY=0

if [ -n "$HARD_RT" ]; then
    log "${GREEN}Hard real-time mode enabled.${NC}"
    log "  - FIFO priority 99, SMP spread, 200us interval, histogram up to 20us"
    log "  - Target: all samples under 20us (Overflows == 0)"
fi

log "Parameters: duration=${CYCLICTEST_DURATION}s, threads=${CYCLICTEST_THREADS}"
if [ -n "$HARD_RT" ]; then
    log "  - Mode: hard-rt (prio=99, smp, interval=200us, histogram=20us)"
    log "  - Affinity: SMP spread (all available CPUs)"
else
    log "  - Affinity: CPU${CYCLICTEST_AFFINITY}"
fi

if have_cmd cyclictest; then
    CYCLICTEST_TMP=$(mktemp)

    if [ -n "$HARD_RT" ]; then
        cyclictest \
            --duration="${CYCLICTEST_DURATION}s" \
            --threads="${CYCLICTEST_THREADS}" \
            --priority=99 \
            --smp \
            --interval=200 \
            --histogram=20 \
            --mlockall \
            --verbose 2>&1 \
            | tee "$CYCLICTEST_TMP" \
            | tee -a "$BENCHMARK_LOG"
    else
        cyclictest \
            -D "${CYCLICTEST_DURATION}" \
            -t "${CYCLICTEST_THREADS}" \
            -a "${CYCLICTEST_AFFINITY}" \
            -m -v 2>&1 \
            | tee "$CYCLICTEST_TMP" \
            | tee -a "$BENCHMARK_LOG"
    fi

    if [ -n "$HARD_RT" ]; then
        # Parse cyclictest output for hard RT mode.
        # Two output formats depending on --smp:
        #
        # Compact format (--smp):
        #   # Histogram
        #   000001 <per-CPU bin counts>
        #   ...
        #   # Max Latencies: <per-CPU max values>
        #   # Histogram Overflows: <per-CPU overflow counts>
        #
        # Standard format (single CPU):
        #   # Histogram
        #   # Thread: T:0
        #   # Total: N
        #   # Overflows: N
        #
        read -r LATENCY_OVER_20US LATENCY_MAX_US <<EOF
$(awk '
BEGIN { overflows = 0; max_lat = 0; is_compact = 0 }

/# Histogram Overflows:/ {
    is_compact = 1
    overflows = 0
    for (i = 3; i <= NF; i++)
        overflows += $i + 0
}

/^# Max Latencies:/ {
    if (NF >= 4) {
        for (i = 4; i <= NF; i++) {
            val = $i + 0
            if (val > max_lat) max_lat = val
        }
    }
}

/^# Overflows:[[:space:]]+[0-9]/ && !is_compact {
    overflows = $NF + 0
}

/^# Total:[[:space:]]+[0-9]/ && !is_compact {
    total = $NF + 0
}

END {
    printf "%s %s\n", \
        (overflows ? overflows : ""), \
        (max_lat ? max_lat : "")
}
' "$CYCLICTEST_TMP")
EOF
        LATENCY_TOTAL_SAMPLES=""
        LATENCY_SPIKES_OVER_100US=""
    else
        read -r LATENCY_MAX_US LATENCY_SPIKES_OVER_100US LATENCY_SAMPLES <<EOF
$(awk '
/^[[:space:]]*[0-9]+:/ {
    value = $NF + 0
    if (value > max) {
        max = value
    }
    if (value > 100) {
        spikes++
    }
    count++
}
END {
    printf "%s %s %s\n", (count ? max : ""), (count ? spikes + 0 : ""), (count ? count : "")
}' "$CYCLICTEST_TMP")
EOF
    fi

    rm -f "$CYCLICTEST_TMP"

    log ""
    log "Cyclictest completed. Check results above."
    if [ -n "$HARD_RT" ]; then
        if [ -n "$LATENCY_OVER_20US" ]; then
            log "  - Total overflows (>20us, all CPUs): ${LATENCY_OVER_20US}"
        fi
        if [ "${LATENCY_OVER_20US:-0}" = "0" ]; then
            log "  - All samples stayed under 20us. Hard RT target satisfied."
        else
            log "  - Some samples exceeded 20us. Review histogram."
        fi
        log "  - Max latency (across all CPUs): ${LATENCY_MAX_US:-n/a}us"
    else
        log "  - Avg latency: lower is better"
        log "  - Max latency: should be < 100μs for good interactive performance"
    fi
    if [ -n "$LATENCY_MAX_US" ]; then
        log "  - Observed max latency: ${LATENCY_MAX_US}us"
        log "  - Spikes over 100us: ${LATENCY_SPIKES_OVER_100US}"
    fi
else
    log "${YELLOW}Skipping cyclictest: command not found.${NC}"
    log "Install benchmark dependencies first: sudo ./install_benchmark_deps.sh"
fi

header "2. Hackbench (Throughput Benchmark)"
if have_cmd hackbench; then
    THROUGHPUT_BENCHMARK="hackbench"
    log "Running hackbench for scheduler throughput..."
    log "This measures how many messages per second the scheduler can handle."
    log ""

    HACKBENCH_RUNS=5

    log "Parameters: runs=${HACKBENCH_RUNS}"
    log ""

    HACKBENCH_TMP=$(mktemp)
    for i in $(seq 1 $HACKBENCH_RUNS); do
        log "--- Run $i/$HACKBENCH_RUNS ---"
        hackbench -l 1000 -g 10 2>&1 \
            | tee -a "$HACKBENCH_TMP" \
            | tee -a "$BENCHMARK_LOG"
    done
    HACKBENCH_MEAN_SECONDS=$(awk '
/^Time:/ {
    sum += $2
    count++
}
END {
    if (count) {
        printf "%.3f\n", sum / count
    }
}' "$HACKBENCH_TMP")
    rm -f "$HACKBENCH_TMP"

    log ""
    log "Hackbench completed. Check results above."
    log "  - Time (ms): lower is better"
    log "  - Throughput (msgs/sec): higher is better"
    if [ -n "$HACKBENCH_MEAN_SECONDS" ]; then
        log "  - Mean hackbench time: ${HACKBENCH_MEAN_SECONDS}s"
    fi
elif have_cmd sysbench; then
    THROUGHPUT_BENCHMARK="sysbench"
    log "${YELLOW}hackbench not found; falling back to sysbench CPU benchmark.${NC}"
    log "This gives a basic throughput sanity check when hackbench is unavailable."
    log ""

    SYSBENCH_TIME=30
    SYSBENCH_THREADS=4

    log "Parameters: time=${SYSBENCH_TIME}s, threads=${SYSBENCH_THREADS}"
    SYSBENCH_TMP=$(mktemp)
    sysbench cpu --threads="$SYSBENCH_THREADS" --time="$SYSBENCH_TIME" run 2>&1 \
        | tee "$SYSBENCH_TMP" \
        | tee -a "$BENCHMARK_LOG"
    SYSBENCH_EVENTS_PER_SEC=$(awk -F': ' '/events per second:/ { print $2; exit }' "$SYSBENCH_TMP")
    SYSBENCH_AVG_LATENCY_MS=$(awk '
/avg:/ {
    print $2
    exit
}' "$SYSBENCH_TMP")
    rm -f "$SYSBENCH_TMP"

    log ""
    log "Sysbench CPU benchmark completed."
    log "  - events per second: higher is better"
    log "  - average latency: lower is better"
    if [ -n "$SYSBENCH_EVENTS_PER_SEC" ]; then
        log "  - Observed events per second: ${SYSBENCH_EVENTS_PER_SEC}"
    fi
else
    log "${YELLOW}Skipping throughput benchmark: neither hackbench nor sysbench is available.${NC}"
    log "Install benchmark dependencies first: sudo ./install_benchmark_deps.sh"
fi

header "3. Stress-ng (CPU Stress Test)"
log "Running stress-ng for CPU stress testing..."
log "This tests scheduler behavior under heavy load."
log ""

log "Running CPU stress for 60 seconds..."
if have_cmd stress-ng; then
    STRESSNG_TMP=$(mktemp)
    stress-ng --cpu 4 --cpu-load 80 --timeout 60s --metrics-brief 2>&1 \
        | tee "$STRESSNG_TMP" \
        | tee -a "$BENCHMARK_LOG"
    STRESSNG_BOGO_OPS_PER_SEC=$(awk '
/stress-ng: metrc:/ && / cpu[[:space:]]/ {
    print $(NF-1)
    exit
}' "$STRESSNG_TMP")
    rm -f "$STRESSNG_TMP"
    log ""
    log "Stress-ng completed."
    if [ -n "$STRESSNG_BOGO_OPS_PER_SEC" ]; then
        log "  - Bogo ops/s (real time): ${STRESSNG_BOGO_OPS_PER_SEC}"
    fi
else
    log "${YELLOW}Skipping stress-ng: command not found.${NC}"
    log "Install benchmark dependencies first: sudo ./install_benchmark_deps.sh"
fi

header "4. System Load (Quick Check)"
log "System load averages:"
uptime | tee -a "$BENCHMARK_LOG"
log ""

header "5. Scheduler Internal Stats"
if [ "$EXPECTED_SCHEDULER" != "none" ] && [ "$EXPECTED_SCHEDULER" != "any" ]; then
    SCHEDULER_MONITOR_LINE=$(capture_scheduler_monitor_line "$EXPECTED_SCHEDULER")
    if [ -n "$SCHEDULER_MONITOR_LINE" ]; then
        log "$SCHEDULER_MONITOR_LINE"
    else
        log "${YELLOW}No scheduler monitor output captured.${NC}"
    fi
else
    log "No scheduler monitor capture for baseline/unspecified scheduler."
fi

header "Benchmark Complete!"
log ""
log "Results saved to: $BENCHMARK_LOG"
log ""
log "Summary:"
log "  1. Cyclictest - Check for latency spikes (>100μs is concerning)"
log "  2. Hackbench/sysbench - Compare throughput across schedulers"
log "  3. Stress-ng - Verify scheduler handles load without issues"
log ""
log "To compare with other schedulers:"
log "  1. Reset: ./reset_sched_ext_state.sh"
log "  2. Switch: Use scx_cosmos or another scheduler"
log "  3. Re-run: sudo ./benchmark.sh"
log "  4. Compare: Check $BENCHMARK_LOG"

if [ -n "$SUMMARY_FILE" ]; then
    mkdir -p "$(dirname "$SUMMARY_FILE")"
    cat > "$SUMMARY_FILE" <<EOF
BENCHMARK_LABEL=${BENCHMARK_LABEL}
EXPECTED_SCHEDULER=${EXPECTED_SCHEDULER}
KERNEL_RELEASE=$(uname -r)
SCHED_EXT_STATE=${SCHED_EXT_STATE}
CURRENT_SCHEDULER=${CURRENT_SCHED}
LATENCY_MAX_US=${LATENCY_MAX_US}
LATENCY_SPIKES_OVER_100US=${LATENCY_SPIKES_OVER_100US}
LATENCY_SAMPLES=${LATENCY_SAMPLES}
LATENCY_HARD_RT=${HARD_RT}
LATENCY_OVER_20US=${LATENCY_OVER_20US}
LATENCY_TOTAL_SAMPLES=${LATENCY_TOTAL_SAMPLES}
THROUGHPUT_BENCHMARK=${THROUGHPUT_BENCHMARK}
HACKBENCH_MEAN_SECONDS=${HACKBENCH_MEAN_SECONDS}
SYSBENCH_EVENTS_PER_SEC=${SYSBENCH_EVENTS_PER_SEC}
SYSBENCH_AVG_LATENCY_MS=${SYSBENCH_AVG_LATENCY_MS}
STRESSNG_BOGO_OPS_PER_SEC=${STRESSNG_BOGO_OPS_PER_SEC}
SCHEDULER_MONITOR_LINE=${SCHEDULER_MONITOR_LINE}
LOG_PATH=${BENCHMARK_LOG}
EOF
fi
