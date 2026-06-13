#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Install scx_flow v3.0.4-cherryfix from the galpt/scx fork for local testing.
# This branch contains the rotating tier dispatch fix (Model A) for the
# runnable task stall (DEFICIT tier starvation) found during benchmarking.
# Every 4 dispatches rotate the starting tier so no tier waits longer
# than 3 dispatch calls before being serviced first.
#
# Usage:
#   sudo ./install_scx_flow_v3.0.4-cherryfix.sh
#
# To switch back to the PR branch:
#   sudo ./install_scx_flow_v3.0.4-cherrypick.sh

set -euo pipefail

BUILD_DIR="/tmp/scx-flow-v3.0.4-cherryfix-build"
INSTALL_PATH="/usr/bin/scx_flow"
FORK_BRANCH="scx_flow-v3.0.4-cherryfix"
FORK_REPO="https://github.com/galpt/scx.git"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$1"; }
step()  { printf "\n${BOLD}${CYAN}── %s ──${NC}\n" "$1\n"; }

if [ "$EUID" -ne 0 ]; then echo "Run as root."; exit 1; fi

step "Cloning scx_flow v3.0.4-cherryfix"
[ -d "$BUILD_DIR" ] && rm -rf "$BUILD_DIR"
git clone --branch "$FORK_BRANCH" --depth 1 "$FORK_REPO" "$BUILD_DIR"

step "Building"
cd "$BUILD_DIR"
cargo build --release -p scx_flow
info "Build complete."

step "Stopping conflicting services and processes"
systemctl stop scx 2>/dev/null || true
systemctl disable scx 2>/dev/null || true
pkill -x scx_flow 2>/dev/null || true
pkill -x scx_loader 2>/dev/null || true

step "Installing binary"
cp target/release/scx_flow "$INSTALL_PATH"
chmod 755 "$INSTALL_PATH"

step "Creating drop-in override (direct execution)"
mkdir -p /etc/systemd/system/scx.service.d
cat > /etc/systemd/system/scx.service.d/direct-exec.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/scx_flow
EOF

step "Enabling web UI for scx_loader-managed schedulers"
mkdir -p /etc/systemd/system/scx_loader.service.d
cat > /etc/systemd/system/scx_loader.service.d/flow-webui.conf << 'EOF'
# scx_flow Web UI needs TCP socket access on port 50005.
# Remove the network restrictions inherited by scheduler child processes.
[Service]
RestrictAddressFamilies=
SocketBindDeny=
EOF
systemctl daemon-reload

step "Starting scx_loader for GUI management"
if command -v scx_loader >/dev/null 2>&1 && systemctl list-unit-files scx_loader --no-legend >/dev/null 2>&1; then
    systemctl enable --now scx_loader 2>/dev/null || true
    info "scx_loader active — use CachyOS Kernel Manager GUI to start"
fi

step "Verification"
printf "  %-20s %s\n" "Binary:" "$(scx_flow --version 2>/dev/null || echo FAILED)"
printf "  %-20s %s\n" "scx.service:" "$(systemctl is-active scx 2>/dev/null || echo stopped)"
printf "  %-20s %s\n" "scx_loader:" "$(systemctl is-active scx_loader 2>/dev/null || echo inactive)"
printf "  %-20s %s\n" "sched_ext:" "$(cat /sys/kernel/sched_ext/state 2>/dev/null || echo unknown)"

rm -rf "$BUILD_DIR"
echo ""
echo "=== scx_flow v3.0.4-cherryfix installed ==="
echo "Rotating tier dispatch (Model A): dispatch phase rotates every call — no tier waits longer than 3 dispatches."
echo ""
echo "To test the fix:"
echo "  sudo ./reset_sched_ext_state.sh"
echo "  sudo ./mini_benchmarker.sh --schedulers scx_flow --runs 1"
echo ""
echo "To switch back to the PR branch:"
echo "  sudo ./install_scx_flow_v3.0.4-cherrypick.sh"
echo ""
echo "To remove scx_flow entirely:"
echo "  sudo ./uninstall.sh"
