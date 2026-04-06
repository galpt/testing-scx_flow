#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SUDO_BIN="${SUDO_BIN:-sudo}"

run_step() {
    local title="$1"
    shift

    printf '\n========================================\n'
    printf '%s\n' "$title"
    printf '========================================\n'
    "$@"
}

cd "$ROOT_DIR"

run_step \
    "Burst strict validation" \
    "$SUDO_BIN" ./burst_benchmarker.sh --strict --runs 2 \
    --schedulers "baseline scx_cosmos scx_pandemonium scx_flow"

run_step \
    "Mixed-workload validation" \
    "$SUDO_BIN" ./mixed_benchmarker.sh \
    --schedulers "scx_cosmos scx_pandemonium scx_flow"

run_step \
    "Deadline validation" \
    "$SUDO_BIN" ./deadline_benchmarker.sh --runs 2 \
    --schedulers "baseline scx_cosmos scx_pandemonium scx_flow"

run_step \
    "Longrun validation" \
    "$SUDO_BIN" ./longrun_benchmarker.sh \
    --schedulers "scx_cosmos scx_pandemonium scx_flow"

run_step \
    "Fork/thread validation" \
    "$SUDO_BIN" ./fork_thread_benchmarker.sh \
    --schedulers "baseline scx_cosmos scx_pandemonium scx_flow"

printf '\nKeeper validation bundle completed.\n'
