#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Debug scx_flow v3.1.0 (Waiting Room) — capture all output to a log file
# for analysis.  Run with sudo.
#
# Usage: sudo bash debug_scx_flow_3.1.0.sh
#
# Output: /tmp/scx_flow_3.1.0_debug_YYYYMMDD_HHMMSS.log

set -euo pipefail

LOG="/tmp/scx_flow_3.1.0_debug_$(date +%Y%m%d_%H%M%S).log"
BUILD_DIR="/tmp/scx-flow-v3.1.0-debug-build"
BRANCH="flow-3.1.0"
REPO="https://github.com/galpt/scx.git"
BINARY="$BUILD_DIR/target/release/scx_flow"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; NC='\033[0m'

log() {
    echo -e "$1" | tee -a "$LOG"
    echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG"
}

step()  { log "\n${BOLD}${CYAN}── %s ──${NC}\n" "$1"; }

if [ "$EUID" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi

rm -f "$LOG"

step "1. Kernel and sched_ext state"
log "  Kernel: $(uname -r)"
log "  sched_ext state: $(cat /sys/kernel/sched_ext/state 2>/dev/null || echo 'unavailable')"
log "  sched_ext ops:   $(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo 'none')"
log "  unprivileged_bpf: $(cat /proc/sys/kernel/unprivileged_bpf_disabled 2>/dev/null || echo 'unknown')"
log "  MEMLOCK limit: $(ulimit -l 2>/dev/null || echo 'unknown')"

step "2. Clone and build scx_flow v3.1.0 from $BRANCH"
rm -rf "$BUILD_DIR"
git clone --branch "$BRANCH" --depth 1 "$REPO" "$BUILD_DIR" 2>&1 | tee -a "$LOG"
cd "$BUILD_DIR"
cargo build --release -p scx_flow 2>&1 | tee -a "$LOG"
log ""
if [ -x "$BINARY" ]; then
    log "  Binary: $BINARY"
    log "  Size: $(stat --format='%s bytes' "$BINARY")"
    log "  Version: $($BINARY --version 2>&1 || echo 'FAILED')"
else
    log "  ${RED}BUILD FAILED — binary not found at $BINARY${NC}"
    log "  See build output above for errors."
    log "  === LOG END ==="
    log "  Log saved to: $LOG"
    exit 1
fi

step "3. Stop conflicting services and processes"
systemctl stop scx 2>/dev/null || true
pkill -x scx_flow 2>/dev/null || true
pkill -x scx_loader 2>/dev/null || true
sleep 1
log "  Services stopped."

step "4. Start scx_flow v3.1.0 and capture full output"
CAPTURE_LOG="$LOG"
export RUST_BACKTRACE=1
export RUST_LOG=debug
ulimit -l unlimited 2>/dev/null || log "  (warning: cannot raise MEMLOCK limit)"

# Run with timeout so we capture ALL output
timeout 10 "$BINARY" --debug > /tmp/scx_flow_3.1.0_run.log 2>&1 &
PID=$!
sleep 3

# Check if it's running
if kill -0 "$PID" 2>/dev/null; then
    log "  scx_flow started (PID $PID) — running..."
    sleep 4
    log "  sched_ext state after start: $(cat /sys/kernel/sched_ext/state 2>/dev/null || echo 'unavailable')"
    log "  sched_ext ops after start:   $(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo 'none')"
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
    log "  scx_flow stopped."
else
    log "  ${RED}scx_flow failed to start or exited immediately.${NC}"
fi

sleep 1

# Print stdout/stderr
log ""
log "  --- scx_flow stdout/stderr ---"
cat /tmp/scx_flow_3.1.0_run.log >> "$LOG"
cat /tmp/scx_flow_3.1.0_run.log
log ""
log "  --- end stdout/stderr ---"

step "5. sched_ext kernel log (dmesg)"
dmesg 2>/dev/null | grep -i -E 'sched_ext|scx_flow|bpf.*verifier|bpf.*load' | tail -40 >> "$LOG"
dmesg 2>/dev/null | grep -i -E 'sched_ext|scx_flow|bpf.*verifier|bpf.*load' | tail -40

step "6. journalctl (scx.service + kernel)"
log "  --- scx.service ---"
journalctl -u scx.service -n 50 --no-pager 2>/dev/null >> "$LOG" || log "  (scx.service not found)"
journalctl -u scx.service -n 20 --no-pager 2>/dev/null || true
log ""
log "  --- kernel sched_ext messages ---"
journalctl -k -n 100 --no-pager 2>/dev/null | grep -i -E 'sched_ext|scx_flow|bpf' >> "$LOG" || true

step "7. Active scheduler check"
log "  sched_ext state: $(cat /sys/kernel/sched_ext/state 2>/dev/null || echo 'unavailable')"
log "  Active ops:      $(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo 'none')"

step "8. Cleanup"
rm -rf "$BUILD_DIR"
rm -f /tmp/scx_flow_3.1.0_run.log

log ""
log "  === LOG FILE ==="
log "  $LOG"
log ""
log "  === SUMMARY ==="
log ""
grep -E 'Error|error:|FAILED|panic|verifier|rejected|disabled' "$LOG" 2>/dev/null | grep -v "grep -E" || log "  (no obvious errors found in log)"

echo ""
echo "  === DONE ==="
echo "  Full debug log: $LOG"
echo ""
echo "  Copy-paste the full contents of $LOG for analysis."
