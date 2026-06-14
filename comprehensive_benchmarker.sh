#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Comprehensive multi-scheduler benchmark suite (8 workloads).
# Inspired by the pandemonium v5.13.0 comparison table, extended for
# scx_flow v3.0.4.
#
# Usage: sudo ./comprehensive_benchmarker.sh [options]
#
# Options:
#   --runs N                  Number of benchmark runs per scheduler (default: 1)
#   --keep-results N          Keep only the newest N result directories (default: 3)
#   --results-dir DIR         Write this run into DIR instead of the default timestamped path
#   --schedulers "LIST"       Space-separated scheduler list
#                             Default: "baseline scx_cosmos scx_bpfland scx_flow"
#   --skip-workload LIST      Comma-separated workload names to skip
#   -h, --help                Show this help
#
# Workloads:
#   1. stress-ng-cpu-cache-mem    Combined CPU + cache + memory stress
#   2. perf-sched-msg-fork        perf bench sched messaging (fork)
#   3. perf-memcpy                perf bench mem memcpy
#   4. argon2-hashing             Argon2 password hash
#   5. xz-compression             xz -9e compression
#   6. primes                     Prime number computation (sysbench)
#   7. x265-encoding              x265 video encode
#   8. ffmpeg-compilation         Build ffmpeg from source (optional, needs git)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESET_SCRIPT="$SCRIPT_DIR/reset_sched_ext_state.sh"
RESULTS_ROOT="$SCRIPT_DIR/comprehensive-bench-results"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RESULTS_DIR="$RESULTS_ROOT/$TIMESTAMP"
KEEP_RESULTS=3
RUNS=1
SCHEDULERS=(baseline scx_cosmos scx_bpfland scx_flow)
SKIP_WORKLOADS=""
SUDO_KEEPALIVE_PID=""
INITIAL_SERVICE_ACTIVE=0
RESTORE_DONE=0
CURRENT_RUNTIME_LOG=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
say()  { printf "${BOLD}${CYAN}[comprehensive]${NC} %s\n" "$1"; }
ok()   { printf "${BOLD}${GREEN}[ ok ]${NC} %s\n" "$1"; }
warn() { printf "${BOLD}${YELLOW}[warn]${NC} %s\n" "$1"; }
err()  { printf "${BOLD}${RED}[err ]${NC} %s\n" "$1" >&2; }

ALL_WORKLOADS=(
    stress-ng-cpu-cache-mem
    perf-sched-msg-fork
    perf-memcpy
    argon2-hashing
    xz-compression
    primes
    x265-encoding
    ffmpeg-compilation
)

usage() {
    cat <<'EOF'
Usage: sudo ./comprehensive_benchmarker.sh [options]

Options:
  --runs N                  Number of benchmark runs per scheduler (default: 1)
  --keep-results N          Keep only the newest N result directories (default: 3)
  --results-dir DIR         Write this run into DIR instead of the default timestamped path
  --schedulers "LIST"       Space-separated scheduler list
                            Default: "baseline scx_cosmos scx_bpfland scx_flow"
  --skip-workload LIST      Comma-separated workloads to skip (ffmpeg-compilation,etc)
  --clean-cache             Remove the cache directory (ffmpeg source, etc.)
  -h, --help                Show this help

Workloads:
  1. stress-ng-cpu-cache-mem
  2. perf-sched-msg-fork
  3. perf-memcpy
  4. argon2-hashing
  5. xz-compression
  6. primes
  7. x265-encoding
  8. ffmpeg-compilation  (cloned to .cache/ffmpeg-src on first run)
EOF
}

run_privileged() {
    if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

ensure_sudo_ready() {
    if [ "$(id -u)" -eq 0 ]; then return; fi
    command -v sudo >/dev/null 2>&1 || { err "sudo is required."; exit 1; }
    say "Refreshing sudo credentials"
    sudo -v
}

start_sudo_keepalive() {
    if [ "$(id -u)" -eq 0 ]; then return; fi
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
    local current="$1" expected="$2" short_name
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

restore_default_service_state() {
    if [ "$RESTORE_DONE" -eq 1 ]; then return; fi
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
    if [ -n "${SUDO_USER:-}" ] && [ -d "$RESULTS_DIR" ]; then
        run_privileged chown -R "${SUDO_USER}:$(id -gn "$SUDO_USER")" "$RESULTS_DIR" >/dev/null 2>&1 || true
    fi
}

cleanup() {
    restore_default_service_state
    stop_sudo_keepalive
    fix_results_ownership
}

trap cleanup EXIT

wait_for_scheduler_state() {
    local expected="$1" want="${2:-active}" attempt=0
    while [ "$attempt" -lt 60 ]; do
        if [ "$want" = "active" ] && scheduler_is_attached "$expected"; then return 0; fi
        if [ "$want" = "inactive" ] && ! scheduler_is_attached "$expected" && ! pgrep -x "$expected" >/dev/null 2>&1; then return 0; fi
        attempt=$((attempt + 1))
        sleep 0.5
    done
    return 1
}

wait_for_sched_ext_disabled() {
    local attempt=0
    while [ "$attempt" -lt 60 ]; do
        if [ "$(current_sched_ext_state)" = "disabled" ] && [ -z "$(current_sched_ext_ops)" ]; then return 0; fi
        attempt=$((attempt + 1))
        sleep 0.5
    done
    return 1
}

stop_all_schedulers() {
    run_privileged systemctl unset-environment SCX_SCHEDULER_OVERRIDE >/dev/null 2>&1 || true
    run_privileged systemctl unset-environment SCX_FLAGS_OVERRIDE >/dev/null 2>&1 || true
    if [ -x "$RESET_SCRIPT" ]; then
        run_privileged "$RESET_SCRIPT"
        wait_for_sched_ext_disabled || true
        return
    fi
    if service_exists && systemctl is-active --quiet scx.service; then
        run_privileged systemctl stop scx.service || true
    fi
    for proc in scx_flow scx_cosmos scx_bpfland scx_cake scx_pandemonium pandemonium; do
        pkill -x "$proc" >/dev/null 2>&1 || true
    done
    wait_for_sched_ext_disabled || true
}

manual_scheduler_short_name() {
    case "$1" in
        scx_flow) printf 'flow\n' ;;
        scx_cosmos) printf 'cosmos\n' ;;
        scx_bpfland) printf 'bpfland\n' ;;
        scx_cake) printf 'cake\n' ;;
        scx_pandemonium|pandemonium) printf 'pandemonium\n' ;;
        *) return 1 ;;
    esac
}

scheduler_binary_path() {
    command -v "$1" 2>/dev/null || true
}

start_scheduler_manual() {
    local scheduler="$1" run_name="$2" short_name="" binary_path="" runtime_log=""
    short_name="$(manual_scheduler_short_name "$scheduler")"
    binary_path="$(scheduler_binary_path "$scheduler")"
    [ -n "$binary_path" ] || { err "Could not resolve binary path for $scheduler"; return 1; }
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

# ---------------------------------------------------------------------------
# Per-workload runners
# ---------------------------------------------------------------------------

run_stress_ng_cpu_cache_mem() {
    log_file="$1" timeout_sec="$2"
    stress-ng --cpu 4 --cache 4 --mem 4 --timeout "${timeout_sec}s" --metrics-brief 2>&1
}

run_perf_sched_msg() {
    log_file="$1" timeout_sec="$2"
    perf bench sched messaging -g 24 -l 6000 2>&1
}

run_perf_memcpy() {
    log_file="$1" timeout_sec="$2"
    perf bench mem memcpy -l 100 -s 1MB 2>&1
}

run_argon2_hashing() {
    log_file="$1" timeout_sec="$2"
    # 3 iterations, 2048 KiB memory, 1 thread — about 5s on modern CPU
    echo -n "benchmark-password" | timeout "${timeout_sec}s" \
        argon2 "benchmark-salt" -t 3 -m 21 -p 1 -l 32 -id 2>&1
}

run_xz_compression() {
    log_file="$1" timeout_sec="$2"
    timeout "${timeout_sec}s" bash -c '
        dd if=/dev/urandom bs=1M count=64 2>/dev/null | \
        xz -c -9 -e > /dev/null 2>&1
    ' 2>&1
}

run_primes() {
    log_file="$1" timeout_sec="$2"
    if command -v sysbench >/dev/null 2>&1; then
        sysbench primes --cpu-max-prime=200000 --time="$timeout_sec" run 2>&1
    elif command -v openssl >/dev/null 2>&1; then
        # fallback: openssl speed primes (if available)
        openssl speed prime 2>&1 | head -20
    else
        # Pure bash prime sieve (slow but works)
        timeout "${timeout_sec}s" bash -c '
            n=200000; is_prime=()
            for ((i=2; i<=n; i++)); do is_prime[i]=1; done
            for ((i=2; i*i<=n; i++)); do
                if ((is_prime[i])); then
                    for ((j=i*i; j<=n; j+=i)); do is_prime[j]=0; done
                fi
            done
            count=0
            for ((i=2; i<=n; i++)); do ((count+=is_prime[i])); done
            echo "Found $count primes up to $n"
        ' 2>&1
    fi
}

run_x265_encoding() {
    log_file="$1" timeout_sec="$2"
    if ! command -v x265 >/dev/null 2>&1; then
        echo "SKIP: x265 not installed"
        return 0
    fi
    # Encode 100 frames of black 1080p video
    timeout "${timeout_sec}s" \
        x265 --input /dev/zero --input-res 1920x1080 --fps 30 \
            --frames 100 --preset medium --crf 28 \
            --output /dev/null 2>&1 || true
}

CACHE_DIR="$SCRIPT_DIR/.cache"
FFMPEG_SRC="$CACHE_DIR/ffmpeg-src"

run_ffmpeg_compilation() {
    log_file="$1" timeout_sec="$2"
    if [ ! -d "$FFMPEG_SRC" ]; then
        say "Cloning ffmpeg source (depth=1) to $FFMPEG_SRC..."
        mkdir -p "$CACHE_DIR"
        if ! git clone --depth 1 "https://github.com/FFmpeg/FFmpeg.git" "$FFMPEG_SRC" 2>&1; then
            echo "WARN: failed to clone ffmpeg source; skipping ffmpeg-compilation"
            rm -rf "$FFMPEG_SRC"
            return 0
        fi
        ok "ffmpeg source cloned"
    fi
    local build_dir="$FFMPEG_SRC/build"
    mkdir -p "$build_dir"
    cd "$build_dir"
    ../configure --disable-all --disable-autodetect --enable-small 2>&1
    timeout "${timeout_sec}s" make -j"$(nproc)" 2>&1 || true
}

clean_cache() {
    if [ -d "$CACHE_DIR" ]; then
        say "Removing cache directory: $CACHE_DIR"
        rm -rf "$CACHE_DIR"
        ok "Cache cleaned"
    else
        say "No cache directory to clean"
    fi
}

# ---------------------------------------------------------------------------
# Run a single workload and record its duration
# ---------------------------------------------------------------------------

run_workload() {
    local workload="$1" log_dir="$2" label="$3"
    local log_file="$log_dir/${workload}.log"
    local result_file="$log_dir/${workload}.result"
    local timeout_sec

    case "$workload" in
        stress-ng-cpu-cache-mem)  timeout_sec=30 ;;
        perf-sched-msg-fork)      timeout_sec=120 ;;
        perf-memcpy)              timeout_sec=30 ;;
        argon2-hashing)           timeout_sec=30 ;;
        xz-compression)           timeout_sec=60 ;;
        primes)                   timeout_sec=30 ;;
        x265-encoding)            timeout_sec=30 ;;
        ffmpeg-compilation)       timeout_sec=600 ;;
        *) echo "Unknown workload: $workload"; return 1 ;;
    esac

    printf '  %-35s' "$workload..." >&2
    local start_ns end_ns elapsed_ns elapsed_sec start_wall end_wall

    start_ns="$(date +%s%N)"
    start_wall="$(date +%s)"

    case "$workload" in
        stress-ng-cpu-cache-mem)  run_stress_ng_cpu_cache_mem "$log_file" "$timeout_sec" >"$log_file" 2>&1 || true ;;
        perf-sched-msg-fork)      run_perf_sched_msg "$log_file" "$timeout_sec" >"$log_file" 2>&1 || true ;;
        perf-memcpy)              run_perf_memcpy "$log_file" "$timeout_sec" >"$log_file" 2>&1 || true ;;
        argon2-hashing)           run_argon2_hashing "$log_file" "$timeout_sec" >"$log_file" 2>&1 || true ;;
        xz-compression)           run_xz_compression "$log_file" "$timeout_sec" >"$log_file" 2>&1 || true ;;
        primes)                   run_primes "$log_file" "$timeout_sec" >"$log_file" 2>&1 || true ;;
        x265-encoding)            run_x265_encoding "$log_file" "$timeout_sec" >"$log_file" 2>&1 || true ;;
        ffmpeg-compilation)       run_ffmpeg_compilation "$log_file" "$timeout_sec" >"$log_file" 2>&1 || true ;;
    esac

    local exit_code=$?
    end_ns="$(date +%s%N)"
    end_wall="$(date +%s)"
    elapsed_ns=$((end_ns - start_ns))
    elapsed_sec=$(awk "BEGIN { printf \"%.3f\", $elapsed_ns / 1000000000 }")

    printf '%s' "$elapsed_sec" > "$result_file"

    # Check for SKIP in output
    if grep -q "SKIP:" "$log_file" 2>/dev/null; then
        printf '  SKIPPED (%s sec)\n' "$elapsed_sec" >&2
        echo "skipped" > "$result_file"
    elif [ "$exit_code" -ne 0 ] && [ "$exit_code" -ne 124 ]; then
        printf '  FAILED (exit=%d, %s sec)\n' "$exit_code" "$elapsed_sec" >&2
        echo "failed" > "$result_file"
    else
        printf '  %s sec\n' "$elapsed_sec" >&2
    fi
}

# ---------------------------------------------------------------------------
# Render outputs
# ---------------------------------------------------------------------------

render_csv_report() {
    local tagged_dir="$RESULTS_DIR/tagged"
    mkdir -p "$tagged_dir"
    local csv="$tagged_dir/comprehensive_benchmarker_summary.csv"
    local report="$tagged_dir/comprehensive_benchmarker_report.md"

    # Read all scheduler run dirs
    local scheduler_names=()
    for d in "$RESULTS_DIR/runs"/*; do
        [ -d "$d" ] || continue
        scheduler_names+=("$(basename "$d")")
    done

    # Build header
    local header="scheduler"
    for wl in "${ALL_WORKLOADS[@]}"; do
        header="$header,$wl"
    done
    header="$header,total,relative"

    echo "$header" > "$csv"

    local baseline_total=""

    for scheduler in "${scheduler_names[@]}"; do
        local run_dir="$RESULTS_DIR/runs/$scheduler/run_1"
        [ -d "$run_dir" ] || continue
        local row="$scheduler"
        local total=0
        local missing=0
        for wl in "${ALL_WORKLOADS[@]}"; do
            local result_file="$run_dir/${wl}.result"
            if [ -f "$result_file" ]; then
                local val
                val="$(cat "$result_file")"
                if [ "$val" = "skipped" ] || [ "$val" = "failed" ]; then
                    row="$row,"
                else
                    row="$row,$val"
                    total=$(awk "BEGIN { printf \"%.3f\", $total + $val }")
                fi
            else
                row="$row,"
                missing=$((missing + 1))
            fi
        done
        total_fmt=$(awk "BEGIN { printf \"%.3f\", $total }")
        if [ "$scheduler" = "baseline" ]; then
            baseline_total="$total"
            row="$row,$total_fmt,1.000x"
        elif [ -n "$baseline_total" ] && [ "$(echo "$baseline_total > 0" | bc)" -eq 1 ]; then
            relative=$(awk "BEGIN { printf \"%.3fx\", $total / $baseline_total }")
            row="$row,$total_fmt,$relative"
        else
            row="$row,$total_fmt,"
        fi
        echo "$row" >> "$csv"
    done

    # Create markdown report
    {
        echo "# Comprehensive Benchmarker Report"
        echo ""
        echo "Generated: $(date)"
        echo "Kernel: $(uname -r)"
        echo "CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
        echo "CPU Cores: $(nproc)"
        echo ""
        echo "## Total wall-time across ${#ALL_WORKLOADS[@]} workloads (lower is faster)"
        echo ""
        echo "| Scheduler | Total (s) | Relative |"
        echo "| --- | ---: | ---: |"
        while IFS=, read -r sched rest; do
            [ "$sched" = "scheduler" ] && continue
            # Extract total and relative from last two fields
            local total_val rel_val
            total_val=$(echo "$rest" | awk -F, '{print $(NF-1)}')
            rel_val=$(echo "$rest" | awk -F, '{print $NF}')
            printf '| %s | %s | %s |\n' "$sched" "$total_val" "$rel_val"
        done < "$csv"
    } > "$report"

    # Render charts
    local plotter="$SCRIPT_DIR/comprehensive_benchmarker_plot.py"
    if [ -f "$plotter" ]; then
        python3 "$plotter" --csv "$csv" --output-dir "$tagged_dir"
        say "PNG:    $tagged_dir/comprehensive_benchmarker_comparison.png"
        say "SVG:    $tagged_dir/comprehensive_benchmarker_comparison.svg"
    fi

    say "CSV:    $csv"
    say "Report: $report"
}

prune_old_results() {
    [ -d "$RESULTS_ROOT" ] || return 0
    local old_dirs
    old_dirs=$(ls -1dt "$RESULTS_ROOT"/* 2>/dev/null | tail -n +"$((KEEP_RESULTS + 1))" || true)
    [ -n "$old_dirs" ] || return 0
    while IFS= read -r old_dir; do
        [ -n "$old_dir" ] || continue
        rm -rf "$old_dir"
    done <<< "$old_dirs"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

while [ "$#" -gt 0 ]; do
    case "$1" in
        --runs) RUNS="$2"; shift 2 ;;
        --keep-results) KEEP_RESULTS="$2"; shift 2 ;;
        --results-dir) RESULTS_DIR="$2"; shift 2 ;;
        --schedulers) read -r -a SCHEDULERS <<< "$2"; shift 2 ;;
        --skip-workload) SKIP_WORKLOADS="$2"; shift 2 ;;
        --clean-cache) clean_cache; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) err "Unknown option: $1"; usage >&2; exit 1 ;;
    esac
done

# Parse skip list
declare -A SKIP_MAP
if [ -n "$SKIP_WORKLOADS" ]; then
    IFS=',' read -ra SKIP_LIST <<< "$SKIP_WORKLOADS"
    for wl in "${SKIP_LIST[@]}"; do
        SKIP_MAP["$wl"]=1
    done
fi

case "$RUNS" in ''|*[!0-9]*|0) err "--runs must be a positive integer"; exit 1 ;; esac

ensure_sudo_ready
start_sudo_keepalive
capture_initial_state

mkdir -p "$RESULTS_DIR/runs"

say "Results directory: $RESULTS_DIR"
say "Schedulers: ${SCHEDULERS[*]}"
say "Workloads: ${ALL_WORKLOADS[*]}"

for scheduler in "${SCHEDULERS[@]}"; do
    say "==========================================="
    say "Scheduler: $scheduler"
    say "==========================================="

    say "Resetting sched_ext state for $scheduler..."
    stop_all_schedulers
    say "Reset done, progressing to workloads..."

    if [ "$scheduler" != "baseline" ]; then
        if ! start_scheduler_manual "$scheduler" "$scheduler"; then
            warn "Activation failed for $scheduler; skipping"
            continue
        fi
    fi

    for run_index in $(seq 1 "$RUNS"); do
        run_dir="$RESULTS_DIR/runs/${scheduler}/run_${run_index}"
        mkdir -p "$run_dir"
        log_file="$run_dir/benchmark.log"
        echo "=== Comprehensive benchmark: $scheduler run $run_index ===" > "$log_file"
        echo "Started: $(date)" >> "$log_file"
        echo "sched_ext state: $(current_sched_ext_state)" >> "$log_file"
        echo "scheduler: $(current_sched_ext_ops)" >> "$log_file"

        for workload in "${ALL_WORKLOADS[@]}"; do
            if [ "${SKIP_MAP[$workload]:-}" = "1" ]; then
                echo "  SKIPPED: $workload (user skip)" >> "$log_file"
                say "  $workload: skipped"
                continue
            fi
            say "  $workload... (0 sec)" 2>/dev/null || printf '  %-40s' "$workload..."
            run_workload "$workload" "$run_dir" "${scheduler}/run${run_index}" >> "$log_file" 2>&1
        done

        echo "Completed: $(date)" >> "$log_file"
        say "  Run $run_index/$RUNS done"
    done

    if [ "$scheduler" != "baseline" ]; then
        stop_all_schedulers
    fi
done

restore_default_service_state
render_csv_report
fix_results_ownership
prune_old_results

ok "Comprehensive benchmark complete"
say "Results: $RESULTS_DIR"
say "CSV:     $RESULTS_DIR/tagged/comprehensive_benchmarker_summary.csv"
say "Report:  $RESULTS_DIR/tagged/comprehensive_benchmarker_report.md"
