#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Compare schedulers using a sustained long-run periodic latency probe.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_SCRIPT="$SCRIPT_DIR/longrun_benchmark.sh"
PLOTTER_SCRIPT="$SCRIPT_DIR/longrun_benchmarker_plot.py"
RESET_SCRIPT="$SCRIPT_DIR/reset_sched_ext_state.sh"
RESULTS_ROOT="$SCRIPT_DIR/longrun-comparison-results"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RESULTS_DIR="$RESULTS_ROOT/$TIMESTAMP"
KEEP_RESULTS=3
RUNS=1
SCHEDULERS=(baseline scx_cosmos scx_bpfland scx_flow)
DURATION_SECONDS=60
PERIOD_US=1000
WORKERS=4
LATE_THRESHOLD_US=1000
CPU_HOGS=""
CPU_LOAD=85
SUDO_KEEPALIVE_PID=""
INITIAL_SERVICE_ACTIVE=0
RESTORE_DONE=0
CURRENT_RUNTIME_LOG=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

say()  { printf "${BOLD}${CYAN}[longrun-mini]${NC} %s\n" "$1"; }
ok()   { printf "${BOLD}${GREEN}[ ok ]${NC} %s\n" "$1"; }
warn() { printf "${BOLD}${YELLOW}[warn]${NC} %s\n" "$1"; }
err()  { printf "${BOLD}${RED}[err ]${NC} %s\n" "$1" >&2; }

usage() {
    cat <<EOF
Usage: ./longrun_benchmarker.sh [options]

Compare schedulers using a sustained long-run periodic latency benchmark and
generate CSV/PNG/SVG outputs.

Options:
  --runs N                  Number of benchmark runs per scheduler (default: 1)
  --keep-results N          Keep only the newest N result directories (default: 3)
  --results-dir DIR         Write this run into DIR instead of the default timestamped path
  --schedulers "LIST"       Space-separated scheduler list
                            Default: "baseline scx_cosmos scx_bpfland scx_flow"
  --duration-seconds N      Benchmark duration (default: ${DURATION_SECONDS})
  --period-us N             Probe period in microseconds (default: ${PERIOD_US})
  --workers N               Number of probe workers (default: ${WORKERS})
  --late-threshold-us N     Soft lateness threshold in microseconds (default: ${LATE_THRESHOLD_US})
  --cpu-hogs N              Number of stress-ng CPU hogs (default: same as workers)
  --cpu-load N              stress-ng CPU load percentage (default: ${CPU_LOAD})
  -h, --help                Show this help
EOF
}

run_privileged() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

ensure_sudo_ready() {
    if [ "$(id -u)" -eq 0 ]; then
        return
    fi
    command -v sudo >/dev/null 2>&1 || { err "sudo is required."; exit 1; }
    say "Refreshing sudo credentials"
    sudo -v
}

start_sudo_keepalive() {
    if [ "$(id -u)" -eq 0 ]; then
        return
    fi
    (
        while true; do
            sudo -n true >/dev/null 2>&1 || exit 0
            sleep 60
        done
    ) &
    SUDO_KEEPALIVE_PID=$!
}

stop_sudo_keepalive() {
    if [ -n "$SUDO_KEEPALIVE_PID" ] && kill -0 "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1; then
        kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
    SUDO_KEEPALIVE_PID=""
}

current_sched_ext_state() {
    cat /sys/kernel/sched_ext/state 2>/dev/null || echo "unknown"
}

current_sched_ext_ops() {
    cat /sys/kernel/sched_ext/root/ops 2>/dev/null || true
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
        "$expected"|"$expected"_*|"$short_name"|"$short_name"_*) return 0 ;;
        *) return 1 ;;
    esac
}

scheduler_is_attached() {
    local name="$1"
    scheduler_matches_name "$(current_sched_ext_ops)" "$name" &&
        [ "$(current_sched_ext_state)" = "enabled" ]
}

service_exists() {
    command -v systemctl >/dev/null 2>&1 && systemctl cat scx.service >/dev/null 2>&1
}

capture_initial_state() {
    if service_exists && systemctl is-active --quiet scx.service; then
        INITIAL_SERVICE_ACTIVE=1
    fi
}

capture_scheduler_diagnostics() {
    local scheduler="$1"
    local run_index="$2"
    local diag_file="$RESULTS_DIR/diagnostics/${scheduler}_run${run_index}.log"

    mkdir -p "$RESULTS_DIR/diagnostics"
    {
        printf 'timestamp=%s\n' "$(date -Iseconds)"
        printf 'scheduler=%s\n' "$scheduler"
        printf 'sched_ext_state=%s\n' "$(current_sched_ext_state)"
        printf 'sched_ext_ops=%s\n' "$(current_sched_ext_ops)"
        printf '\n== systemctl status scx.service ==\n'
        run_privileged systemctl status scx.service --no-pager || true
        printf '\n== journalctl -u scx.service ==\n'
        run_privileged journalctl -u scx.service -n 120 --no-pager || true
        printf '\n== journalctl -k ==\n'
        run_privileged journalctl -k -n 120 --no-pager || true
    } > "$diag_file" 2>&1
}

restore_default_service_state() {
    if [ "$RESTORE_DONE" -eq 1 ]; then
        return
    fi
    RESTORE_DONE=1

    if service_exists; then
        run_privileged systemctl unset-environment SCX_SCHEDULER_OVERRIDE >/dev/null 2>&1 || true
        run_privileged systemctl unset-environment SCX_FLAGS_OVERRIDE >/dev/null 2>&1 || true
        if [ "$INITIAL_SERVICE_ACTIVE" -eq 1 ]; then
            run_privileged systemctl restart scx.service >/dev/null 2>&1 || true
        else
            run_privileged systemctl stop scx.service >/dev/null 2>&1 || true
        fi
    fi
}

fix_results_ownership() {
    if [ -z "${SUDO_USER:-}" ] || [ ! -d "$RESULTS_DIR" ]; then
        return
    fi
    run_privileged chown -R "${SUDO_USER}:$(id -gn "$SUDO_USER")" "$RESULTS_DIR" >/dev/null 2>&1 || true
}

cleanup() {
    restore_default_service_state
    stop_sudo_keepalive
    fix_results_ownership
}

trap cleanup EXIT

wait_for_scheduler_state() {
    local expected="$1"
    local attempt=0
    local want="${2:-active}"

    while [ "$attempt" -lt 60 ]; do
        if [ "$want" = "active" ] && scheduler_is_attached "$expected"; then
            return 0
        fi
        if [ "$want" = "inactive" ] && ! scheduler_is_attached "$expected" && ! pgrep -x "$expected" >/dev/null 2>&1; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 0.5
    done

    return 1
}

stop_all_schedulers() {
    run_privileged systemctl unset-environment SCX_SCHEDULER_OVERRIDE >/dev/null 2>&1 || true
    run_privileged systemctl unset-environment SCX_FLAGS_OVERRIDE >/dev/null 2>&1 || true

    if [ -x "$RESET_SCRIPT" ]; then
        say "Resetting sched_ext state"
        run_privileged "$RESET_SCRIPT"
        return
    fi

    err "Missing reset helper: $RESET_SCRIPT"
    exit 1
}

scheduler_binary_path() {
    command -v "$1" 2>/dev/null || true
}

start_scheduler_manual() {
    local scheduler="$1"
    local run_name="$2"
    local binary_path=""
    local runtime_log=""

    binary_path="$(scheduler_binary_path "$scheduler")"
    [ -n "$binary_path" ] || { err "Could not resolve binary path for $scheduler"; return 1; }

    runtime_log="$RESULTS_DIR/console/${scheduler}_${run_name}.log"
    CURRENT_RUNTIME_LOG="$runtime_log"
    mkdir -p "$RESULTS_DIR/console"

    say "Starting $scheduler directly"
    run_privileged env RUST_LOG=info "$binary_path" >"$runtime_log" 2>&1 &

    if wait_for_scheduler_state "$scheduler" active; then
        ok "Scheduler state is ready for $scheduler"
    else
        err "Timed out waiting for scheduler state: $scheduler"
        return 1
    fi
}

write_summary_metadata() {
    local summary_file="$1"
    local scheduler="$2"
    local run_index="$3"
    local compare_status="$4"
    local note="$5"

    {
        printf 'SCHEDULER_UNDER_TEST=%s\n' "$scheduler"
        printf 'RUN_INDEX=%s\n' "$run_index"
        printf 'COMPARE_STATUS=%s\n' "$compare_status"
        printf 'COMPARE_NOTE=%s\n' "$note"
        printf 'POST_RUN_SCHED_EXT_STATE=%s\n' "$(current_sched_ext_state)"
        printf 'POST_RUN_CURRENT_SCHEDULER=%s\n' "$(current_sched_ext_ops)"
    } >> "$summary_file"
}

write_skipped_summary() {
    local summary_file="$1"
    local scheduler="$2"
    local run_index="$3"
    local note="$4"

    cat > "$summary_file" <<EOF
BENCHMARK_LABEL=${scheduler} run ${run_index}
EXPECTED_SCHEDULER=${scheduler}
SCHED_EXT_STATE=$(current_sched_ext_state)
CURRENT_SCHEDULER=$(current_sched_ext_ops)
LONGRUN_DURATION_SECONDS=
LONGRUN_PERIOD_US=
LONGRUN_TARGET_HZ=
LONGRUN_WORKERS=
LONGRUN_CPUS=
LONGRUN_SAMPLES=
LONGRUN_MEAN_LATE_US=
LONGRUN_P95_LATE_US=
LONGRUN_P99_LATE_US=
LONGRUN_MAX_LATE_US=
LONGRUN_MISS_COUNT=
LONGRUN_MISS_RATIO_PCT=
LONGRUN_LATE_THRESHOLD_US=
LONGRUN_LATE_OVER_THRESHOLD_COUNT=
LONGRUN_LATE_OVER_THRESHOLD_RATIO_PCT=
CPU_HOGS=
CPU_LOAD=
LOG_PATH=
RAW_JSON_PATH=
SCHEDULER_UNDER_TEST=${scheduler}
RUN_INDEX=${run_index}
COMPARE_STATUS=skipped
COMPARE_NOTE=${note}
POST_RUN_SCHED_EXT_STATE=$(current_sched_ext_state)
POST_RUN_CURRENT_SCHEDULER=$(current_sched_ext_ops)
EOF
}

run_single_benchmark() {
    local scheduler="$1"
    local run_index="$2"
    local log_file="$RESULTS_DIR/logs/${scheduler}_run${run_index}.log"
    local summary_file="$RESULTS_DIR/summaries/${scheduler}_run${run_index}.env"
    local label="${scheduler} run ${run_index}"
    local expected="$scheduler"
    local run_name="${scheduler}_run$(printf '%02d' "$run_index")"

    if [ "$scheduler" = "baseline" ]; then
        expected="none"
    fi

    if [ "$scheduler" != "baseline" ] && ! command -v "$scheduler" >/dev/null 2>&1; then
        warn "Skipping $scheduler run $run_index because the binary is not installed"
        write_skipped_summary "$summary_file" "$scheduler" "$run_index" "scheduler-binary-not-found"
        return 0
    fi

    stop_all_schedulers

    if [ "$scheduler" != "baseline" ]; then
        if ! start_scheduler_manual "$scheduler" "$run_name"; then
            warn "Activation failed for $scheduler run $run_index; capturing diagnostics and continuing"
            capture_scheduler_diagnostics "$scheduler" "$run_index"
            write_skipped_summary "$summary_file" "$scheduler" "$run_index" "scheduler-activation-timeout"
            return 0
        fi
    fi

    say "Running longrun benchmark for $label"
    if run_privileged "$BENCHMARK_SCRIPT" \
        --log-file "$log_file" \
        --summary-file "$summary_file" \
        --expected-scheduler "$expected" \
        --label "$label" \
        --duration-seconds "$DURATION_SECONDS" \
        --period-us "$PERIOD_US" \
        --workers "$WORKERS" \
        --late-threshold-us "$LATE_THRESHOLD_US" \
        --cpu-hogs "${CPU_HOGS:-$WORKERS}" \
        --cpu-load "$CPU_LOAD"; then
        write_summary_metadata "$summary_file" "$scheduler" "$run_index" "completed" ""
        ok "Completed $label"
    else
        capture_scheduler_diagnostics "$scheduler" "$run_index"
        write_summary_metadata "$summary_file" "$scheduler" "$run_index" "failed" "benchmark-script-exited-nonzero"
        err "Benchmark failed for $label"
        return 0
    fi
}

render_outputs() {
    local tagged_dir="$RESULTS_DIR/tagged"
    mkdir -p "$tagged_dir"
    python3 "$PLOTTER_SCRIPT" --summaries-dir "$RESULTS_DIR/summaries" --output-dir "$tagged_dir"
}

prune_old_results() {
    local old_dirs=""

    [ -d "$RESULTS_ROOT" ] || return 0
    old_dirs=$(ls -1dt "$RESULTS_ROOT"/* 2>/dev/null | tail -n +"$((KEEP_RESULTS + 1))" || true)
    [ -n "$old_dirs" ] || return 0

    warn "Pruning old longrun result directories, keeping the newest ${KEEP_RESULTS}"
    while IFS= read -r old_dir; do
        [ -n "$old_dir" ] || continue
        rm -rf "$old_dir"
    done <<EOF
$old_dirs
EOF
}

require_prereqs() {
    [ -x "$BENCHMARK_SCRIPT" ] || { err "Missing longrun benchmark script: $BENCHMARK_SCRIPT"; exit 1; }
    [ -f "$PLOTTER_SCRIPT" ] || { err "Missing plotter script: $PLOTTER_SCRIPT"; exit 1; }
    [ -x "$SCRIPT_DIR/longrun_probe.py" ] || { err "Missing or non-executable longrun probe helper: $SCRIPT_DIR/longrun_probe.py"; exit 1; }
    command -v python3 >/dev/null 2>&1 || { err "python3 is required for chart generation."; exit 1; }
    service_exists || { err "scx.service was not found. Install the scheduler first."; exit 1; }
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --runs) RUNS="$2"; shift 2 ;;
        --keep-results) KEEP_RESULTS="$2"; shift 2 ;;
        --results-dir) RESULTS_DIR="$2"; shift 2 ;;
        --schedulers) read -r -a SCHEDULERS <<< "$2"; shift 2 ;;
        --duration-seconds) DURATION_SECONDS="$2"; shift 2 ;;
        --period-us) PERIOD_US="$2"; shift 2 ;;
        --workers) WORKERS="$2"; shift 2 ;;
        --late-threshold-us) LATE_THRESHOLD_US="$2"; shift 2 ;;
        --cpu-hogs) CPU_HOGS="$2"; shift 2 ;;
        --cpu-load) CPU_LOAD="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) err "Unknown option: $1"; usage >&2; exit 1 ;;
    esac
done

require_prereqs
ensure_sudo_ready
start_sudo_keepalive
capture_initial_state

mkdir -p "$RESULTS_DIR/logs" "$RESULTS_DIR/summaries"

say "Results directory: $RESULTS_DIR"
say "Schedulers: ${SCHEDULERS[*]}"

for scheduler in "${SCHEDULERS[@]}"; do
    for run_index in $(seq 1 "$RUNS"); do
        run_single_benchmark "$scheduler" "$run_index"
    done
done

render_outputs
prune_old_results

ok "Longrun benchmark comparison complete"
say "CSV/PNG/SVG/report written to: $RESULTS_DIR/tagged"
