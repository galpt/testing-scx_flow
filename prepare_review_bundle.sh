#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Generate a concise review-ready summary from a mini_benchmarker comparison
# directory and optional hook/lifecycle validation logs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPARISON_DIR=""
HOOK_LOG=""
LIFECYCLE_LOG=""
LATENCY_SUMMARY=""
OUTPUT_PATH=""

usage() {
    cat <<EOF
Usage: ./prepare_review_bundle.sh [options]

Options:
  --comparison-dir PATH   mini_benchmarker comparison result directory to summarize
  --hook-log PATH         Optional validate_hooks_scx_flow output log
  --lifecycle-log PATH    Optional validate_lifecycle_scx_flow output log
  --latency-summary PATH  Optional latency_stress_scx_flow summary env file
  --output PATH           Output markdown path
  -h, --help              Show this help
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --comparison-dir)
            COMPARISON_DIR="$2"
            shift 2
            ;;
        --hook-log)
            HOOK_LOG="$2"
            shift 2
            ;;
        --lifecycle-log)
            LIFECYCLE_LOG="$2"
            shift 2
            ;;
        --latency-summary)
            LATENCY_SUMMARY="$2"
            shift 2
            ;;
        --output)
            OUTPUT_PATH="$2"
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

if [ -z "$COMPARISON_DIR" ]; then
    COMPARISON_DIR="$(ls -1dt "$SCRIPT_DIR"/comparison-results/* 2>/dev/null | head -n 1 || true)"
fi

if [ -z "$COMPARISON_DIR" ] || [ ! -d "$COMPARISON_DIR" ]; then
    echo "Could not find a comparison result directory to summarize." >&2
    exit 1
fi

if [ -z "$LATENCY_SUMMARY" ]; then
    LATENCY_SUMMARY="$(ls -1dt "$SCRIPT_DIR"/latency-stress-results/*/latency_stress_summary.env 2>/dev/null | head -n 1 || true)"
fi

SUMMARY_CSV="$COMPARISON_DIR/tagged/mini_benchmarker_summary.csv"
REPORT_MD="$COMPARISON_DIR/tagged/mini_benchmarker_report.md"
PNG_PATH="$COMPARISON_DIR/tagged/mini_benchmarker_comparison.png"
SVG_PATH="$COMPARISON_DIR/tagged/mini_benchmarker_comparison.svg"

if [ ! -f "$SUMMARY_CSV" ]; then
    echo "Missing summary CSV: $SUMMARY_CSV" >&2
    exit 1
fi

if [ -z "$OUTPUT_PATH" ]; then
    mkdir -p "$SCRIPT_DIR/review-bundles"
    OUTPUT_PATH="$SCRIPT_DIR/review-bundles/scx_flow_review_$(date +%Y%m%d_%H%M%S).md"
else
    mkdir -p "$(dirname "$OUTPUT_PATH")"
fi

csv_field() {
    local scheduler="$1"
    local field="$2"

    awk -F, -v scheduler="$scheduler" -v field="$field" '
    NR == 1 {
        for (i = 1; i <= NF; i++) {
            if ($i == field) {
                idx = i
                break
            }
        }
        next
    }
    $1 == scheduler && idx > 0 {
        print $idx
        exit
    }
    ' "$SUMMARY_CSV"
}

fmt_or_na() {
    local value="$1"
    if [ -z "$value" ]; then
        printf 'n/a'
    else
        printf '%s' "$value"
    fi
}

parse_metric_from_log() {
    local pattern="$1"
    local path="$2"

    if [ -z "$path" ] || [ ! -f "$path" ]; then
        return 0
    fi

    sed -n "s/^${pattern}: //p" "$path" | tail -n 1
}

parse_metric_from_env() {
    local key="$1"
    local path="$2"

    if [ -z "$path" ] || [ ! -f "$path" ]; then
        return 0
    fi

    sed -n "s/^${key}=//p" "$path" | tail -n 1
}

FLOW_LATENCY="$(csv_field scx_flow latency_max_us)"
FLOW_SPIKES="$(csv_field scx_flow latency_spikes_over_100us)"
FLOW_HACKBENCH="$(csv_field scx_flow hackbench_mean_seconds)"
FLOW_STRESSNG="$(csv_field scx_flow stressng_bogo_ops_per_sec)"
COSMOS_LATENCY="$(csv_field scx_cosmos latency_max_us)"
COSMOS_SPIKES="$(csv_field scx_cosmos latency_spikes_over_100us)"
COSMOS_HACKBENCH="$(csv_field scx_cosmos hackbench_mean_seconds)"
COSMOS_STRESSNG="$(csv_field scx_cosmos stressng_bogo_ops_per_sec)"
BPFLAND_LATENCY="$(csv_field scx_bpfland latency_max_us)"
BPFLAND_SPIKES="$(csv_field scx_bpfland latency_spikes_over_100us)"
BPFLAND_HACKBENCH="$(csv_field scx_bpfland hackbench_mean_seconds)"
BPFLAND_STRESSNG="$(csv_field scx_bpfland stressng_bogo_ops_per_sec)"

HOOK_RUNNABLE="$(parse_metric_from_log 'runnable() max activity' "$HOOK_LOG")"
HOOK_CPU_RELEASE="$(parse_metric_from_log 'cpu_release() max activity' "$HOOK_LOG")"
LIFE_INIT_TASK="$(parse_metric_from_log 'init_task() max activity' "$LIFECYCLE_LOG")"
LIFE_ENABLE="$(parse_metric_from_log 'enable() max activity' "$LIFECYCLE_LOG")"
LIFE_EXIT_TASK="$(parse_metric_from_log 'exit_task() max activity' "$LIFECYCLE_LOG")"
LATENCY_RESULTS_DIR="$(parse_metric_from_env 'RESULTS_DIR' "$LATENCY_SUMMARY")"
LATENCY_LOG_PATH="$(parse_metric_from_env 'LOG_PATH' "$LATENCY_SUMMARY")"
LATENCY_MONITOR_PATH="$(parse_metric_from_env 'MONITOR_PATH' "$LATENCY_SUMMARY")"
LATENCY_KERNEL_LOG_PATH="$(parse_metric_from_env 'KERNEL_LOG_PATH' "$LATENCY_SUMMARY")"
LATENCY_OVERALL_STATUS="$(parse_metric_from_env 'OVERALL_STATUS' "$LATENCY_SUMMARY")"
LATENCY_OVERALL_NOTE="$(parse_metric_from_env 'OVERALL_NOTE' "$LATENCY_SUMMARY")"
LATENCY_MIXED_STATUS="$(parse_metric_from_env 'MIXED_PHASE_STATUS' "$LATENCY_SUMMARY")"
LATENCY_MIXED_MAX="$(parse_metric_from_env 'MIXED_LATENCY_MAX_US' "$LATENCY_SUMMARY")"
LATENCY_MIXED_P95="$(parse_metric_from_env 'MIXED_LATENCY_P95_US' "$LATENCY_SUMMARY")"
LATENCY_MIXED_P99="$(parse_metric_from_env 'MIXED_LATENCY_P99_US' "$LATENCY_SUMMARY")"
LATENCY_MIXED_SPIKES="$(parse_metric_from_env 'MIXED_SPIKES_OVER_100US' "$LATENCY_SUMMARY")"
LATENCY_RT_STATUS="$(parse_metric_from_env 'RT_PHASE_STATUS' "$LATENCY_SUMMARY")"
LATENCY_RT_MAX="$(parse_metric_from_env 'RT_LATENCY_MAX_US' "$LATENCY_SUMMARY")"
LATENCY_RT_P95="$(parse_metric_from_env 'RT_LATENCY_P95_US' "$LATENCY_SUMMARY")"
LATENCY_RT_P99="$(parse_metric_from_env 'RT_LATENCY_P99_US' "$LATENCY_SUMMARY")"
LATENCY_RT_SPIKES="$(parse_metric_from_env 'RT_SPIKES_OVER_100US' "$LATENCY_SUMMARY")"
LATENCY_RUNNABLE_MAX="$(parse_metric_from_env 'RUNNABLE_MAX' "$LATENCY_SUMMARY")"
LATENCY_CPU_RELEASE_MAX="$(parse_metric_from_env 'CPU_RELEASE_MAX' "$LATENCY_SUMMARY")"
LATENCY_RESERVE_LOCAL_MAX="$(parse_metric_from_env 'RESERVED_LOCAL_MAX' "$LATENCY_SUMMARY")"
LATENCY_RESERVE_GLOBAL_MAX="$(parse_metric_from_env 'RESERVED_GLOBAL_MAX' "$LATENCY_SUMMARY")"
LATENCY_SHARED_WAKE_MAX="$(parse_metric_from_env 'SHARED_WAKE_MAX' "$LATENCY_SUMMARY")"
LATENCY_WAKE_PREEMPT_MAX="$(parse_metric_from_env 'WAKE_PREEMPT_MAX' "$LATENCY_SUMMARY")"
LATENCY_KERNEL_DISABLES="$(parse_metric_from_env 'KERNEL_DISABLE_EVENTS' "$LATENCY_SUMMARY")"
LATENCY_KERNEL_STALLS="$(parse_metric_from_env 'KERNEL_STALL_EVENTS' "$LATENCY_SUMMARY")"
LATENCY_KERNEL_REENABLES="$(parse_metric_from_env 'KERNEL_REENABLE_EVENTS' "$LATENCY_SUMMARY")"
LATENCY_FINAL_MODE="$(parse_metric_from_env 'FINAL_AUTOTUNE_MODE' "$LATENCY_SUMMARY")"
LATENCY_FINAL_GEN="$(parse_metric_from_env 'FINAL_AUTOTUNE_GENERATION' "$LATENCY_SUMMARY")"

cat > "$OUTPUT_PATH" <<EOF
# scx_flow Review Bundle

Generated: $(date)

## Comparison Snapshot

Source comparison:
- [$COMPARISON_DIR]($COMPARISON_DIR)
- [$REPORT_MD]($REPORT_MD)
- [$PNG_PATH]($PNG_PATH)
- [$SVG_PATH]($SVG_PATH)

| Scheduler | Max latency (us) | Spikes >100us | Hackbench mean (s) | Stress-ng bogo ops/s |
| --- | ---: | ---: | ---: | ---: |
| scx_flow | $(fmt_or_na "$FLOW_LATENCY") | $(fmt_or_na "$FLOW_SPIKES") | $(fmt_or_na "$FLOW_HACKBENCH") | $(fmt_or_na "$FLOW_STRESSNG") |
| scx_cosmos | $(fmt_or_na "$COSMOS_LATENCY") | $(fmt_or_na "$COSMOS_SPIKES") | $(fmt_or_na "$COSMOS_HACKBENCH") | $(fmt_or_na "$COSMOS_STRESSNG") |
| scx_bpfland | $(fmt_or_na "$BPFLAND_LATENCY") | $(fmt_or_na "$BPFLAND_SPIKES") | $(fmt_or_na "$BPFLAND_HACKBENCH") | $(fmt_or_na "$BPFLAND_STRESSNG") |

## Latency-Stress Snapshot

EOF

if [ -n "$LATENCY_SUMMARY" ] && [ -f "$LATENCY_SUMMARY" ]; then
cat >> "$OUTPUT_PATH" <<EOF
Source latency-stress run:
- [$LATENCY_RESULTS_DIR]($LATENCY_RESULTS_DIR)
- [$LATENCY_LOG_PATH]($LATENCY_LOG_PATH)
- [$LATENCY_MONITOR_PATH]($LATENCY_MONITOR_PATH)
- [$LATENCY_KERNEL_LOG_PATH]($LATENCY_KERNEL_LOG_PATH)

Latency-stress overall status:
- status: $(fmt_or_na "$LATENCY_OVERALL_STATUS")
- note: $(fmt_or_na "$LATENCY_OVERALL_NOTE")

| Phase | Status | P95 latency (us) | P99 latency (us) | Max latency (us) | Spikes >100us |
| --- | --- | ---: | ---: | ---: | ---: |
| Mixed load + wake storm | $(fmt_or_na "$LATENCY_MIXED_STATUS") | $(fmt_or_na "$LATENCY_MIXED_P95") | $(fmt_or_na "$LATENCY_MIXED_P99") | $(fmt_or_na "$LATENCY_MIXED_MAX") | $(fmt_or_na "$LATENCY_MIXED_SPIKES") |
| RT interference | $(fmt_or_na "$LATENCY_RT_STATUS") | $(fmt_or_na "$LATENCY_RT_P95") | $(fmt_or_na "$LATENCY_RT_P99") | $(fmt_or_na "$LATENCY_RT_MAX") | $(fmt_or_na "$LATENCY_RT_SPIKES") |

Latency-stress monitor peaks:
- runnable(): $(fmt_or_na "$LATENCY_RUNNABLE_MAX")
- cpu_release(): $(fmt_or_na "$LATENCY_CPU_RELEASE_MAX")
- reserve_local: $(fmt_or_na "$LATENCY_RESERVE_LOCAL_MAX")
- reserve_global: $(fmt_or_na "$LATENCY_RESERVE_GLOBAL_MAX")
- shared_wake: $(fmt_or_na "$LATENCY_SHARED_WAKE_MAX")
- wake_preempt: $(fmt_or_na "$LATENCY_WAKE_PREEMPT_MAX")
- kernel disable events: $(fmt_or_na "$LATENCY_KERNEL_DISABLES")
- kernel runnable-stall events: $(fmt_or_na "$LATENCY_KERNEL_STALLS")
- kernel re-enable events: $(fmt_or_na "$LATENCY_KERNEL_REENABLES")
- final autotune mode: $(fmt_or_na "$LATENCY_FINAL_MODE") (gen $(fmt_or_na "$LATENCY_FINAL_GEN"))

EOF
else
cat >> "$OUTPUT_PATH" <<EOF
No latency-stress summary was supplied for this bundle.

EOF
fi

cat >> "$OUTPUT_PATH" <<EOF
## Validated Coverage

Hook validation:
- runnable(): $(fmt_or_na "$HOOK_RUNNABLE")
- cpu_release(): $(fmt_or_na "$HOOK_CPU_RELEASE")

Lifecycle validation:
- init_task(): $(fmt_or_na "$LIFE_INIT_TASK")
- enable(): $(fmt_or_na "$LIFE_ENABLE")
- exit_task(): $(fmt_or_na "$LIFE_EXIT_TASK")

## Review-Ready Claims

- \`scx_flow\` attaches successfully and stays active as the live \`sched_ext\` scheduler.
- The scheduler is benchmark-competitive on throughput workloads and remains in the same general performance pack as the compared schedulers.
- \`runnable()\`, \`cpu_release()\`, \`init_task()\`, \`enable()\`, and \`exit_task()\` have targeted validation coverage when the optional logs are supplied.
- The adversarial latency-stress suite can capture mixed-load and RT-interference behavior when the optional summary is supplied.
- The scheduler defaults to bounded adaptive tuning rather than exposing workload-specific CLI tuning knobs.

## Limits We Should State Plainly

- The current implementation does not justify hard wakeup-latency guarantees.
- Benchmark outcomes still vary with hardware, power profile, and background load.
- The strict RT/watchdog runnable-stall scenario should not be treated as unique to \`scx_flow\`; the same latency-stress comparison can reproduce it on \`scx_cosmos\` too.
- \`scx_flow\` can be presented as production-capable in the same practical general-purpose sense as \`scx_cosmos\`, but it still has a narrower and less mature implementation surface overall.
- The adaptive controller is intentionally conservative and currently tunes only a small bounded set of policy knobs.
EOF

echo "Wrote review bundle to: $OUTPUT_PATH"
