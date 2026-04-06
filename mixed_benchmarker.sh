#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Compare schedulers using the mixed-workload latency-stress benchmark.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPARE_SCRIPT="$SCRIPT_DIR/latency_stress_compare.sh"
RESULTS_ROOT="$SCRIPT_DIR/mixed-comparison-results"
DEFAULT_SCHEDULERS="scx_cosmos scx_bpfland scx_flow"

usage() {
    cat <<EOF
Usage: sudo ./mixed_benchmarker.sh [options]

Compare schedulers using the mixed-workload latency-stress benchmark and
generate CSV/PNG/SVG outputs focused on mixed/RT p95, p99, and max latency.

Options:
  --schedulers "LIST"       Space-separated scheduler list
                            Default: "${DEFAULT_SCHEDULERS}"
  --results-root DIR        Root directory for timestamped results
                            Default: ${RESULTS_ROOT}
  --results-dir DIR         Write this run into DIR instead of the default timestamped path
  --keep-results N          Keep only the newest N result directories (default: 3)
  -h, --help                Show this help
EOF
}

ARGS=(
    --results-root "$RESULTS_ROOT"
    --artifact-stem "mixed_benchmarker_comparison"
    --report-title "Mixed-Workload Comparison"
    --schedulers "$DEFAULT_SCHEDULERS"
)

while [ "$#" -gt 0 ]; do
    case "$1" in
        --schedulers|--results-root|--results-dir|--keep-results)
            ARGS+=("$1" "$2")
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

exec "$COMPARE_SCRIPT" "${ARGS[@]}"
