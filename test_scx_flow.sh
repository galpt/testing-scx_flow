#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Test script for scx_flow - runs uninstall, install, and shows status
set -e

cd "$(dirname "$0")"

echo "========================================"
echo "Testing scx_flow"
echo "Current time: $(date)"
echo "========================================"
echo ""

TEST_START_EPOCH="$(date +%s)"

echo ">>> Step 1: Uninstalling..."
sudo sh uninstall.sh
echo ""

echo ">>> Step 2: Installing..."
sudo sh install.sh
echo ""

echo ">>> Step 3: Checking sched_ext state..."
cat /sys/kernel/sched_ext/state
echo ">>> Active scheduler:"
cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "(none)"
echo ""

echo ">>> Step 4: Checking status helper..."
./status_scx_flow.sh || true
echo ""

echo ">>> Step 5: Checking systemctl status..."
sudo systemctl status scx.service | head -10
echo ""

echo ">>> Step 6: Checking kernel log for scx since test start..."
sudo journalctl -k --since "@$TEST_START_EPOCH" --no-pager | grep "sched_ext:\\|scx_flow" || true
echo ""

echo "========================================"
echo "Test complete"
echo "========================================"
