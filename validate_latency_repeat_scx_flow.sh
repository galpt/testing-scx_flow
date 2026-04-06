#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Repeat the strict latency-stress validation several times so scheduler
# decisions can be based on medians and worst cases instead of a single run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_ROOT="$SCRIPT_DIR/latency-stress-repeat-results"
PLOT_SCRIPT="$SCRIPT_DIR/latency_stress_plot.py"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RESULTS_DIR="$RESULTS_ROOT/$TIMESTAMP"
RUNS=5
KEEP_RESULTS=3
SCHEDULER_NAME="${SCHEDULER_NAME:-scx_flow}"
SCHEDULER_BIN=""
ACTIVATION_MODE=""
STRICT_FLAG="--strict"
ANY_FAILED=0
LOG_FILE=""
CSV_FILE=""
REPORT_FILE=""
SUMMARY_FILE=""
INITIAL_SERVICE_ACTIVE=0
RESTORE_DONE=0

usage() {
    cat <<EOF
Usage: sudo ./validate_latency_repeat_scx_flow.sh [options]

Options:
  --runs N                Number of strict latency-stress runs to execute (default: 5)
  --results-dir DIR       Write this aggregate run into DIR instead of the default timestamped path
  --keep-results N        Keep only the newest N aggregate result directories (default: 3)
  --scheduler-name NAME   Scheduler to validate (default: scx_flow)
  --scheduler-bin PATH    Path to scheduler binary (default: command -v NAME)
  --activation-mode MODE  How to activate the scheduler between runs: install or manual
                          (default: install for scx_flow, manual for others)
  --no-strict             Do not pass --strict to latency_stress_scx_flow.sh
  -h, --help              Show this help
EOF
}

require_option_value() {
    local option="$1"
    local value="${2-}"

    if [ -z "$value" ] || [[ "$value" == --* ]]; then
        echo "Missing value for $option" >&2
        usage >&2
        exit 1
    fi
}

log() {
    printf '%s\n' "$1" | tee -a "$LOG_FILE"
}

fix_results_ownership() {
    if [ -n "${SUDO_USER:-}" ] && [ -d "$RESULTS_DIR" ]; then
        chown -R "${SUDO_USER}:$(id -gn "$SUDO_USER")" "$RESULTS_DIR" >/dev/null 2>&1 || true
    fi
}

service_exists() {
    command -v systemctl >/dev/null 2>&1 && systemctl cat scx.service >/dev/null 2>&1
}

capture_initial_state() {
    if service_exists && systemctl is-active --quiet scx.service; then
        INITIAL_SERVICE_ACTIVE=1
    fi
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
    fix_results_ownership
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

stop_all_schedulers() {
    if service_exists && systemctl is-active --quiet scx.service; then
        systemctl stop scx.service || true
    fi

    systemctl unset-environment SCX_SCHEDULER_OVERRIDE >/dev/null 2>&1 || true
    systemctl unset-environment SCX_FLAGS_OVERRIDE >/dev/null 2>&1 || true

    for proc in scx_flow scx_cosmos scx_bpfland scx_timely scx_cake scx_pandemonium pandemonium; do
        pkill -x "$proc" >/dev/null 2>&1 || true
    done

    wait_for_scheduler_state flow inactive || true
    wait_for_scheduler_state cosmos inactive || true
    wait_for_scheduler_state bpfland inactive || true
    wait_for_scheduler_state timely inactive || true
    wait_for_scheduler_state cake inactive || true
    wait_for_scheduler_state pandemonium inactive || true
}

start_scheduler_manual() {
    local scheduler="$1"
    local binary_path="$2"
    local run_dir="$3"
    local runtime_log="$run_dir/${scheduler}.runtime.log"

    mkdir -p "$run_dir"
    env RUST_LOG=info "$binary_path" >"$runtime_log" 2>&1 &
    wait_for_scheduler_state "$scheduler" active
}

activate_scheduler() {
    local run_dir="$1"

    if [ "$ACTIVATION_MODE" = "install" ]; then
        log ">>> reinstalling and reactivating $SCHEDULER_NAME via install.sh"
        "$SCRIPT_DIR/install.sh" --force >>"$LOG_FILE" 2>&1
    else
        log ">>> manually starting $SCHEDULER_NAME"
        start_scheduler_manual "$SCHEDULER_NAME" "$SCHEDULER_BIN" "$run_dir" >>"$LOG_FILE" 2>&1
    fi
}

num_or_zero() {
    local value="${1:-}"

    case "$value" in
        ''|*[!0-9]*)
            printf '0\n'
            ;;
        *)
            printf '%s\n' "$value"
            ;;
    esac
}

median_from_file() {
    local file="$1"

    awk '
    {
        vals[NR] = $1 + 0
    }
    END {
        if (NR == 0) {
            print 0
            exit
        }
        n = asort(vals)
        mid = int((n + 1) / 2)
        if (n % 2 == 1) {
            printf "%d\n", vals[mid]
        } else {
            avg = (vals[mid] + vals[mid + 1]) / 2
            if (avg == int(avg))
                printf "%d\n", avg
            else
                printf "%.1f\n", avg
        }
    }
    ' "$file"
}

max_from_file() {
    local file="$1"

    awk '
    BEGIN { max = 0 }
    {
        value = $1 + 0
        if (NR == 1 || value > max)
            max = value
    }
    END { print max }
    ' "$file"
}

count_matching_csv_column() {
    local file="$1"
    local column="$2"
    local needle="$3"

    awk -F',' -v column="$column" -v needle="$needle" '
    NR == 1 {
        for (i = 1; i <= NF; i++) {
            if ($i == column) {
                col = i
                break
            }
        }
        next
    }
    col > 0 && $col == needle { count++ }
    END { print count + 0 }
    ' "$file"
}

sum_csv_column() {
    local file="$1"
    local column="$2"

    awk -F',' -v column="$column" '
    NR == 1 {
        for (i = 1; i <= NF; i++) {
            if ($i == column) {
                col = i
                break
            }
        }
        next
    }
    col > 0 { sum += ($col + 0) }
    END { print sum + 0 }
    ' "$file"
}

trap cleanup EXIT INT TERM

while [ "$#" -gt 0 ]; do
    case "$1" in
        --runs)
            require_option_value "$1" "${2-}"
            RUNS="$2"
            shift 2
            ;;
        --results-dir)
            require_option_value "$1" "${2-}"
            RESULTS_DIR="$2"
            shift 2
            ;;
        --keep-results)
            require_option_value "$1" "${2-}"
            KEEP_RESULTS="$2"
            shift 2
            ;;
        --scheduler-name)
            require_option_value "$1" "${2-}"
            SCHEDULER_NAME="$2"
            shift 2
            ;;
        --scheduler-bin)
            require_option_value "$1" "${2-}"
            SCHEDULER_BIN="$2"
            shift 2
            ;;
        --activation-mode)
            require_option_value "$1" "${2-}"
            ACTIVATION_MODE="$2"
            shift 2
            ;;
        --no-strict)
            STRICT_FLAG=""
            shift
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

if [ -z "${SCHEDULER_BIN:-}" ]; then
    SCHEDULER_BIN="$(command -v "$SCHEDULER_NAME" || true)"
fi

if [ -z "${ACTIVATION_MODE:-}" ]; then
    if [ "$SCHEDULER_NAME" = "scx_flow" ]; then
        ACTIVATION_MODE="install"
    else
        ACTIVATION_MODE="manual"
    fi
fi

if [ "$ACTIVATION_MODE" != "install" ] && [ "$ACTIVATION_MODE" != "manual" ]; then
    echo "Unsupported activation mode: $ACTIVATION_MODE" >&2
    exit 1
fi

if [ "$ACTIVATION_MODE" = "install" ] && [ "$SCHEDULER_NAME" != "scx_flow" ]; then
    echo "--activation-mode install is only supported for scx_flow in this harness." >&2
    exit 1
fi

if [ -z "$SCHEDULER_BIN" ] || [ ! -x "$SCHEDULER_BIN" ]; then
    echo "Could not find executable scheduler binary for $SCHEDULER_NAME. Use --scheduler-bin PATH." >&2
    exit 1
fi

capture_initial_state
mkdir -p "$RESULTS_DIR"
LOG_FILE="$RESULTS_DIR/repeat_latency_stress.log"
CSV_FILE="$RESULTS_DIR/repeat_latency_stress.csv"
REPORT_FILE="$RESULTS_DIR/repeat_latency_stress_report.md"
SUMMARY_FILE="$RESULTS_DIR/repeat_latency_stress_summary.env"
PNG_FILE="$RESULTS_DIR/repeat_latency_stress.png"
SVG_FILE="$RESULTS_DIR/repeat_latency_stress.svg"
: >"$LOG_FILE"

cat >"$CSV_FILE" <<'EOF'
run,script_exit,overall_status,overall_note,post_state,mixed_p95_us,mixed_p99_us,mixed_max_us,mixed_spikes_100us,rt_p95_us,rt_p99_us,rt_max_us,rt_spikes_100us,disable_events,stall_events,reenable_events,failed_to_run_events,final_mode,summary_path
EOF

log "========================================"
log "Repeated strict latency-stress validation"
log "Started: $(date)"
log "Runs: $RUNS"
log "Results dir: $RESULTS_DIR"
log "Scheduler name: $SCHEDULER_NAME"
log "Scheduler binary: $SCHEDULER_BIN"
log "Activation mode: $ACTIVATION_MODE"
log "Strict inner runs: ${STRICT_FLAG:-disabled}"
log "========================================"

for run in $(seq 1 "$RUNS"); do
    run_name="$(printf 'run%02d' "$run")"
    run_dir="$RESULTS_DIR/$run_name"
    summary_path="$run_dir/latency_stress_summary.env"
    run_exit=0

    mkdir -p "$run_dir"

    log ""
    log ">>> $run_name: resetting sched_ext state"
    stop_all_schedulers >>"$LOG_FILE" 2>&1 || true
    "$SCRIPT_DIR/reset_sched_ext_state.sh" >>"$LOG_FILE" 2>&1 || true

    activate_scheduler "$run_dir"

    log ">>> $run_name: running latency_stress_scx_flow.sh ${STRICT_FLAG:-}"
    set +e
    if [ -n "$STRICT_FLAG" ]; then
        "$SCRIPT_DIR/latency_stress_scx_flow.sh" \
            --results-dir "$run_dir" \
            --scheduler-name "$SCHEDULER_NAME" \
            --scheduler-bin "$SCHEDULER_BIN" \
            "$STRICT_FLAG" >>"$LOG_FILE" 2>&1
        run_exit=$?
    else
        "$SCRIPT_DIR/latency_stress_scx_flow.sh" \
            --results-dir "$run_dir" \
            --scheduler-name "$SCHEDULER_NAME" \
            --scheduler-bin "$SCHEDULER_BIN" >>"$LOG_FILE" 2>&1
        run_exit=$?
    fi
    set -e

    if [ ! -f "$summary_path" ]; then
        log ">>> $run_name: missing summary file at $summary_path"
        ANY_FAILED=1
        printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
            "$run_name" "$run_exit" "missing" "summary-missing" "" \
            "0" "0" "0" "0" "0" "0" "0" "0" "0" "0" "0" "0" "" "$summary_path" >>"$CSV_FILE"
        continue
    fi

    aggregate_results_dir="$RESULTS_DIR"
    # shellcheck disable=SC1090
    . "$summary_path"
    RESULTS_DIR="$aggregate_results_dir"

    mixed_p95="$(num_or_zero "${MIXED_LATENCY_P95_US:-}")"
    mixed_p99="$(num_or_zero "${MIXED_LATENCY_P99_US:-}")"
    mixed_max="$(num_or_zero "${MIXED_LATENCY_MAX_US:-}")"
    mixed_spikes="$(num_or_zero "${MIXED_SPIKES_OVER_100US:-}")"
    rt_p95="$(num_or_zero "${RT_LATENCY_P95_US:-}")"
    rt_p99="$(num_or_zero "${RT_LATENCY_P99_US:-}")"
    rt_max="$(num_or_zero "${RT_LATENCY_MAX_US:-}")"
    rt_spikes="$(num_or_zero "${RT_SPIKES_OVER_100US:-}")"
    disable_events="$(num_or_zero "${KERNEL_DISABLE_EVENTS:-}")"
    stall_events="$(num_or_zero "${KERNEL_STALL_EVENTS:-}")"
    reenable_events="$(num_or_zero "${KERNEL_REENABLE_EVENTS:-}")"
    failed_to_run_events="$(num_or_zero "${KERNEL_FAILED_TO_RUN_EVENTS:-}")"

    if [ "$run_exit" -ne 0 ] || [ "${OVERALL_STATUS:-}" != "completed" ]; then
        ANY_FAILED=1
    fi

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$run_name" \
        "$run_exit" \
        "${OVERALL_STATUS:-unknown}" \
        "${OVERALL_NOTE:-}" \
        "${POST_RUN_SCHED_EXT_STATE:-}" \
        "$mixed_p95" \
        "$mixed_p99" \
        "$mixed_max" \
        "$mixed_spikes" \
        "$rt_p95" \
        "$rt_p99" \
        "$rt_max" \
        "$rt_spikes" \
        "$disable_events" \
        "$stall_events" \
        "$reenable_events" \
        "$failed_to_run_events" \
        "${FINAL_AUTOTUNE_MODE:-}" \
        "$summary_path" >>"$CSV_FILE"

    log ">>> $run_name summary: mixed p95=${mixed_p95}us p99=${mixed_p99}us max=${mixed_max}us spikes=${mixed_spikes}, rt p95=${rt_p95}us p99=${rt_p99}us max=${rt_max}us spikes=${rt_spikes}, status=${OVERALL_STATUS:-unknown}, post_state=${POST_RUN_SCHED_EXT_STATE:-unknown}"
done

tmp_mixed_p95="$(mktemp)"
tmp_mixed_p99="$(mktemp)"
tmp_mixed_max="$(mktemp)"
tmp_mixed_spikes="$(mktemp)"
tmp_rt_p95="$(mktemp)"
tmp_rt_p99="$(mktemp)"
tmp_rt_max="$(mktemp)"
tmp_rt_spikes="$(mktemp)"
trap 'rm -f "$tmp_mixed_p95" "$tmp_mixed_p99" "$tmp_mixed_max" "$tmp_mixed_spikes" "$tmp_rt_p95" "$tmp_rt_p99" "$tmp_rt_max" "$tmp_rt_spikes"; cleanup' EXIT INT TERM

awk -F',' 'NR > 1 { print $6 }' "$CSV_FILE" >"$tmp_mixed_p95"
awk -F',' 'NR > 1 { print $7 }' "$CSV_FILE" >"$tmp_mixed_p99"
awk -F',' 'NR > 1 { print $8 }' "$CSV_FILE" >"$tmp_mixed_max"
awk -F',' 'NR > 1 { print $9 }' "$CSV_FILE" >"$tmp_mixed_spikes"
awk -F',' 'NR > 1 { print $10 }' "$CSV_FILE" >"$tmp_rt_p95"
awk -F',' 'NR > 1 { print $11 }' "$CSV_FILE" >"$tmp_rt_p99"
awk -F',' 'NR > 1 { print $12 }' "$CSV_FILE" >"$tmp_rt_max"
awk -F',' 'NR > 1 { print $13 }' "$CSV_FILE" >"$tmp_rt_spikes"

MEDIAN_MIXED_P95_US="$(median_from_file "$tmp_mixed_p95")"
WORST_MIXED_P95_US="$(max_from_file "$tmp_mixed_p95")"
MEDIAN_MIXED_P99_US="$(median_from_file "$tmp_mixed_p99")"
WORST_MIXED_P99_US="$(max_from_file "$tmp_mixed_p99")"
MEDIAN_MIXED_MAX_US="$(median_from_file "$tmp_mixed_max")"
WORST_MIXED_MAX_US="$(max_from_file "$tmp_mixed_max")"
MEDIAN_MIXED_SPIKES_100US="$(median_from_file "$tmp_mixed_spikes")"
WORST_MIXED_SPIKES_100US="$(max_from_file "$tmp_mixed_spikes")"
MEDIAN_RT_P95_US="$(median_from_file "$tmp_rt_p95")"
WORST_RT_P95_US="$(max_from_file "$tmp_rt_p95")"
MEDIAN_RT_P99_US="$(median_from_file "$tmp_rt_p99")"
WORST_RT_P99_US="$(max_from_file "$tmp_rt_p99")"
MEDIAN_RT_MAX_US="$(median_from_file "$tmp_rt_max")"
WORST_RT_MAX_US="$(max_from_file "$tmp_rt_max")"
MEDIAN_RT_SPIKES_100US="$(median_from_file "$tmp_rt_spikes")"
WORST_RT_SPIKES_100US="$(max_from_file "$tmp_rt_spikes")"

FAILED_RUNS="$(count_matching_csv_column "$CSV_FILE" "overall_status" "failed")"
DISABLED_RUNS="$(count_matching_csv_column "$CSV_FILE" "post_state" "disabled")"
STALL_EVENT_SUM="$(sum_csv_column "$CSV_FILE" "stall_events")"
DISABLE_EVENT_SUM="$(sum_csv_column "$CSV_FILE" "disable_events")"
REENABLE_EVENT_SUM="$(sum_csv_column "$CSV_FILE" "reenable_events")"
FAILED_TO_RUN_EVENT_SUM="$(sum_csv_column "$CSV_FILE" "failed_to_run_events")"

cat >"$SUMMARY_FILE" <<EOF
RESULTS_DIR=${RESULTS_DIR}
SCHEDULER_NAME=${SCHEDULER_NAME}
SCHEDULER_BIN=${SCHEDULER_BIN}
ACTIVATION_MODE=${ACTIVATION_MODE}
RUNS=${RUNS}
FAILED_RUNS=${FAILED_RUNS}
DISABLED_RUNS=${DISABLED_RUNS}
STALL_EVENT_SUM=${STALL_EVENT_SUM}
DISABLE_EVENT_SUM=${DISABLE_EVENT_SUM}
REENABLE_EVENT_SUM=${REENABLE_EVENT_SUM}
FAILED_TO_RUN_EVENT_SUM=${FAILED_TO_RUN_EVENT_SUM}
MEDIAN_MIXED_P95_US=${MEDIAN_MIXED_P95_US}
WORST_MIXED_P95_US=${WORST_MIXED_P95_US}
MEDIAN_MIXED_P99_US=${MEDIAN_MIXED_P99_US}
WORST_MIXED_P99_US=${WORST_MIXED_P99_US}
MEDIAN_MIXED_MAX_US=${MEDIAN_MIXED_MAX_US}
WORST_MIXED_MAX_US=${WORST_MIXED_MAX_US}
MEDIAN_MIXED_SPIKES_100US=${MEDIAN_MIXED_SPIKES_100US}
WORST_MIXED_SPIKES_100US=${WORST_MIXED_SPIKES_100US}
MEDIAN_RT_P95_US=${MEDIAN_RT_P95_US}
WORST_RT_P95_US=${WORST_RT_P95_US}
MEDIAN_RT_P99_US=${MEDIAN_RT_P99_US}
WORST_RT_P99_US=${WORST_RT_P99_US}
MEDIAN_RT_MAX_US=${MEDIAN_RT_MAX_US}
WORST_RT_MAX_US=${WORST_RT_MAX_US}
MEDIAN_RT_SPIKES_100US=${MEDIAN_RT_SPIKES_100US}
WORST_RT_SPIKES_100US=${WORST_RT_SPIKES_100US}
CSV_PATH=${CSV_FILE}
LOG_PATH=${LOG_FILE}
REPORT_PATH=${REPORT_FILE}
EOF

cat >"$REPORT_FILE" <<EOF
# Repeated Latency-Stress Report

This report aggregates repeated \`latency_stress_scx_flow.sh\` runs for
\`${SCHEDULER_NAME}\` so scheduler decisions can use medians and worst cases
instead of single-run noise.

## Summary

- Scheduler: \`${SCHEDULER_NAME}\`
- Binary: \`${SCHEDULER_BIN}\`
- Activation mode: \`${ACTIVATION_MODE}\`
- Runs: ${RUNS}
- Failed runs: ${FAILED_RUNS}
- Runs ending with \`sched_ext=disabled\`: ${DISABLED_RUNS}
- Total stall events: ${STALL_EVENT_SUM}
- Total disable events: ${DISABLE_EVENT_SUM}
- Total re-enable events: ${REENABLE_EVENT_SUM}
- Total failed-to-run events: ${FAILED_TO_RUN_EVENT_SUM}

Artifacts:
- [${CSV_FILE}](${CSV_FILE})
- [${PNG_FILE}](${PNG_FILE})
- [${SVG_FILE}](${SVG_FILE})

## Aggregates

| Metric | Median | Worst |
| --- | ---: | ---: |
| Mixed p95 latency (us) | ${MEDIAN_MIXED_P95_US} | ${WORST_MIXED_P95_US} |
| Mixed p99 latency (us) | ${MEDIAN_MIXED_P99_US} | ${WORST_MIXED_P99_US} |
| Mixed max latency (us) | ${MEDIAN_MIXED_MAX_US} | ${WORST_MIXED_MAX_US} |
| Mixed spikes >100us | ${MEDIAN_MIXED_SPIKES_100US} | ${WORST_MIXED_SPIKES_100US} |
| RT p95 latency (us) | ${MEDIAN_RT_P95_US} | ${WORST_RT_P95_US} |
| RT p99 latency (us) | ${MEDIAN_RT_P99_US} | ${WORST_RT_P99_US} |
| RT max latency (us) | ${MEDIAN_RT_MAX_US} | ${WORST_RT_MAX_US} |
| RT spikes >100us | ${MEDIAN_RT_SPIKES_100US} | ${WORST_RT_SPIKES_100US} |

## Per-Run Table

| Run | Script exit | Overall status | Post state | Mixed p95 (us) | Mixed p99 (us) | Mixed max (us) | Mixed spikes >100us | RT p95 (us) | RT p99 (us) | RT max (us) | RT spikes >100us | Disable | Stall | Re-enable | Final mode |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
EOF

awk -F',' '
NR == 1 { next }
{
    printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n",
        $1, $2, $3, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $18
}
' "$CSV_FILE" >>"$REPORT_FILE"

log ""
log "========================================"
log "Repeated latency-stress summary"
log "========================================"
log "Scheduler: $SCHEDULER_NAME"
log "Runs: $RUNS"
log "Failed runs: $FAILED_RUNS"
log "Median mixed p95 latency: ${MEDIAN_MIXED_P95_US}us"
log "Worst mixed p95 latency: ${WORST_MIXED_P95_US}us"
log "Median mixed p99 latency: ${MEDIAN_MIXED_P99_US}us"
log "Worst mixed p99 latency: ${WORST_MIXED_P99_US}us"
log "Median mixed max latency: ${MEDIAN_MIXED_MAX_US}us"
log "Worst mixed max latency: ${WORST_MIXED_MAX_US}us"
log "Median mixed spikes >100us: ${MEDIAN_MIXED_SPIKES_100US}"
log "Worst mixed spikes >100us: ${WORST_MIXED_SPIKES_100US}"
log "Median RT p95 latency: ${MEDIAN_RT_P95_US}us"
log "Worst RT p95 latency: ${WORST_RT_P95_US}us"
log "Median RT p99 latency: ${MEDIAN_RT_P99_US}us"
log "Worst RT p99 latency: ${WORST_RT_P99_US}us"
log "Median RT max latency: ${MEDIAN_RT_MAX_US}us"
log "Worst RT max latency: ${WORST_RT_MAX_US}us"
log "Median RT spikes >100us: ${MEDIAN_RT_SPIKES_100US}"
log "Worst RT spikes >100us: ${WORST_RT_SPIKES_100US}"
log "Summary file: $SUMMARY_FILE"
log "CSV file: $CSV_FILE"
log "Report file: $REPORT_FILE"

if command -v python3 >/dev/null 2>&1; then
    python3 "$PLOT_SCRIPT" --mode repeat --csv "$CSV_FILE" --output-dir "$RESULTS_DIR"
    log "PNG file: $PNG_FILE"
    log "SVG file: $SVG_FILE"
else
    log "Skipping chart render: python3 not found"
fi

prune_old_results

rm -f "$tmp_mixed_p95" "$tmp_mixed_p99" "$tmp_mixed_max" "$tmp_mixed_spikes" "$tmp_rt_p95" "$tmp_rt_p99" "$tmp_rt_max" "$tmp_rt_spikes"
trap cleanup EXIT INT TERM

if [ "$ANY_FAILED" -ne 0 ]; then
    exit 1
fi
