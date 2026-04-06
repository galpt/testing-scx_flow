#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Targeted latency-stress validation for scx_flow. This complements the broad
# comparison benchmark with a more adversarial wakeup/load/interference run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEDULER_NAME="${SCHEDULER_NAME:-scx_flow}"
SCHEDULER_BIN="${SCHEDULER_BIN:-$(command -v scx_flow || true)}"
RESULTS_ROOT="$SCRIPT_DIR/latency-stress-results"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RESULTS_DIR="$RESULTS_ROOT/$TIMESTAMP"
KEEP_RESULTS=3
MONITOR_INTERVAL="0.2"
MIXED_SECONDS=20
MIXED_THREADS=4
MIXED_AFFINITY=0
WAKE_WORKERS=8
WAKE_SLEEP_SEC="0.002"
FORK_ROUNDS=10
FORK_WIDTH=32
HOG_COUNT=4
HOG_LOAD=85
RT_SECONDS=10
RT_CPU=0
RT_PRESSURE_SECONDS=2
STRICT=0

LOG_FILE=""
SUMMARY_FILE=""
MONITOR_FILE=""
KERNEL_LOG_FILE=""
WORKLOAD_PIDS=()
MONITOR_PID=""
RUN_START_EPOCH="$(date +%s)"

usage() {
    cat <<EOF
Usage: sudo ./latency_stress_scx_flow.sh [options]

Options:
  --results-dir DIR         Write this run into DIR instead of the default timestamped path
  --keep-results N          Keep only the newest N result directories (default: 3)
  --mixed-seconds N         Cyclictest duration for mixed-load phase (default: 20)
  --rt-seconds N            Cyclictest duration for RT-interference phase (default: 10)
  --rt-cpu N                CPU to target for RT interference (default: 0)
  --scheduler-name NAME     Expected active scheduler name (default: scx_flow)
  --scheduler-bin PATH      Path to scx_flow binary (default: command -v scx_flow)
  --strict                  Exit non-zero if key latency phases fail to run
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

is_baseline_scheduler() {
    case "$SCHEDULER_NAME" in
        baseline|none) return 0 ;;
        *) return 1 ;;
    esac
}

start_monitor_capture() {
    if is_baseline_scheduler; then
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

wait_for_workloads() {
    local pid

    for pid in "${WORKLOAD_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    WORKLOAD_PIDS=()
}

fix_results_ownership() {
    if [ -n "${SUDO_USER:-}" ] && [ -d "$RESULTS_DIR" ]; then
        chown -R "${SUDO_USER}:$(id -gn "$SUDO_USER")" "$RESULTS_DIR" >/dev/null 2>&1 || true
    fi
}

cleanup() {
    wait_for_workloads
    stop_monitor_capture
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
        --mixed-seconds)
            MIXED_SECONDS="$2"
            shift 2
            ;;
        --rt-seconds)
            RT_SECONDS="$2"
            shift 2
            ;;
        --rt-cpu)
            RT_CPU="$2"
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
        --strict)
            STRICT=1
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

if ! is_baseline_scheduler && { [ -z "$SCHEDULER_BIN" ] || [ ! -x "$SCHEDULER_BIN" ]; }; then
    echo "Could not find executable scx_flow binary. Use --scheduler-bin PATH." >&2
    exit 1
fi

CURRENT_SCHED="$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || true)"
CURRENT_STATE="$(cat /sys/kernel/sched_ext/state 2>/dev/null || echo "unknown")"
if is_baseline_scheduler; then
    if [ "$CURRENT_STATE" != "disabled" ]; then
        echo "Baseline mode expects sched_ext to be disabled right now: $CURRENT_STATE" >&2
        exit 1
    fi
else
    if ! scheduler_matches_name "$CURRENT_SCHED" "$SCHEDULER_NAME"; then
        echo "$SCHEDULER_NAME is not the active scheduler right now: ${CURRENT_SCHED:-none}" >&2
        echo "Activate $SCHEDULER_NAME first, then rerun this validation." >&2
        exit 1
    fi

    if [ "$CURRENT_STATE" != "enabled" ]; then
        echo "sched_ext is not enabled right now: $CURRENT_STATE" >&2
        exit 1
    fi
fi

if ! have_cmd cyclictest; then
    echo "cyclictest is required for latency_stress_scx_flow.sh. Run sudo ./install_benchmark_deps.sh first." >&2
    exit 1
fi

mkdir -p "$RESULTS_DIR"
LOG_FILE="$RESULTS_DIR/latency_stress.log"
SUMMARY_FILE="$RESULTS_DIR/latency_stress_summary.env"
MONITOR_FILE="$RESULTS_DIR/scx_flow_monitor.log"
KERNEL_LOG_FILE="$RESULTS_DIR/kernel_sched_ext.log"
: >"$LOG_FILE"
: >"$MONITOR_FILE"
: >"$KERNEL_LOG_FILE"

parse_cyclictest_metrics() {
    local file="$1"
    local sorted_samples
    local count
    local p95_rank
    local p99_rank

    sorted_samples="$(mktemp)"

    awk '
/^[[:space:]]*[0-9]+:/ {
    print $NF + 0
}
' "$file" | sort -n >"$sorted_samples"

    count="$(wc -l <"$sorted_samples")"
    count="${count//[[:space:]]/}"
    if [ -z "$count" ] || [ "$count" -eq 0 ]; then
        rm -f "$sorted_samples"
        printf '\n'
        return
    fi

    p95_rank=$(((count * 95 + 99) / 100))
    p99_rank=$(((count * 99 + 99) / 100))

    awk -v p95_rank="$p95_rank" -v p99_rank="$p99_rank" '
{
    value = $1 + 0
    max = value
    if (value > 100) {
        spikes++
    }
    if (NR == p95_rank) {
        p95 = value
    }
    if (NR == p99_rank) {
        p99 = value
    }
}
END {
    printf "%s %s %s %s %s\n", max, spikes + 0, NR, p95, p99
}
' "$sorted_samples"

    rm -f "$sorted_samples"
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

run_wake_storm() {
    local workers="$1"
    local iterations="$2"
    local delay="$3"
    local i

    for i in $(seq 1 "$workers"); do
        bash -c '
            iters="$1"
            pause="$2"
            for ((j = 0; j < iters; j++)); do
                : >/dev/null
                sleep "$pause"
            done
        ' _ "$iterations" "$delay" &
        WORKLOAD_PIDS+=("$!")
    done
}

run_fork_storm() {
    local rounds="$1"
    local width="$2"
    local round idx

    for round in $(seq 1 "$rounds"); do
        for idx in $(seq 1 "$width"); do
            bash -c 'exit 0' &
        done
        wait
        for idx in $(seq 1 "$width"); do
            sh -c 'true' &
        done
        wait
        sleep 0.02
    done
}

start_normal_hogs() {
    local seconds="$1"
    local i

    if ! have_cmd stress-ng; then
        return 1
    fi

    for i in $(seq 1 "$HOG_COUNT"); do
        stress-ng --cpu 1 --cpu-load "$HOG_LOAD" --timeout "${seconds}s" --metrics-brief \
            >>"$LOG_FILE" 2>&1 &
        WORKLOAD_PIDS+=("$!")
    done
    return 0
}

run_mixed_phase() {
    local tmpfile="$1"
    local wake_iters=$((MIXED_SECONDS * 500))
    local mixed_timeout=$((MIXED_SECONDS + 15))

    log ""
    log ">>> Phase 1: mixed latency under CPU load, wake storms, and short-lived task churn"
    if start_normal_hogs "$MIXED_SECONDS"; then
        log "Started ${HOG_COUNT} stress-ng CPU hogs for ${MIXED_SECONDS}s."
    else
        log "stress-ng not available; running mixed phase without synthetic CPU hogs."
    fi

    run_wake_storm "$WAKE_WORKERS" "$wake_iters" "$WAKE_SLEEP_SEC"
    run_fork_storm "$FORK_ROUNDS" "$FORK_WIDTH" &
    WORKLOAD_PIDS+=("$!")

    if have_cmd timeout; then
        timeout --foreground "${mixed_timeout}s" \
            cyclictest -D "$MIXED_SECONDS" -t "$MIXED_THREADS" -a "$MIXED_AFFINITY" -m -v 2>&1 \
            | tee "$tmpfile" >>"$LOG_FILE"
    else
        cyclictest -D "$MIXED_SECONDS" -t "$MIXED_THREADS" -a "$MIXED_AFFINITY" -m -v 2>&1 \
            | tee "$tmpfile" >>"$LOG_FILE"
    fi

    wait_for_workloads
}

run_rt_phase() {
    local tmpfile="$1"
    local rt_timeout=$((RT_SECONDS + RT_PRESSURE_SECONDS + 15))

    log ""
    log ">>> Phase 2: latency under RT interference on CPU${RT_CPU}"
    if ! have_cmd taskset || ! have_cmd chrt || ! have_cmd timeout; then
        log "Skipping RT interference phase: need taskset, chrt, and timeout."
        return 2
    fi

    if have_cmd timeout; then
        timeout --foreground "${rt_timeout}s" \
            taskset -c "$RT_CPU" cyclictest -D "$RT_SECONDS" -t 1 -a "$RT_CPU" -m -v 2>&1 \
            | tee "$tmpfile" >>"$LOG_FILE" &
    else
        taskset -c "$RT_CPU" cyclictest -D "$RT_SECONDS" -t 1 -a "$RT_CPU" -m -v 2>&1 \
            | tee "$tmpfile" >>"$LOG_FILE" &
    fi
    WORKLOAD_PIDS+=("$!")

    sleep 1
    log "Injecting a short FIFO RT hog without adding a pinned normal-task busy loop."
    timeout --foreground --kill-after=1s "${RT_PRESSURE_SECONDS}s" \
        taskset -c "$RT_CPU" chrt -f 10 bash -c 'while :; do :; done' >>"$LOG_FILE" 2>&1 || true

    wait_for_workloads
    return 0
}

prune_old_results() {
    local old_dirs

    [ -d "$RESULTS_ROOT" ] || return 0
    old_dirs=$(ls -1dt "$RESULTS_ROOT"/* 2>/dev/null | tail -n +"$((KEEP_RESULTS + 1))" || true)
    [ -n "$old_dirs" ] || return 0

    while IFS= read -r old_dir; do
        [ -n "$old_dir" ] || continue
        rm -rf "$old_dir"
    done <<EOF
$old_dirs
EOF
}

log "========================================"
log "$SCHEDULER_NAME latency-stress validation"
log "Started: $(date)"
log "Kernel: $(uname -r)"
log "Scheduler: ${CURRENT_SCHED:-none}"
log "sched_ext state: $CURRENT_STATE"
if ! is_baseline_scheduler; then
    log "Binary: $SCHEDULER_BIN"
fi
log "Results dir: $RESULTS_DIR"
log "========================================"

start_monitor_capture
sleep 0.2

MIXED_TMP="$(mktemp)"
RT_TMP="$(mktemp)"
trap 'rm -f "$MIXED_TMP" "$RT_TMP"; cleanup' EXIT INT TERM

MIXED_PHASE_STATUS="completed"
RT_PHASE_STATUS="completed"

run_mixed_phase "$MIXED_TMP" || MIXED_PHASE_STATUS="failed"
read -r MIXED_LATENCY_MAX_US MIXED_SPIKES_OVER_100US MIXED_SAMPLES MIXED_LATENCY_P95_US MIXED_LATENCY_P99_US <<EOF
$(parse_cyclictest_metrics "$MIXED_TMP")
EOF

RT_STATUS_CODE=0
run_rt_phase "$RT_TMP" || RT_STATUS_CODE=$?
case "$RT_STATUS_CODE" in
    0) RT_PHASE_STATUS="completed" ;;
    2) RT_PHASE_STATUS="skipped-missing-tools" ;;
    *) RT_PHASE_STATUS="failed" ;;
esac
read -r RT_LATENCY_MAX_US RT_SPIKES_OVER_100US RT_SAMPLES RT_LATENCY_P95_US RT_LATENCY_P99_US <<EOF
$(parse_cyclictest_metrics "$RT_TMP")
EOF

sleep 0.5
stop_monitor_capture

POST_STATE="$(cat /sys/kernel/sched_ext/state 2>/dev/null || echo "unknown")"
POST_SCHED="$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || true)"

journalctl -k --since "@$RUN_START_EPOCH" --no-pager \
    | grep 'sched_ext' >"$KERNEL_LOG_FILE" || true

SCHEDULER_MATCH_NAME="$(scheduler_short_name "$SCHEDULER_NAME")"
KERNEL_DISABLE_EVENTS="$(grep 'disabled' "$KERNEL_LOG_FILE" | grep -F "$SCHEDULER_MATCH_NAME" | wc -l || true)"
KERNEL_STALL_EVENTS="$(grep -c 'disabled (runnable task stall)' "$KERNEL_LOG_FILE" || true)"
KERNEL_REENABLE_EVENTS="$(grep 'enabled' "$KERNEL_LOG_FILE" | grep -F "$SCHEDULER_MATCH_NAME" | wc -l || true)"
KERNEL_FAILED_TO_RUN_EVENTS="$(grep 'failed to run for' "$KERNEL_LOG_FILE" | grep -F "$SCHEDULER_MATCH_NAME" | wc -l || true)"

OVERALL_STATUS="completed"
OVERALL_NOTE=""
if [ "${KERNEL_STALL_EVENTS:-0}" -gt 0 ]; then
    OVERALL_STATUS="failed"
    OVERALL_NOTE="runnable-task-stall-detected"
elif [ "$POST_STATE" != "enabled" ]; then
    OVERALL_STATUS="failed"
    OVERALL_NOTE="sched-ext-not-enabled-after-run"
fi

RUNNABLE_MAX="$(max_counter_from_monitor "runnable" "$MONITOR_FILE")"
CPU_RELEASE_MAX="$(max_counter_from_monitor "cpu_release" "$MONITOR_FILE")"
INIT_TASK_MAX="$(max_counter_from_monitor "init_task" "$MONITOR_FILE")"
ENABLE_MAX="$(max_counter_from_monitor "enable" "$MONITOR_FILE")"
EXIT_TASK_MAX="$(max_counter_from_monitor "exit_task" "$MONITOR_FILE")"
RESERVED_LOCAL_MAX="$(max_counter_from_monitor "reserve_local" "$MONITOR_FILE")"
RESERVED_GLOBAL_MAX="$(max_counter_from_monitor "reserve_global" "$MONITOR_FILE")"
SHARED_WAKE_MAX="$(max_counter_from_monitor "shared_wake" "$MONITOR_FILE")"
WAKE_PREEMPT_MAX="$(max_counter_from_monitor "wake_preempt" "$MONITOR_FILE")"
FINAL_MODE="$(last_field_from_monitor "mode" "$MONITOR_FILE")"
FINAL_GEN="$(last_field_from_monitor "gen" "$MONITOR_FILE")"
FINAL_RESERVED_CAP_US="$(last_field_from_monitor "reserve_cap_us" "$MONITOR_FILE")"
FINAL_SHARED_SLICE_US="$(last_field_from_monitor "shared_slice_us" "$MONITOR_FILE")"
FINAL_REFILL_FLOOR_US="$(last_field_from_monitor "refill_floor_us" "$MONITOR_FILE")"
FINAL_PREEMPT_BUDGET_US="$(last_field_from_monitor "preempt_budget_us" "$MONITOR_FILE")"
FINAL_PREEMPT_REFILL_US="$(last_field_from_monitor "preempt_refill_us" "$MONITOR_FILE")"

cat > "$SUMMARY_FILE" <<EOF
RESULTS_DIR=${RESULTS_DIR}
LOG_PATH=${LOG_FILE}
MONITOR_PATH=${MONITOR_FILE}
KERNEL_LOG_PATH=${KERNEL_LOG_FILE}
KERNEL_RELEASE=$(uname -r)
SCHEDULER=${CURRENT_SCHED}
EXPECTED_SCHEDULER=${SCHEDULER_NAME}
PRE_RUN_SCHED_EXT_STATE=${CURRENT_STATE}
POST_RUN_SCHED_EXT_STATE=${POST_STATE}
POST_RUN_CURRENT_SCHEDULER=${POST_SCHED}
OVERALL_STATUS=${OVERALL_STATUS}
OVERALL_NOTE=${OVERALL_NOTE}
MIXED_PHASE_STATUS=${MIXED_PHASE_STATUS}
MIXED_LATENCY_MAX_US=${MIXED_LATENCY_MAX_US}
MIXED_SPIKES_OVER_100US=${MIXED_SPIKES_OVER_100US}
MIXED_LATENCY_SAMPLES=${MIXED_SAMPLES}
MIXED_LATENCY_P95_US=${MIXED_LATENCY_P95_US}
MIXED_LATENCY_P99_US=${MIXED_LATENCY_P99_US}
RT_PHASE_STATUS=${RT_PHASE_STATUS}
RT_LATENCY_MAX_US=${RT_LATENCY_MAX_US}
RT_SPIKES_OVER_100US=${RT_SPIKES_OVER_100US}
RT_LATENCY_SAMPLES=${RT_SAMPLES}
RT_LATENCY_P95_US=${RT_LATENCY_P95_US}
RT_LATENCY_P99_US=${RT_LATENCY_P99_US}
RUNNABLE_MAX=${RUNNABLE_MAX}
CPU_RELEASE_MAX=${CPU_RELEASE_MAX}
INIT_TASK_MAX=${INIT_TASK_MAX}
ENABLE_MAX=${ENABLE_MAX}
EXIT_TASK_MAX=${EXIT_TASK_MAX}
RESERVED_LOCAL_MAX=${RESERVED_LOCAL_MAX}
RESERVED_GLOBAL_MAX=${RESERVED_GLOBAL_MAX}
SHARED_WAKE_MAX=${SHARED_WAKE_MAX}
WAKE_PREEMPT_MAX=${WAKE_PREEMPT_MAX}
KERNEL_DISABLE_EVENTS=${KERNEL_DISABLE_EVENTS}
KERNEL_STALL_EVENTS=${KERNEL_STALL_EVENTS}
KERNEL_REENABLE_EVENTS=${KERNEL_REENABLE_EVENTS}
KERNEL_FAILED_TO_RUN_EVENTS=${KERNEL_FAILED_TO_RUN_EVENTS}
FINAL_AUTOTUNE_MODE=${FINAL_MODE}
FINAL_AUTOTUNE_GENERATION=${FINAL_GEN}
FINAL_RESERVED_CAP_US=${FINAL_RESERVED_CAP_US}
FINAL_SHARED_SLICE_US=${FINAL_SHARED_SLICE_US}
FINAL_REFILL_FLOOR_US=${FINAL_REFILL_FLOOR_US}
FINAL_PREEMPT_BUDGET_US=${FINAL_PREEMPT_BUDGET_US}
FINAL_PREEMPT_REFILL_US=${FINAL_PREEMPT_REFILL_US}
EOF

log ""
log "========================================"
log "Latency-stress summary"
log "========================================"
log "Overall status: $OVERALL_STATUS"
if [ -n "$OVERALL_NOTE" ]; then
    log "Overall note: $OVERALL_NOTE"
fi
log "Mixed phase status: $MIXED_PHASE_STATUS"
log "Mixed max latency: ${MIXED_LATENCY_MAX_US:-n/a}us"
log "Mixed p95 latency: ${MIXED_LATENCY_P95_US:-n/a}us"
log "Mixed p99 latency: ${MIXED_LATENCY_P99_US:-n/a}us"
log "Mixed spikes >100us: ${MIXED_SPIKES_OVER_100US:-n/a}"
log "RT phase status: $RT_PHASE_STATUS"
log "RT max latency: ${RT_LATENCY_MAX_US:-n/a}us"
log "RT p95 latency: ${RT_LATENCY_P95_US:-n/a}us"
log "RT p99 latency: ${RT_LATENCY_P99_US:-n/a}us"
log "RT spikes >100us: ${RT_SPIKES_OVER_100US:-n/a}"
log "Kernel disable events: ${KERNEL_DISABLE_EVENTS:-0}"
log "Kernel runnable-stall events: ${KERNEL_STALL_EVENTS:-0}"
log "Kernel re-enable events: ${KERNEL_REENABLE_EVENTS:-0}"
log "Kernel failed-to-run events: ${KERNEL_FAILED_TO_RUN_EVENTS:-0}"
log "Monitor max runnable: $RUNNABLE_MAX"
log "Monitor max cpu_release: $CPU_RELEASE_MAX"
log "Monitor max reserve_local: $RESERVED_LOCAL_MAX"
log "Monitor max reserve_global: $RESERVED_GLOBAL_MAX"
log "Monitor max shared_wake: $SHARED_WAKE_MAX"
log "Monitor max wake_preempt: $WAKE_PREEMPT_MAX"
log "Final autotune mode: ${FINAL_MODE:-unknown}"
log "Summary file: $SUMMARY_FILE"
log "Monitor log: $MONITOR_FILE"
log "Kernel log: $KERNEL_LOG_FILE"

rm -f "$MIXED_TMP" "$RT_TMP"
trap cleanup EXIT INT TERM

prune_old_results

if [ "$STRICT" -eq 1 ]; then
    if [ "$MIXED_PHASE_STATUS" != "completed" ] || [ -z "${MIXED_LATENCY_MAX_US:-}" ]; then
        echo "Strict mode failure: mixed latency phase did not complete cleanly." >&2
        exit 1
    fi
    if [ "$POST_STATE" != "enabled" ]; then
        echo "Strict mode failure: sched_ext is no longer enabled after the run." >&2
        exit 1
    fi
    if [ "${KERNEL_STALL_EVENTS:-0}" -gt 0 ]; then
        echo "Strict mode failure: runnable task stall was detected during the run." >&2
        exit 1
    fi
fi
