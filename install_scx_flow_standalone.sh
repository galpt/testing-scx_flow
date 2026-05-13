#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Install scx_flow as the default sched-ext scheduler.
# Cleans up all temporary files after install — only leaves:
#   /usr/bin/scx_flow, /etc/systemd/system/scx.service, /etc/default/scx
#
# Usage: ./install_scx_flow_standalone.sh
#
set -euo pipefail

CACHE_DIR="$HOME/.cache/scx-flow-install"
SCX_CLONE="$CACHE_DIR/scx"
TESTING_CLONE="$CACHE_DIR/testing-scx_flow"
SCX_REPO="https://github.com/sched-ext/scx"
TESTING_REPO="https://github.com/galpt/testing-scx_flow"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$1"; }
step()  { printf "\n${BOLD}${CYAN}── %s ──${NC}\n" "$1"; }

cleanup() {
    sudo rm -rf "$HOME/.cache/scx-flow-build" 2>/dev/null || true
    sudo rm -rf "$CACHE_DIR" 2>/dev/null || true
}
trap 'cleanup' EXIT

echo "============================================================"
echo " Install scx_flow sched-ext scheduler"
echo "============================================================"
echo ""

info "Requesting sudo access (password needed once)..."
sudo -v
while true; do sudo -n true; sleep 30; done 2>/dev/null &
KEEPER_PID=$!
trap 'cleanup; kill $KEEPER_PID 2>/dev/null' EXIT

step "Stop scx_loader"
sudo systemctl disable --now scx_loader 2>/dev/null || true
info "scx_loader stopped."

step "Clone scheduler source"
sudo rm -rf "$SCX_CLONE" 2>/dev/null || true
mkdir -p "$CACHE_DIR"
git clone --depth=1 "$SCX_REPO" "$SCX_CLONE"
info "Source cloned."

step "Clone install helper"
sudo rm -rf "$TESTING_CLONE" 2>/dev/null || true
git clone --depth=1 "$TESTING_REPO" "$TESTING_CLONE"
info "Helper cloned."

step "Run install.sh (builds scx_flow, creates scx.service)"
cd "$TESTING_CLONE"
sudo SCX_SOURCE_DIR="$SCX_CLONE/scheds/experimental/scx_flow" \
    sh install.sh --force 2>&1

step "Verification"
printf "  %-20s %s\n" "scx_flow:" "$(scx_flow --version 2>/dev/null || echo 'FAILED')"
printf "  %-20s %s\n" "scx.service:" "$(systemctl is-active scx 2>/dev/null || echo 'FAILED')"
printf "  %-20s %s\n" "Scheduler:" "$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo 'checking...')"

echo ""
echo "============================================================"
echo " Done! scx_flow is installed and active."
echo "  Temp files removed."
echo ""
echo "  Manage:  systemctl [status|stop|start|restart] scx"
echo "============================================================"
