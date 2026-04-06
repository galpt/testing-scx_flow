#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Compare schedulers using the same latency-stress workload.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STRESS_SCRIPT="$SCRIPT_DIR/latency_stress_scx_flow.sh"
PLOT_SCRIPT="$SCRIPT_DIR/latency_stress_plot.py"
RESET_SCRIPT="$SCRIPT_DIR/reset_sched_ext_state.sh"
RESULTS_ROOT="$SCRIPT_DIR/latency-stress-comparisons"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RESULTS_DIR="$RESULTS_ROOT/$TIMESTAMP"
KEEP_RESULTS=3
SCHEDULERS=(scx_cosmos scx_flow)
CURRENT_RUNTIME_LOG=""
INITIAL_SERVICE_ACTIVE=0
RESTORE_DONE=0
ARTIFACT_STEM="latency_stress_compare"
REPORT_TITLE="Latency-Stress Comparison"

usage() {
    cat <<EOF
Usage: sudo ./latency_stress_compare.sh [options]

Options:
  --schedulers "LIST"       Space-separated scheduler list (default: "scx_cosmos scx_flow")
  --results-root DIR        Root directory for timestamped results (default: latency-stress-comparisons/)
  --results-dir DIR         Write this run into DIR instead of the default timestamped path
  --keep-results N          Keep only the newest N result directories (default: 3)
  --artifact-stem NAME      Output stem for CSV/PNG/SVG/report (default: latency_stress_compare)
  --report-title TEXT       Report/chart title (default: "Latency-Stress Comparison")
  -h, --help                Show this help
EOF
}

scheduler_short_name() {
    case "$1" in
        scx_*) printf '%s\n' "${1#scx_}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

scheduler_matches_name() {
    local current="$1"
    local expected="$2"
    local short_name

    short_name="$(scheduler_short_name "$expected")"
    case "$current" in
        "$expected"|"$expected"_*|"$short_name"|"$short_name"_*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

current_sched_ext_state() {
    cat /sys/kernel/sched_ext/state 2>/dev/null || echo "unknown"
}

current_sched_ext_ops() {
    cat /sys/kernel/sched_ext/root/ops 2>/dev/null || true
}

service_exists() {
    command -v systemctl >/dev/null 2>&1 && systemctl cat scx.service >/dev/null 2>&1
}

capture_initial_state() {
    if service_exists && systemctl is-active --quiet scx.service; then
        INITIAL_SERVICE_ACTIVE=1
    fi
}

wait_for_scheduler_state() {
    local expected="$1"
    local want="${2:-active}"
    local attempt=0
    local current

    while [ "$attempt" -lt 60 ]; do
        current="$(current_sched_ext_ops)"
        if [ "$want" = "active" ]; then
            if scheduler_matches_name "$current" "$expected" &&
               [ "$(current_sched_ext_state)" = "enabled" ]; then
                return 0
            fi
        else
            if ! scheduler_matches_name "$current" "$expected"; then
                return 0
            fi
        fi

        attempt=$((attempt + 1))
        sleep 0.5
    done

    return 1
}

wait_for_sched_ext_disabled() {
    local attempt=0

    while [ "$attempt" -lt 60 ]; do
        if [ "$(current_sched_ext_state)" = "disabled" ] &&
           [ -z "$(current_sched_ext_ops)" ]; then
            return 0
        fi

        attempt=$((attempt + 1))
        sleep 0.5
    done

    return 1
}

stop_all_schedulers() {
    if [ -x "$RESET_SCRIPT" ]; then
        "$RESET_SCRIPT"
        wait_for_sched_ext_disabled
        return
    fi

    if service_exists && systemctl is-active --quiet scx.service; then
        systemctl stop scx.service || true
    fi

    systemctl unset-environment SCX_SCHEDULER_OVERRIDE >/dev/null 2>&1 || true
    systemctl unset-environment SCX_FLAGS_OVERRIDE >/dev/null 2>&1 || true

    for proc in scx_flow scx_cosmos scx_bpfland scx_pandemonium pandemonium; do
        pkill -x "$proc" >/dev/null 2>&1 || true
    done

    wait_for_scheduler_state flow inactive || true
    wait_for_scheduler_state cosmos inactive || true
    wait_for_scheduler_state bpfland inactive || true
    wait_for_scheduler_state pandemonium inactive || true
    wait_for_sched_ext_disabled || true
}

start_scheduler_manual() {
    local scheduler="$1"
    local binary_path=""

    binary_path="$(command -v "$scheduler" 2>/dev/null || true)"
    [ -n "$binary_path" ] || {
        echo "Could not resolve binary path for $scheduler" >&2
        return 1
    }

    CURRENT_RUNTIME_LOG="$RESULTS_DIR/console/${scheduler}.log"
    mkdir -p "$RESULTS_DIR/console"

    env RUST_LOG=info "$binary_path" >"$CURRENT_RUNTIME_LOG" 2>&1 &

    wait_for_scheduler_state "$scheduler" active
}

summary_field() {
    local path="$1"
    local key="$2"
    sed -n "s/^${key}=//p" "$path" | tail -n 1
}

display_scheduler_name() {
    local scheduler="$1"
    local summary="$2"
    local kernel_release=""

    if [ "$scheduler" = "baseline" ]; then
        kernel_release="$(summary_field "$summary" KERNEL_RELEASE)"
        if [ -n "$kernel_release" ]; then
            printf 'baseline (%s)\n' "$kernel_release"
            return
        fi
    fi

    printf '%s\n' "$scheduler"
}

write_report() {
    local report="$RESULTS_DIR/${ARTIFACT_STEM}_report.md"
    local csv="$RESULTS_DIR/${ARTIFACT_STEM}_summary.csv"
    local png="$RESULTS_DIR/${ARTIFACT_STEM}.png"
    local svg="$RESULTS_DIR/${ARTIFACT_STEM}.svg"
    local scheduler summary display_name

    {
        echo "scheduler,display_scheduler,kernel_release,overall_status,overall_note,mixed_p95_us,mixed_p99_us,mixed_max_us,rt_p95_us,rt_p99_us,rt_max_us,kernel_stalls,summary_path"
        for scheduler in "${SCHEDULERS[@]}"; do
            summary="$RESULTS_DIR/runs/${scheduler}/latency_stress_summary.env"
            [ -f "$summary" ] || continue
            display_name="$(display_scheduler_name "$scheduler" "$summary")"
            printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
                "$scheduler" \
                "$display_name" \
                "$(summary_field "$summary" KERNEL_RELEASE)" \
                "$(summary_field "$summary" OVERALL_STATUS)" \
                "$(summary_field "$summary" OVERALL_NOTE)" \
                "$(summary_field "$summary" MIXED_LATENCY_P95_US)" \
                "$(summary_field "$summary" MIXED_LATENCY_P99_US)" \
                "$(summary_field "$summary" MIXED_LATENCY_MAX_US)" \
                "$(summary_field "$summary" RT_LATENCY_P95_US)" \
                "$(summary_field "$summary" RT_LATENCY_P99_US)" \
                "$(summary_field "$summary" RT_LATENCY_MAX_US)" \
                "$(summary_field "$summary" KERNEL_STALL_EVENTS)" \
                "$summary"
        done
    } >"$csv"

    {
        echo "# ${REPORT_TITLE}"
        echo
        echo "Generated: $(date)"
        echo
        echo "Artifacts:"
        echo "- [$csv]($csv)"
        echo "- [$png]($png)"
        echo "- [$svg]($svg)"
        echo
        echo "| Scheduler | Overall status | Note | Mixed p95 (us) | Mixed p99 (us) | Mixed max (us) | RT p95 (us) | RT p99 (us) | RT max (us) | Kernel stall events |"
        echo "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
        for scheduler in "${SCHEDULERS[@]}"; do
            summary="$RESULTS_DIR/runs/${scheduler}/latency_stress_summary.env"
            [ -f "$summary" ] || continue
            display_name="$(display_scheduler_name "$scheduler" "$summary")"
            printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
                "$display_name" \
                "$(summary_field "$summary" OVERALL_STATUS)" \
                "$(summary_field "$summary" OVERALL_NOTE)" \
                "$(summary_field "$summary" MIXED_LATENCY_P95_US)" \
                "$(summary_field "$summary" MIXED_LATENCY_P99_US)" \
                "$(summary_field "$summary" MIXED_LATENCY_MAX_US)" \
                "$(summary_field "$summary" RT_LATENCY_P95_US)" \
                "$(summary_field "$summary" RT_LATENCY_P99_US)" \
                "$(summary_field "$summary" RT_LATENCY_MAX_US)" \
                "$(summary_field "$summary" KERNEL_STALL_EVENTS)"
        done
        echo
        for scheduler in "${SCHEDULERS[@]}"; do
            summary="$RESULTS_DIR/runs/${scheduler}/latency_stress_summary.env"
            [ -f "$summary" ] || continue
            echo "- [$scheduler summary]($summary)"
            echo "- [$scheduler kernel log]($RESULTS_DIR/runs/${scheduler}/kernel_sched_ext.log)"
            echo "- [$scheduler monitor log]($RESULTS_DIR/runs/${scheduler}/scx_flow_monitor.log)"
        done
    } >"$report"

    echo "Report: $report"
    echo "CSV:    $csv"
}

render_charts() {
    local csv="$RESULTS_DIR/${ARTIFACT_STEM}_summary.csv"

    if ! command -v python3 >/dev/null 2>&1; then
        echo "Skipping chart render: python3 not found"
        return 0
    fi

    python3 "$PLOT_SCRIPT" \
        --mode compare \
        --csv "$csv" \
        --output-dir "$RESULTS_DIR" \
        --stem "$ARTIFACT_STEM" \
        --figure-title "$REPORT_TITLE"
    echo "PNG:    $RESULTS_DIR/${ARTIFACT_STEM}.png"
    echo "SVG:    $RESULTS_DIR/${ARTIFACT_STEM}.svg"
}

prune_old_results() {
    local old_dirs

    [ -d "$RESULTS_ROOT" ] || return 0
    old_dirs=$(ls -1dt "$RESULTS_ROOT"/* 2>/dev/null | tail -n +"$((KEEP_RESULTS + 1))" || true)
    [ -n "$old_dirs" ] || return 0

    while IFS= read -r old_dir; do
        [ -n "$old_dir" ] || continue
        rm -rf "$old_dir"
    done <<EOF
$old_dirs
EOF
}

restore_default_service_state() {
    if [ "$RESTORE_DONE" -eq 1 ]; then
        return
    fi
    RESTORE_DONE=1

    if service_exists; then
        systemctl unset-environment SCX_SCHEDULER_OVERRIDE >/dev/null 2>&1 || true
        systemctl unset-environment SCX_FLAGS_OVERRIDE >/dev/null 2>&1 || true
        if [ "$INITIAL_SERVICE_ACTIVE" -eq 1 ]; then
            systemctl restart scx.service >/dev/null 2>&1 || true
        else
            systemctl stop scx.service >/dev/null 2>&1 || true
        fi
    fi
}

cleanup() {
    restore_default_service_state
    if [ -n "${SUDO_USER:-}" ] && [ -d "$RESULTS_DIR" ]; then
        chown -R "${SUDO_USER}:$(id -gn "$SUDO_USER")" "$RESULTS_DIR" >/dev/null 2>&1 || true
    fi
}

trap cleanup EXIT

while [ "$#" -gt 0 ]; do
    case "$1" in
        --schedulers)
            read -r -a SCHEDULERS <<< "$2"
            shift 2
            ;;
        --results-root)
            RESULTS_ROOT="$2"
            RESULTS_DIR="$RESULTS_ROOT/$TIMESTAMP"
            shift 2
            ;;
        --results-dir)
            RESULTS_DIR="$2"
            shift 2
            ;;
        --keep-results)
            KEEP_RESULTS="$2"
            shift 2
            ;;
        --artifact-stem)
            ARTIFACT_STEM="$2"
            shift 2
            ;;
        --report-title)
            REPORT_TITLE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo $0" >&2
    exit 1
fi

[ -x "$STRESS_SCRIPT" ] || {
    echo "Missing stress script: $STRESS_SCRIPT" >&2
    exit 1
}

capture_initial_state

mkdir -p "$RESULTS_DIR/runs"

for scheduler in "${SCHEDULERS[@]}"; do
    echo "========================================"
    echo "Scheduler: $scheduler"
    echo "========================================"

    stop_all_schedulers
    if [ "$scheduler" = "baseline" ]; then
        if ! "$STRESS_SCRIPT" \
            --scheduler-name baseline \
            --results-dir "$RESULTS_DIR/runs/$scheduler" \
            --strict; then
            echo "$scheduler latency-stress run exited non-zero; summary should still be available."
        fi
    else
        if ! start_scheduler_manual "$scheduler"; then
            echo "Failed to activate $scheduler" >&2
            continue
        fi

        if ! "$STRESS_SCRIPT" \
            --scheduler-name "$scheduler" \
            --scheduler-bin "$(command -v "$scheduler")" \
            --results-dir "$RESULTS_DIR/runs/$scheduler" \
            --strict; then
            echo "$scheduler latency-stress run exited non-zero; summary should still be available."
        fi
    fi
done

write_report
render_charts
prune_old_results
