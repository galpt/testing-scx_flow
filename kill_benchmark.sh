#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Kill benchmark processes

echo "=== Killing benchmark processes ==="

# Kill common benchmark tools
pkill -9 -f "mini_benchmarker.sh" 2>/dev/null || true
pkill -9 -f "benchmark.sh" 2>/dev/null || true
pkill -9 -f "hackbench" 2>/dev/null || true
pkill -9 -f "stress-ng" 2>/dev/null || true
pkill -9 -f "tbench" 2>/dev/null || true
pkill -9 -f "lmbench" 2>/dev/null || true
pkill -9 -f "sysbench" 2>/dev/null || true
pkill -9 -f "perf" 2>/dev/null || true
pkill -9 -f "cyclictest" 2>/dev/null || true
pkill -9 -f "rt-tests" 2>/dev/null || true

echo "Benchmark processes killed."
echo ""
echo "This also stops mini_benchmarker/benchmark wrappers if they were running."
echo ""
echo "Note: scx_flow may still be running."
echo "To stop scx_flow: sudo ./reset_sched_ext_state.sh"
