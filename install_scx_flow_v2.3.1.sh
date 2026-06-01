#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Install scx_flow v2.3.1 (Temporal Budget + Adaptive Slice — IDEAS-003)
# from the galpt/scx fork branch scx_flow-v2.3.1.
#
# v2.3.1 adds the adaptive minimum slice: budget-exhausted tasks that stay
# runnable grow their effective time slice from 50us up to 1ms automatically,
# preventing the preemption-loop trap that caused game freezes on v2.3.0.
#
# This installs to /usr/bin/scx_flow (same path as the stable v2.2.6),
# so uninstall.sh can cleanly remove it, and install_scx_flow_standalone.sh
# can replace it with the upstream version.
#
# Usage:
#   sudo ./install_scx_flow_v2.3.1.sh
#
# To switch between versions:
#   sudo ./install_scx_flow_v2.3.0.sh    # temporal budget (no adaptive slice)
#   sudo ./install_scx_flow_v2.3.1.sh    # temporal budget + adaptive slice
#   sudo ./install_scx_flow_standalone.sh # stable v2.2.6 from upstream
#
#   sudo ./uninstall.sh                  # remove any version
#
set -euo pipefail

BUILD_DIR="/tmp/scx-flow-v2.3.1-build"
INSTALL_PATH="/usr/bin/scx_flow"
SERVICE_NAME="scx"
SCX_DEFAULTS="/etc/default/scx"
SYSTEMD_SERVICE="/etc/systemd/system/scx.service"
SCX_LOADER_SERVICE="scx_loader"
FORK_BRANCH="scx_flow-v2.3.1"
FORK_REPO="https://github.com/galpt/scx.git"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
RED='\033[0;31m'; YELLOW='\033[1;33m'
info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$1"; }
step()  { printf "\n${BOLD}${CYAN}── %s ──${NC}\n" "$1\n"; }
warn()  { printf "${BOLD}${YELLOW}[WARN]${NC} %s\n" "$1"; }
err()   { printf "${RED}[ERR ]${NC} %s\n" "$1" >&2; }

cleanup() {
    rm -rf "$BUILD_DIR" 2>/dev/null || true
}
trap 'cleanup' EXIT

# ──────────────────────────────────────────────
# 0. Prerequisites
# ──────────────────────────────────────────────
echo "============================================================"
echo " Install scx_flow v2.3.1 (Temporal Budget + Adaptive Slice)"
echo "============================================================"

step "Checking dependencies"
for cmd in git cargo clang pkg-config; do
    if ! command -v "$cmd" &>/dev/null; then
        err "$cmd not found. Install build dependencies first."
        echo "  Arch:  sudo pacman -S base-devel clang cargo pkg-config"
        echo "  Ubuntu: sudo apt install build-essential clang cargo pkg-config libelf-dev"
        exit 1
    fi
done
info "All build dependencies found."

if [ "$EUID" -ne 0 ]; then
    err "This script must be run as root (sudo)."
    exit 1
fi

# ──────────────────────────────────────────────
# 1. Clone and build
# ──────────────────────────────────────────────
step "Cloning scx_flow v2.3.1 branch"
if [ -d "$BUILD_DIR" ]; then
    rm -rf "$BUILD_DIR"
fi
git clone --branch "$FORK_BRANCH" --depth 1 "$FORK_REPO" "$BUILD_DIR"
info "Cloned ${FORK_BRANCH} from ${FORK_REPO}"
cd "$BUILD_DIR"

step "Building scx_flow v2.3.1"
cargo build --release -p scx_flow
info "Build complete."

# ──────────────────────────────────────────────
# 2. Stop conflicting loader
# ──────────────────────────────────────────────
step "Preparing the system"
systemctl disable --now "$SCX_LOADER_SERVICE" 2>/dev/null || true
info "scx_loader stopped (if it was running)."

# If scx.service is already running, stop it so we can update the binary
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl stop "$SERVICE_NAME"
    info "scx.service stopped for binary update."
fi

# ──────────────────────────────────────────────
# 3. Install binary to /usr/bin/scx_flow
# ──────────────────────────────────────────────
step "Setting SCX_SCHEDULER=scx_flow in /etc/default/scx"
if [ -f "$SCX_DEFAULTS" ] && ! grep -q "^SCX_SCHEDULER=scx_flow" "$SCX_DEFAULTS" 2>/dev/null; then
    printf 'SCX_SCHEDULER=scx_flow\n' >> "$SCX_DEFAULTS"
elif [ ! -f "$SCX_DEFAULTS" ]; then
    printf 'SCX_SCHEDULER=scx_flow\n' > "$SCX_DEFAULTS"
fi
chmod 644 "$SCX_DEFAULTS" 2>/dev/null || true
info "SCX_SCHEDULER set to scx_flow"

step "Installing to ${INSTALL_PATH}"
step "Installing to ${INSTALL_PATH}"
cp target/release/scx_flow "$INSTALL_PATH"
chmod 755 "$INSTALL_PATH"
info "Installed: ${INSTALL_PATH}"

# ──────────────────────────────────────────────
# 4. Ensure scx.service is set up
# ──────────────────────────────────────────────
if [ -f "$SYSTEMD_SERVICE" ]; then
    # Service file exists — just restart with the new binary
    systemctl daemon-reload
    systemctl restart "$SERVICE_NAME"
    info "scx.service restarted with v2.3.1 binary."
else
    info "scx.service not found — creating it via install.sh."
    TESTING_CLONE="/tmp/scx-flow-v2.3.1-testing"
    rm -rf "$TESTING_CLONE"
    git clone --depth 1 "https://github.com/galpt/testing-scx_flow.git" "$TESTING_CLONE"
    SCX_SOURCE_DIR="$BUILD_DIR/scheds/experimental/scx_flow" \
        sh "$TESTING_CLONE/install.sh" --force 2>&1 | grep -v "build\|cargo\|Compiling\|Finished"
    rm -rf "$TESTING_CLONE"
    info "scx.service created and started."
fi

# ──────────────────────────────────────────────
# 5. Verify
# ──────────────────────────────────────────────
step "Verifying installation"
INSTALLED_VER="$("$INSTALL_PATH" --version 2>/dev/null || echo 'FAILED')"
printf "  %-20s %s\n" "scx_flow binary:" "$INSTALLED_VER"
printf "  %-20s %s\n" "scx.service:" "$(systemctl is-active scx 2>/dev/null || echo 'FAILED')"
printf "  %-20s %s\n" "Active scheduler:" "$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo 'not yet')"

cleanup

echo ""
echo "============================================================"
echo "  scx_flow v2.3.1 installed."
echo "============================================================"
echo ""
echo "  The v2.3.1 binary replaces /usr/bin/scx_flow."
echo ""
echo "  v2.3.1 adds the adaptive minimum slice: budget-exhausted tasks"
echo "  that stay runnable grow their slice from 50us up to 1ms."
echo "  This prevents the game-freeze issue found in v2.3.0."
echo ""
echo "  To install v2.3.0 instead (temporal budget, no adaptive slice):"
echo "    sudo ./install_scx_flow_v2.3.0.sh"
echo ""
echo "  To revert to stable v2.2.6 from upstream:"
echo "    sudo ./install_scx_flow_standalone.sh"
echo ""
echo "  To remove scx_flow entirely:"
echo "    sudo ./uninstall.sh"
echo ""
echo "  Manage:  systemctl [status|stop|start|restart] scx"
echo "  Monitor:  scx_flow --monitor 2"
