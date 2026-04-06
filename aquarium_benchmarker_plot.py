#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
"""Render CSV, PNG, SVG, and Markdown summaries for Aquarium benchmark env files."""

from __future__ import annotations

import argparse
import csv
import statistics
from pathlib import Path

import matplotlib.pyplot as plt

METRICS = [
    ("AQUARIUM_RAF_AVG_FPS", "Aquarium Average FPS", "higher"),
    ("AQUARIUM_RAF_1P_LOW_FPS", "Aquarium 1% Low FPS", "higher"),
    ("AQUARIUM_P95_FRAME_MS", "Aquarium p95 Frame Time (ms)", "lower"),
    ("AQUARIUM_JANK_OVER_33MS", "Aquarium Jank >33ms", "lower"),
    ("STRESSNG_BOGO_OPS_PER_SEC", "Stress-ng Bogo Ops/s", "higher"),
]

COLOR_BY_SCHEDULER = {
    "baseline": "#4e79a7",
    "scx_cosmos": "#f28e2b",
    "scx_bpfland": "#59a14f",
    "scx_cake": "#edc948",
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


def load_meta_file(path: Path | None) -> dict[str, str]:
    if path is None or not path.exists():
        return {}
    return parse_env_file(path)


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
            "display_scheduler": scheduler,
            "runs": len(items),
            "status": ", ".join(sorted({item.get("COMPARE_STATUS", "unknown") for item in items})),
            "current_scheduler": items[-1].get("CURRENT_SCHEDULER", ""),
            "sched_ext_state": items[-1].get("SCHED_EXT_STATE", ""),
            "kernel_release": items[-1].get("KERNEL_RELEASE", ""),
            "fish_count": items[-1].get("AQUARIUM_FISH_COUNT", ""),
            "notes": "; ".join(note for note in {item.get("COMPARE_NOTE", "") for item in items} if note),
            "log_paths": "; ".join(item.get("LOG_PATH", "") for item in items if item.get("LOG_PATH")),
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
        aggregated.append(entry)

    ordered = {
        name: index
        for index, name in enumerate(["baseline", "scx_cosmos", "scx_bpfland", "scx_cake", "scx_flow"])
    }
    aggregated.sort(key=lambda item: ordered.get(str(item["scheduler"]), 999))
    return aggregated


def summarize_run_counts(aggregated: list[dict[str, object]], meta: dict[str, str]) -> str:
    run_counts = sorted({int(entry["runs"]) for entry in aggregated if entry.get("runs") is not None})
    warmup_runs = 0
    try:
        warmup_runs = int(meta.get("WARMUP_RUNS", "0") or "0")
    except ValueError:
        warmup_runs = 0
    if not run_counts:
        return "Run count unavailable"
    if len(run_counts) == 1:
        run_label = "run" if run_counts[0] == 1 else "runs"
        summary = f"Averages over {run_counts[0]} {run_label} per scheduler."
        if warmup_runs > 0:
            warmup_label = "warmup run" if warmup_runs == 1 else "warmup runs"
            summary += f" Each scheduler had {warmup_runs} uncounted {warmup_label} first."
        return summary
    return "Runs per scheduler vary; see labels and report table."


def sort_metric_entries(
    aggregated: list[dict[str, object]], metric_key: str, direction: str
) -> list[dict[str, object]]:
    present = [entry for entry in aggregated if entry.get(metric_key) is not None]
    missing = [entry for entry in aggregated if entry.get(metric_key) is None]
    reverse = direction == "higher"
    present.sort(key=lambda entry: float(entry[metric_key]), reverse=reverse)
    return present + missing


def write_csv(out_dir: Path, aggregated: list[dict[str, object]]) -> Path:
    csv_path = out_dir / "aquarium_benchmarker_summary.csv"
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
                "fish_count",
                "aquarium_raf_avg_fps",
                "aquarium_raf_1p_low_fps",
                "aquarium_p95_frame_ms",
                "aquarium_jank_over_33ms",
                "stressng_bogo_ops_per_sec",
                "notes",
                "log_paths",
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
                    entry["fish_count"],
                    "" if entry["AQUARIUM_RAF_AVG_FPS"] is None else f"{entry['AQUARIUM_RAF_AVG_FPS']:.2f}",
                    "" if entry["AQUARIUM_RAF_1P_LOW_FPS"] is None else f"{entry['AQUARIUM_RAF_1P_LOW_FPS']:.2f}",
                    "" if entry["AQUARIUM_P95_FRAME_MS"] is None else f"{entry['AQUARIUM_P95_FRAME_MS']:.2f}",
                    "" if entry["AQUARIUM_JANK_OVER_33MS"] is None else f"{entry['AQUARIUM_JANK_OVER_33MS']:.2f}",
                    "" if entry["STRESSNG_BOGO_OPS_PER_SEC"] is None else f"{entry['STRESSNG_BOGO_OPS_PER_SEC']:.2f}",
                    entry["notes"],
                    entry["log_paths"],
                ]
            )
    return csv_path


def render_chart(out_dir: Path, aggregated: list[dict[str, object]], meta: dict[str, str]) -> tuple[Path, Path]:
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
            label = "n/a" if value is None else f"{float(value):.2f}"
            ax.text(
                bar.get_width() + annotation_pad,
                bar.get_y() + bar.get_height() / 2,
                f"{label}",
                va="center",
            )

    run_count_summary = summarize_run_counts(aggregated, meta)
    fish_counts = sorted({str(entry.get("fish_count", "")).strip() for entry in aggregated if str(entry.get("fish_count", "")).strip()})
    fish_summary = f" Fish count: {', '.join(fish_counts)}." if fish_counts else ""
    fig.suptitle("scx_flow Aquarium Benchmarker Comparison", fontsize=14, fontweight="bold")
    fig.text(
        0.5,
        0.955,
        f"{run_count_summary}{fish_summary} Charts are auto-sorted from best to worst.",
        ha="center",
        va="top",
        fontsize=10,
    )
    fig.tight_layout(rect=(0, 0, 1, 0.94))

    png_path = out_dir / "aquarium_benchmarker_comparison.png"
    svg_path = out_dir / "aquarium_benchmarker_comparison.svg"
    fig.savefig(png_path, dpi=160)
    fig.savefig(svg_path)
    plt.close(fig)
    return png_path, svg_path


def write_report(out_dir: Path, aggregated: list[dict[str, object]], meta: dict[str, str]) -> Path:
    report_path = out_dir / "aquarium_benchmarker_report.md"
    run_count_summary = summarize_run_counts(aggregated, meta)
    fish_counts = sorted({str(entry.get("fish_count", "")).strip() for entry in aggregated if str(entry.get("fish_count", "")).strip()})
    lines = [
        "# Aquarium Benchmarker Report",
        "",
        "This report aggregates the latest Aquarium comparison run across the selected schedulers.",
        "",
        f"Run count summary: {run_count_summary}",
    ]
    if fish_counts:
        lines.append(f"Fish count(s): {', '.join(fish_counts)}")
    lines.extend(
        [
            "",
            "| Scheduler | Runs | Status | sched_ext state | Current scheduler | Avg FPS | 1% low FPS | p95 frame ms | Jank >33ms | Stress-ng bogo ops/s |",
            "| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |",
        ]
    )
    for entry in aggregated:
        lines.append(
            "| {scheduler} | {runs} | {status} | {sched_ext_state} | {current_scheduler} | {avg_fps} | {low_fps} | {p95_ms} | {jank} | {stressng} |".format(
                scheduler=entry["display_scheduler"],
                runs=entry["runs"],
                status=entry["status"],
                sched_ext_state=entry["sched_ext_state"] or "unknown",
                current_scheduler=entry["current_scheduler"] or "none",
                avg_fps="n/a" if entry["AQUARIUM_RAF_AVG_FPS"] is None else f"{entry['AQUARIUM_RAF_AVG_FPS']:.2f}",
                low_fps="n/a" if entry["AQUARIUM_RAF_1P_LOW_FPS"] is None else f"{entry['AQUARIUM_RAF_1P_LOW_FPS']:.2f}",
                p95_ms="n/a" if entry["AQUARIUM_P95_FRAME_MS"] is None else f"{entry['AQUARIUM_P95_FRAME_MS']:.2f}",
                jank="n/a" if entry["AQUARIUM_JANK_OVER_33MS"] is None else f"{entry['AQUARIUM_JANK_OVER_33MS']:.2f}",
                stressng="n/a" if entry["STRESSNG_BOGO_OPS_PER_SEC"] is None else f"{entry['STRESSNG_BOGO_OPS_PER_SEC']:.2f}",
            )
        )

    lines.extend(
        [
            "",
            "## Notes",
            "",
            "- Higher is better for Aquarium FPS and 1% low FPS.",
            "- Lower is better for frame time and jank counts.",
            "- Stress-ng bogo ops/s is a rough background throughput sanity check.",
            "- Review the raw log paths from `aquarium_benchmarker_summary.csv` when a row shows `failed` or `skipped`.",
        ]
    )
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return report_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--summaries-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--meta-file", type=Path)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    rows = load_rows(args.summaries_dir)
    aggregated = aggregate(rows)
    meta = load_meta_file(args.meta_file)
    write_csv(args.output_dir, aggregated)
    render_chart(args.output_dir, aggregated, meta)
    write_report(args.output_dir, aggregated, meta)


if __name__ == "__main__":
    main()
