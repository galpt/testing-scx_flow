#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Install scx_flow v3.0.0 (2-lane dispatch architecture)
# from the galpt/scx fork branch scx_flow-v3.0.0.
#
# v3.0.0 replaces the 5-lane classification system (temporal urgency,
# containment, 12+ tunables) with a minimal 2-lane system:
#
#   Quick lane (per-CPU FIFO DSQ):  wakeup tasks, 200us slice
#   Normal lane (global vtime DSQ): all other tasks, 1ms slice
#
# No containment.  No temporal urgency.  No classification beyond
# "wakeup vs. re-enqueue".  ~2900 fewer lines than v2.3.0.
#
# This installs to /usr/bin/scx_flow (same path as the stable v2.2.6),
# so uninstall.sh can cleanly remove it.
#
# Usage:
#   sudo ./install_scx_flow_v3.0.0.sh
#
set -euo pipefail

BUILD_DIR="/tmp/scx-flow-v3.0.0-build"
INSTALL_PATH="/usr/bin/scx_flow"
SERVICE_NAME="scx"
SYSTEMD_SERVICE="/etc/systemd/system/scx.service"
SCX_DEFAULTS="/etc/default/scx"
SCX_LOADER_SERVICE="scx_loader"
FORK_BRANCH="scx_flow-v3.0.0"
FORK_REPO="https://github.com/galpt/scx.git"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
RED='\033[0;31m'; YELLOW='\033[1;33m'
info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$1"; }
step()  { printf "\n${BOLD}${CYAN}── %s ──${NC}\n" "$1\n"; }
err()   { printf "${RED}[ERR ]${NC} %s\n" "$1" >&2; }

cleanup() { rm -rf "$BUILD_DIR" 2>/dev/null || true; }
trap 'cleanup' EXIT

echo "============================================================"
echo " Install scx_flow v3.0.0 (2-Lane Dispatch)"
echo "============================================================"

step "Checking dependencies"
for cmd in git cargo clang pkg-config; do
    if ! command -v "$cmd" &>/dev/null; then
        err "$cmd not found."
        exit 1
    fi
done
info "All build dependencies found."

if [ "$EUID" -ne 0 ]; then
    err "This script must be run as root (sudo)."
    exit 1
fi

step "Cloning scx_flow v3.0.0 branch"
[ -d "$BUILD_DIR" ] && rm -rf "$BUILD_DIR"
git clone --branch "$FORK_BRANCH" --depth 1 "$FORK_REPO" "$BUILD_DIR"
cd "$BUILD_DIR"

step "Building scx_flow v3.0.0"
cargo build --release -p scx_flow
info "Build complete."

step "Preparing the system"
# Stop scx.service if running (it conflicts with scx_loader used by GUI)
systemctl stop "$SERVICE_NAME" 2>/dev/null || true

step "Ensuring /etc/default/scx has SCX_SCHEDULER=scx_flow"
if [ -f "$SCX_DEFAULTS" ] && ! grep -q "^SCX_SCHEDULER=scx_flow" "$SCX_DEFAULTS" 2>/dev/null; then
    if [ "$(wc -l < "$SCX_DEFAULTS" 2>/dev/null || echo 0)" -le 1 ]; then
        # File is empty or nearly empty — write the required line
        printf 'SCX_SCHEDULER=scx_flow\n' > "$SCX_DEFAULTS"
    else
        # Append to existing content
        printf 'SCX_SCHEDULER=scx_flow\n' >> "$SCX_DEFAULTS"
    fi
elif [ ! -f "$SCX_DEFAULTS" ]; then
    printf 'SCX_SCHEDULER=scx_flow\n' > "$SCX_DEFAULTS"
fi
chmod 644 "$SCX_DEFAULTS" 2>/dev/null || true
info "SCX_SCHEDULER set to scx_flow"

step "Installing to ${INSTALL_PATH}"
cp target/release/scx_flow "$INSTALL_PATH"
chmod 755 "$INSTALL_PATH"

if [ -f "$SYSTEMD_SERVICE" ]; then
    # Override the shell-wrapper ExecStart with direct binary execution.
    mkdir -p /etc/systemd/system/scx.service.d
    cat > /etc/systemd/system/scx.service.d/direct-exec.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/scx_flow
EOF
    systemctl daemon-reload
fi

# Stop and disable scx.service (conflicts with scx_loader used by GUI)
systemctl stop "$SERVICE_NAME" 2>/dev/null || true
systemctl disable "$SERVICE_NAME" 2>/dev/null || true

# Enable scx_loader for GUI management via DBUS
if command -v scx_loader >/dev/null 2>&1; then
    if systemctl list-unit-files scx_loader --no-legend >/dev/null 2>&1; then
        systemctl enable --now scx_loader 2>/dev/null || true
    fi
    info "scx_loader is active — use the CachyOS Kernel Manager GUI to manage"
    info "or run: scx_flow --monitor 2"
fi

step "Verifying installation"
INSTALLED_VER="$("$INSTALL_PATH" --version 2>/dev/null || echo 'FAILED')"
printf "  %-20s %s\n" "scx_flow binary:" "$INSTALLED_VER"
printf "  %-20s %s\n" "scx.service:" "$(systemctl is-active scx 2>/dev/null || echo 'stopped')"
printf "  %-20s %s\n" "scx_loader:" "$(systemctl is-active scx_loader 2>/dev/null || echo 'inactive')"

# Show current scheduler state (may be inactive until GUI applies it)
printf "  %-20s %s\n" "Kernel state:" "$(cat /sys/kernel/sched_ext/state 2>/dev/null || echo 'unknown')"
_ops="$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || true)"
printf "  %-20s %s\n" "Active sched:" "${_ops:-none}"

cleanup

echo ""
echo "============================================================"
echo "  scx_flow v3.0.0 installed."
echo "============================================================"
echo ""
echo "  The v2.3.x branch is archived at scx_flow-v2.3.7."
echo ""
echo "  v3.0.0 replaces 5 lanes (urgent latency, latency, reserved,"
echo "  shared, contained) with 2 lanes (Quick, Normal)."
echo ""
echo "  - No containment (no watchdog crash, no 3-second freezes)"
echo "  - No temporal urgency (no bucket lockstep)"
echo "  - No classification beyond 'wakeup vs re-enqueue'"
echo "  - ~2900 fewer lines of code than v2.3.0"
echo ""
echo "  The scheduler is managed by scx_loader (DBUS).  Open the CachyOS"
echo "  Kernel Manager GUI and click Apply to start scx_flow v3.0.0."
echo ""
echo "  Monitor:  scx_flow --monitor 2"
