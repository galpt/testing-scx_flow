#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Compare scx_flow against baseline and other schedulers using benchmark.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_SCRIPT="$SCRIPT_DIR/benchmark.sh"
PLOTTER_SCRIPT="$SCRIPT_DIR/mini_benchmarker_plot.py"
RESET_SCRIPT="$SCRIPT_DIR/reset_sched_ext_state.sh"
RESULTS_ROOT="$SCRIPT_DIR/comparison-results"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RESULTS_DIR="$RESULTS_ROOT/$TIMESTAMP"
KEEP_RESULTS=3
RUNS=1
SCHEDULERS=(baseline scx_cosmos scx_bpfland scx_cake scx_flow)
SUDO_KEEPALIVE_PID=""
INITIAL_SERVICE_ACTIVE=0
RESTORE_DONE=0
CURRENT_RUNTIME_LOG=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

say()  { printf "${BOLD}${CYAN}[mini]${NC} %s\n" "$1"; }
ok()   { printf "${BOLD}${GREEN}[ ok ]${NC} %s\n" "$1"; }
warn() { printf "${BOLD}${YELLOW}[warn]${NC} %s\n" "$1"; }
err()  { printf "${BOLD}${RED}[err ]${NC} %s\n" "$1" >&2; }

usage() {
    cat <<EOF
Usage: ./mini_benchmarker.sh [options]

Compare schedulers using benchmark.sh and generate CSV/PNG/SVG outputs.

Options:
  --runs N                  Number of full benchmark runs per scheduler (default: 1)
  --keep-results N          Keep only the newest N comparison result directories (default: 3)
  --results-dir DIR         Write this run into DIR instead of the default timestamped path
  --schedulers "LIST"       Space-separated scheduler list
                            Default: "baseline scx_cosmos scx_bpfland scx_cake scx_flow"
  -h, --help                Show this help

Examples:
  sudo ./mini_benchmarker.sh
  sudo ./mini_benchmarker.sh --schedulers "scx_cosmos scx_flow"
  sudo ./mini_benchmarker.sh --runs 2 --keep-results 3
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
    command -v sudo >/dev/null 2>&1 || {
        err "sudo is required to switch schedulers and run benchmarks."
        exit 1
    }
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

scheduler_is_active() {
    local name="$1"
    case "$(current_sched_ext_ops)" in
        *"$name"*) return 0 ;;
    esac
    pgrep -x "scx_${name}" >/dev/null 2>&1
}

scheduler_is_attached() {
    local name="$1"
    case "$(current_sched_ext_ops)" in
        *"$name"*)
            [ "$(current_sched_ext_state)" = "enabled" ]
            ;;
        *)
            return 1
            ;;
    esac
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
        printf '\n== systemctl show scx.service ==\n'
        run_privileged systemctl show scx.service \
            -p ActiveState \
            -p SubState \
            -p Result \
            -p ExecMainStatus \
            -p ExecMainCode \
            -p ActiveEnterTimestamp \
            || true
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
        if [ "$want" = "inactive" ] && ! scheduler_is_attached "$expected" && ! pgrep -x "scx_${expected}" >/dev/null 2>&1; then
            return 0
        fi

        attempt=$((attempt + 1))
        sleep 0.5
    done

    return 1
}

wait_for_sched_ext_idle() {
    local attempt=0
    while [ "$attempt" -lt 20 ]; do
        if [ -z "$(current_sched_ext_ops)" ]; then
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

    warn "reset_sched_ext_state.sh not available; falling back to inline cleanup"

    if service_exists && systemctl is-active --quiet scx.service; then
        say "Stopping scx.service"
        run_privileged systemctl stop scx.service || true
    fi

    for proc in scx_flow scx_cosmos scx_bpfland scx_cake scx_pandemonium pandemonium; do
        if pgrep -x "$proc" >/dev/null 2>&1; then
            say "Stopping running $proc processes"
            run_privileged pkill -x "$proc" || true
        fi
    done

    wait_for_scheduler_state flow inactive || true
    wait_for_scheduler_state cosmos inactive || true
    wait_for_scheduler_state bpfland inactive || true
    wait_for_scheduler_state cake inactive || true
    wait_for_scheduler_state pandemonium inactive || true
    wait_for_sched_ext_idle || true
}

manual_scheduler_short_name() {
    case "$1" in
        scx_flow) printf 'flow\n' ;;
        scx_cosmos) printf 'cosmos\n' ;;
        scx_bpfland) printf 'bpfland\n' ;;
        scx_cake) printf 'cake\n' ;;
        scx_pandemonium|pandemonium) printf 'pandemonium\n' ;;
        *)
            return 1
            ;;
    esac
}

scheduler_binary_path() {
    command -v "$1" 2>/dev/null || true
}

start_scheduler_manual() {
    local scheduler="$1"
    local run_name="$2"
    local short_name=""
    local binary_path=""
    local runtime_log=""

    short_name="$(manual_scheduler_short_name "$scheduler")"
    binary_path="$(scheduler_binary_path "$scheduler")"
    [ -n "$binary_path" ] || {
        err "Could not resolve binary path for $scheduler"
        return 1
    }
    runtime_log="$RESULTS_DIR/console/${scheduler}_${run_name}.log"
    CURRENT_RUNTIME_LOG="$runtime_log"
    mkdir -p "$RESULTS_DIR/console"

    say "Starting $scheduler directly"
    run_privileged env RUST_LOG=info "$binary_path" >"$runtime_log" 2>&1 &

    if wait_for_scheduler_state "$short_name" active; then
        ok "Scheduler state is ready for $scheduler"
    else
        if grep -Fq "another sched_ext scheduler is already running" "$runtime_log" 2>/dev/null; then
            err "$scheduler refused to start because another sched_ext scheduler was still active"
        fi
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
LATENCY_MAX_US=
LATENCY_SPIKES_OVER_100US=
LATENCY_SAMPLES=
THROUGHPUT_BENCHMARK=none
HACKBENCH_MEAN_SECONDS=
SYSBENCH_EVENTS_PER_SEC=
SYSBENCH_AVG_LATENCY_MS=
STRESSNG_BOGO_OPS_PER_SEC=
LOG_PATH=
SCHEDULER_UNDER_TEST=${scheduler}
RUN_INDEX=${run_index}
COMPARE_STATUS=skipped
COMPARE_NOTE=${note}
POST_RUN_SCHED_EXT_STATE=$(current_sched_ext_state)
POST_RUN_CURRENT_SCHEDULER=$(current_sched_ext_ops)
EOF
}

normalize_scheduler_name() {
    local scheduler="$1"

    case "$scheduler" in
        scx_baseline)
            printf 'baseline\n'
            ;;
        pandemonium)
            printf 'scx_pandemonium\n'
            ;;
        *)
            printf '%s\n' "$scheduler"
            ;;
    esac
}

run_single_benchmark() {
    local scheduler
    local run_index="$2"
    scheduler="$(normalize_scheduler_name "$1")"
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

    say "Running benchmark for $label"
    if run_privileged "$BENCHMARK_SCRIPT" \
        --log-file "$log_file" \
        --summary-file "$summary_file" \
        --expected-scheduler "$expected" \
        --label "$label"; then
        write_summary_metadata "$summary_file" "$scheduler" "$run_index" "completed" ""
        ok "Completed $label"
    else
        capture_scheduler_diagnostics "$scheduler" "$run_index"
        write_summary_metadata "$summary_file" "$scheduler" "$run_index" "failed" "benchmark-script-exited-nonzero"
        err "Benchmark failed for $label"
        return 0
    fi

    return 0
}

render_outputs() {
    local tagged_dir="$RESULTS_DIR/tagged"
    mkdir -p "$tagged_dir"
    python3 "$PLOTTER_SCRIPT" \
        --summaries-dir "$RESULTS_DIR/summaries" \
        --output-dir "$tagged_dir"
}

prune_old_results() {
    local old_dirs=""

    [ -d "$RESULTS_ROOT" ] || return 0
    old_dirs=$(ls -1dt "$RESULTS_ROOT"/* 2>/dev/null | tail -n +"$((KEEP_RESULTS + 1))" || true)
    [ -n "$old_dirs" ] || return 0

    warn "Pruning old comparison result directories, keeping the newest ${KEEP_RESULTS}"
    while IFS= read -r old_dir; do
        [ -n "$old_dir" ] || continue
        rm -rf "$old_dir"
    done <<EOF
$old_dirs
EOF
}

require_prereqs() {
    [ -x "$BENCHMARK_SCRIPT" ] || {
        err "Missing benchmark script: $BENCHMARK_SCRIPT"
        exit 1
    }
    [ -f "$PLOTTER_SCRIPT" ] || {
        err "Missing plotter script: $PLOTTER_SCRIPT"
        exit 1
    }
    command -v python3 >/dev/null 2>&1 || {
        err "python3 is required for chart generation."
        exit 1
    }
    service_exists || {
        err "scx.service was not found. Install the scheduler first."
        exit 1
    }
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --runs)
            RUNS="$2"
            shift 2
            ;;
        --keep-results)
            KEEP_RESULTS="$2"
            shift 2
            ;;
        --results-dir)
            RESULTS_DIR="$2"
            shift 2
            ;;
        --schedulers)
            read -r -a SCHEDULERS <<< "$2"
            for i in "${!SCHEDULERS[@]}"; do
                SCHEDULERS[$i]="$(normalize_scheduler_name "${SCHEDULERS[$i]}")"
            done
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            err "Unknown option: $1"
            usage >&2
            exit 1
            ;;
    esac
done

case "$RUNS" in
    ''|*[!0-9]*|0)
        err "--runs must be a positive integer"
        exit 1
        ;;
esac

case "$KEEP_RESULTS" in
    ''|*[!0-9]*)
        err "--keep-results must be zero or a positive integer"
        exit 1
        ;;
esac

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

restore_default_service_state
render_outputs
fix_results_ownership

if [ "$KEEP_RESULTS" -gt 0 ]; then
    prune_old_results
fi

ok "Comparison run complete"
say "Results: $RESULTS_DIR"
say "CSV   : $RESULTS_DIR/tagged/mini_benchmarker_summary.csv"
say "PNG   : $RESULTS_DIR/tagged/mini_benchmarker_comparison.png"
say "SVG   : $RESULTS_DIR/tagged/mini_benchmarker_comparison.svg"
say "Report: $RESULTS_DIR/tagged/mini_benchmarker_report.md"
