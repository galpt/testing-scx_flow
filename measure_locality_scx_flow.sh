#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Measure CPU placement, migration, and cache-related signals under a mixed
# latency/throughput workload before making topology-aware scheduler changes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEDULER_NAME="${SCHEDULER_NAME:-scx_flow}"
SCHEDULER_BIN="${SCHEDULER_BIN:-$(command -v scx_flow || true)}"
RESULTS_ROOT="$SCRIPT_DIR/locality-measurements"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RESULTS_DIR="$RESULTS_ROOT/$TIMESTAMP"
KEEP_RESULTS=3
DURATION=20
SAMPLE_MS=20
STRESS_CPUS=4
STRESS_LOAD=80
CYCLICTEST_INTERVAL_US=200
MONITOR_INTERVAL="0.2"
USE_PERF=1

LOG_FILE=""
SUMMARY_FILE=""
REPORT_FILE=""
TOPOLOGY_FILE=""
SAMPLE_FILE=""
THREAD_SUMMARY_FILE=""
PERF_STAT_FILE=""
MONITOR_FILE=""
CYCLICTEST_FILE=""
WORKLOAD_PIDS=()
PERF_PID=""
MONITOR_PID=""
SAMPLER_PID=""

usage() {
    cat <<EOF
Usage: sudo ./measure_locality_scx_flow.sh [options]

Options:
  --results-dir DIR         Write this run into DIR instead of the default timestamped path
  --keep-results N          Keep only the newest N result directories (default: 3)
  --duration N              Mixed-workload duration in seconds (default: 20)
  --sample-ms N             Sampling interval for thread CPU snapshots (default: 20)
  --stress-cpus N           Number of stress-ng CPU workers (default: 4)
  --stress-load N           stress-ng CPU load percentage (default: 80)
  --scheduler-name NAME     Expected active scheduler name (default: scx_flow)
  --scheduler-bin PATH      Path to scheduler binary for --monitor (default: command -v scx_flow)
  --no-perf                 Skip optional perf stat capture
  -h, --help                Show this help
EOF
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

scheduler_matches_name() {
    local current="$1"
    local expected="$2"
    local short_name

    short_name="$(scheduler_short_name "$expected")"
    case "$current" in
        "$expected"|"$expected"_*|"$short_name"|"$short_name"_*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

log() {
    printf '%s\n' "$1" | tee -a "$LOG_FILE"
}

cleanup_pids() {
    local pid

    for pid in "${WORKLOAD_PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    for pid in "${WORKLOAD_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    WORKLOAD_PIDS=()
}

stop_sampler() {
    if [ -n "$SAMPLER_PID" ]; then
        kill "$SAMPLER_PID" 2>/dev/null || true
        wait "$SAMPLER_PID" 2>/dev/null || true
        SAMPLER_PID=""
    fi
}

stop_monitor() {
    if [ -n "$MONITOR_PID" ]; then
        kill "$MONITOR_PID" 2>/dev/null || true
        wait "$MONITOR_PID" 2>/dev/null || true
        MONITOR_PID=""
    fi
}

stop_perf() {
    if [ -n "$PERF_PID" ]; then
        wait "$PERF_PID" 2>/dev/null || true
        PERF_PID=""
    fi
}

fix_results_ownership() {
    if [ -n "${SUDO_USER:-}" ] && [ -d "$RESULTS_DIR" ]; then
        chown -R "${SUDO_USER}:$(id -gn "$SUDO_USER")" "$RESULTS_DIR" >/dev/null 2>&1 || true
    fi
}

cleanup() {
    cleanup_pids
    stop_sampler
    stop_monitor
    stop_perf
    fix_results_ownership
}

trap cleanup EXIT INT TERM

while [ "$#" -gt 0 ]; do
    case "$1" in
        --results-dir)
            RESULTS_DIR="$2"
            shift 2
            ;;
        --keep-results)
            KEEP_RESULTS="$2"
            shift 2
            ;;
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --sample-ms)
            SAMPLE_MS="$2"
            shift 2
            ;;
        --stress-cpus)
            STRESS_CPUS="$2"
            shift 2
            ;;
        --stress-load)
            STRESS_LOAD="$2"
            shift 2
            ;;
        --scheduler-name)
            SCHEDULER_NAME="$2"
            shift 2
            ;;
        --scheduler-bin)
            SCHEDULER_BIN="$2"
            shift 2
            ;;
        --no-perf)
            USE_PERF=0
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

if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo $0" >&2
    exit 1
fi

if ! have_cmd cyclictest || ! have_cmd stress-ng; then
    echo "cyclictest and stress-ng are required. Run sudo ./install_benchmark_deps.sh first." >&2
    exit 1
fi

if [ -z "$SCHEDULER_BIN" ] || [ ! -x "$SCHEDULER_BIN" ]; then
    echo "Could not find executable scheduler binary. Use --scheduler-bin PATH." >&2
    exit 1
fi

CURRENT_SCHED="$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || true)"
CURRENT_STATE="$(cat /sys/kernel/sched_ext/state 2>/dev/null || echo "unknown")"
if ! scheduler_matches_name "$CURRENT_SCHED" "$SCHEDULER_NAME"; then
    echo "$SCHEDULER_NAME is not the active scheduler right now: ${CURRENT_SCHED:-none}" >&2
    echo "Activate $SCHEDULER_NAME first, then rerun this measurement." >&2
    exit 1
fi

if [ "$CURRENT_STATE" != "enabled" ]; then
    echo "sched_ext is not enabled right now: $CURRENT_STATE" >&2
    exit 1
fi

mkdir -p "$RESULTS_DIR"
LOG_FILE="$RESULTS_DIR/locality_measurement.log"
SUMMARY_FILE="$RESULTS_DIR/locality_summary.env"
REPORT_FILE="$RESULTS_DIR/locality_report.md"
TOPOLOGY_FILE="$RESULTS_DIR/cpu_topology.csv"
SAMPLE_FILE="$RESULTS_DIR/cyclictest_samples.csv"
THREAD_SUMMARY_FILE="$RESULTS_DIR/cyclictest_thread_locality.csv"
PERF_STAT_FILE="$RESULTS_DIR/perf_stat.csv"
MONITOR_FILE="$RESULTS_DIR/scx_flow_monitor.log"
CYCLICTEST_FILE="$RESULTS_DIR/cyclictest.out"

: >"$LOG_FILE"
: >"$MONITOR_FILE"
: >"$SAMPLE_FILE"

write_topology_csv() {
    local cpu_dir
    local cpu
    local node
    local package_id
    local core_id
    local die_id
    local llc_id
    local llc_shared
    local cache_dir
    local level
    local cache_type

    printf 'cpu,node,package,die,core,llc_id,llc_shared_cpu_list\n' >"$TOPOLOGY_FILE"

    for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
        [ -d "$cpu_dir" ] || continue
        cpu="${cpu_dir##*/cpu}"

        node="na"
        if compgen -G "$cpu_dir/node*" >/dev/null; then
            node="$(basename "$(compgen -G "$cpu_dir/node*" | head -n 1)")"
            node="${node#node}"
        fi

        package_id="$(cat "$cpu_dir/topology/physical_package_id" 2>/dev/null || echo na)"
        core_id="$(cat "$cpu_dir/topology/core_id" 2>/dev/null || echo na)"
        die_id="$(cat "$cpu_dir/topology/die_id" 2>/dev/null || echo na)"
        llc_id="na"
        llc_shared="na"

        for cache_dir in "$cpu_dir"/cache/index*; do
            [ -d "$cache_dir" ] || continue
            level="$(cat "$cache_dir/level" 2>/dev/null || echo '')"
            cache_type="$(cat "$cache_dir/type" 2>/dev/null || echo '')"
            if [ "$level" = "3" ] && [ "$cache_type" = "Unified" ]; then
                llc_id="$(cat "$cache_dir/id" 2>/dev/null || basename "$cache_dir")"
                llc_shared="$(cat "$cache_dir/shared_cpu_list" 2>/dev/null || echo na)"
                break
            fi
        done

        printf '%s,%s,%s,%s,%s,%s,%s\n' \
            "$cpu" "$node" "$package_id" "$die_id" "$core_id" "$llc_id" "$llc_shared" \
            >>"$TOPOLOGY_FILE"
    done
}

start_monitor() {
    "$SCHEDULER_BIN" --monitor "$MONITOR_INTERVAL" >"$MONITOR_FILE" 2>/dev/null &
    MONITOR_PID="$!"
}

start_perf() {
    if [ "$USE_PERF" -eq 0 ] || ! have_cmd perf; then
        return
    fi

    perf stat -a -x, \
        -e cycles,instructions,cache-references,cache-misses,cpu-migrations,context-switches \
        -o "$PERF_STAT_FILE" -- sleep "$DURATION" >/dev/null 2>&1 &
    PERF_PID="$!"
}

start_sampler() {
    local pid="$1"
    local sample_sec

    sample_sec="$(awk -v ms="$SAMPLE_MS" 'BEGIN { printf "%.3f", ms / 1000 }')"

    (
        while kill -0 "$pid" 2>/dev/null; do
            local ts_ns
            ts_ns="$(date +%s%N)"
            ps -T -p "$pid" -o pid=,spid=,psr=,comm= 2>/dev/null | \
                awk -v ts="$ts_ns" '
                    NF >= 4 && $3 ~ /^[0-9]+$/ {
                        printf "%s,cyclictest,%s,%s,%s,%s\n", ts, $1, $2, $3, $4
                    }
                ' >>"$SAMPLE_FILE"
            sleep "$sample_sec"
        done
    ) &
    SAMPLER_PID="$!"
}

parse_perf_counter() {
    local event="$1"

    if [ ! -f "$PERF_STAT_FILE" ]; then
        return 0
    fi

    awk -F, -v event="$event" '
        $3 == event {
            value = $1
            gsub(/[[:space:]]/, "", value)
            if (value != "" && value !~ /<not/) {
                print value
                exit
            }
        }
    ' "$PERF_STAT_FILE"
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
                if (value > max)
                    max = value
            }
        }
    }
    END { print max }
    ' "$file"
}

last_field_from_monitor() {
    local key="$1"
    local file="$2"

    awk -v key="$key" '
    {
        for (i = 1; i <= NF; i++) {
            if ($i ~ ("^" key "=")) {
                split($i, parts, "=")
                value = parts[2]
            }
        }
    }
    END { print value }
    ' "$file"
}

log "=== Measuring locality and placement signals for $SCHEDULER_NAME ==="
log "Results directory: $RESULTS_DIR"
log "Current scheduler: ${CURRENT_SCHED:-none}"
log "Duration: ${DURATION}s"
log "Sampling interval: ${SAMPLE_MS}ms"
log "stress-ng workers: $STRESS_CPUS @ ${STRESS_LOAD}%"

write_topology_csv
start_monitor
start_perf

stress-ng --cpu "$STRESS_CPUS" --cpu-load "$STRESS_LOAD" --timeout "${DURATION}s" \
    --metrics-brief >>"$LOG_FILE" 2>&1 &
STRESS_PID="$!"
WORKLOAD_PIDS+=("$STRESS_PID")

cyclictest --mlockall --smp --priority=80 --interval="$CYCLICTEST_INTERVAL_US" \
    --duration="$DURATION" >"$CYCLICTEST_FILE" 2>&1 &
CYCLICTEST_PID="$!"
WORKLOAD_PIDS+=("$CYCLICTEST_PID")

start_sampler "$CYCLICTEST_PID"

wait "$CYCLICTEST_PID"
wait "$STRESS_PID"
WORKLOAD_PIDS=()

stop_sampler
stop_monitor
stop_perf

awk -F, -v topo="$TOPOLOGY_FILE" -v thread_csv="$THREAD_SUMMARY_FILE" '
BEGIN {
    while ((getline line < topo) > 0) {
        if (line ~ /^cpu,/) {
            continue
        }
        split(line, parts, ",")
        cpu_llc[parts[1]] = parts[6]
        if (parts[6] != "" && parts[6] != "na" && !seen_llc[parts[6]]++) {
            system_llc_count++
        }
    }
    close(topo)
}
{
    tid = $4
    cpu = $5
    llc = cpu_llc[cpu]
    if (llc == "") {
        llc = "na"
    }

    samples[tid]++
    unique_cpu[tid, cpu] = 1
    unique_llc[tid, llc] = 1

    if (prev_cpu[tid] != "" && cpu != prev_cpu[tid]) {
        cpu_changes[tid]++
        total_cpu_changes++
    }
    if (prev_llc[tid] != "" && llc != prev_llc[tid]) {
        llc_changes[tid]++
        total_llc_changes++
    }

    prev_cpu[tid] = cpu
    prev_llc[tid] = llc
    last_cpu[tid] = cpu
    last_llc[tid] = llc
    total_samples++
}
END {
    print "tid,samples,cpu_changes,llc_changes,unique_cpus,unique_llcs,last_cpu,last_llc" > thread_csv

    for (key in samples) {
        cpu_unique = 0
        llc_unique = 0
        for (cpu_key in unique_cpu) {
            split(cpu_key, parts, SUBSEP)
            if (parts[1] == key)
                cpu_unique++
        }
        for (llc_key in unique_llc) {
            split(llc_key, parts, SUBSEP)
            if (parts[1] == key)
                llc_unique++
        }

        if (cpu_changes[key] + 0 > max_cpu_changes)
            max_cpu_changes = cpu_changes[key] + 0
        if (llc_changes[key] + 0 > max_llc_changes)
            max_llc_changes = llc_changes[key] + 0

        total_threads++
        printf "%s,%d,%d,%d,%d,%d,%s,%s\n",
            key,
            samples[key] + 0,
            cpu_changes[key] + 0,
            llc_changes[key] + 0,
            cpu_unique,
            llc_unique,
            last_cpu[key],
            last_llc[key] >> thread_csv
    }

    printf "TOTAL_THREAD_SAMPLES=%d\n", total_samples
    printf "TOTAL_THREADS_OBSERVED=%d\n", total_threads
    printf "TOTAL_CPU_CHANGES=%d\n", total_cpu_changes
    printf "TOTAL_LLC_CHANGES=%d\n", total_llc_changes
    printf "MAX_THREAD_CPU_CHANGES=%d\n", max_cpu_changes
    printf "MAX_THREAD_LLC_CHANGES=%d\n", max_llc_changes
    printf "SYSTEM_LLC_COUNT=%d\n", system_llc_count
}
' "$SAMPLE_FILE" >"$SUMMARY_FILE"

TOTAL_THREAD_SAMPLES="$(sed -n 's/^TOTAL_THREAD_SAMPLES=//p' "$SUMMARY_FILE")"
TOTAL_THREADS_OBSERVED="$(sed -n 's/^TOTAL_THREADS_OBSERVED=//p' "$SUMMARY_FILE")"
TOTAL_CPU_CHANGES="$(sed -n 's/^TOTAL_CPU_CHANGES=//p' "$SUMMARY_FILE")"
TOTAL_LLC_CHANGES="$(sed -n 's/^TOTAL_LLC_CHANGES=//p' "$SUMMARY_FILE")"
MAX_THREAD_CPU_CHANGES="$(sed -n 's/^MAX_THREAD_CPU_CHANGES=//p' "$SUMMARY_FILE")"
MAX_THREAD_LLC_CHANGES="$(sed -n 's/^MAX_THREAD_LLC_CHANGES=//p' "$SUMMARY_FILE")"
SYSTEM_LLC_COUNT="$(sed -n 's/^SYSTEM_LLC_COUNT=//p' "$SUMMARY_FILE")"
CPU_CHANGE_RATE_PER_1K="$(awk -v c="${TOTAL_CPU_CHANGES:-0}" -v s="${TOTAL_THREAD_SAMPLES:-0}" 'BEGIN { if (s == 0) print "0.00"; else printf "%.2f", (c * 1000) / s }')"
LLC_CHANGE_RATE_PER_1K="$(awk -v c="${TOTAL_LLC_CHANGES:-0}" -v s="${TOTAL_THREAD_SAMPLES:-0}" 'BEGIN { if (s == 0) print "0.00"; else printf "%.2f", (c * 1000) / s }')"
LLC_PER_CPU_CHANGE_RATIO="$(awk -v llc="${TOTAL_LLC_CHANGES:-0}" -v cpu="${TOTAL_CPU_CHANGES:-0}" 'BEGIN { if (cpu == 0) print "0.00"; else printf "%.2f", llc / cpu }')"

PERF_CYCLES="$(parse_perf_counter cycles)"
PERF_INSTRUCTIONS="$(parse_perf_counter instructions)"
PERF_CACHE_REFERENCES="$(parse_perf_counter cache-references)"
PERF_CACHE_MISSES="$(parse_perf_counter cache-misses)"
PERF_CPU_MIGRATIONS="$(parse_perf_counter cpu-migrations)"
PERF_CONTEXT_SWITCHES="$(parse_perf_counter context-switches)"
FINAL_AUTOTUNE_MODE="$(last_field_from_monitor mode "$MONITOR_FILE")"
FINAL_AUTOTUNE_GENERATION="$(last_field_from_monitor gen "$MONITOR_FILE")"
MAX_RESERVED_LOCAL="$(max_counter_from_monitor reserve_local "$MONITOR_FILE")"
MAX_RESERVED_GLOBAL="$(max_counter_from_monitor reserve_global "$MONITOR_FILE")"
MAX_SHARED_WAKE="$(max_counter_from_monitor shared_wake "$MONITOR_FILE")"
MAX_WAKE_PREEMPT="$(max_counter_from_monitor wake_preempt "$MONITOR_FILE")"

cat >>"$SUMMARY_FILE" <<EOF
RESULTS_DIR=$RESULTS_DIR
LOG_PATH=$LOG_FILE
REPORT_PATH=$REPORT_FILE
TOPOLOGY_PATH=$TOPOLOGY_FILE
SAMPLE_PATH=$SAMPLE_FILE
THREAD_SUMMARY_PATH=$THREAD_SUMMARY_FILE
MONITOR_PATH=$MONITOR_FILE
PERF_STAT_PATH=$PERF_STAT_FILE
CYCLICTEST_OUTPUT_PATH=$CYCLICTEST_FILE
SCHEDULER_NAME=$SCHEDULER_NAME
DURATION_SECONDS=$DURATION
SAMPLE_MS=$SAMPLE_MS
CPU_CHANGE_RATE_PER_1000_SAMPLES=$CPU_CHANGE_RATE_PER_1K
LLC_CHANGE_RATE_PER_1000_SAMPLES=$LLC_CHANGE_RATE_PER_1K
LLC_PER_CPU_CHANGE_RATIO=$LLC_PER_CPU_CHANGE_RATIO
SYSTEM_LLC_COUNT=${SYSTEM_LLC_COUNT:-0}
PERF_CYCLES=${PERF_CYCLES:-}
PERF_INSTRUCTIONS=${PERF_INSTRUCTIONS:-}
PERF_CACHE_REFERENCES=${PERF_CACHE_REFERENCES:-}
PERF_CACHE_MISSES=${PERF_CACHE_MISSES:-}
PERF_CPU_MIGRATIONS=${PERF_CPU_MIGRATIONS:-}
PERF_CONTEXT_SWITCHES=${PERF_CONTEXT_SWITCHES:-}
FINAL_AUTOTUNE_MODE=${FINAL_AUTOTUNE_MODE:-}
FINAL_AUTOTUNE_GENERATION=${FINAL_AUTOTUNE_GENERATION:-}
RESERVED_LOCAL_MAX=${MAX_RESERVED_LOCAL:-0}
RESERVED_GLOBAL_MAX=${MAX_RESERVED_GLOBAL:-0}
SHARED_WAKE_MAX=${MAX_SHARED_WAKE:-0}
WAKE_PREEMPT_MAX=${MAX_WAKE_PREEMPT:-0}
EOF

cat >"$REPORT_FILE" <<EOF
# scx_flow Locality Measurement

Generated: $(date)

This run is intended to answer one narrow question before changing scheduler
policy: does the current workload show enough migration and cross-LLC movement
to justify locality-aware CPU preference as the next step?

## Inputs

- scheduler: $SCHEDULER_NAME
- duration: ${DURATION}s
- sampling interval: ${SAMPLE_MS}ms
- stress-ng workers: $STRESS_CPUS @ ${STRESS_LOAD}%

## Key Signals

| Metric | Value |
| --- | ---: |
| cyclictest thread samples | ${TOTAL_THREAD_SAMPLES:-0} |
| cyclictest threads observed | ${TOTAL_THREADS_OBSERVED:-0} |
| total CPU changes | ${TOTAL_CPU_CHANGES:-0} |
| total LLC changes | ${TOTAL_LLC_CHANGES:-0} |
| system LLC domains observed | ${SYSTEM_LLC_COUNT:-0} |
| CPU changes / 1000 samples | $CPU_CHANGE_RATE_PER_1K |
| LLC changes / 1000 samples | $LLC_CHANGE_RATE_PER_1K |
| LLC changes / CPU changes | $LLC_PER_CPU_CHANGE_RATIO |
| max per-thread CPU changes | ${MAX_THREAD_CPU_CHANGES:-0} |
| max per-thread LLC changes | ${MAX_THREAD_LLC_CHANGES:-0} |
| final autotune mode | ${FINAL_AUTOTUNE_MODE:-n/a} |
| final autotune generation | ${FINAL_AUTOTUNE_GENERATION:-n/a} |

## Scheduler Monitor Peaks

- reserve_local: ${MAX_RESERVED_LOCAL:-0}
- reserve_global: ${MAX_RESERVED_GLOBAL:-0}
- shared_wake: ${MAX_SHARED_WAKE:-0}
- wake_preempt: ${MAX_WAKE_PREEMPT:-0}

## Perf Stat Snapshot

- cycles: ${PERF_CYCLES:-n/a}
- instructions: ${PERF_INSTRUCTIONS:-n/a}
- cache references: ${PERF_CACHE_REFERENCES:-n/a}
- cache misses: ${PERF_CACHE_MISSES:-n/a}
- cpu migrations: ${PERF_CPU_MIGRATIONS:-n/a}
- context switches: ${PERF_CONTEXT_SWITCHES:-n/a}

## How To Read This

- If the system LLC domain count is 1, this machine cannot validate cross-LLC benefits directly.
- If CPU changes are low and LLC changes are also low, locality is probably not the first missing lever.
- If CPU changes are high but LLC changes stay low, the workload is moving but mostly within a shared cache domain.
- If LLC changes rise with CPU changes, locality-aware placement becomes a stronger candidate.
- High cache misses alone do not prove a topology problem; they only tell us locality is still worth examining.

## Artifacts

- [$TOPOLOGY_FILE]($TOPOLOGY_FILE)
- [$SAMPLE_FILE]($SAMPLE_FILE)
- [$THREAD_SUMMARY_FILE]($THREAD_SUMMARY_FILE)
- [$MONITOR_FILE]($MONITOR_FILE)
- [$CYCLICTEST_FILE]($CYCLICTEST_FILE)
- [$PERF_STAT_FILE]($PERF_STAT_FILE)
- [$LOG_FILE]($LOG_FILE)
EOF

log ""
log "=== Locality measurement complete ==="
log "CPU changes / 1000 samples: $CPU_CHANGE_RATE_PER_1K"
log "LLC changes / 1000 samples: $LLC_CHANGE_RATE_PER_1K"
log "LLC changes / CPU changes: $LLC_PER_CPU_CHANGE_RATIO"
log "Report: $REPORT_FILE"

mkdir -p "$RESULTS_ROOT"
if [ "$KEEP_RESULTS" -gt 0 ]; then
    mapfile -t old_results < <(ls -1dt "$RESULTS_ROOT"/* 2>/dev/null | tail -n +$((KEEP_RESULTS + 1)) || true)
    if [ "${#old_results[@]}" -gt 0 ]; then
        rm -rf "${old_results[@]}"
    fi
fi
