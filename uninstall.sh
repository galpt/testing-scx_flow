#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# scx_flow uninstallation script
#
# Usage: sudo sh uninstall.sh [options]
#
# Options:
#   --force       Skip confirmation prompts
#   --dry-run     Print the actions without changing the system
#   --purge       Also remove the scx.service file
#   --help, -h    Print this help text and exit

BINARY_NAME="scx_flow"
SERVICE_NAME="scx"
BINARY_PATH="/usr/bin/${BINARY_NAME}"
SCX_DEFAULTS="/etc/default/scx"
SYSTEMD_SERVICE="/etc/systemd/system/${SERVICE_NAME}.service"

FORCE=""
DRY_RUN=""
PURGE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --force) FORCE="1"; shift ;;
        --dry-run) DRY_RUN="1"; shift ;;
        --purge) PURGE="1"; shift ;;
        --help|-h)
            sed -n '/^# Options:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \{0,2\}//'
            exit 0
            ;;
        *)
            printf '[ERR ] Unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info()  { printf "${BLUE}[INFO]${NC}  %s\n" "$1"; }
log_ok()    { printf "${GREEN}[ OK ]${NC}  %s\n" "$1"; }
log_warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$1"; }
log_error() { printf "${RED}[ERR ]${NC}  %s\n" "$1" >&2; }
log_step()  { printf "\n${BOLD}${CYAN}──── %s ────${NC}\n" "$1"; }

run() {
    if [ -n "$DRY_RUN" ]; then
        printf "${YELLOW}[DRY ]${NC}  %s\n" "$*"
    else
        eval "$@"
    fi
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "Run as root: sudo sh $0 $*"
        exit 1
    fi
}

confirm() {
    [ -n "$FORCE" ] && return 0
    printf "%s [y/N]: " "$1" >&2
    if ! read -r _ans; then
        log_warn "No input available, assuming 'n'"
        return 1
    fi
    case "$_ans" in y|Y) return 0 ;; *) return 1 ;; esac
}

# Try to stop a service with timeout, handle broken systemd
stop_service_safe() {
    local service="$1"
    local timeout=5
    
    log_info "Stopping ${service}..."
    
    # First try normal stop
    if timeout "$timeout" systemctl stop "$service" 2>/dev/null; then
        log_ok "${service} stopped"
        return 0
    fi
    
    # If that fails, try to kill the main process directly
    log_warn "systemctl stop timed out, trying direct kill..."
    
    # Find and kill the main process
    local pid
    pid=$(pgrep -f "^$service$" 2>/dev/null | head -1 || true)
    if [ -n "$pid" ]; then
        kill -9 "$pid" 2>/dev/null || true
        log_ok "Killed ${service} process ${pid}"
    fi
    
    # Try to disable (may also timeout)
    timeout "$timeout" systemctl disable "$service" 2>/dev/null || true
    
    return 0
}

kill_scheduler_processes() {
    log_info "Killing any leftover scx_flow processes..."
    
    # Kill all scx_flow processes
    for pid in $(pgrep -x "${BINARY_NAME}" 2>/dev/null || true); do
        log_info "Killing ${BINARY_NAME} PID ${pid}"
        kill -9 "$pid" 2>/dev/null || true
    done
    
    # Also kill any systemd-run scopes running scx_flow
    for pid in $(pgrep -f "systemd-run.*${BINARY_NAME}" 2>/dev/null || true); do
        log_info "Killing systemd-run PID ${pid}"
        kill -9 "$pid" 2>/dev/null || true
    done
    
    # Wait briefly
    sleep 0.5
    
    # Verify they're dead
    if pgrep -x "${BINARY_NAME}" >/dev/null 2>&1; then
        log_warn "Some ${BINARY_NAME} processes still running"
    else
        log_ok "Scheduler processes killed"
    fi
}

cleanup_scx_defaults() {
    if [ ! -f "$SCX_DEFAULTS" ]; then
        return 0
    fi
    if ! grep -q "^SCX_SCHEDULER=${BINARY_NAME}" "$SCX_DEFAULTS" 2>/dev/null; then
        return 0
    fi

    if [ -n "$DRY_RUN" ]; then
        log_info "(dry-run) Would clean ${SCX_DEFAULTS}"
        return 0
    fi

    _tmp=$(mktemp)
    grep -v "Managed by scx_flow installer" "$SCX_DEFAULTS" \
        | grep -v "^SCX_SCHEDULER=${BINARY_NAME}" \
        | grep -v "^SCX_FLAGS=" \
        > "$_tmp" || true
    cp "$_tmp" "$SCX_DEFAULTS"
    rm -f "$_tmp"
    log_ok "Cleaned ${SCX_DEFAULTS}"
}

remove_files() {
    if [ -f "$BINARY_PATH" ]; then
        log_info "Removing ${BINARY_PATH}..."
        run "rm -f '$BINARY_PATH'"
        log_ok "Binary removed"
    fi
    if [ -n "$PURGE" ] && [ -f "$SYSTEMD_SERVICE" ]; then
        log_info "Removing ${SYSTEMD_SERVICE}..."
        run "rm -f '$SYSTEMD_SERVICE'"
        log_ok "Service file removed"
    fi
}

reload_systemd() {
    log_info "Reloading systemd daemon..."
    # Use timeout to prevent hanging if systemd is broken
    timeout 5 systemctl daemon-reload 2>/dev/null || true
    log_ok "Systemd reloaded"
}

main() {
    log_step "scx_flow uninstaller"
    check_root

    if ! confirm "This will stop the scx service and remove scx_flow. Continue?"; then
        log_info "Uninstall cancelled"
        exit 0
    fi

    kill_scheduler_processes
    stop_service_safe "${SERVICE_NAME}"
    cleanup_scx_defaults
    remove_files
    reload_systemd

    log_step "Done"
    log_ok "scx_flow has been removed"
}

main "$@"
