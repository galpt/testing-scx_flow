#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
"""Render PNG/SVG charts for latency-stress comparison and repeat CSV files."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

COMPARE_METRICS = [
    ("mixed_p95_us", "Mixed p95 (us)", "lower"),
    ("mixed_p99_us", "Mixed p99 (us)", "lower"),
    ("mixed_max_us", "Mixed max (us)", "lower"),
    ("rt_p95_us", "RT p95 (us)", "lower"),
    ("rt_p99_us", "RT p99 (us)", "lower"),
    ("rt_max_us", "RT max (us)", "lower"),
    ("kernel_stalls", "Kernel stall events", "lower"),
]

COLOR_BY_SCHEDULER = {
    "baseline": "#4e79a7",
    "scx_cosmos": "#f28e2b",
    "scx_bpfland": "#59a14f",
    "scx_cake": "#edc948",
    "scx_flow": "#e15759",
}


def read_csv_rows(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
        return list(reader.fieldnames or []), rows


def as_float(value: str | None) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except ValueError:
        return None


def render_compare(
    csv_path: Path,
    output_dir: Path,
    stem: str,
    figure_title: str,
) -> tuple[Path, Path]:
    _, rows = read_csv_rows(csv_path)
    active_metrics = [metric for metric in COMPARE_METRICS if any(as_float(row.get(metric[0])) is not None for row in rows)]
    if not active_metrics:
        raise SystemExit("No numeric comparison metrics were available to plot")

    fig, axes = plt.subplots(len(active_metrics), 1, figsize=(12, 3.2 * len(active_metrics)))
    if len(active_metrics) == 1:
        axes = [axes]

    for ax, (metric_key, title, direction) in zip(axes, active_metrics):
        present = [row for row in rows if as_float(row.get(metric_key)) is not None]
        missing = [row for row in rows if as_float(row.get(metric_key)) is None]
        present.sort(key=lambda row: float(row[metric_key]), reverse=(direction == "higher"))
        ranked = present + missing

        labels = [row.get("display_scheduler") or row.get("scheduler", "unknown") for row in ranked]
        values = [as_float(row.get(metric_key)) for row in ranked]
        display_values = [0.0 if value is None else value for value in values]
        colors = [COLOR_BY_SCHEDULER.get(row.get("scheduler", ""), "#76b7b2") for row in ranked]

        bars = ax.barh(labels, display_values, color=colors)
        ax.set_title(f"{title} ({direction} is better)")
        ax.grid(axis="x", linestyle="--", alpha=0.3)
        ax.invert_yaxis()

        pad = max(display_values, default=0.0) * 0.01
        if pad <= 0:
            pad = 0.05
        for bar, value in zip(bars, values):
            label = "n/a" if value is None else f"{value:.2f}"
            ax.text(bar.get_width() + pad, bar.get_y() + bar.get_height() / 2, label, va="center")

    fig.suptitle(figure_title, fontsize=14, fontweight="bold")
    fig.text(0.5, 0.955, "Charts are auto-sorted from best to worst for each metric.", ha="center", va="top", fontsize=10)
    fig.tight_layout(rect=(0, 0, 1, 0.94))

    png_path = output_dir / f"{stem}.png"
    svg_path = output_dir / f"{stem}.svg"
    fig.savefig(png_path, dpi=160)
    fig.savefig(svg_path)
    plt.close(fig)
    return png_path, svg_path


def render_repeat(csv_path: Path, output_dir: Path) -> tuple[Path, Path]:
    _, rows = read_csv_rows(csv_path)
    if not rows:
        raise SystemExit("No repeat rows were available to plot")

    runs = [row.get("run", f"run{index + 1}") for index, row in enumerate(rows)]
    x = np.arange(len(runs))
    width = 0.24

    fig, axes = plt.subplots(2, 2, figsize=(14, 9))
    ((ax_mixed, ax_rt), (ax_mixed_spikes, ax_rt_spikes)) = axes

    mixed_p95 = [as_float(row.get("mixed_p95_us")) or 0.0 for row in rows]
    mixed_p99 = [as_float(row.get("mixed_p99_us")) or 0.0 for row in rows]
    mixed_max = [as_float(row.get("mixed_max_us")) or 0.0 for row in rows]
    rt_p95 = [as_float(row.get("rt_p95_us")) or 0.0 for row in rows]
    rt_p99 = [as_float(row.get("rt_p99_us")) or 0.0 for row in rows]
    rt_max = [as_float(row.get("rt_max_us")) or 0.0 for row in rows]
    mixed_spikes = [as_float(row.get("mixed_spikes_100us")) or 0.0 for row in rows]
    rt_spikes = [as_float(row.get("rt_spikes_100us")) or 0.0 for row in rows]

    ax_mixed.bar(x - width, mixed_p95, width, label="p95", color="#4e79a7")
    ax_mixed.bar(x, mixed_p99, width, label="p99", color="#f28e2b")
    ax_mixed.bar(x + width, mixed_max, width, label="max", color="#e15759")
    ax_mixed.set_title("Mixed Latency Tails by Run")
    ax_mixed.set_ylabel("Latency (us)")
    ax_mixed.set_xticks(x, runs)
    ax_mixed.grid(axis="y", linestyle="--", alpha=0.3)
    ax_mixed.legend()

    ax_rt.bar(x - width, rt_p95, width, label="p95", color="#4e79a7")
    ax_rt.bar(x, rt_p99, width, label="p99", color="#f28e2b")
    ax_rt.bar(x + width, rt_max, width, label="max", color="#e15759")
    ax_rt.set_title("RT Latency Tails by Run")
    ax_rt.set_ylabel("Latency (us)")
    ax_rt.set_xticks(x, runs)
    ax_rt.grid(axis="y", linestyle="--", alpha=0.3)
    ax_rt.legend()

    ax_mixed_spikes.bar(runs, mixed_spikes, color="#59a14f")
    ax_mixed_spikes.set_title("Mixed Spikes >100us by Run")
    ax_mixed_spikes.set_ylabel("Spike count")
    ax_mixed_spikes.grid(axis="y", linestyle="--", alpha=0.3)

    ax_rt_spikes.bar(runs, rt_spikes, color="#edc948")
    ax_rt_spikes.set_title("RT Spikes >100us by Run")
    ax_rt_spikes.set_ylabel("Spike count")
    ax_rt_spikes.grid(axis="y", linestyle="--", alpha=0.3)

    fig.suptitle("Repeated Latency-Stress Validation", fontsize=14, fontweight="bold")
    fig.tight_layout(rect=(0, 0, 1, 0.95))

    png_path = output_dir / "repeat_latency_stress.png"
    svg_path = output_dir / "repeat_latency_stress.svg"
    fig.savefig(png_path, dpi=160)
    fig.savefig(svg_path)
    plt.close(fig)
    return png_path, svg_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("compare", "repeat"), required=True)
    parser.add_argument("--csv", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--stem", default="latency_stress_compare")
    parser.add_argument("--figure-title", default="Latency-Stress Scheduler Comparison")
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    if args.mode == "compare":
        render_compare(args.csv, args.output_dir, args.stem, args.figure_title)
    else:
        render_repeat(args.csv, args.output_dir)


if __name__ == "__main__":
    main()
