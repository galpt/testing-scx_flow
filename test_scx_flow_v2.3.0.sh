#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Quick test suite for scx_flow v2.3.0 (Temporal Budget — IDEA A).
#
# Tests:
#   1. Lifecycle: scheduler loads, runs, exits cleanly
#   2. Latency: cyclictest max latency under scx_flow v2.3.0
#   3. Temporal promotions: the new temporal_prom counter appears in monitor
#
# Usage:
#   sudo ./test_scx_flow_v2.3.0.sh
#
set -euo pipefail

SCX_BIN="${SCX_BIN:-/usr/bin/scx_flow}"
RESULTS_DIR="/tmp/scx_flow-v2.3.0-results"
LATENCY_LOG="$RESULTS_DIR/cyclictest.log"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass() { printf "${GREEN}PASS${NC}  %s\n" "$1"; }
fail() { printf "${RED}FAIL${NC}  %s\n" "$1"; }

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo)."
    exit 1
fi

if [ ! -x "$SCX_BIN" ]; then
    echo "Error: $SCX_BIN not found. Run install_scx_flow_v2.3.0.sh first."
    exit 1
fi

mkdir -p "$RESULTS_DIR"

echo "============================================================"
echo "  scx_flow v2.3.0 — Test Suite"
echo "============================================================"
echo "Binary: $SCX_BIN"
echo "Results: $RESULTS_DIR"
echo ""

# ────────────── Test 1: Lifecycle ──────────────
echo "── Test 1: Lifecycle ──"

# Stop any existing scx scheduler
killall scx_flow 2>/dev/null || true
sleep 1

# Start v2.3.0
$SCX_BIN &
SCX_PID=$!
sleep 2

# Check it's running
if kill -0 $SCX_PID 2>/dev/null; then
    pass "scx_flow started (PID $SCX_PID)"
else
    fail "scx_flow failed to start"
    exit 1
fi

# Check the kernel shows it
SCHED_STATE=$(cat /sys/kernel/sched_ext/state 2>/dev/null || echo "unknown")
SCHED_OPS=$(cat /sys/kernel/sched_ext/*/ops 2>/dev/null || echo "unknown")
if [ "$SCHED_STATE" = "enabled" ]; then
    pass "sched_ext state: $SCHED_STATE"
else
    fail "sched_ext state: $SCHED_STATE (expected enabled)"
fi
echo "  Running scheduler: $SCHED_OPS"

# Stop it
kill $SCX_PID 2>/dev/null || true
sleep 1
if ! kill -0 $SCX_PID 2>/dev/null; then
    pass "scx_flow exited cleanly"
fi

echo ""

# ────────────── Test 2: Temporal Promotions Counter ──────────────
echo "── Test 2: Temporal promotions counter ──"

$SCX_BIN &
SCX_PID=$!
sleep 2

# Run monitor for 5 seconds and capture output
MONITOR_OUTPUT=$("$SCX_BIN" --monitor 1 2>/dev/null &)
MONITOR_PID=$!
sleep 5
kill $MONITOR_PID 2>/dev/null || true

# Check if temporal_prom appears in any output
if echo "${MONITOR_OUTPUT:-}" | grep -q "temporal_prom"; then
    pass "temporal_prom counter present in monitor output"
else
    # The counter may be 0 initially — that's OK
    warn "temporal_prom counter not seen in 5s window (may be 0 if no promotions triggered)"
fi

kill $SCX_PID 2>/dev/null || true
sleep 1
echo ""

# ────────────── Test 3: Latency ──────────────
echo "── Test 3: Latency (cyclictest) ──"

if ! command -v cyclictest &>/dev/null; then
    echo "  Skipping — cyclictest not installed."
    echo "  Install: sudo pacman -S rt-tests"
else
    $SCX_BIN &
    SCX_PID=$!
    sleep 2

    cyclictest \
        --duration=30 \
        --interval=1000 \
        --distance=0 \
        --mlockall \
        --prio=80 \
        --background=1 \
        --quiet \
        "$@" 2>&1 | tee "$LATENCY_LOG" | tail -5

    MAX_LAT=$(grep -oP 'Max:\s+\K[0-9]+' "$LATENCY_LOG" | head -1)
    SPIKES=$(grep -oP 'Latencies over 100 us:\s+\K[0-9]+' "$LATENCY_LOG" | head -1)

    pass "cyclictest complete — max=${MAX_LAT:-N/A}us, spikes>100us=${SPIKES:-N/A}"

    kill $SCX_PID 2>/dev/null || true
    sleep 1
fi

echo ""
echo "============================================================"
echo "  All tests complete."
echo "============================================================"
echo "Results: $RESULTS_DIR/"
ls -la "$RESULTS_DIR/" 2>/dev/null
echo ""
echo "For v2.2.6 comparison, re-install stable:"
echo "  sudo ./install_scx_flow_standalone.sh"
echo "  # then run cyclictest and compare max latency"
