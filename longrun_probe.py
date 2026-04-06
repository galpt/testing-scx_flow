#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
"""Run a sustained periodic wake probe and emit long-run summary env fields."""

from __future__ import annotations

import argparse
import ctypes
import json
import multiprocessing as mp
import os
import time
from pathlib import Path

LIBC = ctypes.CDLL("libc.so.6", use_errno=True)
CLOCK_MONOTONIC = 1
TIMER_ABSTIME = 1


class Timespec(ctypes.Structure):
    _fields_ = [("tv_sec", ctypes.c_long), ("tv_nsec", ctypes.c_long)]


LIBC.clock_nanosleep.argtypes = [
    ctypes.c_int,
    ctypes.c_int,
    ctypes.POINTER(Timespec),
    ctypes.c_void_p,
]
LIBC.clock_nanosleep.restype = ctypes.c_int


def clock_nanosleep_abs(target_ns: int) -> None:
    request = Timespec(target_ns // 1_000_000_000, target_ns % 1_000_000_000)
    while True:
        ret = LIBC.clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, ctypes.byref(request), None)
        if ret == 0:
            return
        if ret == 4:
            continue
        raise OSError(ret, os.strerror(ret))


def percentile(sorted_values: list[int], pct: float) -> int:
    if not sorted_values:
        return 0
    rank = max(1, (len(sorted_values) * int(pct * 100) + 99) // 100)
    return sorted_values[min(rank - 1, len(sorted_values) - 1)]


def worker(cpu: int, duration_ns: int, period_ns: int, late_threshold_ns: int, queue: mp.Queue) -> None:
    os.sched_setaffinity(0, {cpu})
    start_ns = time.monotonic_ns()
    deadline_ns = start_ns + period_ns
    end_ns = start_ns + duration_ns
    lateness_us: list[int] = []
    miss_count = 0
    late_over_threshold_count = 0

    while deadline_ns <= end_ns:
        clock_nanosleep_abs(deadline_ns)
        now_ns = time.monotonic_ns()
        late_ns = max(0, now_ns - deadline_ns)
        late_us = late_ns // 1_000
        lateness_us.append(late_us)
        if late_ns > period_ns:
            miss_count += 1
        if late_ns > late_threshold_ns:
            late_over_threshold_count += 1
        deadline_ns += period_ns

    queue.put(
        {
            "cpu": cpu,
            "samples": len(lateness_us),
            "miss_count": miss_count,
            "late_over_threshold_count": late_over_threshold_count,
            "lateness_us": lateness_us,
        }
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duration-seconds", type=float, default=60.0)
    parser.add_argument("--period-us", type=int, default=1_000)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--cpus", default="")
    parser.add_argument("--late-threshold-us", type=int, default=1_000)
    parser.add_argument("--output-json", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    online_cpus = sorted(os.sched_getaffinity(0))
    if not online_cpus:
        raise SystemExit("No online CPUs available for longrun probe")

    if args.cpus:
        cpus = [int(part) for part in args.cpus.split(",") if part.strip()]
    else:
        cpus = online_cpus[: max(1, min(args.workers, len(online_cpus)))]

    if not cpus:
        raise SystemExit("No CPUs selected for longrun probe")

    workers = min(args.workers, len(cpus))
    cpus = cpus[:workers]
    duration_ns = int(args.duration_seconds * 1_000_000_000)
    period_ns = args.period_us * 1_000
    late_threshold_ns = args.late_threshold_us * 1_000

    queue: mp.Queue = mp.Queue()
    processes = [
        mp.Process(target=worker, args=(cpu, duration_ns, period_ns, late_threshold_ns, queue))
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
        raise SystemExit(f"longrun probe worker exited non-zero: {exit_code}")

    all_lateness = sorted(late_us for result in results for late_us in result["lateness_us"])
    samples = len(all_lateness)
    miss_count = sum(int(result["miss_count"]) for result in results)
    late_over_threshold_count = sum(int(result["late_over_threshold_count"]) for result in results)
    mean_late_us = (sum(all_lateness) / samples) if samples else 0.0

    payload = {
        "LONGRUN_DURATION_SECONDS": f"{args.duration_seconds:.3f}",
        "LONGRUN_PERIOD_US": str(args.period_us),
        "LONGRUN_TARGET_HZ": f"{1_000_000 / args.period_us:.2f}",
        "LONGRUN_WORKERS": str(workers),
        "LONGRUN_CPUS": ",".join(str(cpu) for cpu in cpus),
        "LONGRUN_SAMPLES": str(samples),
        "LONGRUN_MEAN_LATE_US": f"{mean_late_us:.2f}",
        "LONGRUN_P95_LATE_US": str(percentile(all_lateness, 0.95)),
        "LONGRUN_P99_LATE_US": str(percentile(all_lateness, 0.99)),
        "LONGRUN_MAX_LATE_US": str(all_lateness[-1] if all_lateness else 0),
        "LONGRUN_MISS_COUNT": str(miss_count),
        "LONGRUN_MISS_RATIO_PCT": f"{(miss_count * 100.0 / samples) if samples else 0.0:.4f}",
        "LONGRUN_LATE_THRESHOLD_US": str(args.late_threshold_us),
        "LONGRUN_LATE_OVER_THRESHOLD_COUNT": str(late_over_threshold_count),
        "LONGRUN_LATE_OVER_THRESHOLD_RATIO_PCT": f"{(late_over_threshold_count * 100.0 / samples) if samples else 0.0:.4f}",
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
