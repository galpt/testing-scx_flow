#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Fix scx_flow for use with the CachyOS Kernel Manager GUI (scx-manager).
#
# The CachyOS Kernel Manager GUI manages schedulers through scx_loader via
# DBUS. After certain operations the GUI can no longer start or manage
# scx_flow. The scx-manager >= 1.15.11 package fixed the original crate
# version mismatch (scx_loader 1.1.1 compat), but the GUI still needs the
# binary present and no conflicting service to work correctly.
#
# This script handles the remaining issues:
#
#   - scx_flow binary is missing (after uninstall.sh, the GUI still lists
#     scx_flow as an available scheduler, but scx_loader cannot launch a
#     missing binary — clicking Apply fails)
#
#   - /etc/scx_loader.toml was written by an older scx_loader version or
#     contains stale entries (the GUI may show config-related errors)
#
#   - scx.service is running (scx_flow is already active, so when the GUI
#     tries to start it via scx_loader, scx_flow refuses with "another
#     sched_ext scheduler is already running")
#
# This script inspects the current state and applies only the fixes that
# are needed, so running it multiple times is safe.
#
# Usage: sudo sh fix-flow-kernel-manager-gui.sh [options]
#
# Options:
#   --dry-run     Print the actions without changing the system
#   --help, -h    Print this help text and exit

set -e

BINARY_NAME="scx_flow"
BINARY_PATH="/usr/bin/${BINARY_NAME}"
SERVICE_NAME="scx"
SCX_DEFAULTS="/etc/default/scx"
SCX_LOADER_BIN="scx_loader"
SCX_LOADER_CONFIG="/etc/scx_loader.toml"
SCX_LOADER_SERVICE="scx_loader"
SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"

DRY_RUN=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN="1"; shift ;;
        --help|-h)
            sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \{0,2\}//'
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
    printf "%s [y/N]: " "$1"
    read -r _ans
    case "$_ans" in y|Y) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# Service helpers
# ---------------------------------------------------------------------------
scx_loader_service_exists() {
    systemctl list-unit-files "${SCX_LOADER_SERVICE}" --no-legend >/dev/null 2>&1 \
        || systemctl cat "${SCX_LOADER_SERVICE}" >/dev/null 2>&1
}

is_scx_loader_service_active() {
    systemctl is-active --quiet "${SCX_LOADER_SERVICE}" 2>/dev/null
}

scx_service_exists() {
    systemctl list-unit-files "${SERVICE_NAME}.service" --no-legend >/dev/null 2>&1
}

is_scx_service_active() {
    systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Step 1 — Back up and remove stale /etc/scx_loader.toml
#
# The scx-tools 1.1.1 update changed the scx_loader config struct. If
# /etc/scx_loader.toml was written by an older version, the GUI shows
# "Cannot get scx flags from scx_loader configuration".
#
# Removing it lets scx_loader (and the GUI) create a fresh default config.
# ---------------------------------------------------------------------------
fix_stale_config() {
    log_step "Step 1: scx_loader Configuration"

    if [ ! -f "${SCX_LOADER_CONFIG}" ]; then
        log_info "${SCX_LOADER_CONFIG} does not exist — config is already fresh"
        return 0
    fi

    log_info "${SCX_LOADER_CONFIG} exists ($(wc -c < "${SCX_LOADER_CONFIG}" 2>/dev/null || echo '?') bytes)"

    _backup="${SCX_LOADER_CONFIG}.bak.$(date +%Y%m%d-%H%M%S)"
    log_info "Backing up to ${_backup}"
    run "cp \"${SCX_LOADER_CONFIG}\" \"${_backup}\""
    log_ok "Backup saved to ${_backup}"

    log_info "Removing stale ${SCX_LOADER_CONFIG}"
    run "rm -f \"${SCX_LOADER_CONFIG}\""
    if [ ! -f "${SCX_LOADER_CONFIG}" ]; then
        log_ok "Stale config removed — scx_loader will create a fresh one"
    fi
}

# ---------------------------------------------------------------------------
# Step 2 — Install scx_flow if the binary is missing
#
# After uninstall.sh, the binary is gone but the GUI still lists scx_flow
# as an available scheduler (scx_loader reports it). Clicking Apply fails
# silently because scx_loader cannot launch a missing binary.
# ---------------------------------------------------------------------------
ensure_scx_flow_installed() {
    log_step "Step 2: scx_flow Binary"

    if [ -x "${BINARY_PATH}" ]; then
        log_ok "${BINARY_NAME} is already installed"
        _version=$("${BINARY_PATH}" --version 2>/dev/null || echo "unknown")
        log_info "${BINARY_NAME} version: ${_version}"
        return 0
    fi

    log_warn "${BINARY_PATH} not found — scx_flow is not installed"

    _standalone_installer="${SCRIPT_DIR}/install_scx_flow_standalone.sh"
    if [ ! -f "${_standalone_installer}" ]; then
        log_error "Cannot find installer at ${_standalone_installer}"
        log_error "Install scx_flow via: ./install_scx_flow_standalone.sh"
        return 1
    fi

    if [ -z "$DRY_RUN" ]; then
        if ! confirm "Install scx_flow now? (clones from GitHub and builds from source)"; then
            log_warn "Skipping. scx_flow will not be usable from the GUI until installed."
            return 1
        fi
    else
        log_info "(dry-run) Would install scx_flow via standalone installer"
        return 1
    fi

    log_info "Installing scx_flow ..."
    run "sh \"${_standalone_installer}\""

    if [ -x "${BINARY_PATH}" ]; then
        log_ok "${BINARY_NAME} installed successfully"
        _version=$("${BINARY_PATH}" --version 2>/dev/null || echo "unknown")
        log_info "${BINARY_NAME} version: ${_version}"
    else
        log_error "${BINARY_NAME} installation failed"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Step 3 — Stop scx.service if it is running
#
# The GUI manages schedulers through scx_loader via DBUS. If scx.service
# is running, scx_flow is already attached to the kernel and scx_loader
# cannot start a new instance — scx_flow itself refuses with:
#   "another sched_ext scheduler is already running"
#
# Stopping scx.service gives scx_loader a clean slate.
# ---------------------------------------------------------------------------
stop_conflicting_service() {
    log_step "Step 3: Conflicting Service"

    if ! scx_service_exists; then
        log_info "scx.service is not installed — no conflict"
        return 0
    fi

    if ! is_scx_service_active; then
        log_info "scx.service is already stopped"
        return 0
    fi

    log_info "Stopping scx.service (conflicts with scx_loader)..."
    run "systemctl stop \"${SERVICE_NAME}.service\" 2>/dev/null || true"
    run "systemctl disable \"${SERVICE_NAME}.service\" 2>/dev/null || true"

    if is_scx_service_active; then
        log_warn "Could not stop scx.service — try: sudo systemctl stop scx.service"
        return 1
    fi

    log_ok "scx.service stopped — scx_loader can now manage schedulers"
}

# ---------------------------------------------------------------------------
# Show a final summary of the system state
# ---------------------------------------------------------------------------
show_result() {
    log_step "Result"

    _all_ok=0

    # 1. Config
    if [ -f "${SCX_LOADER_CONFIG}" ]; then
        log_warn "${SCX_LOADER_CONFIG} still exists (may have been re-created)"
    else
        log_ok "${SCX_LOADER_CONFIG} is absent — fresh defaults will be used"
    fi

    # 2. scx_loader service
    if scx_loader_service_exists; then
        if is_scx_loader_service_active; then
            log_ok "scx_loader.service is active (GUI communicates via this)"
        else
            log_info "scx_loader.service will start on demand when GUI opens"
        fi
    else
        log_warn "scx_loader.service is not available — install scx-tools"
        _all_ok=1
    fi

    # 3. scx_flow binary
    if [ -x "${BINARY_PATH}" ]; then
        log_ok "${BINARY_NAME} binary is installed"
    else
        log_warn "${BINARY_NAME} binary is missing — GUI cannot launch it"
        _all_ok=1
    fi

    # 4. scx.service
    if scx_service_exists && is_scx_service_active; then
        log_warn "scx.service is still active — may interfere with scx_loader"
        _all_ok=1
    fi

    return "${_all_ok}"
}

# ===========================================================================
main() {
    log_step "fix-flow-kernel-manager-gui"
    check_root

    [ -n "$DRY_RUN" ] && log_warn "DRY-RUN mode — no changes will be made"

    fix_stale_config

    ensure_scx_flow_installed || true

    stop_conflicting_service || true

    if show_result; then
        log_step "Done"
        log_ok "System is ready. Open the CachyOS Kernel Manager GUI and click"
        log_ok "Apply to let scx_loader manage scx_flow."
        exit 0
    else
        log_step "Done"
        log_warn "Some issues remain — see messages above"
        exit 1
    fi
}

main "$@"
