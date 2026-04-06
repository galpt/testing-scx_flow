#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
"""Render CSV, PNG, SVG, and Markdown summaries for burst benchmark env files."""

from __future__ import annotations

import argparse
import csv
import statistics
from pathlib import Path

import matplotlib.pyplot as plt

METRICS = [
    ("BURST_LATENCY_P95_US", "Burst p95 Lateness (us)", "lower"),
    ("BURST_LATENCY_P99_US", "Burst p99 Lateness (us)", "lower"),
    ("BURST_LATENCY_MAX_US", "Burst Max Lateness (us)", "lower"),
    ("BURST_MISS_RATIO_PCT", "Burst Miss Ratio (%)", "lower"),
    ("BURST_LATE_OVER_THRESHOLD_RATIO_PCT", "Burst Late Over Threshold Ratio (%)", "lower"),
]

COLOR_BY_SCHEDULER = {
    "baseline": "#4e79a7",
    "scx_cosmos": "#f28e2b",
    "scx_bpfland": "#59a14f",
    "scx_cake": "#edc948",
    "scx_flow": "#e15759",
    "scx_pandemonium": "#76b7b2",
}

SCHEDULER_ALIASES = {
    "scx_baseline": "baseline",
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


def format_metric_value(metric_key: str, value: float | None) -> str:
    if value is None:
        return "n/a"
    if metric_key in ("BURST_MISS_RATIO_PCT", "BURST_LATE_OVER_THRESHOLD_RATIO_PCT"):
        if value < 0.01:
            return f"{value:.4f}"
        return f"{value:.3f}"
    return f"{value:.2f}"


def load_rows(summaries_dir: Path) -> list[dict[str, str]]:
    rows = [parse_env_file(path) for path in sorted(summaries_dir.glob("*.env"))]
    if not rows:
        raise SystemExit(f"No summary files found in {summaries_dir}")
    return rows


def aggregate(rows: list[dict[str, str]]) -> list[dict[str, object]]:
    grouped: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        scheduler = row.get("SCHEDULER_UNDER_TEST") or row.get("EXPECTED_SCHEDULER") or "unknown"
        scheduler = SCHEDULER_ALIASES.get(scheduler, scheduler)
        grouped.setdefault(scheduler, []).append(row)

    aggregated: list[dict[str, object]] = []
    for scheduler, items in grouped.items():
        representative = next(
            (item for item in reversed(items) if item.get("COMPARE_STATUS") == "completed"),
            items[-1],
        )
        entry: dict[str, object] = {
            "scheduler": scheduler,
            "display_scheduler": scheduler,
            "runs": len(items),
            "status": ", ".join(sorted({item.get("COMPARE_STATUS", "unknown") for item in items})),
            "sched_ext_state": representative.get("SCHED_EXT_STATE", ""),
            "current_scheduler": representative.get("CURRENT_SCHEDULER", ""),
            "kernel_release": representative.get("KERNEL_RELEASE", ""),
            "period_us": representative.get("BURST_PERIOD_US", ""),
            "window_ms": representative.get("BURST_WINDOW_MS", ""),
            "interval_ms": representative.get("BURST_INTERVAL_MS", ""),
            "late_threshold_us": representative.get("BURST_LATE_THRESHOLD_US", ""),
            "notes": "; ".join(note for note in {item.get("COMPARE_NOTE", "") for item in items} if note),
            "log_paths": "; ".join(item.get("LOG_PATH", "") for item in items if item.get("LOG_PATH")),
            "raw_json_paths": "; ".join(item.get("RAW_JSON_PATH", "") for item in items if item.get("RAW_JSON_PATH")),
        }
        if scheduler == "baseline" and entry["kernel_release"]:
            entry["display_scheduler"] = f"baseline ({entry['kernel_release']})"
        for metric_key, _, _ in METRICS:
            values = [
                parsed
                for item in items
                if (parsed := as_float(item.get(metric_key))) is not None
            ]
            entry[metric_key] = statistics.fmean(values) if values else None
        resolution_values = [
            parsed
            for item in items
            if (parsed := as_float(item.get("BURST_MISS_RATIO_RESOLUTION_PCT"))) is not None
        ]
        entry["BURST_MISS_RATIO_RESOLUTION_PCT"] = (
            statistics.fmean(resolution_values) if resolution_values else None
        )
        aggregated.append(entry)

    ordered = {
        name: index
        for index, name in enumerate(["baseline", "scx_cosmos", "scx_bpfland", "scx_cake", "scx_flow", "scx_pandemonium"])
    }
    aggregated.sort(key=lambda item: ordered.get(str(item["scheduler"]), 999))
    return aggregated


def summarize_run_counts(aggregated: list[dict[str, object]]) -> str:
    run_counts = sorted({int(entry["runs"]) for entry in aggregated if entry.get("runs") is not None})
    if not run_counts:
        return "Run count unavailable"
    if len(run_counts) == 1:
        run_label = "run" if run_counts[0] == 1 else "runs"
        return f"Averages over {run_counts[0]} {run_label} per scheduler."
    return "Runs per scheduler vary; see labels and report table."


def sort_metric_entries(aggregated: list[dict[str, object]], metric_key: str, direction: str) -> list[dict[str, object]]:
    present = [entry for entry in aggregated if entry.get(metric_key) is not None]
    missing = [entry for entry in aggregated if entry.get(metric_key) is None]
    reverse = direction == "higher"
    present.sort(key=lambda entry: float(entry[metric_key]), reverse=reverse)
    return present + missing


def write_csv(out_dir: Path, aggregated: list[dict[str, object]]) -> Path:
    csv_path = out_dir / "burst_benchmarker_summary.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "scheduler",
                "display_scheduler",
                "runs",
                "status",
                "sched_ext_state",
                "current_scheduler",
                "kernel_release",
                "period_us",
                "window_ms",
                "interval_ms",
                "late_threshold_us",
                "burst_latency_p95_us",
                "burst_latency_p99_us",
                "burst_latency_max_us",
                "burst_miss_ratio_pct",
                "burst_miss_ratio_resolution_pct",
                "burst_late_over_threshold_ratio_pct",
                "notes",
                "log_paths",
                "raw_json_paths",
            ]
        )
        for entry in aggregated:
            writer.writerow(
                [
                    entry["scheduler"],
                    entry["display_scheduler"],
                    entry["runs"],
                    entry["status"],
                    entry["sched_ext_state"],
                    entry["current_scheduler"],
                    entry["kernel_release"],
                    entry["period_us"],
                    entry["window_ms"],
                    entry["interval_ms"],
                    entry["late_threshold_us"],
                    "" if entry["BURST_LATENCY_P95_US"] is None else f"{entry['BURST_LATENCY_P95_US']:.2f}",
                    "" if entry["BURST_LATENCY_P99_US"] is None else f"{entry['BURST_LATENCY_P99_US']:.2f}",
                    "" if entry["BURST_LATENCY_MAX_US"] is None else f"{entry['BURST_LATENCY_MAX_US']:.2f}",
                    "" if entry["BURST_MISS_RATIO_PCT"] is None else f"{entry['BURST_MISS_RATIO_PCT']:.4f}",
                    "" if entry.get("BURST_MISS_RATIO_RESOLUTION_PCT") is None else f"{entry['BURST_MISS_RATIO_RESOLUTION_PCT']:.4f}",
                    "" if entry["BURST_LATE_OVER_THRESHOLD_RATIO_PCT"] is None else f"{entry['BURST_LATE_OVER_THRESHOLD_RATIO_PCT']:.4f}",
                    entry["notes"],
                    entry["log_paths"],
                    entry["raw_json_paths"],
                ]
            )
    return csv_path


def render_chart(out_dir: Path, aggregated: list[dict[str, object]]) -> tuple[Path, Path]:
    active_metrics = [metric for metric in METRICS if any(entry.get(metric[0]) is not None for entry in aggregated)]
    if not active_metrics:
        raise SystemExit("No numeric metrics were available to plot")

    fig, axes = plt.subplots(len(active_metrics), 1, figsize=(12, 3.2 * len(active_metrics)))
    if len(active_metrics) == 1:
        axes = [axes]

    for ax, (metric_key, title, direction) in zip(axes, active_metrics):
        ranked_entries = sort_metric_entries(aggregated, metric_key, direction)
        labels = [str(entry["display_scheduler"]) for entry in ranked_entries]
        values = [entry.get(metric_key) for entry in ranked_entries]
        display_values = [0.0 if value is None else float(value) for value in values]
        colors = [COLOR_BY_SCHEDULER.get(str(entry["scheduler"]), "#76b7b2") for entry in ranked_entries]
        bars = ax.barh(labels, display_values, color=colors)
        ax.set_title(f"{title} ({direction} is better)")
        ax.grid(axis="x", linestyle="--", alpha=0.3)
        ax.invert_yaxis()
        annotation_pad = max(display_values, default=0.0) * 0.01
        if annotation_pad <= 0.0:
            annotation_pad = 0.05
        for bar, value in zip(bars, values):
            label = format_metric_value(metric_key, None if value is None else float(value))
            ax.text(bar.get_width() + annotation_pad, bar.get_y() + bar.get_height() / 2, label, va="center")

    run_count_summary = summarize_run_counts(aggregated)
    period_us = next((str(entry.get("period_us", "")).strip() for entry in aggregated if str(entry.get("period_us", "")).strip()), "")
    window_ms = next((str(entry.get("window_ms", "")).strip() for entry in aggregated if str(entry.get("window_ms", "")).strip()), "")
    interval_ms = next((str(entry.get("interval_ms", "")).strip() for entry in aggregated if str(entry.get("interval_ms", "")).strip()), "")
    fig.suptitle("Burst Benchmarker Comparison", fontsize=14, fontweight="bold")
    fig.text(
        0.5,
        0.955,
        f"{run_count_summary} Probe period: {period_us}us. Burst window: {window_ms}ms every {interval_ms}ms.",
        ha="center",
        va="top",
        fontsize=10,
    )
    fig.tight_layout(rect=(0, 0, 1, 0.94))

    png_path = out_dir / "burst_benchmarker_comparison.png"
    svg_path = out_dir / "burst_benchmarker_comparison.svg"
    fig.savefig(png_path, dpi=160)
    fig.savefig(svg_path)
    plt.close(fig)
    return png_path, svg_path


def write_report(out_dir: Path, aggregated: list[dict[str, object]]) -> Path:
    report_path = out_dir / "burst_benchmarker_report.md"
    run_count_summary = summarize_run_counts(aggregated)
    period_us = next((str(entry.get("period_us", "")).strip() for entry in aggregated if str(entry.get("period_us", "")).strip()), "")
    window_ms = next((str(entry.get("window_ms", "")).strip() for entry in aggregated if str(entry.get("window_ms", "")).strip()), "")
    interval_ms = next((str(entry.get("interval_ms", "")).strip() for entry in aggregated if str(entry.get("interval_ms", "")).strip()), "")
    lines = [
        "# Burst Benchmarker Report",
        "",
        "This report aggregates sudden load-spike tail latency probe runs across the selected schedulers.",
        "",
        f"Run count summary: {run_count_summary}",
    ]
    if period_us:
        lines.append(f"Probe period: {period_us}us")
    if window_ms and interval_ms:
        lines.append(f"Burst window: {window_ms}ms every {interval_ms}ms")
    lines.extend(
        [
            "",
            "| Scheduler | Runs | Status | sched_ext state | Current scheduler | Burst p95 (us) | Burst p99 (us) | Burst max (us) | Burst miss ratio (%) | Miss resolution (%) | Burst late > threshold (%) |",
            "| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
    )
    for entry in aggregated:
        lines.append(
            "| {scheduler} | {runs} | {status} | {sched_ext_state} | {current_scheduler} | {p95} | {p99} | {max_late} | {miss_ratio} | {resolution} | {late_ratio} |".format(
                scheduler=entry["display_scheduler"],
                runs=entry["runs"],
                status=entry["status"],
                sched_ext_state=entry["sched_ext_state"] or "unknown",
                current_scheduler=entry["current_scheduler"] or "none",
                p95="n/a" if entry["BURST_LATENCY_P95_US"] is None else f"{entry['BURST_LATENCY_P95_US']:.2f}",
                p99="n/a" if entry["BURST_LATENCY_P99_US"] is None else f"{entry['BURST_LATENCY_P99_US']:.2f}",
                max_late="n/a" if entry["BURST_LATENCY_MAX_US"] is None else f"{entry['BURST_LATENCY_MAX_US']:.2f}",
                miss_ratio="n/a" if entry["BURST_MISS_RATIO_PCT"] is None else f"{entry['BURST_MISS_RATIO_PCT']:.4f}",
                resolution="n/a" if entry.get("BURST_MISS_RATIO_RESOLUTION_PCT") is None else f"{entry['BURST_MISS_RATIO_RESOLUTION_PCT']:.4f}",
                late_ratio="n/a" if entry["BURST_LATE_OVER_THRESHOLD_RATIO_PCT"] is None else f"{entry['BURST_LATE_OVER_THRESHOLD_RATIO_PCT']:.4f}",
            )
        )

    lines.extend(
        [
            "",
            "## Notes",
            "",
            "- Lower is better for all burst-tail metrics.",
            "- `Burst miss ratio` counts burst-window probe samples that woke later than a full probe period.",
            "- `Miss resolution` is the smallest non-zero miss ratio this run can observe from its active burst sample count.",
            "- `Burst late > threshold` is a softer tail signal using the configured lateness threshold.",
            "- Review the raw log and JSON paths from `burst_benchmarker_summary.csv` when a row shows `failed` or `skipped`.",
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
