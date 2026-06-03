#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Debug installation failure of scx_flow v3.0.1.
# Run: sudo bash debug_scx_flow_install.sh
# Then copy-paste the full output.

set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'
RED='\033[0;31m'; NC='\033[0m'
info() { printf "${GREEN}[INFO]${NC}  %s\n" "$1"; }
step() { printf "\n${BOLD}${CYAN}-- %s --${NC}\n" "$1"; }
err()  { printf "${RED}[ERR]${NC}  %s\n" "$1"; }

if [ "$EUID" -ne 0 ]; then
    err "Run with sudo."
    exit 1
fi

step "1. Kernel and sched_ext state"
printf "  Kernel: %s\n" "$(uname -r)"
printf "  sched_ext state: "
cat /sys/kernel/sched_ext/state 2>/dev/null || echo "unavailable"
printf "  Active scheduler: "
cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "none"

step "2. Build scx_flow v3.0.1"
BUILD_DIR="/tmp/scx-flow-debug-$(date +%s)"
git clone --branch scx_flow-v3.0.1 --depth 1 \
    https://github.com/galpt/scx.git "$BUILD_DIR" 2>&1
cd "$BUILD_DIR"
cargo build --release -p scx_flow 2>&1
BINARY="$BUILD_DIR/target/release/scx_flow"
printf "\n  Binary: %s\n" "$BINARY"
printf "  Version: "; "$BINARY" --version 2>&1 || echo "(version flag failed)"

step "3. Stop existing schedulers"
systemctl stop scx.service 2>/dev/null || true
pkill -x scx_flow scx_cosmos scx_bpfland 2>/dev/null || true
sleep 1

step "4. Start scx_flow and capture logs"
printf "\n  Starting scx_flow (timeout 5s)...\n"
timeout 5 "$BINARY" > /tmp/scx_flow_debug.log 2>&1 &
PID=$!
sleep 3

if kill -0 "$PID" 2>/dev/null; then
    info "scx_flow is RUNNING (PID $PID)"
    printf "  sched_ext state: "
    cat /sys/kernel/sched_ext/state 2>/dev/null || echo "unknown"
    printf "  Active scheduler: "
    cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "none"
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
else
    err "scx_flow failed to start or exited immediately"
    printf "\n  --- scx_flow stdout/stderr ---\n"
    cat /tmp/scx_flow_debug.log 2>/dev/null || echo "(empty)"
    printf "\n  --- dmesg (sched_ext/BPF/verifier) ---\n"
    dmesg 2>/dev/null | grep -i -E 'sched_ext|bpf|scx_flow|verifier' | tail -30
    printf "\n  --- journalctl (scx.service) ---\n"
    journalctl -u scx.service -n 20 --no-pager 2>/dev/null || echo "(no scx.service)"
fi

step "5. Cleanup"
rm -rf "$BUILD_DIR"
printf "\nDone.\n"
