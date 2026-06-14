#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Multi-scheduler comprehensive benchmark — compares schedulers using the
# same tool invocations as the CachyOS mini-benchmarker (stress-ng jobfile,
# primesieve, perf sched -t, etc.) and generates CSV/PNG/SVG results like
# the mini_benchmarker.
#
# Usage: sudo ./comprehensive_benchmarker.sh [options]
#
# Options:
#   --runs N                  Number of runs per scheduler (default: 1)
#   --keep-results N          Keep N newest result dirs (default: 3)
#   --results-dir DIR         Write results to DIR instead of timestamped path
#   --schedulers "LIST"       Space-separated scheduler list
#                             Default: "baseline scx_cosmos scx_bpfland scx_flow"
#   --skip-workload LIST      Comma-separated workloads to skip
#   --workdir DIR             Asset cache directory (default: ./.cache/cachyos-bench)
#   --no-download             Skip downloading assets
#   --clean-cache             Remove cached assets and exit
#   -h, --help                Show this help

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
WORKDIR="${WORKDIR:-$SCRIPT_DIR/.cache/cachyos-bench}"
NO_DOWNLOAD=false
SUDO_KEEPALIVE_PID=""
INITIAL_SERVICE_ACTIVE=0
RESTORE_DONE=0
CURRENT_RUNTIME_LOG=""
LOGFILE=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
TB=$(tput bold); TN=$(tput sgr0)
say()  { printf "${BOLD}${CYAN}[comprehensive]${NC} %s\n" "$1"; }
ok()   { printf "${BOLD}${GREEN}[ ok ]${NC} %s\n" "$1"; }
warn() { printf "${BOLD}${YELLOW}[warn]${NC} %s\n" "$1"; }
err()  { printf "${BOLD}${RED}[err ]${NC} %s\n" "$1" >&2; }

CPUCORES=$(nproc)

# Find time command — /usr/bin/time (package "time") or fallback to bash builtin
TIME_CMD=""
if [ -x /usr/bin/time ]; then
    TIME_CMD="/usr/bin/time"
elif command -v gtime &>/dev/null; then
    TIME_CMD="gtime"
else
    # Fallback: shell-based timing
    TIME_CMD=""
    warn "/usr/bin/time not found — install 'time' package for accurate measurements"
fi

time_cmd() {
    local outfile="$1"
    shift
    if [ -n "$TIME_CMD" ]; then
        "$TIME_CMD" -f "%e" -o "$outfile" "$@" &>/dev/null
    else
        local start end
        start=$(date +%s%N)
        "$@" &>/dev/null
        end=$(date +%s%N)
        awk "BEGIN { printf \"%.3f\n\", ($end - $start) / 1000000000 }" > "$outfile"
    fi
}

declare -A WLABEL
WLABEL=(
    [stress-ng-cpu-cache-mem]="stress-ng cpu-cache-mem"
    [perf-sched-msg-fork]="perf sched msg fork thread"
    [perf-memcpy]="perf memcpy"
    [primes]="calculating prime numbers"
    [argon2-hashing]="argon2 hashing"
    [xz-compression]="xz compression"
    [x265-encoding]="x265 encoding"
    [ffmpeg-compilation]="ffmpeg compilation"
    [y-cruncher]="y-cruncher pi 1b"
)

ALL_WORKLOADS=("${!WLABEL[@]}")

# --- Common utilities (from mini_benchmarker) ---
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
    ( while true; do sudo -n true >/dev/null 2>&1 || exit 0; sleep 60; done ) &
    SUDO_KEEPALIVE_PID=$!
}

stop_sudo_keepalive() {
    if [ -n "$SUDO_KEEPALIVE_PID" ] && kill -0 "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1; then
        kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true; wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
    SUDO_KEEPALIVE_PID=""
}

current_sched_ext_state() { cat /sys/kernel/sched_ext/state 2>/dev/null || echo "unknown"; }
current_sched_ext_ops() { cat /sys/kernel/sched_ext/root/ops 2>/dev/null || true; }

scheduler_short_name() {
    case "$1" in scx_*) printf '%s\n' "${1#scx_}" ;; *) printf '%s\n' "$1" ;; esac
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
    scheduler_matches_name "$(current_sched_ext_ops)" "$name" && [ "$(current_sched_ext_state)" = "enabled" ]
}

service_exists() {
    command -v systemctl >/dev/null 2>&1 && systemctl cat scx.service >/dev/null 2>&1
}

capture_initial_state() {
    if service_exists && systemctl is-active --quiet scx.service; then
        INITIAL_SERVICE_ACTIVE=1
    fi
}

wait_for_scheduler_state() {
    local expected="$1" want="${2:-active}" attempt=0
    while [ "$attempt" -lt 60 ]; do
        if [ "$want" = "active" ] && scheduler_is_attached "$expected"; then return 0; fi
        if [ "$want" = "inactive" ] && ! scheduler_is_attached "$expected" && ! pgrep -x "$expected" >/dev/null 2>&1; then return 0; fi
        attempt=$((attempt + 1)); sleep 0.5
    done
    return 1
}

wait_for_sched_ext_disabled() {
    local attempt=0
    while [ "$attempt" -lt 60 ]; do
        if [ "$(current_sched_ext_state)" = "disabled" ] && [ -z "$(current_sched_ext_ops)" ]; then return 0; fi
        attempt=$((attempt + 1)); sleep 0.5
    done; return 1
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
        scx_flow) printf 'flow\n' ;; scx_cosmos) printf 'cosmos\n' ;;
        scx_bpfland) printf 'bpfland\n' ;; scx_cake) printf 'cake\n' ;;
        scx_pandemonium|pandemonium) printf 'pandemonium\n' ;;
        *) return 1 ;;
    esac
}

scheduler_binary_path() { command -v "$1" 2>/dev/null || true; }

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
cleanup_sigint() {
    say "Interrupted — shutting down workloads..."
    pkill -P $$ 2>/dev/null || true
    cleanup
    exit 130
}
trap cleanup_sigint SIGINT SIGTERM

# --- Asset preparation (CachyOS-style) ---
prepare_assets() {
    mkdir -p "$WORKDIR"
    echo -e "${TB}Checking and preparing test assets...${TN}"

    # stress-ng jobfile
    cat > "$WORKDIR/stressC" <<-EOF
run sequential 0
no-rand-seed
temp-path /tmp
timeout 0
matrix CPUCORES
matrix-method prod
matrix-size 256
matrix-ops $((2400 / CPUCORES))
sparsematrix CPUCORES
sparsematrix-method hash
sparsematrix-items 15000
sparsematrix-ops $((2400 / CPUCORES))
shm CPUCORES
shm-bytes 16m
shm-ops $((2400 / CPUCORES))
fork CPUCORES
fork-max 8
fork-ops $((24000 / CPUCORES))
cpu CPUCORES
cpu-method cdouble
cpu-ops $((4800 / CPUCORES))
bsearch CPUCORES
bsearch-ops $((2400 / CPUCORES))
stream CPUCORES
stream-ops $((4800 / CPUCORES))
list CPUCORES
list-ops $((2400 / CPUCORES))
qsort CPUCORES
qsort-size 65536
qsort-ops $((2400 / CPUCORES))
memfd CPUCORES
memfd-bytes 128m
memfd-fds 128
memfd-ops $((2400 / CPUCORES))
EOF
    sed -i "s/CPUCORES/$CPUCORES/g" "$WORKDIR/stressC"

    ! $NO_DOWNLOAD || return 0

    # x265 video
    if command -v x265 &>/dev/null && [ ! -f "$WORKDIR/bosphorus_hd.y4m" ]; then
        if [ ! -f "$WORKDIR/bosphorus_hd.7z" ] || ! 7z t "$WORKDIR/bosphorus_hd.7z" &>/dev/null; then
            echo "--> Downloading video archive..."
            wget -c --show-progress -qO "$WORKDIR/bosphorus_hd.7z" \
                http://ultravideo.cs.tut.fi/video/Bosphorus_1920x1080_120fps_420_8bit_YUV_Y4M.7z
        fi
        cd "$WORKDIR" && 7z e bosphorus_hd.7z -o./ &>/dev/null 2>&1 || true
        mv Bosphorus_1920x1080_120fps_420_8bit_YUV.y4m bosphorus_hd.y4m 2>/dev/null || true
    fi

    # Firefox tarball for xz
    if [ ! -f "$WORKDIR/firefox102.tar" ]; then
        if [ ! -f "$WORKDIR/firefox102.tar.xz" ] || ! xz -t "$WORKDIR/firefox102.tar.xz" &>/dev/null; then
            echo "--> Downloading Firefox archive..."
            wget -c --show-progress -qO "$WORKDIR/firefox102.tar.xz" \
                http://ftp.mozilla.org/pub/firefox/releases/102.9.0esr/source/firefox-102.9.0esr.source.tar.xz
        fi
        echo "--> Unzipping Firefox tarball..."
        xz -d -k -q -f "$WORKDIR/firefox102.tar.xz"
    fi

    # FFmpeg source
    if [ ! -d "$WORKDIR/ffmpeg-src" ]; then
        echo "--> Cloning ffmpeg source..."
        git clone --depth 1 "https://github.com/FFmpeg/FFmpeg.git" "$WORKDIR/ffmpeg-src" 2>/dev/null || true
        if [ -d "$WORKDIR/ffmpeg-src" ]; then
            cd "$WORKDIR/ffmpeg-src" || true
            ./configure --prefix=/tmp --disable-debug --enable-static \
                --enable-gpl --enable-version3 --disable-ffplay --disable-ffprobe \
                --disable-programs --disable-doc --disable-network --disable-protocols \
                --disable-filters --disable-iconv --enable-libdrm --disable-stripping \
                --disable-autodetect --cpu=native &>/dev/null || true
        fi
    fi

    # y-cruncher
    if [ ! -d "$WORKDIR/y-cruncher" ]; then
        local YCVER="0.8.6.9545"
        if [ ! -f "$WORKDIR/y-cruncher.tar.xz" ] || ! tar -tf "$WORKDIR/y-cruncher.tar.xz" &>/dev/null; then
            echo "--> Downloading y-cruncher archive..."
            wget -c --show-progress -qO "$WORKDIR/y-cruncher.tar.xz" \
                "https://github.com/Mysticial/y-cruncher/releases/download/v${YCVER}/y-cruncher.v${YCVER}-static.tar.xz"
        fi
        cd "$WORKDIR" && tar -xf y-cruncher.tar.xz 2>/dev/null || true
        mkdir -p "$WORKDIR/y-cruncher" 2>/dev/null || true
        mv "$WORKDIR"/y-cruncher\ v*/ "$WORKDIR/y-cruncher/" 2>/dev/null || true
    fi
}

# --- CachyOS-style workload runners ---
ulimit -n 4096

animate() {
    local idx=$1 pid=$2 s='-+' i=0
    while kill -0 "$pid" &>/dev/null; do
        # Check scheduler integrity on every tick for non-baseline
        if [ "${CURRENT_SCHED:-none}" != "none" ] && [ "${CURRENT_SCHED:-baseline}" != "baseline" ]; then
            local current_ops
            current_ops=$(current_sched_ext_ops)
            if [ -z "$current_ops" ]; then
                printf "\n${RED}${TB}**** Scheduler crashed during workload! ****${TN}\n"
                kill -9 "$pid" 2>/dev/null || true
                echo "${WLABEL[$1]:-$1}: FAILED (scheduler crashed)" >> "$LOGFILE"
                return 1
            fi
        fi
        i=$(( (i+1) % 2 ))
        printf "\b${s:$i:1}"
        sleep 1
    done
    printf "\b "
    local result
    result=$(cat "$RF" 2>/dev/null || echo "FAILED")
    echo "$result"
    echo "${WLABEL[$1]:-$1}: $result" >> "$LOGFILE"
}

run_workload() {
    local wl="$1"
    local log_dir="$2"
    shift 2
    RF="$log_dir/${wl}.result"
    local pid=""

    case "$wl" in
        stress-ng-cpu-cache-mem)
            time_cmd "$RF" "" stress-ng -q --job "$WORKDIR/stressC" &>/dev/null &
            pid=$!
            ;;
        perf-sched-msg-fork)
            perf bench -f simple sched messaging -t -g 24 -l 6000 1>"$RF" &
            pid=$!
            ;;
        perf-memcpy)
            time_cmd "$RF" "" perf bench -f simple mem memcpy \
                --nr_loops 100 --size 2GB -f default &>/dev/null &
            pid=$!
            ;;
        primes)
            if ! command -v primesieve &>/dev/null; then
                echo "SKIP" > "$RF"
            else
                time_cmd "$RF" "" primesieve 666000000000 --no-status &
                pid=$!
            fi
            ;;
        argon2-hashing)
            time_cmd "$RF" "" argon2 BenchieSalt -id -t 20 -m 21 \
                -p "$CPUCORES" &>/dev/null <<< "$(head -c 64 /dev/urandom)" &
            pid=$!
            ;;
        xz-compression)
            if [ ! -f "$WORKDIR/firefox102.tar" ]; then
                echo "SKIP" > "$RF"
            else
                time_cmd "$RF" "" xz -z -k -T"${CPUCORES}" -Qqq \
                    -f "$WORKDIR/firefox102.tar" &
                pid=$!
            fi
            ;;
        x265-encoding)
            if [ ! -f "$WORKDIR/bosphorus_hd.y4m" ]; then
                echo "SKIP" > "$RF"
            else
                time_cmd "$RF" "" x265 -p slow -b 6 -o /dev/null \
                    --no-progress --log-level none --input "$WORKDIR/bosphorus_hd.y4m" &
                pid=$!
            fi
            ;;
        ffmpeg-compilation)
            if [ ! -d "$WORKDIR/ffmpeg-src" ]; then
                echo "SKIP" > "$RF"
            else
                cd "$WORKDIR/ffmpeg-src" || { echo "SKIP" > "$RF"; break; }
                time_cmd "$RF" "" make -s -j"${CPUCORES}" &>/dev/null &
                pid=$!
            fi
            ;;
        y-cruncher)
            local ycdir
            ycdir=$(find "$WORKDIR/y-cruncher" -maxdepth 2 -name 'y-cruncher' -type f 2>/dev/null | head -1)
            if [ -z "$ycdir" ]; then
                echo "SKIP" > "$RF"
            else
                ycdir=$(dirname "$ycdir")
                cd "$ycdir" || { echo "SKIP" > "$RF"; break; }
                rm -f "Pi"*.txt
                time_cmd "$RF" "" ./y-cruncher bench 1b -od:0 -o "$WORKDIR" &
                pid=$!
            fi
            ;;
    esac

    if [ -f "$RF" ] && [ "$(cat "$RF" 2>/dev/null)" = "SKIP" ]; then
        printf '  %-40s %s\n' "${WLABEL[$wl]:-$wl}..." "SKIPPED"
        echo "${WLABEL[$wl]:-$wl}: SKIPPED" >> "$LOGFILE"
        return 0
    fi

    printf '  %-40s' "${WLABEL[$wl]:-$wl}..."
    animate "$wl" "$pid" || true
    wait "$pid" 2>/dev/null || true
}

# --- Render outputs (from mini_benchmarker) ---
render_csv_report() {
    local tagged_dir="$RESULTS_DIR/tagged"
    mkdir -p "$tagged_dir"
    local csv="$tagged_dir/comprehensive_benchmarker_summary.csv"
    local report="$tagged_dir/comprehensive_benchmarker_report.md"

    local scheduler_names=()
    for d in "$RESULTS_DIR/runs"/*; do
        [ -d "$d" ] || continue
        scheduler_names+=("$(basename "$d")")
    done

    # Build CSV
    {
        printf 'scheduler'
        for wl in $(printf '%s\n' "${ALL_WORKLOADS[@]}" | sort); do
            printf ',%s' "$wl"
        done
        printf ',total,relative\n'
    } > "$csv"

    local baseline_total=""
    for scheduler in "${scheduler_names[@]}"; do
        local run_dir="$RESULTS_DIR/runs/$scheduler/run_1"
        [ -d "$run_dir" ] || continue
        printf '%s' "$scheduler" >> "$csv"
        local total=0
        for wl in $(printf '%s\n' "${ALL_WORKLOADS[@]}" | sort); do
            local result_file="$run_dir/${wl}.result"
            if [ -f "$result_file" ]; then
                local val
                val="$(cat "$result_file")"
                case "$val" in
                    ''|SKIP|failed) printf ',' >> "$csv" ;;
                    *)
                        printf ',%s' "$val" >> "$csv"
                        total=$(awk "BEGIN { printf \"%.3f\", $total + $val }")
                        ;;
                esac
            else
                printf ',' >> "$csv"
            fi
        done
        total_fmt=$(awk "BEGIN { printf \"%.3f\", $total }")
        if [ "$scheduler" = "baseline" ]; then
            baseline_total="$total"
            printf ',%s,1.000x\n' "$total_fmt" >> "$csv"
        elif [ -n "$baseline_total" ] && [ "$(echo "$baseline_total > 0" | bc -l)" -eq 1 ]; then
            relative=$(awk "BEGIN { printf \"%.3fx\", $total / $baseline_total }")
            printf ',%s,%s\n' "$total_fmt" "$relative" >> "$csv"
        else
            printf ',%s,\n' "$total_fmt" >> "$csv"
        fi
    done

    # Render charts if plotter exists
    local plotter="$SCRIPT_DIR/comprehensive_benchmarker_plot.py"
    if [ -f "$plotter" ]; then
        python3 "$plotter" --csv "$csv" --output-dir "$tagged_dir" 2>/dev/null || true
    fi

    say "CSV:    $csv"
    say "PNG:    $tagged_dir/comprehensive_benchmarker_comparison.png"
    say "SVG:    $tagged_dir/comprehensive_benchmarker_comparison.svg"
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

# --- Main ---
usage() {
    cat <<EOF
Usage: sudo ./comprehensive_benchmarker.sh [options]
  --runs N                  Runs per scheduler (default: 1)
  --keep-results N          Keep N newest result dirs (default: 3)
  --results-dir DIR         Custom results directory
  --schedulers "LIST"       Space-separated list (default: "baseline scx_cosmos ...")
  --skip-workload LIST      Comma-separated workloads to skip
  --workdir DIR             Asset cache directory
  --no-download             Skip downloading video/ffmpeg/etc
  --clean-cache             Remove cached assets and exit
  -h, --help                Show this help
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --runs) RUNS="$2"; shift 2 ;;
        --keep-results) KEEP_RESULTS="$2"; shift 2 ;;
        --results-dir) RESULTS_DIR="$2"; shift 2 ;;
        --schedulers) read -r -a SCHEDULERS <<< "$2"; shift 2 ;;
        --skip-workload) SKIP_WORKLOADS="$2"; shift 2 ;;
        --workdir) WORKDIR="$2"; shift 2 ;;
        --no-download) NO_DOWNLOAD=true; shift ;;
        --clean-cache)
            echo "Cleaning cache: $WORKDIR"
            rm -rf "$WORKDIR"/firefox102.tar* "$WORKDIR"/bosphorus_hd* "$WORKDIR"/*.7z
            rm -rf "$WORKDIR"/ffmpeg-src "$WORKDIR"/y-cruncher* "$WORKDIR"/run* "$WORKDIR"/stressC
            echo "Done."; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) err "Unknown option: $1"; usage >&2; exit 1 ;;
    esac
done

case "$RUNS" in ''|*[!0-9]*|0) err "--runs must be a positive integer"; exit 1 ;; esac

declare -A SKIP_MAP
if [ -n "$SKIP_WORKLOADS" ]; then
    IFS=',' read -ra SKIP_LIST <<< "$SKIP_WORKLOADS"
    for wl in "${SKIP_LIST[@]}"; do SKIP_MAP["$wl"]=1; done
fi

ensure_sudo_ready
start_sudo_keepalive
capture_initial_state

mkdir -p "$RESULTS_DIR/runs"
prepare_assets
ulimit -n 4096

say "Results directory: $RESULTS_DIR"
say "Schedulers: ${SCHEDULERS[*]}"
say "Workloads: ${ALL_WORKLOADS[*]}"

for scheduler in "${SCHEDULERS[@]}"; do
    say "==========================================="
    say "Scheduler: $scheduler"
    say "==========================================="
    CURRENT_SCHED="$scheduler"

    stop_all_schedulers

    if [ "$scheduler" != "baseline" ]; then
        if ! start_scheduler_manual "$scheduler" "$scheduler"; then
            warn "Activation failed for $scheduler; skipping"
            continue
        fi
    fi

    for run_index in $(seq 1 "$RUNS"); do
        run_dir="$RESULTS_DIR/runs/${scheduler}/run_${run_index}"
        mkdir -p "$run_dir"
        LOGFILE="$run_dir/benchmark.log"
        {
            echo "=== Comprehensive benchmark: $scheduler run $run_index ==="
            echo "Started: $(date)"
            echo "sched_ext state: $(current_sched_ext_state)"
            echo "scheduler: $(current_sched_ext_ops)"
        } > "$LOGFILE"

        for wl in "${ALL_WORKLOADS[@]}"; do
            if [ "${SKIP_MAP[$wl]:-}" = "1" ]; then
                say "  $wl: skipped"
                echo "$wl: SKIPPED (user skip)" >> "$LOGFILE"
                continue
            fi
            run_workload "$wl" "$run_dir"
        done

        echo "Completed: $(date)" >> "$LOGFILE"
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
