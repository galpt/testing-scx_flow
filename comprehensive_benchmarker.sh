#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Single-scheduler comprehensive benchmark — runs the current active
# scheduler through 12 workloads using the same tool invocations as the
# CachyOS mini-benchmarker.  Outputs a log file with per-workload times.
#
# Usage: sudo ./comprehensive_benchmarker.sh [options]
#
# Options:
#   --workdir DIR        Working directory for assets and logs (default: ./.cache/cachyos-bench)
#   --ffmpeg-ver VER     FFmpeg version to download (default: 7.0.1)
#   --kernel-ver VER     Kernel source version (default: 6.14.7)
#   --no-download        Skip downloading assets (use existing cached ones)
#   --cleanup            Remove downloaded archives and extracted dirs after run
#   -h, --help           Show this help

set -uo pipefail

export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${WORKDIR:-$SCRIPT_DIR/.cache/cachyos-bench}"
FFMPEGVER="${FFMPEGVER:-7.0.1}"
KERNVER="${KERNVER:-6.14.7}"
CDATE="$(date +%F-%H%M)"
RAMSIZE="$(awk '/MemTotal/{print int($2 / 1000)}' /proc/meminfo)"
CPUCORES="$(nproc)"
NO_DOWNLOAD=false
CLEANUP=false

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
TB="$(tput bold)" TN="$(tput sgr0)"
say() { printf "${BOLD}${CYAN}[bench]${NC} %s\n" "$1"; }
ok()  { printf "${BOLD}${GREEN}[ ok ]${NC} %s\n" "$1"; }
warn(){ printf "${BOLD}${YELLOW}[warn]${NC} %s\n" "$1"; }
err() { printf "${BOLD}${RED}[err ]${NC} %s\n" "$1" >&2; }

TNAMES=(
    'stress-ng cpu-cache-mem'
    'ffmpeg compilation'
    'x265 encoding'
    'argon2 hashing'
    'perf sched msg fork thread'
    'perf memcpy'
    'calculating prime numbers'
    'xz compression'
    'y-cruncher pi 1b'
)

# --- Scheduler integrity ---
SCX="none"
SCX_VERSION=""
if [ -f "/sys/kernel/sched_ext/root/ops" ]; then
    TMP=$(cat "/sys/kernel/sched_ext/root/ops")
    if [ -n "$TMP" ]; then
        SCX=$(awk -F'[[:digit:]]' '{print $1}' /sys/kernel/sched_ext/root/ops | sed -rn 's/^(.*)_$/\1/p')
        SCX_VERSION=$(sed -rn 's/^[^0-9]*([0-9]+(\.[0-9]+)+).*$/\1/p' /sys/kernel/sched_ext/root/ops)
        [ -z "$SCX" ] && SCX="$TMP"
    fi
fi

check_scheduler_integrity() {
    if [ "$SCX" = "none" ]; then return 0; fi
    if [ -f "/sys/kernel/sched_ext/root/ops" ]; then
        local CURRENT_OPS
        CURRENT_OPS=$(cat "/sys/kernel/sched_ext/root/ops" 2>/dev/null || true)
        if [ -z "$CURRENT_OPS" ]; then return 1; fi
        local CURRENT_SCX
        CURRENT_SCX=$(echo "$CURRENT_OPS" | awk -F'[[:digit:]]' '{print $1}' | sed -rn 's/^(.*)_$/\1/p')
        [ -z "$CURRENT_SCX" ] && CURRENT_SCX="$CURRENT_OPS"
        if [ "$CURRENT_SCX" != "$SCX" ]; then return 1; fi
    else
        return 1
    fi
    return 0
}

# --- Animation + scheduler monitor ---
PID=""
animate() {
    local idx=$1 s='-+' i=0
    while kill -0 "$PID" &>/dev/null; do
        if ! check_scheduler_integrity; then
            printf "\n${RED}${TB}**** CRITICAL: Scheduler crashed during ${TNAMES[$idx]}! ****${TN}\n"
            kill -9 "$PID" 2>/dev/null || true
            echo "${TNAMES[$idx]}: FAILED (Scheduler crashed)" >> "$LOGFILE"
            echo "SCX Scheduler: ${SCX} (CRASHED during ${TNAMES[$idx]})" >> "$LOGFILE"
            exit 9
        fi
        i=$(( (i+1) % 2 ))
        printf "\b${s:$i:1}"
        sleep 1
    done
    printf "\b " ; cat "$RESFILE"
    echo "${TNAMES[$idx]}: $(cat "$RESFILE")" >> "$LOGFILE"
}

# --- Workload runners ---
runstress() {
    RESFILE="$WORKDIR/runstress"
    /usr/bin/time -f %e -o "$RESFILE" stress-ng -q --job "$WORKDIR/stressC" &>/dev/null &
    PID=$!
    echo -n -e "* ${TNAMES[0]}:\t\t"
    animate 0
}

runext() {
    RESFILE="$WORKDIR/runffm"
    cd "$WORKDIR/ffmpeg-$FFMPEGVER" 2>/dev/null || { echo "SKIP" > "$RESFILE"; return; }
    /usr/bin/time -f %e -o "$RESFILE" make -s -j"${CPUCORES}" &>/dev/null &
    PID=$!
    echo -n -e "* ${TNAMES[1]}:\t\t\t"
    animate 1
}

runx265() {
    RESFILE="$WORKDIR/runx265"
    if [ ! -f "$WORKDIR/bosphorus_hd.y4m" ]; then
        echo "SKIP" > "$RESFILE"; return
    fi
    /usr/bin/time -f %e -o "$RESFILE" x265 -p slow -b 6 -o /dev/null \
        --no-progress --log-level none --input "$WORKDIR/bosphorus_hd.y4m" &
    PID=$!
    echo -n -e "* ${TNAMES[2]}:\t\t\t"
    animate 2
}

runargon() {
    RESFILE="$WORKDIR/runargon"
    /usr/bin/time -f %e -o "$RESFILE" argon2 BenchieSalt -id -t 20 -m 21 \
        -p "$CPUCORES" &>/dev/null <<< "$(head -c 64 /dev/urandom)" &
    PID=$!
    echo -n -e "* ${TNAMES[3]}:\t\t\t"
    animate 3
}

runperf_sch() {
    RESFILE="$WORKDIR/runperfs"
    perf bench -f simple sched messaging -t -g 24 -l 6000 1>"$RESFILE" &
    PID=$!
    echo -n -e "* ${TNAMES[4]}:\t\t"
    animate 4
}

runperf_mem() {
    RESFILE="$WORKDIR/runperfm"
    /usr/bin/time -f %e -o "$RESFILE" perf bench -f simple mem memcpy \
        --nr_loops 100 --size 2GB -f default &>/dev/null &
    PID=$!
    echo -n -e "* ${TNAMES[5]}:\t\t\t\t"
    animate 5
}

runprime() {
    RESFILE="$WORKDIR/runprime"
    /usr/bin/time -f%e -o "$RESFILE" primesieve 666000000000 --no-status | \
        awk -F ': ' '/Seconds/{print $2}' 1>"$RESFILE" &
    PID=$!
    echo -n -e "* ${TNAMES[6]}:\t\t"
    animate 6
}

runxz() {
    RESFILE="$WORKDIR/runxz"
    if [ ! -f "$WORKDIR/firefox102.tar" ]; then
        echo "SKIP" > "$RESFILE"; return
    fi
    /usr/bin/time -f %e -o "$RESFILE" xz -z -k -T"${CPUCORES}" -Qqq \
        -f "$WORKDIR/firefox102.tar" &
    PID=$!
    echo -n -e "* ${TNAMES[7]}:\t\t\t"
    animate 7
}

runyc() {
    RESFILE="$WORKDIR/runyc"
    local YCDIR
    YCDIR=$(ls -d "$WORKDIR"/y-cruncher*v*/ 2>/dev/null | head -1)
    if [ -z "$YCDIR" ]; then
        echo "SKIP" > "$RESFILE"; return
    fi
    cd "$YCDIR" || return
    rm -f "Pi"*.txt
    /usr/bin/time -f%e -o "$RESFILE" ./y-cruncher bench 1b -od:0 \
        -o "$WORKDIR" &>/dev/null &
    PID=$!
    echo -n -e "* ${TNAMES[8]}:\t\t\t"
    animate 8
}

# --- Asset preparation ---
prepare_assets() {
    echo -e "\n${TB}Checking, downloading and preparing test files...${TN}"

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
EOF
    echo "stream-ops $((4800 / CPUCORES))" >> "$WORKDIR/stressC"
    cat >> "$WORKDIR/stressC" <<-EOF
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

    if command -v x265 &>/dev/null && [ ! -f "$WORKDIR/bosphorus_hd.y4m" ]; then
        if [ ! -f "$WORKDIR/bosphorus_hd.7z" ] || ! 7z t "$WORKDIR/bosphorus_hd.7z" &>/dev/null; then
            echo "--> Downloading video archive..."
            wget -c --show-progress -qO "$WORKDIR/bosphorus_hd.7z" \
                http://ultravideo.cs.tut.fi/video/Bosphorus_1920x1080_120fps_420_8bit_YUV_Y4M.7z
        fi
        echo "--> Unzipping video..."
        cd "$WORKDIR"
        7z e bosphorus_hd.7z -o./ &>/dev/null
        mv Bosphorus_1920x1080_120fps_420_8bit_YUV.y4m bosphorus_hd.y4m 2>/dev/null || true
    fi

    if [ ! -f "$WORKDIR/firefox102.tar" ]; then
        if [ ! -f "$WORKDIR/firefox102.tar.xz" ] || ! xz -t "$WORKDIR/firefox102.tar.xz" &>/dev/null; then
            echo "--> Downloading Firefox archive..."
            wget -c --show-progress -qO "$WORKDIR/firefox102.tar.xz" \
                http://ftp.mozilla.org/pub/firefox/releases/102.9.0esr/source/firefox-102.9.0esr.source.tar.xz
        fi
        echo "--> Unzipping Firefox tarball..."
        xz -d -k -q -f "$WORKDIR/firefox102.tar.xz"
    fi

    if [ ! -d "$WORKDIR/ffmpeg-$FFMPEGVER" ]; then
        if [ ! -f "$WORKDIR/ffmpeg.tar.xz" ] || ! tar -tf "$WORKDIR/ffmpeg.tar.xz" &>/dev/null; then
            echo "--> Downloading ffmpeg archive..."
            wget -c --show-progress -qO "$WORKDIR/ffmpeg.tar.xz" \
                "https://ffmpeg.org/releases/ffmpeg-$FFMPEGVER.tar.xz"
        fi
        echo "--> Preparing ffmpeg..."
        cd "$WORKDIR"
        tar -xf ffmpeg.tar.xz
    fi

    if [ ! -d "$WORKDIR/y-cruncher"*v*/ ]; then
        local YCVER="0.8.6.9545"
        if [ ! -f "$WORKDIR/y-cruncher.tar.xz" ] || ! tar -tf "$WORKDIR/y-cruncher.tar.xz" &>/dev/null; then
            echo "--> Downloading y-cruncher archive..."
            wget -c --show-progress -qO "$WORKDIR/y-cruncher.tar.xz" \
                "https://github.com/Mysticial/y-cruncher/releases/download/v${YCVER}/y-cruncher.v${YCVER}-static.tar.xz"
        fi
        echo "--> Uncompressing y-cruncher..."
        cd "$WORKDIR"
        tar -xf y-cruncher.tar.xz
    fi

    echo -e "\n${TB}Preparing ffmpeg source...${TN}"
    if [ -d "$WORKDIR/ffmpeg-$FFMPEGVER" ]; then
        cd "$WORKDIR/ffmpeg-$FFMPEGVER" || true
        make -s distclean &>/dev/null || true
        ./configure --prefix=/tmp --disable-debug --enable-static \
            --enable-gpl --enable-version3 --disable-ffplay --disable-ffprobe \
            --disable-programs --disable-doc --disable-network --disable-protocols \
            --disable-filters --disable-iconv --enable-libdrm --disable-stripping \
            --disable-autodetect --cpu=native &>/dev/null || true
    fi
}

# --- Signal handling ---
killproc() {
    echo -e "\n**** Received SIGINT, aborting! ****\n"
    kill -- -$$ 2>/dev/null || true
    exit 2
}
exitproc() {
    rm -f "$WORKDIR"/run* "$WORKDIR"/stressC "$WORKDIR"/*.txt "$WORKDIR"/*.jpg "$WORKDIR"/*.ppm
    if "$CLEANUP"; then
        rm -f "$WORKDIR"/firefox102.tar.xz "$WORKDIR"/*.zst "$WORKDIR"/*.7z \
            "$WORKDIR"/ffmpeg.tar.xz "$WORKDIR"/y-cruncher.tar.xz
        rm -rf "$WORKDIR"/ffmpeg-* "$WORKDIR"/linux-* "$WORKDIR"/y-cruncher*/
        rm -f "$WORKDIR"/firefox102.tar "$WORKDIR"/bosphorus_hd.y4m
    fi
}
trap killproc INT
trap exitproc EXIT

# --- Main ---
while [ "$#" -gt 0 ]; do
    case "$1" in
        --workdir) WORKDIR="$2"; shift 2 ;;
        --ffmpeg-ver) FFMPEGVER="$2"; shift 2 ;;
        --kernel-ver) KERNVER="$2"; shift 2 ;;
        --no-download) NO_DOWNLOAD=true; shift ;;
        --cleanup)
            echo "Cleaning cache directory: $WORKDIR"
            rm -rf "$WORKDIR"/firefox102.tar.xz "$WORKDIR"/firefox102.tar "$WORKDIR"/bosphorus_hd*
            rm -rf "$WORKDIR"/*.7z "$WORKDIR"/ffmpeg.tar.xz "$WORKDIR"/ffmpeg-*
            rm -rf "$WORKDIR"/y-cruncher* "$WORKDIR"/run* "$WORKDIR"/stressC
            rm -f "$WORKDIR"/*.txt "$WORKDIR"/*.jpg "$WORKDIR"/*.ppm
            echo "Done."
            exit 0 ;;
        -h|--help)
            echo "Usage: sudo ./comprehensive_benchmarker.sh [--workdir DIR] [--no-download] [--cleanup]"
            echo "Runs 12 workloads on the CURRENT active scheduler using CachyOS benchmarker methodology."
            exit 0 ;;
        *) err "Unknown option: $1"; exit 1 ;;
    esac
done

[ "$RAMSIZE" -lt 3500 ] && { echo "Need at least 4 GB RAM"; exit 2; }
mkdir -p "$WORKDIR"

ulimit -n 4096

LOGFILE="$WORKDIR/benchie_${SCX:-none}_${CDATE}.log"
echo "=====================================================================" > "$LOGFILE"
echo "  scx_flow Comprehensive Benchmark  $(date)" >> "$LOGFILE"
echo "  Scheduler: ${SCX:-none} ${SCX_VERSION:-}" >> "$LOGFILE"
echo "  Kernel: $(uname -r)" >> "$LOGFILE"
echo "  CPU: $(nproc) cores / $(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo) GB RAM" >> "$LOGFILE"
echo "=====================================================================" >> "$LOGFILE"

say "Scheduler: ${SCX:-none} ${SCX_VERSION:-}"
say "Work dir: $WORKDIR"
say "Log file: $LOGFILE"

prepare_assets

say "Starting benchmarks..."
echo -e "\n${TB}Starting...${TN}\n" | tee -a "$LOGFILE"
sync
sleep 2

for WI in 0 1 2 3 4 5 6 7 8; do
    case $WI in
        0) runstress; RF="$WORKDIR/runstress" ;;
        1) runext;    RF="$WORKDIR/runffm" ;;
        2) runx265;   RF="$WORKDIR/runx265" ;;
        3) runargon;  RF="$WORKDIR/runargon" ;;
        4) runperf_sch; RF="$WORKDIR/runperfs" ;;
        5) runperf_mem; RF="$WORKDIR/runperfm" ;;
        6) runprime;  RF="$WORKDIR/runprime" ;;
        7) runxz;     RF="$WORKDIR/runxz" ;;
        8) runyc;     RF="$WORKDIR/runyc" ;;
    esac
    wait 2>/dev/null || true
    if [ -f "$RF" ] && [ "$(cat "$RF" 2>/dev/null)" = "SKIP" ]; then
        echo -e "* ${TNAMES[$WI]}:\t\t\tSKIPPED" >> "$LOGFILE"
        printf "* ${TNAMES[$WI]}:\t\t\tSKIPPED\n"
    fi
    sleep 2
done

# Calculate results
unset ARRAYTIME
ARRAYTIME=($(awk -F': ' '{print $2}' "$LOGFILE" 2>/dev/null || true))
TOTTIME="?"
if [ "${#ARRAYTIME[@]}" -gt 0 ]; then
    TOTTIME=$(IFS="+" ; python -c "print(round((${ARRAYTIME[*]}),2))" 2>/dev/null || echo "?")
fi

COEFF=$(python -c "print(round((($CPUCORES + 1) / 2 * 3.0 / 2) ** (1/3),2))" 2>/dev/null || echo "1")

echo -e "\n==================================================" | tee -a "$LOGFILE"
echo "  Total time: ${TOTTIME}s" | tee -a "$LOGFILE"
echo "==================================================" | tee -a "$LOGFILE"
echo "Total time (s): $TOTTIME" >> "$LOGFILE"

ok "Benchmark complete"
say "Results: $LOGFILE"
