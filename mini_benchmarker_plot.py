#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
"""Render CSV, PNG, SVG, and Markdown summaries from mini benchmark env files."""

from __future__ import annotations

import argparse
import csv
import statistics
from pathlib import Path

import matplotlib.pyplot as plt

METRICS = [
    ("LATENCY_MAX_US", "Cyclictest Max Latency (us)", "lower"),
    ("LATENCY_SPIKES_OVER_100US", "Latency Spikes >100us", "lower"),
    ("HACKBENCH_MEAN_SECONDS", "Hackbench Mean Time (s)", "lower"),
    ("SYSBENCH_EVENTS_PER_SEC", "Sysbench Events/s", "higher"),
    ("STRESSNG_BOGO_OPS_PER_SEC", "Stress-ng Bogo Ops/s", "higher"),
]

COLOR_BY_SCHEDULER = {
    "baseline": "#4e79a7",
    "scx_cosmos": "#f28e2b",
    "scx_bpfland": "#59a14f",
    "scx_flow": "#e15759",
}


def parse_env_file(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not raw_line or raw_line.startswith("#") or "=" not in raw_line:
            continue
        key, value = raw_line.split("=", 1)
        data[key.strip()] = value.strip()
    data["__path__"] = str(path)
    return data


def as_float(value: str | None) -> float | None:
    if not value:
        return None
    try:
        return float(value)
    except ValueError:
        return None


def load_rows(summaries_dir: Path) -> list[dict[str, str]]:
    rows = [parse_env_file(path) for path in sorted(summaries_dir.glob("*.env"))]
    if not rows:
        raise SystemExit(f"No summary files found in {summaries_dir}")
    return rows


def aggregate(rows: list[dict[str, str]]) -> list[dict[str, object]]:
    grouped: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        scheduler = row.get("SCHEDULER_UNDER_TEST") or row.get("EXPECTED_SCHEDULER") or "unknown"
        grouped.setdefault(scheduler, []).append(row)

    aggregated: list[dict[str, object]] = []
    for scheduler, items in grouped.items():
        entry: dict[str, object] = {
            "scheduler": scheduler,
            "runs": len(items),
            "status": ", ".join(sorted({item.get("COMPARE_STATUS", "unknown") for item in items})),
            "current_scheduler": items[-1].get("CURRENT_SCHEDULER", ""),
            "sched_ext_state": items[-1].get("SCHED_EXT_STATE", ""),
            "notes": "; ".join(note for note in {item.get("COMPARE_NOTE", "") for item in items} if note),
            "log_paths": "; ".join(item.get("LOG_PATH", "") for item in items if item.get("LOG_PATH")),
        }
        for metric_key, _, _ in METRICS:
            values = [
                parsed
                for item in items
                if (parsed := as_float(item.get(metric_key))) is not None
            ]
            entry[metric_key] = statistics.fmean(values) if values else None
        aggregated.append(entry)

    ordered = {name: index for index, name in enumerate(["baseline", "scx_cosmos", "scx_bpfland", "scx_flow"])}
    aggregated.sort(key=lambda item: ordered.get(str(item["scheduler"]), 999))
    return aggregated


def sort_metric_entries(
    aggregated: list[dict[str, object]], metric_key: str, direction: str
) -> list[dict[str, object]]:
    present = [entry for entry in aggregated if entry.get(metric_key) is not None]
    missing = [entry for entry in aggregated if entry.get(metric_key) is None]
    reverse = direction == "higher"
    present.sort(key=lambda entry: float(entry[metric_key]), reverse=reverse)
    return present + missing


def write_csv(out_dir: Path, aggregated: list[dict[str, object]]) -> Path:
    csv_path = out_dir / "mini_benchmarker_summary.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "scheduler",
                "runs",
                "status",
                "sched_ext_state",
                "current_scheduler",
                "latency_max_us",
                "latency_spikes_over_100us",
                "hackbench_mean_seconds",
                "sysbench_events_per_sec",
                "stressng_bogo_ops_per_sec",
                "notes",
                "log_paths",
            ]
        )
        for entry in aggregated:
            writer.writerow(
                [
                    entry["scheduler"],
                    entry["runs"],
                    entry["status"],
                    entry["sched_ext_state"],
                    entry["current_scheduler"],
                    "" if entry["LATENCY_MAX_US"] is None else f"{entry['LATENCY_MAX_US']:.2f}",
                    "" if entry["LATENCY_SPIKES_OVER_100US"] is None else f"{entry['LATENCY_SPIKES_OVER_100US']:.2f}",
                    "" if entry["HACKBENCH_MEAN_SECONDS"] is None else f"{entry['HACKBENCH_MEAN_SECONDS']:.3f}",
                    "" if entry["SYSBENCH_EVENTS_PER_SEC"] is None else f"{entry['SYSBENCH_EVENTS_PER_SEC']:.2f}",
                    "" if entry["STRESSNG_BOGO_OPS_PER_SEC"] is None else f"{entry['STRESSNG_BOGO_OPS_PER_SEC']:.2f}",
                    entry["notes"],
                    entry["log_paths"],
                ]
            )
    return csv_path


def render_chart(out_dir: Path, aggregated: list[dict[str, object]]) -> tuple[Path, Path]:
    active_metrics = [
        metric for metric in METRICS if any(entry.get(metric[0]) is not None for entry in aggregated)
    ]
    if not active_metrics:
        raise SystemExit("No numeric metrics were available to plot")

    fig, axes = plt.subplots(len(active_metrics), 1, figsize=(12, 3.2 * len(active_metrics)))
    if len(active_metrics) == 1:
        axes = [axes]

    for ax, (metric_key, title, direction) in zip(axes, active_metrics):
        ranked_entries = sort_metric_entries(aggregated, metric_key, direction)
        labels = [str(entry["scheduler"]) for entry in ranked_entries]
        values = [entry.get(metric_key) for entry in ranked_entries]
        display_values = [0.0 if value is None else float(value) for value in values]
        colors = [
            COLOR_BY_SCHEDULER.get(label, "#76b7b2")
            for label in labels
        ]
        bars = ax.barh(labels, display_values, color=colors)
        ax.set_title(f"{title} ({direction} is better)")
        ax.grid(axis="x", linestyle="--", alpha=0.3)
        ax.invert_yaxis()
        annotation_pad = max(display_values, default=0.0) * 0.01
        if annotation_pad <= 0.0:
            annotation_pad = 0.05
        for bar, value in zip(bars, values):
            label = "n/a" if value is None else f"{float(value):.2f}"
            ax.text(
                bar.get_width() + annotation_pad,
                bar.get_y() + bar.get_height() / 2,
                f"{label}",
                va="center",
            )

    fig.suptitle("scx_flow Mini Benchmarker Comparison", fontsize=14, fontweight="bold")
    fig.text(
        0.5,
        0.955,
        "Charts are auto-sorted from best to worst.",
        ha="center",
        va="top",
        fontsize=10,
    )
    fig.tight_layout(rect=(0, 0, 1, 0.94))

    png_path = out_dir / "mini_benchmarker_comparison.png"
    svg_path = out_dir / "mini_benchmarker_comparison.svg"
    fig.savefig(png_path, dpi=160)
    fig.savefig(svg_path)
    plt.close(fig)
    return png_path, svg_path


def write_report(out_dir: Path, aggregated: list[dict[str, object]]) -> Path:
    report_path = out_dir / "mini_benchmarker_report.md"
    lines = [
        "# Mini Benchmarker Report",
        "",
        "This report aggregates the latest comparison run across the selected schedulers.",
        "",
        "| Scheduler | Runs | Status | sched_ext state | Current scheduler | Max latency (us) | Spikes >100us | Hackbench mean (s) | Sysbench events/s | Stress-ng bogo ops/s |",
        "| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for entry in aggregated:
        lines.append(
            "| {scheduler} | {runs} | {status} | {sched_ext_state} | {current_scheduler} | {latency} | {spikes} | {hackbench} | {sysbench} | {stressng} |".format(
                scheduler=entry["scheduler"],
                runs=entry["runs"],
                status=entry["status"],
                sched_ext_state=entry["sched_ext_state"] or "unknown",
                current_scheduler=entry["current_scheduler"] or "none",
                latency="n/a" if entry["LATENCY_MAX_US"] is None else f"{entry['LATENCY_MAX_US']:.2f}",
                spikes="n/a" if entry["LATENCY_SPIKES_OVER_100US"] is None else f"{entry['LATENCY_SPIKES_OVER_100US']:.2f}",
                hackbench="n/a" if entry["HACKBENCH_MEAN_SECONDS"] is None else f"{entry['HACKBENCH_MEAN_SECONDS']:.3f}",
                sysbench="n/a" if entry["SYSBENCH_EVENTS_PER_SEC"] is None else f"{entry['SYSBENCH_EVENTS_PER_SEC']:.2f}",
                stressng="n/a" if entry["STRESSNG_BOGO_OPS_PER_SEC"] is None else f"{entry['STRESSNG_BOGO_OPS_PER_SEC']:.2f}",
            )
        )

    lines.extend(
        [
            "",
            "## Notes",
            "",
            "- Lower is better for latency and hackbench time.",
            "- Higher is better for sysbench events/s and stress-ng bogo ops/s.",
            "- Review the raw log paths from `mini_benchmarker_summary.csv` when a row shows `failed` or `skipped`.",
        ]
    )
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return report_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--summaries-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    rows = load_rows(args.summaries_dir)
    aggregated = aggregate(rows)
    write_csv(args.output_dir, aggregated)
    render_chart(args.output_dir, aggregated)
    write_report(args.output_dir, aggregated)


if __name__ == "__main__":
    main()
