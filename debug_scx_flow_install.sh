#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Debug installation failure of scx_flow v3.0.3.
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
printf "  sched_ext root ops: "
cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "none"
printf "  BPF unprivileged: "
cat /proc/sys/kernel/unprivileged_bpf_disabled 2>/dev/null || echo "unknown"
printf "  MEMLOCK limit: " 
ulimit -l 2>/dev/null || echo "unknown"

step "2. Build scx_flow v3.0.3 from local repo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../scx" && pwd)"
cd "$REPO_DIR"
cargo build --release -p scx_flow 2>&1
BINARY="$REPO_DIR/target/release/scx_flow"
printf "\n  Binary: %s\n" "$BINARY"
printf "  Version: "; "$BINARY" --version 2>&1 || echo "(version flag failed)"
printf "  Size: "; stat --format='%s bytes' "$BINARY" 2>/dev/null || true

step "3. Stop existing schedulers"
systemctl stop scx.service 2>/dev/null || true
pkill -x scx_flow scx_cosmos scx_bpfland 2>/dev/null || true
sleep 1

step "4. Start scx_flow (full debug) and capture logs"
printf "\n  Starting scx_flow (timeout 5s)...\n"
ulimit -l unlimited 2>/dev/null || printf "  (cannot raise MEMLOCK limit)\n"
# Run synchronously with timeout so we capture ALL output
timeout 5 "$BINARY" --debug > /tmp/scx_flow_debug.log 2>&1
EXIT_CODE=$?
printf "\n  Exit code: %d\n" "$EXIT_CODE"

if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 124 ]; then
    info "scx_flow completed (exit=$EXIT_CODE)"
    if [ $EXIT_CODE -eq 124 ]; then
        info "  (exit 124 = timeout after 5s — likely it was RUNNING)"
    fi
else
    err "scx_flow failed (exit=$EXIT_CODE)"
    printf "\n  --- scx_flow stdout/stderr ---\n"
    cat /tmp/scx_flow_debug.log 2>/dev/null || echo "(empty)"
    printf "\n  --- dmesg (sched_ext/BPF/verifier) ---\n"
    dmesg 2>/dev/null | grep -i -E 'sched_ext|bpf|scx_flow|verifier' | tail -40
    printf "\n  --- journalctl (scx.service) ---\n"
    journalctl -u scx.service -n 20 --no-pager 2>/dev/null || echo "(no scx.service)"
fi

step "5. Active scheduler check"
printf "  sched_ext state: "
cat /sys/kernel/sched_ext/state 2>/dev/null || echo "unavailable"
printf "  Active scheduler: "
cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "none"

step "6. Cleanup"
rm -f /tmp/scx_flow_debug.log
printf "\nDone.\n"
