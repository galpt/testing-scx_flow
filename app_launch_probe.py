#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
"""Run an app-launch latency probe and emit env-style summary fields."""

from __future__ import annotations

import argparse
import json
import multiprocessing as mp
import os
import subprocess
import time
from pathlib import Path


def percentile(sorted_values: list[int], pct: float) -> int:
    if not sorted_values:
        return 0
    rank = max(1, (len(sorted_values) * int(pct * 100) + 99) // 100)
    return sorted_values[min(rank - 1, len(sorted_values) - 1)]


def worker(cpu: int, duration_ns: int, late_threshold_ns: int, command: list[str], queue: mp.Queue) -> None:
    os.sched_setaffinity(0, {cpu})
    lat_us_values: list[int] = []
    over_threshold_count = 0
    failures = 0
    end_ns = time.monotonic_ns() + duration_ns

    while time.monotonic_ns() < end_ns:
        start_ns = time.monotonic_ns()
        try:
            subprocess.run(
                command,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except subprocess.CalledProcessError:
            failures += 1
            continue
        elapsed_ns = time.monotonic_ns() - start_ns
        lat_us = elapsed_ns // 1_000
        lat_us_values.append(lat_us)
        if elapsed_ns > late_threshold_ns:
            over_threshold_count += 1

    queue.put(
        {
            "cpu": cpu,
            "samples": len(lat_us_values),
            "failures": failures,
            "over_threshold_count": over_threshold_count,
            "lat_us": lat_us_values,
        }
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duration-seconds", type=float, default=20.0)
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--late-threshold-us", type=int, default=5_000)
    parser.add_argument("--cpus", default="")
    parser.add_argument("--output-json", type=Path)
    parser.add_argument(
        "--command",
        nargs="+",
        default=["/usr/bin/true"],
        help="Command to launch repeatedly (default: /usr/bin/true)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    online_cpus = sorted(os.sched_getaffinity(0))
    if not online_cpus:
        raise SystemExit("No online CPUs available for app-launch probe")

    if args.cpus:
        cpus = [int(part) for part in args.cpus.split(",") if part.strip()]
    else:
        cpus = online_cpus[: max(1, min(args.workers, len(online_cpus)))]

    if not cpus:
        raise SystemExit("No CPUs selected for app-launch probe")

    workers = min(args.workers, len(cpus))
    cpus = cpus[:workers]
    duration_ns = int(args.duration_seconds * 1_000_000_000)
    late_threshold_ns = args.late_threshold_us * 1_000

    ctx = mp.get_context("fork")
    queue: mp.Queue = ctx.Queue()
    processes = [
        ctx.Process(target=worker, args=(cpu, duration_ns, late_threshold_ns, args.command, queue))
        for cpu in cpus
    ]

    for process in processes:
        process.start()

    results = [queue.get() for _ in processes]

    exit_code = 0
    for process in processes:
        process.join()
        if process.exitcode not in (0, None):
            exit_code = process.exitcode

    if exit_code != 0:
        raise SystemExit(f"app-launch probe worker exited non-zero: {exit_code}")

    all_lat_us = sorted(value for result in results for value in result["lat_us"])
    samples = len(all_lat_us)
    failures = sum(int(result["failures"]) for result in results)
    over_threshold_count = sum(int(result["over_threshold_count"]) for result in results)
    mean_lat_us = (sum(all_lat_us) / samples) if samples else 0.0

    payload = {
        "APP_LAUNCH_DURATION_SECONDS": f"{args.duration_seconds:.3f}",
        "APP_LAUNCH_WORKERS": str(workers),
        "APP_LAUNCH_CPUS": ",".join(str(cpu) for cpu in cpus),
        "APP_LAUNCH_COMMAND": " ".join(args.command),
        "APP_LAUNCH_SAMPLES": str(samples),
        "APP_LAUNCH_FAILURES": str(failures),
        "APP_LAUNCH_MEAN_US": f"{mean_lat_us:.2f}",
        "APP_LAUNCH_P95_US": str(percentile(all_lat_us, 0.95)),
        "APP_LAUNCH_P99_US": str(percentile(all_lat_us, 0.99)),
        "APP_LAUNCH_MAX_US": str(all_lat_us[-1] if all_lat_us else 0),
        "APP_LAUNCH_LATE_THRESHOLD_US": str(args.late_threshold_us),
        "APP_LAUNCH_OVER_THRESHOLD_COUNT": str(over_threshold_count),
        "APP_LAUNCH_OVER_THRESHOLD_RATIO_PCT": f"{(over_threshold_count * 100.0 / samples) if samples else 0.0:.4f}",
    }

    if args.output_json:
        args.output_json.write_text(
            json.dumps({"summary": payload, "workers": results}, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    for key, value in payload.items():
        print(f"{key}={value}")


if __name__ == "__main__":
    main()
