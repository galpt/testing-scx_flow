#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Single-run WebGL Aquarium benchmark for the active scheduler.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_SCRIPT="$SCRIPT_DIR/aquarium_probe.js"
BENCHMARK_LOG="${BENCHMARK_LOG:-$SCRIPT_DIR/aquarium_benchmark_$(date +%Y%m%d_%H%M%S).log}"
SUMMARY_FILE=""
EXPECTED_SCHEDULER="scx_flow"
BENCHMARK_LABEL=""
FISH_COUNT=2000
DURATION_SECONDS=45
SETTLE_SECONDS=5
VIEWPORT_WIDTH=1600
VIEWPORT_HEIGHT=900
HEADLESS=0
BROWSER_PATH=""
STRESS_CPU_WORKERS=0
STRESS_IOMIX_WORKERS=4
STRESS_VM_WORKERS=2
STRESS_VM_BYTES="256M"
AQUARIUM_URL="https://webglsamples.org/aquarium/aquarium.html"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

usage() {
    cat <<EOF
Usage: ./aquarium_benchmark.sh [options]

Run a single Aquarium + stress-ng benchmark against the currently active scheduler.

Options:
  --log-file PATH             Write the benchmark log to PATH
  --summary-file PATH         Write machine-readable summary metrics to PATH
  --expected-scheduler NAME   Expected active scheduler, 'none', or 'any'
  --label TEXT                Optional benchmark label written into the log
  --fish-count N              Aquarium fish count (default: ${FISH_COUNT})
  --duration-seconds N        Measurement duration after settle (default: ${DURATION_SECONDS})
  --settle-seconds N          Warm-up duration before sampling (default: ${SETTLE_SECONDS})
  --width N                   Browser viewport width (default: ${VIEWPORT_WIDTH})
  --height N                  Browser viewport height (default: ${VIEWPORT_HEIGHT})
  --headless                  Run browser headless (not recommended for desktop comparisons)
  --browser-path PATH         Override Chromium executable path
  -h, --help                  Show this help
EOF
}

is_expected_scheduler_match() {
    local current="$1"
    local expected_short=""

    case "$EXPECTED_SCHEDULER" in
        any) return 0 ;;
        none) [ -z "$current" ] || [ "$current" = "none" ] || [ "$current" = "unknown" ] ;;
        *)
            expected_short="${EXPECTED_SCHEDULER#scx_}"
            case "$1" in
                "$EXPECTED_SCHEDULER"|"$EXPECTED_SCHEDULER"_*|"$expected_short"|"$expected_short"_*) return 0 ;;
                *) return 1 ;;
            esac
            ;;
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

probe_dependency_check() {
    if ! have_cmd node; then
        log "${YELLOW}Missing:${NC} node"
        log "Install Node.js first."
        exit 1
    fi

    if ! have_cmd stress-ng; then
        log "${YELLOW}Missing:${NC} stress-ng"
        log "Run sudo ./install_benchmark_deps.sh first."
        exit 1
    fi

    if [ "$HEADLESS" -eq 0 ] && [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        log "${YELLOW}Missing:${NC} GUI display environment"
        log "Use a graphical session or pass --headless for non-desktop validation."
        exit 1
    fi
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
        --width)
            VIEWPORT_WIDTH="$2"
            shift 2
            ;;
        --height)
            VIEWPORT_HEIGHT="$2"
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
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

mkdir -p "$(dirname "$BENCHMARK_LOG")"
echo "=== Aquarium Benchmark Log ===" > "$BENCHMARK_LOG"
log "Benchmark started at $(date)"
if [ -n "$BENCHMARK_LABEL" ]; then
    log "Benchmark label: $BENCHMARK_LABEL"
fi

header "System Information"
log "Kernel: $(uname -r)"
log "CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
log "CPU Cores: $(nproc)"
log "Fish count: ${FISH_COUNT}"
log "Duration: ${DURATION_SECONDS}s"
log "Settle: ${SETTLE_SECONDS}s"
log "Viewport: ${VIEWPORT_WIDTH}x${VIEWPORT_HEIGHT}"
log "Headless: ${HEADLESS}"

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

probe_dependency_check

SCHEDULER_MONITOR_LINE=""
if [[ "$CURRENT_SCHED" == scx_* ]]; then
    scheduler_short="${CURRENT_SCHED%%_*}"
    if [[ "$CURRENT_SCHED" == scx_flow_* ]]; then
        scheduler_short="scx_flow"
    fi
    if have_cmd "$EXPECTED_SCHEDULER"; then
        SCHEDULER_MONITOR_LINE="$(capture_scheduler_monitor_line "$EXPECTED_SCHEDULER")"
    fi
fi

TOTAL_STRESS_SECONDS=$((DURATION_SECONDS + SETTLE_SECONDS + 5))
STRESS_LOG="$(mktemp)"
PROBE_JSON="$(mktemp)"

cleanup() {
    rm -f "$STRESS_LOG" "$PROBE_JSON"
}
trap cleanup EXIT

header "Aquarium + Stress Benchmark"
log "Launching mixed stress-ng workload for ${TOTAL_STRESS_SECONDS}s..."
stress-ng \
    --cpu "$STRESS_CPU_WORKERS" \
    --iomix "$STRESS_IOMIX_WORKERS" \
    --vm "$STRESS_VM_WORKERS" \
    --vm-bytes "$STRESS_VM_BYTES" \
    --timeout "${TOTAL_STRESS_SECONDS}s" \
    --metrics-brief >"$STRESS_LOG" 2>&1 &
STRESS_PID=$!

log "Launching Aquarium probe..."
probe_cmd=(
    node "$PROBE_SCRIPT"
    --out-json "$PROBE_JSON"
    --url "$AQUARIUM_URL"
    --fish-count "$FISH_COUNT"
    --duration-seconds "$DURATION_SECONDS"
    --settle-seconds "$SETTLE_SECONDS"
    --width "$VIEWPORT_WIDTH"
    --height "$VIEWPORT_HEIGHT"
)
if [ "$HEADLESS" -eq 1 ]; then
    probe_cmd+=(--headless)
fi
if [ -n "$BROWSER_PATH" ]; then
    probe_cmd+=(--browser-path "$BROWSER_PATH")
fi

"${probe_cmd[@]}" 2>&1 | tee -a "$BENCHMARK_LOG"

wait "$STRESS_PID" || true
cat "$STRESS_LOG" >> "$BENCHMARK_LOG"

STRESSNG_BOGO_OPS_PER_SEC=$(awk '
($1 == "cpu" || $1 == "iomix" || $1 == "vm") && $6 ~ /^[0-9.]+$/ {
    sum += $6
}
END {
    if (sum > 0)
        printf "%.2f\n", sum
}' "$STRESS_LOG")

readarray -t PROBE_KV < <(python3 - "$PROBE_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], 'r', encoding='utf-8') as handle:
    data = json.load(handle)

keys = [
    "ui_avg_fps",
    "ui_last_fps",
    "raf_avg_fps",
    "raf_median_fps",
    "raf_1p_low_fps",
    "p95_frame_ms",
    "p99_frame_ms",
    "jank_over_33ms",
    "jank_over_50ms",
    "jank_over_100ms",
    "frame_samples",
    "canvas_width",
    "canvas_height",
]

for key in keys:
    value = data.get(key, "")
    if value is None:
        value = ""
    print(f"{key}={value}")
PY
)

for kv in "${PROBE_KV[@]}"; do
    IFS='=' read -r key value <<< "$kv"
    if [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        printf -v "$key" "%s" "$value"
    fi
done

header "Results"
log "Aquarium avg FPS        : ${raf_avg_fps:-n/a}"
log "Aquarium median FPS     : ${raf_median_fps:-n/a}"
log "Aquarium 1% low FPS     : ${raf_1p_low_fps:-n/a}"
log "Aquarium UI avg FPS     : ${ui_avg_fps:-n/a}"
log "Aquarium p95 frame ms   : ${p95_frame_ms:-n/a}"
log "Aquarium p99 frame ms   : ${p99_frame_ms:-n/a}"
log "Jank >33ms              : ${jank_over_33ms:-n/a}"
log "Jank >50ms              : ${jank_over_50ms:-n/a}"
log "Jank >100ms             : ${jank_over_100ms:-n/a}"
log "Frame samples           : ${frame_samples:-n/a}"
if [ -n "${STRESSNG_BOGO_OPS_PER_SEC:-}" ]; then
    log "Stress-ng bogo ops/s    : ${STRESSNG_BOGO_OPS_PER_SEC}"
fi

if [ -n "$SUMMARY_FILE" ]; then
    mkdir -p "$(dirname "$SUMMARY_FILE")"
    cat > "$SUMMARY_FILE" <<EOF
BENCHMARK_LABEL=${BENCHMARK_LABEL:-aquarium benchmark}
EXPECTED_SCHEDULER=${EXPECTED_SCHEDULER}
KERNEL_RELEASE=$(uname -r)
SCHED_EXT_STATE=${SCHED_EXT_STATE}
CURRENT_SCHEDULER=${CURRENT_SCHED}
AQUARIUM_FISH_COUNT=${FISH_COUNT}
AQUARIUM_DURATION_SECONDS=${DURATION_SECONDS}
AQUARIUM_SETTLE_SECONDS=${SETTLE_SECONDS}
AQUARIUM_RAF_AVG_FPS=${raf_avg_fps:-}
AQUARIUM_RAF_MEDIAN_FPS=${raf_median_fps:-}
AQUARIUM_RAF_1P_LOW_FPS=${raf_1p_low_fps:-}
AQUARIUM_UI_AVG_FPS=${ui_avg_fps:-}
AQUARIUM_UI_LAST_FPS=${ui_last_fps:-}
AQUARIUM_P95_FRAME_MS=${p95_frame_ms:-}
AQUARIUM_P99_FRAME_MS=${p99_frame_ms:-}
AQUARIUM_JANK_OVER_33MS=${jank_over_33ms:-}
AQUARIUM_JANK_OVER_50MS=${jank_over_50ms:-}
AQUARIUM_JANK_OVER_100MS=${jank_over_100ms:-}
AQUARIUM_FRAME_SAMPLES=${frame_samples:-}
AQUARIUM_CANVAS_WIDTH=${canvas_width:-}
AQUARIUM_CANVAS_HEIGHT=${canvas_height:-}
STRESSNG_BOGO_OPS_PER_SEC=${STRESSNG_BOGO_OPS_PER_SEC:-}
SCHEDULER_MONITOR_LINE=${SCHEDULER_MONITOR_LINE}
LOG_PATH=${BENCHMARK_LOG}
EOF
fi

log ""
log "Benchmark complete."
log "Results saved to: ${BENCHMARK_LOG}"
if [ -n "$SUMMARY_FILE" ]; then
    log "Summary saved to: ${SUMMARY_FILE}"
fi
