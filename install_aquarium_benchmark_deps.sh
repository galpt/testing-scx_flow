#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
# Install the JavaScript/browser-side dependencies needed for the Aquarium
# benchmark harness.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "node is required. Install Node.js first." >&2
    exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
    echo "npm is required. Install npm first." >&2
    exit 1
fi

cd "$SCRIPT_DIR"

echo "[aquarium-deps] Installing npm dependencies..."
npm install

echo "[aquarium-deps] Installing Playwright Chromium..."
npx playwright install chromium

echo "[aquarium-deps] Done."
