#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Compare schedulers using the WebGL Aquarium under stress and render charts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_SCRIPT="$SCRIPT_DIR/aquarium_benchmark.sh"
PLOTTER_SCRIPT="$SCRIPT_DIR/aquarium_benchmarker_plot.py"
RESET_SCRIPT="$SCRIPT_DIR/reset_sched_ext_state.sh"
RESULTS_ROOT="$SCRIPT_DIR/aquarium-comparison-results"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RESULTS_DIR="$RESULTS_ROOT/$TIMESTAMP"
KEEP_RESULTS=3
RUNS=1
WARMUP_RUNS=1
FISH_COUNT=2000
DURATION_SECONDS=45
SETTLE_SECONDS=5
HEADLESS=0
BROWSER_PATH=""
SCHEDULERS=(baseline scx_cosmos scx_bpfland scx_cake scx_flow)
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

say()  { printf "${BOLD}${CYAN}[aquarium-mini]${NC} %s\n" "$1"; }
ok()   { printf "${BOLD}${GREEN}[ ok ]${NC} %s\n" "$1"; }
warn() { printf "${BOLD}${YELLOW}[warn]${NC} %s\n" "$1"; }
err()  { printf "${BOLD}${RED}[err ]${NC} %s\n" "$1" >&2; }

usage() {
    cat <<EOF
Usage: ./aquarium_benchmarker.sh [options]

Compare schedulers using a WebGL Aquarium + stress-ng benchmark and generate
CSV/PNG/SVG outputs.

Options:
  --runs N                  Number of benchmark runs per scheduler (default: 1)
  --warmup-runs N           Number of uncounted warmup runs per scheduler (default: 1)
  --no-warmup               Disable uncounted warmup runs
  --keep-results N          Keep only the newest N result directories (default: 3)
  --results-dir DIR         Write this run into DIR instead of the default timestamped path
  --schedulers "LIST"       Space-separated scheduler list
                            Default: "baseline scx_cosmos scx_bpfland scx_cake scx_flow"
  --fish-count N            Aquarium fish count (default: ${FISH_COUNT})
  --duration-seconds N      Measurement duration after settle (default: ${DURATION_SECONDS})
  --settle-seconds N        Warm-up duration before sampling (default: ${SETTLE_SECONDS})
  --headless                Run browser headless (not recommended for desktop comparisons)
  --browser-path PATH       Override Chromium executable path
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

run_as_benchmark_user() {
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        local target_home
        local target_path
        target_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
        target_path="$(sudo -iu "$SUDO_USER" /bin/bash -lc 'printf "%s" "$PATH"' 2>/dev/null || true)"
        if [ -z "$target_path" ]; then
            target_path="${target_home}/.local/bin:${target_home}/.cargo/bin:/usr/local/bin:/usr/bin:/bin"
        else
            case ":$target_path:" in
                *:/usr/local/bin:*) ;;
                *) target_path="${target_path}:/usr/local/bin" ;;
            esac
            case ":$target_path:" in
                *:/usr/bin:*) ;;
                *) target_path="${target_path}:/usr/bin" ;;
            esac
            case ":$target_path:" in
                *:/bin:*) ;;
                *) target_path="${target_path}:/bin" ;;
            esac
        fi
        sudo -u "$SUDO_USER" \
            env \
            DISPLAY="${DISPLAY:-}" \
            WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
            XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
            XAUTHORITY="${XAUTHORITY:-}" \
            HOME="${target_home}" \
            PATH="${target_path}" \
            "$@"
    else
        "$@"
    fi
}

ensure_sudo_ready() {
    if [ "$(id -u)" -eq 0 ]; then
        return
    fi
    command -v sudo >/dev/null 2>&1 || {
        err "sudo is required to switch schedulers and reset sched_ext."
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

prepare_results_dirs() {
    mkdir -p "$RESULTS_DIR/logs" "$RESULTS_DIR/summaries" \
        "$RESULTS_DIR/warmups/logs" "$RESULTS_DIR/warmups/summaries"
    fix_results_ownership
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

manual_scheduler_short_name() {
    case "$1" in
        scx_flow) printf 'flow\n' ;;
        scx_cosmos) printf 'cosmos\n' ;;
        scx_bpfland) printf 'bpfland\n' ;;
        scx_cake) printf 'cake\n' ;;
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
AQUARIUM_FISH_COUNT=
AQUARIUM_DURATION_SECONDS=
AQUARIUM_SETTLE_SECONDS=
AQUARIUM_RAF_AVG_FPS=
AQUARIUM_RAF_MEDIAN_FPS=
AQUARIUM_RAF_1P_LOW_FPS=
AQUARIUM_UI_AVG_FPS=
AQUARIUM_UI_LAST_FPS=
AQUARIUM_P95_FRAME_MS=
AQUARIUM_P99_FRAME_MS=
AQUARIUM_JANK_OVER_33MS=
AQUARIUM_JANK_OVER_50MS=
AQUARIUM_JANK_OVER_100MS=
AQUARIUM_FRAME_SAMPLES=
AQUARIUM_CANVAS_WIDTH=
AQUARIUM_CANVAS_HEIGHT=
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

run_single_benchmark() {
    local scheduler="$1"
    local run_index="$2"
    local phase="${3:-measured}"
    local log_file="$RESULTS_DIR/logs/${scheduler}_run${run_index}.log"
    local summary_file="$RESULTS_DIR/summaries/${scheduler}_run${run_index}.env"
    local label="${scheduler} run ${run_index}"
    local expected="$scheduler"
    local run_name="${scheduler}_run$(printf '%02d' "$run_index")"

    if [ "$phase" = "warmup" ]; then
        log_file="$RESULTS_DIR/warmups/logs/${scheduler}_warmup${run_index}.log"
        summary_file="$RESULTS_DIR/warmups/summaries/${scheduler}_warmup${run_index}.env"
        label="${scheduler} warmup ${run_index}"
        run_name="${scheduler}_warmup$(printf '%02d' "$run_index")"
    fi

    if [ "$scheduler" = "baseline" ]; then
        expected="none"
    fi

    if [ "$scheduler" != "baseline" ] && ! command -v "$scheduler" >/dev/null 2>&1; then
        warn "Skipping $scheduler $phase $run_index because the binary is not installed"
        write_skipped_summary "$summary_file" "$scheduler" "$run_index" "scheduler-binary-not-found"
        return 0
    fi

    say "Running Aquarium benchmark for $label"
    local bench_cmd=(
        "$BENCHMARK_SCRIPT"
        --log-file "$log_file"
        --summary-file "$summary_file"
        --expected-scheduler "$expected"
        --label "$label"
        --fish-count "$FISH_COUNT"
        --duration-seconds "$DURATION_SECONDS"
        --settle-seconds "$SETTLE_SECONDS"
    )
    if [ "$HEADLESS" -eq 1 ]; then
        bench_cmd+=(--headless)
    fi
    if [ -n "$BROWSER_PATH" ]; then
        bench_cmd+=(--browser-path "$BROWSER_PATH")
    fi

    if run_as_benchmark_user "${bench_cmd[@]}"; then
        if [ "$phase" = "warmup" ]; then
            write_summary_metadata "$summary_file" "$scheduler" "$run_index" "warmup" ""
            ok "Completed $label (uncounted)"
        else
            write_summary_metadata "$summary_file" "$scheduler" "$run_index" "completed" ""
            ok "Completed $label"
        fi
    else
        if [ "$phase" = "warmup" ]; then
            write_summary_metadata "$summary_file" "$scheduler" "$run_index" "warmup-failed" "aquarium-benchmark-exited-nonzero"
            warn "Warmup benchmark failed for $label"
        else
            write_summary_metadata "$summary_file" "$scheduler" "$run_index" "failed" "aquarium-benchmark-exited-nonzero"
            err "Aquarium benchmark failed for $label"
        fi
        return 0
    fi

    return 0
}

render_outputs() {
    local tagged_dir="$RESULTS_DIR/tagged"
    mkdir -p "$tagged_dir"
    cat > "$RESULTS_DIR/meta.env" <<EOF
RUNS=${RUNS}
WARMUP_RUNS=${WARMUP_RUNS}
FISH_COUNT=${FISH_COUNT}
DURATION_SECONDS=${DURATION_SECONDS}
SETTLE_SECONDS=${SETTLE_SECONDS}
EOF
    python3 "$PLOTTER_SCRIPT" \
        --summaries-dir "$RESULTS_DIR/summaries" \
        --meta-file "$RESULTS_DIR/meta.env" \
        --output-dir "$tagged_dir"
}

prune_old_results() {
    local old_dirs=""

    [ -d "$RESULTS_ROOT" ] || return 0
    old_dirs=$(ls -1dt "$RESULTS_ROOT"/* 2>/dev/null | tail -n +"$((KEEP_RESULTS + 1))" || true)
    [ -n "$old_dirs" ] || return 0

    warn "Pruning old aquarium result directories, keeping the newest ${KEEP_RESULTS}"
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
    command -v node >/dev/null 2>&1 || {
        err "node is required for Aquarium browser automation."
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
        --warmup-runs)
            WARMUP_RUNS="$2"
            shift 2
            ;;
        --no-warmup)
            WARMUP_RUNS=0
            shift
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
            shift 2
            ;;
        --fish-count)
            FISH_COUNT="$2"
            shift 2
            ;;
        --duration-seconds)
            DURATION_SECONDS="$2"
            shift 2
            ;;
        --settle-seconds)
            SETTLE_SECONDS="$2"
            shift 2
            ;;
        --headless)
            HEADLESS=1
            shift
            ;;
        --browser-path)
            BROWSER_PATH="$2"
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

case "$WARMUP_RUNS" in
    ''|*[!0-9]*)
        err "--warmup-runs must be zero or a positive integer"
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

prepare_results_dirs

say "Results directory: $RESULTS_DIR"
say "Schedulers: ${SCHEDULERS[*]}"
say "Fish count: $FISH_COUNT"
say "Warmup runs per scheduler: $WARMUP_RUNS"

for scheduler in "${SCHEDULERS[@]}"; do
    stop_all_schedulers

    if [ "$scheduler" != "baseline" ]; then
        if ! start_scheduler_manual "$scheduler" "$scheduler"; then
            for run_index in $(seq 1 "$RUNS"); do
                write_skipped_summary "$RESULTS_DIR/summaries/${scheduler}_run${run_index}.env" \
                    "$scheduler" "$run_index" "scheduler-activation-timeout"
            done
            continue
        fi
    fi

    if [ "$WARMUP_RUNS" -gt 0 ]; then
        for warmup_index in $(seq 1 "$WARMUP_RUNS"); do
            run_single_benchmark "$scheduler" "$warmup_index" warmup
        done
    fi

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

ok "Aquarium comparison run complete"
say "Results: $RESULTS_DIR"
say "CSV   : $RESULTS_DIR/tagged/aquarium_benchmarker_summary.csv"
say "PNG   : $RESULTS_DIR/tagged/aquarium_benchmarker_comparison.png"
say "SVG   : $RESULTS_DIR/tagged/aquarium_benchmarker_comparison.svg"
say "Report: $RESULTS_DIR/tagged/aquarium_benchmarker_report.md"
