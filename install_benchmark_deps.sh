#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Install benchmark dependencies (Arch Linux / CachyOS)

set -e

echo "=== Installing benchmark dependencies ==="
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo:"
    echo "  sudo $0"
    exit 1
fi

echo "Installing benchmark tools..."

REQUIRED_PACKAGES=(
    rt-tests
    stress-ng
    perf
    sysbench
    schbench
    python-matplotlib
)

# On Arch/CachyOS, hackbench and lmbench are not available as standalone
# official pacman targets on many installations. The benchmark script handles
# them as optional tools and will skip or fall back when they are unavailable.
OPTIONAL_TOOLS=(
    hackbench
    lmbench
)

pacman -Sy --noconfirm "${REQUIRED_PACKAGES[@]}"

echo ""
echo "=== Benchmark dependencies installed! ==="
echo ""
echo "Available benchmarks:"
echo "  - cyclictest (rt-tests)"
echo "  - stress-ng"
echo "  - perf"
echo "  - sysbench"
echo "  - python-matplotlib"
echo ""
echo "Optional tools not installed via pacman here:"
for tool in "${OPTIONAL_TOOLS[@]}"; do
    echo "  - $tool"
done
echo ""
echo "benchmark.sh will automatically skip or fall back if optional tools are missing."
