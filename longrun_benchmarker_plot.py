#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
"""Render CSV, PNG, SVG, and Markdown summaries for longrun benchmark env files."""

from __future__ import annotations

import argparse
import csv
import statistics
from pathlib import Path

import matplotlib.pyplot as plt

METRICS = [
    ("LONGRUN_MISS_RATIO_PCT", "Long-Run Miss Ratio (%)", "lower"),
    ("LONGRUN_LATE_OVER_THRESHOLD_RATIO_PCT", "Late Over Threshold Ratio (%)", "lower"),
    ("LONGRUN_P95_LATE_US", "Long-Run p95 Lateness (us)", "lower"),
    ("LONGRUN_P99_LATE_US", "Long-Run p99 Lateness (us)", "lower"),
    ("LONGRUN_MAX_LATE_US", "Long-Run Max Lateness (us)", "lower"),
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
    if metric_key in ("LONGRUN_MISS_RATIO_PCT", "LONGRUN_LATE_OVER_THRESHOLD_RATIO_PCT"):
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
        representative = next((item for item in reversed(items) if item.get("COMPARE_STATUS") == "completed"), items[-1])
        entry: dict[str, object] = {
            "scheduler": scheduler,
            "display_scheduler": scheduler,
            "runs": len(items),
            "status": ", ".join(sorted({item.get("COMPARE_STATUS", "unknown") for item in items})),
            "sched_ext_state": representative.get("SCHED_EXT_STATE", ""),
            "current_scheduler": representative.get("CURRENT_SCHEDULER", ""),
            "kernel_release": representative.get("KERNEL_RELEASE", ""),
            "target_hz": representative.get("LONGRUN_TARGET_HZ", ""),
            "period_us": representative.get("LONGRUN_PERIOD_US", ""),
            "late_threshold_us": representative.get("LONGRUN_LATE_THRESHOLD_US", ""),
            "notes": "; ".join(note for note in {item.get("COMPARE_NOTE", "") for item in items} if note),
            "log_paths": "; ".join(item.get("LOG_PATH", "") for item in items if item.get("LOG_PATH")),
            "raw_json_paths": "; ".join(item.get("RAW_JSON_PATH", "") for item in items if item.get("RAW_JSON_PATH")),
        }
        if scheduler == "baseline" and entry["kernel_release"]:
            entry["display_scheduler"] = f"baseline ({entry['kernel_release']})"
        for metric_key, _, _ in METRICS:
            values = [parsed for item in items if (parsed := as_float(item.get(metric_key))) is not None]
            entry[metric_key] = statistics.fmean(values) if values else None
        aggregated.append(entry)

    ordered = {name: index for index, name in enumerate(["baseline", "scx_cosmos", "scx_bpfland", "scx_cake", "scx_flow", "scx_pandemonium"])}
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
    present.sort(key=lambda entry: float(entry[metric_key]), reverse=(direction == "higher"))
    return present + missing


def write_csv(out_dir: Path, aggregated: list[dict[str, object]]) -> Path:
    csv_path = out_dir / "longrun_benchmarker_summary.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow([
            "scheduler", "display_scheduler", "runs", "status", "sched_ext_state",
            "current_scheduler", "kernel_release", "target_hz", "period_us", "late_threshold_us",
            "longrun_miss_ratio_pct", "longrun_late_over_threshold_ratio_pct", "longrun_p95_late_us",
            "longrun_p99_late_us", "longrun_max_late_us", "notes", "log_paths", "raw_json_paths",
        ])
        for entry in aggregated:
            writer.writerow([
                entry["scheduler"], entry["display_scheduler"], entry["runs"], entry["status"],
                entry["sched_ext_state"], entry["current_scheduler"], entry["kernel_release"],
                entry["target_hz"], entry["period_us"], entry["late_threshold_us"],
                "" if entry["LONGRUN_MISS_RATIO_PCT"] is None else f"{entry['LONGRUN_MISS_RATIO_PCT']:.4f}",
                "" if entry["LONGRUN_LATE_OVER_THRESHOLD_RATIO_PCT"] is None else f"{entry['LONGRUN_LATE_OVER_THRESHOLD_RATIO_PCT']:.4f}",
                "" if entry["LONGRUN_P95_LATE_US"] is None else f"{entry['LONGRUN_P95_LATE_US']:.2f}",
                "" if entry["LONGRUN_P99_LATE_US"] is None else f"{entry['LONGRUN_P99_LATE_US']:.2f}",
                "" if entry["LONGRUN_MAX_LATE_US"] is None else f"{entry['LONGRUN_MAX_LATE_US']:.2f}",
                entry["notes"], entry["log_paths"], entry["raw_json_paths"],
            ])
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
        annotation_pad = max(display_values, default=0.0) * 0.01 or 0.05
        for bar, value in zip(bars, values):
            ax.text(bar.get_width() + annotation_pad, bar.get_y() + bar.get_height() / 2, format_metric_value(metric_key, None if value is None else float(value)), va="center")

    run_count_summary = summarize_run_counts(aggregated)
    target_hz = next((str(entry.get("target_hz", "")).strip() for entry in aggregated if str(entry.get("target_hz", "")).strip()), "")
    late_threshold_us = next((str(entry.get("late_threshold_us", "")).strip() for entry in aggregated if str(entry.get("late_threshold_us", "")).strip()), "")
    subtitle_parts = [run_count_summary]
    if target_hz:
        subtitle_parts.append(f"Target rate: {target_hz} Hz.")
    if late_threshold_us:
        subtitle_parts.append(f"Soft lateness threshold: {late_threshold_us}us.")
    fig.suptitle("Longrun Benchmarker Comparison", fontsize=14, fontweight="bold")
    fig.text(0.5, 0.955, " ".join(subtitle_parts), ha="center", va="top", fontsize=10)
    fig.tight_layout(rect=(0, 0, 1, 0.94))

    png_path = out_dir / "longrun_benchmarker_comparison.png"
    svg_path = out_dir / "longrun_benchmarker_comparison.svg"
    fig.savefig(png_path, dpi=160)
    fig.savefig(svg_path)
    plt.close(fig)
    return png_path, svg_path


def write_report(out_dir: Path, aggregated: list[dict[str, object]]) -> Path:
    report_path = out_dir / "longrun_benchmarker_report.md"
    run_count_summary = summarize_run_counts(aggregated)
    target_hz = next((str(entry.get("target_hz", "")).strip() for entry in aggregated if str(entry.get("target_hz", "")).strip()), "")
    late_threshold_us = next((str(entry.get("late_threshold_us", "")).strip() for entry in aggregated if str(entry.get("late_threshold_us", "")).strip()), "")
    lines = [
        "# Longrun Benchmarker Report",
        "",
        "This report aggregates sustained periodic latency probe runs under continuous background load.",
        "",
        f"Run count summary: {run_count_summary}",
    ]
    if target_hz:
        lines.append(f"Target rate: {target_hz} Hz")
    if late_threshold_us:
        lines.append(f"Soft lateness threshold: {late_threshold_us}us")
    lines.extend([
        "",
        "| Scheduler | Runs | Status | sched_ext state | Current scheduler | Miss ratio (%) | Late > threshold (%) | p95 late (us) | p99 late (us) | Max late (us) |",
        "| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |",
    ])
    for entry in aggregated:
        lines.append(
            "| {scheduler} | {runs} | {status} | {sched_ext_state} | {current_scheduler} | {miss_ratio} | {late_ratio} | {p95} | {p99} | {max_late} |".format(
                scheduler=entry["display_scheduler"],
                runs=entry["runs"],
                status=entry["status"],
                sched_ext_state=entry["sched_ext_state"] or "unknown",
                current_scheduler=entry["current_scheduler"] or "none",
                miss_ratio="n/a" if entry["LONGRUN_MISS_RATIO_PCT"] is None else f"{entry['LONGRUN_MISS_RATIO_PCT']:.4f}",
                late_ratio="n/a" if entry["LONGRUN_LATE_OVER_THRESHOLD_RATIO_PCT"] is None else f"{entry['LONGRUN_LATE_OVER_THRESHOLD_RATIO_PCT']:.4f}",
                p95="n/a" if entry["LONGRUN_P95_LATE_US"] is None else f"{entry['LONGRUN_P95_LATE_US']:.2f}",
                p99="n/a" if entry["LONGRUN_P99_LATE_US"] is None else f"{entry['LONGRUN_P99_LATE_US']:.2f}",
                max_late="n/a" if entry["LONGRUN_MAX_LATE_US"] is None else f"{entry['LONGRUN_MAX_LATE_US']:.2f}",
            )
        )
    lines.extend([
        "",
        "## Notes",
        "",
        "- Lower is better for miss ratio and all lateness metrics.",
        "- Long-run mode keeps the background CPU load active for the full probe duration.",
        "- Review the raw log and JSON paths from `longrun_benchmarker_summary.csv` when a row shows `failed` or `skipped`.",
    ])
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
