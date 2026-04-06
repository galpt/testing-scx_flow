#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
"""Render CSV, PNG, SVG, and Markdown summaries for fork/thread throughput env files."""

from __future__ import annotations

import argparse
import csv
import statistics
from pathlib import Path

import matplotlib.pyplot as plt

METRICS = [
    ("FORK_THREAD_TIME_SEC", "Fork/Thread Time (sec)", "lower"),
    ("FORK_THREAD_IPC", "IPC", "higher"),
    ("FORK_THREAD_CACHE_MISSES", "Cache Misses", "lower"),
]

COLOR_BY_SCHEDULER = {
    "baseline": "#4e79a7",
    "scx_cosmos": "#f28e2b",
    "scx_bpfland": "#59a14f",
    "scx_cake": "#edc948",
    "scx_flow": "#e15759",
    "scx_pandemonium": "#76b7b2",
}

SCHEDULER_ALIASES = {"scx_baseline": "baseline"}


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
    if metric_key in {"FORK_THREAD_IPC", "FORK_THREAD_TIME_SEC"}:
        return f"{value:.3f}"
    return f"{value:,.0f}"


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

    baseline_time = None
    if "baseline" in grouped:
        vals = [as_float(item.get("FORK_THREAD_TIME_SEC")) for item in grouped["baseline"]]
        vals = [v for v in vals if v is not None]
        if vals:
            baseline_time = statistics.fmean(vals)

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
            "groups": representative.get("FORK_THREAD_GROUPS", ""),
            "nr_loops": representative.get("FORK_THREAD_NR_LOOPS", ""),
            "use_pipe": representative.get("FORK_THREAD_USE_PIPE", ""),
            "use_thread": representative.get("FORK_THREAD_USE_THREAD", ""),
            "notes": "; ".join(note for note in {item.get("COMPARE_NOTE", "") for item in items} if note),
            "log_paths": "; ".join(item.get("LOG_PATH", "") for item in items if item.get("LOG_PATH")),
            "perf_stdout_paths": "; ".join(item.get("PERF_STDOUT_PATH", "") for item in items if item.get("PERF_STDOUT_PATH")),
            "perf_stat_paths": "; ".join(item.get("PERF_STAT_PATH", "") for item in items if item.get("PERF_STAT_PATH")),
        }
        if scheduler == "baseline" and entry["kernel_release"]:
            entry["display_scheduler"] = f"baseline ({entry['kernel_release']})"
        for metric_key in ["FORK_THREAD_TIME_SEC", "FORK_THREAD_IPC", "FORK_THREAD_CACHE_MISSES", "FORK_THREAD_CACHE_REFERENCES"]:
            values = [parsed for item in items if (parsed := as_float(item.get(metric_key))) is not None]
            entry[metric_key] = statistics.fmean(values) if values else None
        time_value = entry.get("FORK_THREAD_TIME_SEC")
        if baseline_time and time_value is not None:
            entry["TIME_VS_BASELINE_PCT"] = ((float(time_value) / baseline_time) - 1.0) * 100.0
        else:
            entry["TIME_VS_BASELINE_PCT"] = None
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
    csv_path = out_dir / "fork_thread_benchmarker_summary.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow([
            "scheduler", "display_scheduler", "runs", "status", "sched_ext_state", "current_scheduler",
            "kernel_release", "groups", "nr_loops", "use_pipe", "use_thread",
            "fork_thread_time_sec", "time_vs_baseline_pct", "fork_thread_ipc",
            "fork_thread_cache_misses", "fork_thread_cache_references",
            "notes", "log_paths", "perf_stdout_paths", "perf_stat_paths",
        ])
        for entry in aggregated:
            writer.writerow([
                entry["scheduler"], entry["display_scheduler"], entry["runs"], entry["status"],
                entry["sched_ext_state"], entry["current_scheduler"], entry["kernel_release"],
                entry["groups"], entry["nr_loops"], entry["use_pipe"], entry["use_thread"],
                "" if entry["FORK_THREAD_TIME_SEC"] is None else f"{entry['FORK_THREAD_TIME_SEC']:.3f}",
                "" if entry["TIME_VS_BASELINE_PCT"] is None else f"{entry['TIME_VS_BASELINE_PCT']:.2f}",
                "" if entry["FORK_THREAD_IPC"] is None else f"{entry['FORK_THREAD_IPC']:.3f}",
                "" if entry["FORK_THREAD_CACHE_MISSES"] is None else f"{entry['FORK_THREAD_CACHE_MISSES']:.0f}",
                "" if entry["FORK_THREAD_CACHE_REFERENCES"] is None else f"{entry['FORK_THREAD_CACHE_REFERENCES']:.0f}",
                entry["notes"], entry["log_paths"], entry["perf_stdout_paths"], entry["perf_stat_paths"],
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
            ax.text(bar.get_width() + annotation_pad, bar.get_y() + bar.get_height() / 2,
                    format_metric_value(metric_key, None if value is None else float(value)), va="center")

    run_count_summary = summarize_run_counts(aggregated)
    groups = next((str(entry.get("groups", "")).strip() for entry in aggregated if str(entry.get("groups", "")).strip()), "")
    nr_loops = next((str(entry.get("nr_loops", "")).strip() for entry in aggregated if str(entry.get("nr_loops", "")).strip()), "")
    subtitle_parts = [run_count_summary]
    if groups:
        subtitle_parts.append(f"Groups: {groups}.")
    if nr_loops:
        subtitle_parts.append(f"Loops: {nr_loops}.")
    fig.suptitle("Fork/Thread Benchmarker Comparison", fontsize=14, fontweight="bold")
    fig.text(0.5, 0.955, " ".join(subtitle_parts), ha="center", va="top", fontsize=10)
    fig.tight_layout(rect=(0, 0, 1, 0.94))

    png_path = out_dir / "fork_thread_benchmarker_comparison.png"
    svg_path = out_dir / "fork_thread_benchmarker_comparison.svg"
    fig.savefig(png_path, dpi=160)
    fig.savefig(svg_path)
    plt.close(fig)
    return png_path, svg_path


def write_report(out_dir: Path, aggregated: list[dict[str, object]]) -> Path:
    report_path = out_dir / "fork_thread_benchmarker_report.md"
    run_count_summary = summarize_run_counts(aggregated)
    groups = next((str(entry.get("groups", "")).strip() for entry in aggregated if str(entry.get("groups", "")).strip()), "")
    nr_loops = next((str(entry.get("nr_loops", "")).strip() for entry in aggregated if str(entry.get("nr_loops", "")).strip()), "")
    lines = [
        "# Fork/Thread Benchmarker Report",
        "",
        "This report aggregates `perf bench sched messaging` throughput runs and supporting `perf stat` counters.",
        "",
        f"Run count summary: {run_count_summary}",
    ]
    if groups:
        lines.append(f"Groups: {groups}")
    if nr_loops:
        lines.append(f"Loops: {nr_loops}")
    lines.extend([
        "",
        "| Scheduler | Runs | Status | sched_ext state | Current scheduler | Time (sec) | vs baseline (%) | IPC | Cache Misses | Cache References |",
        "| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |",
    ])
    for entry in aggregated:
        lines.append(
            "| {scheduler} | {runs} | {status} | {sched_ext_state} | {current_scheduler} | {time_sec} | {vs_baseline} | {ipc} | {cache_misses} | {cache_refs} |".format(
                scheduler=entry["display_scheduler"],
                runs=entry["runs"],
                status=entry["status"],
                sched_ext_state=entry["sched_ext_state"] or "unknown",
                current_scheduler=entry["current_scheduler"] or "none",
                time_sec="n/a" if entry["FORK_THREAD_TIME_SEC"] is None else f"{entry['FORK_THREAD_TIME_SEC']:.3f}",
                vs_baseline="n/a" if entry["TIME_VS_BASELINE_PCT"] is None else f"{entry['TIME_VS_BASELINE_PCT']:+.2f}",
                ipc="n/a" if entry["FORK_THREAD_IPC"] is None else f"{entry['FORK_THREAD_IPC']:.3f}",
                cache_misses="n/a" if entry["FORK_THREAD_CACHE_MISSES"] is None else f"{entry['FORK_THREAD_CACHE_MISSES']:.0f}",
                cache_refs="n/a" if entry["FORK_THREAD_CACHE_REFERENCES"] is None else f"{entry['FORK_THREAD_CACHE_REFERENCES']:.0f}",
            )
        )
    lines.extend([
        "",
        "## Notes",
        "",
        "- Lower is better for time and cache misses.",
        "- Higher is better for IPC.",
        "- This mode wraps `perf bench sched messaging` with `perf stat` so throughput and cache behavior are captured together.",
        "- Review the raw log and perf paths from `fork_thread_benchmarker_summary.csv` when a row shows `failed` or `skipped`.",
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
