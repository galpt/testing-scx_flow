#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
"""Render CSV, PNG, SVG, and Markdown summaries for comprehensive benchmark CSV files."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

WORKLOADS = [
    "stress-ng-cpu-cache-mem",
    "perf-sched-msg-fork",
    "perf-memcpy",
    "argon2-hashing",
    "xz-compression",
    "primes",
    "x265-encoding",
    "ffmpeg-compilation",
]

WORKLOAD_LABELS = {
    "stress-ng-cpu-cache-mem": "stress-ng CPU/Cache/Mem",
    "perf-sched-msg-fork": "perf sched messaging",
    "perf-memcpy": "perf memcpy",
    "argon2-hashing": "Argon2 hashing",
    "xz-compression": "xz compression",
    "primes": "Primes",
    "x265-encoding": "x265 encoding",
    "ffmpeg-compilation": "ffmpeg compilation",
}

COLOR_BY_SCHEDULER = {
    "baseline": "#4e79a7",
    "scx_cosmos": "#f28e2b",
    "scx_bpfland": "#59a14f",
    "scx_cake": "#edc948",
    "scx_flow": "#e15759",
    "scx_pandemonium": "#76b7b2",
    "scx_p2dq": "#b07aa1",
    "scx_rustland": "#ff9da7",
    "scx_lavd": "#9c755f",
    "scx_rusty": "#bab0ac",
    "scx_flash": "#86bcc9",
    "scx_beerland": "#e5876a",
}


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader)


def as_float(value: str | None) -> float | None:
    if value is None or value.strip() == "":
        return None
    try:
        return float(value)
    except ValueError:
        return None


def render_charts(csv_path: Path, output_dir: Path, stem: str) -> tuple[Path, Path]:
    rows = read_csv_rows(csv_path)
    if not rows:
        raise SystemExit("No data rows in CSV")

    active_workloads = [
        wl for wl in WORKLOADS
        if any(as_float(row.get(wl)) is not None for row in rows)
    ]
    if not active_workloads:
        raise SystemExit("No numeric workload data available to plot")

    # Build charts: one per workload + total
    chart_count = len(active_workloads) + 1
    fig, axes = plt.subplots(chart_count, 1, figsize=(12, 3.2 * chart_count))
    if chart_count == 1:
        axes = [axes]

    for ax_idx, (wl, wl_title) in enumerate(
        [(wl, WORKLOAD_LABELS.get(wl, wl)) for wl in active_workloads]
    ):
        ax = axes[ax_idx]

        # Collect (scheduler, value) pairs sorted by value (lower is better)
        present = [
            (row.get("scheduler", "unknown"), as_float(row.get(wl)))
            for row in rows
            if as_float(row.get(wl)) is not None
        ]
        present.sort(key=lambda pair: pair[1])
        missing = [
            row.get("scheduler", "unknown")
            for row in rows
            if as_float(row.get(wl)) is None
        ]

        labels = [p[0] for p in present] + missing
        values = [p[1] for p in present] + [0.0] * len(missing)
        colors = [
            COLOR_BY_SCHEDULER.get(
                p[0] if not p[0].startswith("baseline") else "baseline",
                "#76b7b2",
            )
            for p in present
        ] + ["#cccccc"] * len(missing)

        bars = ax.barh(labels, values, color=colors)
        ax.set_title(f"{wl_title} (lower is better)" if wl != "perf-sched-msg-fork" else
                     f"{wl_title} (lower is better — note: flow v3.0.3 had 73.5s here)")
        ax.grid(axis="x", linestyle="--", alpha=0.3)
        ax.invert_yaxis()

        pad = max(values, default=0.0) * 0.01 or 0.05
        for bar, value in zip(bars, values):
            if value > 0:
                ax.text(bar.get_width() + pad, bar.get_y() + bar.get_height() / 2,
                        f"{value:.1f}" if value >= 10 else f"{value:.2f}",
                        va="center")

    # Total wall-time chart
    ax_total = axes[-1]
    present_total = [
        (row.get("scheduler", "unknown"), as_float(row.get("total")))
        for row in rows
        if as_float(row.get("total")) is not None
    ]
    present_total.sort(key=lambda pair: pair[1])
    labels_total = [p[0] for p in present_total]
    values_total = [p[1] for p in present_total]
    colors_total = [
        COLOR_BY_SCHEDULER.get(
            p[0] if not p[0].startswith("baseline") else "baseline",
            "#76b7b2",
        )
        for p in present_total
    ]

    bars_total = ax_total.barh(labels_total, values_total, color=colors_total)
    ax_total.set_title("Total Wall-Time Across All Workloads (lower is better)")
    ax_total.grid(axis="x", linestyle="--", alpha=0.3)
    ax_total.invert_yaxis()

    if values_total:
        pad_total = max(values_total) * 0.01 or 0.05
        for bar, value in zip(bars_total, values_total):
            ax_total.text(bar.get_width() + pad_total,
                          bar.get_y() + bar.get_height() / 2,
                          f"{value:.3f}", va="center")

    fig.suptitle("Comprehensive Scheduler Comparison", fontsize=14, fontweight="bold")
    fig.text(0.5, 0.955, "Charts are auto-sorted from best to worst for each workload.",
             ha="center", va="top", fontsize=10)
    fig.tight_layout(rect=(0, 0, 1, 0.94))

    png_path = output_dir / f"{stem}.png"
    svg_path = output_dir / f"{stem}.svg"
    fig.savefig(png_path, dpi=160)
    fig.savefig(svg_path)
    plt.close(fig)
    return png_path, svg_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--stem", default="comprehensive_benchmarker_comparison")
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    render_charts(args.csv, args.output_dir, args.stem)


if __name__ == "__main__":
    main()
