#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Monitor scx_flow state and follow scx.service logs.

set -euo pipefail

BINARY_NAME="scx_flow"
SERVICE_NAME="scx.service"
ROOT_OPS_PATH="/sys/kernel/sched_ext/root/ops"
STATE_PATH="/sys/kernel/sched_ext/state"
LINES=50
FOLLOW=1

usage() {
    cat <<EOF
Usage: ./monitor_scx_flow.sh [options]

Show the current sched_ext/scx_flow state and tail scx.service logs.

Options:
  --lines N     Number of existing journal lines to show first (default: 50)
  --once        Print current state and recent logs, then exit
  --help, -h    Show this help text
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --lines)
            LINES="$2"
            shift 2
            ;;
        --once)
            FOLLOW=0
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf '[ERR ] Unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi

print_header() {
    printf '========================================\n'
    printf 'scx_flow Monitor\n'
    printf 'Time: %s\n' "$(date)"
    printf '========================================\n'
}

print_state() {
    local active="(unavailable)"
    local state="(unavailable)"

    if [ -r "$ROOT_OPS_PATH" ]; then
        active="$(cat "$ROOT_OPS_PATH" 2>/dev/null || printf '(unknown)')"
    fi

    if [ -r "$STATE_PATH" ]; then
        state="$(cat "$STATE_PATH" 2>/dev/null || printf '(unknown)')"
    fi

    printf 'Scheduler: %s\n' "$active"
    printf 'sched_ext state: %s\n' "$state"
    printf 'Service status:\n'
    systemctl --no-pager --full status "$SERVICE_NAME" | sed -n '1,10p'
}

service_since_arg() {
    local active_since

    active_since="$(systemctl show -p ActiveEnterTimestamp --value "$SERVICE_NAME" 2>/dev/null || true)"
    if [ -n "$active_since" ]; then
        printf '%s\n' "$active_since"
        return 0
    fi

    return 1
}

print_header
print_state
printf '\n'
printf 'Recent scx.service logs:\n'

SINCE_ARG="$(service_since_arg || true)"

if [ "$FOLLOW" -eq 1 ]; then
    if [ -n "$SINCE_ARG" ]; then
        exec journalctl -u "$SERVICE_NAME" --since "$SINCE_ARG" -f --no-pager
    fi
    exec journalctl -u "$SERVICE_NAME" -n "$LINES" -f --no-pager
else
    if [ -n "$SINCE_ARG" ]; then
        exec journalctl -u "$SERVICE_NAME" --since "$SINCE_ARG" --no-pager
    fi
    exec journalctl -u "$SERVICE_NAME" -n "$LINES" --no-pager
fi
