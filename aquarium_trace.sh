#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Collect trace artifacts for a single Aquarium benchmark run so scheduler
# behavior can be diagnosed from perf/frequency data instead of guessed from FPS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_SCRIPT="$SCRIPT_DIR/aquarium_benchmark.sh"
RESET_SCRIPT="$SCRIPT_DIR/reset_sched_ext_state.sh"
RESULTS_ROOT="$SCRIPT_DIR/aquarium-trace-results"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RESULTS_DIR="$RESULTS_ROOT/$TIMESTAMP"

SCHEDULER="current"
FISH_COUNT=2000
DURATION_SECONDS=45
SETTLE_SECONDS=5
HEADLESS=0
BROWSER_PATH=""
KEEP_RESULTS=3
SUDO_KEEPALIVE_PID=""
INITIAL_SERVICE_ACTIVE=0
RESTORE_DONE=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

say()  { printf "${BOLD}${CYAN}[aquarium-trace]${NC} %s\n" "$1"; }
ok()   { printf "${BOLD}${GREEN}[ ok ]${NC} %s\n" "$1"; }
warn() { printf "${BOLD}${YELLOW}[warn]${NC} %s\n" "$1"; }
err()  { printf "${BOLD}${RED}[err ]${NC} %s\n" "$1" >&2; }

CONSOLE_LOG=""
BENCHMARK_LOG=""
SUMMARY_FILE=""
PERF_DATA=""
PERF_TIMEHIST=""
PERF_LATENCY=""
TURBOSTAT_LOG=""
REPORT_FILE=""

usage() {
    cat <<EOF
Usage: sudo ./aquarium_trace.sh [options]

Switch to a chosen scheduler, run one Aquarium benchmark, and collect trace
artifacts useful for diagnosing FPS vs latency tradeoffs.

Options:
  --scheduler NAME          Scheduler to trace: current, baseline, scx_flow,
                            scx_cosmos, scx_cake, scx_bpfland
                            (default: current)
  --results-dir DIR         Write artifacts into DIR instead of a timestamped dir
  --keep-results N          Keep only the newest N trace dirs (default: ${KEEP_RESULTS})
  --fish-count N            Aquarium fish count (default: ${FISH_COUNT})
  --duration-seconds N      Measurement duration after settle (default: ${DURATION_SECONDS})
  --settle-seconds N        Warm-up duration before sampling (default: ${SETTLE_SECONDS})
  --headless                Run the browser headless
  --browser-path PATH       Override Chromium executable path
  -h, --help                Show this help
EOF
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
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
        err "sudo is required for perf sched capture and scheduler switching."
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
    mkdir -p "$RESULTS_DIR/logs" "$RESULTS_DIR/trace"
    fix_results_ownership

    CONSOLE_LOG="$RESULTS_DIR/logs/trace_console.log"
    BENCHMARK_LOG="$RESULTS_DIR/logs/aquarium_benchmark.log"
    SUMMARY_FILE="$RESULTS_DIR/logs/aquarium_summary.env"
    PERF_DATA="$RESULTS_DIR/trace/perf_sched.data"
    PERF_TIMEHIST="$RESULTS_DIR/trace/perf_sched_timehist.txt"
    PERF_LATENCY="$RESULTS_DIR/trace/perf_sched_latency.txt"
    TURBOSTAT_LOG="$RESULTS_DIR/trace/turbostat.log"
    REPORT_FILE="$RESULTS_DIR/trace_report.md"
}

cleanup() {
    restore_default_service_state
    stop_sudo_keepalive
    fix_results_ownership
}

trap cleanup EXIT

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
    local short_name=""
    local binary_path=""
    local runtime_log=""

    short_name="$(manual_scheduler_short_name "$scheduler")"
    binary_path="$(scheduler_binary_path "$scheduler")"
    [ -n "$binary_path" ] || {
        err "Could not resolve binary path for $scheduler"
        return 1
    }

    runtime_log="$RESULTS_DIR/logs/${scheduler}_runtime.log"
    say "Starting $scheduler directly"
    run_privileged env RUST_LOG=info "$binary_path" >"$runtime_log" 2>&1 &

    if wait_for_scheduler_state "$short_name" active; then
        ok "Scheduler state is ready for $scheduler"
    else
        err "Timed out waiting for scheduler state: $scheduler"
        return 1
    fi
}

benchmark_user_home() {
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        getent passwd "$SUDO_USER" | cut -d: -f6
    else
        printf '%s\n' "$HOME"
    fi
}

benchmark_target_user() {
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        printf '%s\n' "$SUDO_USER"
    else
        id -un
    fi
}

benchmark_user_path() {
    local target_home
    local target_path

    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        target_home="$(benchmark_user_home)"
        target_path="$(sudo -iu "$SUDO_USER" /bin/bash -lc 'printf "%s" "$PATH"' 2>/dev/null || true)"
        if [ -z "$target_path" ]; then
            target_path="${target_home}/.local/bin:${target_home}/.cargo/bin:/usr/local/bin:/usr/bin:/bin"
        fi
    else
        target_path="$PATH"
    fi

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

    printf '%s\n' "$target_path"
}

summary_value() {
    local key="$1"

    awk -F= -v key="$key" '
        $1 == key {
            sub(/^[^=]*=/, "", $0)
            print $0
            exit
        }
    ' "$SUMMARY_FILE"
}

write_report() {
    local bench_status="$1"
    local sched_state="$2"
    local current_ops="$3"
    local turbostat_status="$4"
    local fps_avg=""
    local fps_1p_low=""
    local p95_ms=""
    local jank_33=""
    local bogo_ops=""

    {
        printf '# Aquarium Trace Report\n\n'
        printf '## Run\n\n'
        printf -- '- Scheduler request: `%s`\n' "$SCHEDULER"
        printf -- '- sched_ext state after run: `%s`\n' "$sched_state"
        printf -- '- Active scheduler after run: `%s`\n' "${current_ops:-none}"
        printf -- '- Benchmark status: `%s`\n' "$bench_status"
        printf -- '- Turbostat: `%s`\n' "$turbostat_status"
        printf '\n'

        if [ -f "$SUMMARY_FILE" ]; then
            fps_avg="$(summary_value AQUARIUM_RAF_AVG_FPS)"
            fps_1p_low="$(summary_value AQUARIUM_RAF_1P_LOW_FPS)"
            p95_ms="$(summary_value AQUARIUM_P95_FRAME_MS)"
            jank_33="$(summary_value AQUARIUM_JANK_OVER_33MS)"
            bogo_ops="$(summary_value STRESSNG_BOGO_OPS_PER_SEC)"
            printf '## Benchmark Summary\n\n'
            printf -- '- Average FPS: `%s`\n' "${fps_avg:-unknown}"
            printf -- '- 1%% low FPS: `%s`\n' "${fps_1p_low:-unknown}"
            printf -- '- P95 frame ms: `%s`\n' "${p95_ms:-unknown}"
            printf -- '- Jank >33ms: `%s`\n' "${jank_33:-unknown}"
            printf -- '- stress-ng bogo ops/s: `%s`\n' "${bogo_ops:-unknown}"
            printf '\n'
        fi

        printf '## Artifacts\n\n'
        printf -- '- Benchmark log: `%s`\n' "$BENCHMARK_LOG"
        printf -- '- Benchmark summary: `%s`\n' "$SUMMARY_FILE"
        printf -- '- perf sched data: `%s`\n' "$PERF_DATA"
        printf -- '- perf sched timehist: `%s`\n' "$PERF_TIMEHIST"
        printf -- '- perf sched latency: `%s`\n' "$PERF_LATENCY"
        if [ "$turbostat_status" = "captured" ]; then
            printf -- '- turbostat log: `%s`\n' "$TURBOSTAT_LOG"
        fi
        printf '\n'

        printf '## Next Steps\n\n'
        printf -- '- Compare `%s` and `%s` side by side to see whether low FPS lines up with fragmented run time, worse wake-to-run delay, or lower effective CPU frequency.\n' \
            "$PERF_TIMEHIST" "$TURBOSTAT_LOG"
        printf -- '- If `scx_flow` shows much lower Bzy_MHz / Busy%% than `scx_cosmos`, investigate cpuperf integration first.\n'
        printf -- '- If frequency looks similar but render threads keep getting chopped into short runs, investigate `stable_local` / continuity behavior first.\n'
    } > "$REPORT_FILE"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --scheduler)
            SCHEDULER="$2"
            shift 2
            ;;
        --results-dir)
            RESULTS_DIR="$2"
            shift 2
            ;;
        --keep-results)
            KEEP_RESULTS="$2"
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
            usage
            exit 1
            ;;
    esac
done

ensure_sudo_ready
start_sudo_keepalive
capture_initial_state
prepare_results_dirs

exec > >(tee -a "$CONSOLE_LOG") 2>&1

say "Results dir: $RESULTS_DIR"

have_cmd perf || {
    err "perf is required for aquarium_trace.sh"
    exit 1
}

case "$SCHEDULER" in
    current)
        say "Tracing current scheduler state without switching"
        ;;
    baseline)
        stop_all_schedulers
        ok "Baseline CFS state is ready"
        ;;
    scx_flow|scx_cosmos|scx_cake|scx_bpfland)
        stop_all_schedulers
        start_scheduler_manual "$SCHEDULER"
        ;;
    *)
        err "Unsupported scheduler: $SCHEDULER"
        exit 1
        ;;
esac

current_state="$(current_sched_ext_state)"
current_ops="$(current_sched_ext_ops)"
[ -n "$current_ops" ] || current_ops="none"
say "sched_ext state: $current_state"
say "active scheduler: $current_ops"

benchmark_label="aquarium trace (${SCHEDULER})"
expected_scheduler="any"
case "$SCHEDULER" in
    baseline) expected_scheduler="none" ;;
    current)
        if [ "$current_ops" != "none" ]; then
            expected_scheduler="$current_ops"
        fi
        ;;
    *) expected_scheduler="$SCHEDULER" ;;
esac

turbostat_status="skipped"
if have_cmd turbostat; then
    trace_seconds=$((DURATION_SECONDS + SETTLE_SECONDS + 20))
    say "Starting turbostat capture"
    run_privileged bash -lc \
        "timeout ${trace_seconds}s turbostat --quiet --interval 1 --out '$TURBOSTAT_LOG' >/dev/null 2>&1" &
    TURBOSTAT_PID=$!
    turbostat_status="capturing"
else
    warn "turbostat not found; frequency trace will be skipped"
fi

benchmark_home="$(benchmark_user_home)"
benchmark_path="$(benchmark_user_path)"
benchmark_user="$(benchmark_target_user)"
benchmark_cmd=(
    "$BENCHMARK_SCRIPT"
    --log-file "$BENCHMARK_LOG"
    --summary-file "$SUMMARY_FILE"
    --expected-scheduler "$expected_scheduler"
    --label "$benchmark_label"
    --fish-count "$FISH_COUNT"
    --duration-seconds "$DURATION_SECONDS"
    --settle-seconds "$SETTLE_SECONDS"
)

if [ "$HEADLESS" -eq 1 ]; then
    benchmark_cmd+=(--headless)
fi
if [ -n "$BROWSER_PATH" ]; then
    benchmark_cmd+=(--browser-path "$BROWSER_PATH")
fi

if [ "$benchmark_user" != "root" ]; then
    perf_child_cmd=(
        sudo -u "$benchmark_user"
        env
        DISPLAY="${DISPLAY:-}"
        WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
        XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"
        XAUTHORITY="${XAUTHORITY:-}"
        HOME="$benchmark_home"
        PATH="$benchmark_path"
        "${benchmark_cmd[@]}"
    )
else
    perf_child_cmd=("${benchmark_cmd[@]}")
fi

say "Recording perf sched trace"
benchmark_status="completed"
if ! run_privileged perf sched record -o "$PERF_DATA" -- "${perf_child_cmd[@]}"; then
    benchmark_status="failed"
    warn "Benchmark exited non-zero while tracing"
fi

if [ -n "${TURBOSTAT_PID:-}" ]; then
    wait "$TURBOSTAT_PID" 2>/dev/null || true
    if [ -s "$TURBOSTAT_LOG" ]; then
        turbostat_status="captured"
    else
        turbostat_status="failed"
    fi
fi

if [ -s "$PERF_DATA" ]; then
    say "Rendering perf sched reports"
    if ! run_privileged perf sched timehist -i "$PERF_DATA" > "$PERF_TIMEHIST" 2>&1; then
        warn "perf sched timehist failed; see $PERF_TIMEHIST"
    fi
    if ! run_privileged perf sched latency -i "$PERF_DATA" > "$PERF_LATENCY" 2>&1; then
        warn "perf sched latency failed; see $PERF_LATENCY"
    fi
else
    benchmark_status="failed"
    warn "perf.data was not produced"
fi

write_report "$benchmark_status" "$(current_sched_ext_state)" "$(current_sched_ext_ops)" "$turbostat_status"

fix_results_ownership

if [ "$KEEP_RESULTS" -gt 0 ] && [ -d "$RESULTS_ROOT" ]; then
    find "$RESULTS_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
        | sort -nr \
        | awk -v keep="$KEEP_RESULTS" 'NR > keep { print $2 }' \
        | while read -r old_dir; do
            [ -n "$old_dir" ] || continue
            warn "Pruning old aquarium trace dir: $(basename "$old_dir")"
            rm -rf -- "$old_dir"
        done
fi

ok "Trace run complete"
say "Results: $RESULTS_DIR"
say "Report : $REPORT_FILE"
say "perf   : $PERF_DATA"
say "timehist: $PERF_TIMEHIST"
say "latency: $PERF_LATENCY"
if [ "$turbostat_status" = "captured" ]; then
    say "turbostat: $TURBOSTAT_LOG"
fi
