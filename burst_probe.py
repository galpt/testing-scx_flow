#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
"""Run a periodic wake probe and measure latency specifically during burst windows."""

from __future__ import annotations

import argparse
import ctypes
import json
import multiprocessing as mp
import os
import queue
import sys
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


def summarize(values: list[int], late_threshold_ns: int, period_ns: int) -> dict[str, float | int]:
    sorted_values = sorted(values)
    samples = len(sorted_values)
    late_threshold_us = late_threshold_ns // 1_000
    late_over_threshold = sum(1 for value in sorted_values if value > late_threshold_us)
    miss_count = sum(1 for value in sorted_values if value > period_ns // 1_000)
    mean_late_us = (sum(sorted_values) / samples) if samples else 0.0
    return {
        "samples": samples,
        "mean_late_us": mean_late_us,
        "p95_late_us": percentile(sorted_values, 0.95),
        "p99_late_us": percentile(sorted_values, 0.99),
        "max_late_us": sorted_values[-1] if sorted_values else 0,
        "late_over_threshold_count": late_over_threshold,
        "late_over_threshold_ratio_pct": (late_over_threshold * 100.0 / samples) if samples else 0.0,
        "miss_count": miss_count,
        "miss_ratio_pct": (miss_count * 100.0 / samples) if samples else 0.0,
        "miss_ratio_resolution_pct": (100.0 / samples) if samples else 0.0,
    }


def worker(
    cpu: int,
    duration_ns: int,
    period_ns: int,
    burst_active: mp.synchronize.Event,
    queue: mp.Queue,
) -> None:
    os.sched_setaffinity(0, {cpu})
    start_ns = time.monotonic_ns()
    deadline_ns = start_ns + period_ns
    end_ns = start_ns + duration_ns
    all_lateness_us: list[int] = []
    burst_lateness_us: list[int] = []
    idle_lateness_us: list[int] = []

    while deadline_ns <= end_ns:
        clock_nanosleep_abs(deadline_ns)
        now_ns = time.monotonic_ns()
        late_us = max(0, now_ns - deadline_ns) // 1_000
        all_lateness_us.append(late_us)
        if burst_active.is_set():
            burst_lateness_us.append(late_us)
        else:
            idle_lateness_us.append(late_us)
        deadline_ns += period_ns

    queue.put(
        {
            "cpu": cpu,
            "all_lateness_us": all_lateness_us,
            "burst_lateness_us": burst_lateness_us,
            "idle_lateness_us": idle_lateness_us,
        }
    )


def burner(
    cpu: int,
    stop_event: mp.synchronize.Event,
    burst_active: mp.synchronize.Event,
) -> None:
    os.sched_setaffinity(0, {cpu})
    x = 0
    while not stop_event.is_set():
        if not burst_active.wait(0.01):
            continue
        while burst_active.is_set() and not stop_event.is_set():
            x += 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duration-seconds", type=float, default=20.0)
    parser.add_argument("--period-us", type=int, default=1_000)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--cpus", default="")
    parser.add_argument("--burner-cpus", default="")
    parser.add_argument("--settle-seconds", type=float, default=2.0)
    parser.add_argument("--burst-interval-ms", type=int, default=1_000)
    parser.add_argument("--burst-duration-ms", type=int, default=200)
    parser.add_argument("--late-threshold-us", type=int, default=1_000)
    parser.add_argument("--output-json", type=Path)
    return parser.parse_args()


def parse_cpu_list(raw: str, fallback: list[int]) -> list[int]:
    if not raw:
        return fallback
    cpus = [int(part) for part in raw.split(",") if part.strip()]
    return cpus or fallback


def main() -> None:
    args = parse_args()
    online_cpus = sorted(os.sched_getaffinity(0))
    if not online_cpus:
        raise SystemExit("No online CPUs available for burst probe")

    default_workers = online_cpus[: max(1, min(args.workers, len(online_cpus)))]
    worker_cpus = parse_cpu_list(args.cpus, default_workers)
    worker_cpus = worker_cpus[: max(1, min(args.workers, len(worker_cpus)))]
    burner_cpus = parse_cpu_list(args.burner_cpus, worker_cpus)

    duration_ns = int(args.duration_seconds * 1_000_000_000)
    period_ns = args.period_us * 1_000
    late_threshold_ns = args.late_threshold_us * 1_000
    settle_ns = int(args.settle_seconds * 1_000_000_000)
    burst_interval_ns = args.burst_interval_ms * 1_000_000
    burst_duration_ns = args.burst_duration_ms * 1_000_000

    queue: mp.Queue = mp.Queue()
    burst_active = mp.Event()
    stop_event = mp.Event()

    workers = [
        mp.Process(target=worker, args=(cpu, duration_ns, period_ns, burst_active, queue))
        for cpu in worker_cpus
    ]
    burners = [
        mp.Process(target=burner, args=(cpu, stop_event, burst_active))
        for cpu in burner_cpus
    ]

    for process in workers + burners:
        process.start()

    start_ns = time.monotonic_ns()
    end_ns = start_ns + duration_ns
    next_burst_start_ns = start_ns + settle_ns
    burst_windows: list[dict[str, int]] = []

    while next_burst_start_ns < end_ns:
        clock_nanosleep_abs(next_burst_start_ns)
        burst_end_ns = min(next_burst_start_ns + burst_duration_ns, end_ns)
        burst_active.set()
        burst_windows.append({"start_ns": next_burst_start_ns, "end_ns": burst_end_ns})
        clock_nanosleep_abs(burst_end_ns)
        burst_active.clear()
        next_burst_start_ns += burst_interval_ns

    stop_event.set()
    burst_active.clear()

    results = []
    get_timeout = args.duration_seconds + 30.0
    for p in workers:
        try:
            results.append(queue.get(timeout=get_timeout))
        except queue.Empty:
            print(f"ERROR: worker pid={p.pid} did not produce results within {get_timeout:.0f}s",
                  file=sys.stderr)
            for q in workers + burners:
                q.kill()
            sys.exit(1)

    exit_code = 0
    for process in workers + burners:
        process.join()
        if process.exitcode not in (0, None):
            exit_code = process.exitcode

    if exit_code != 0:
        raise SystemExit(f"burst probe worker exited non-zero: {exit_code}")

    all_lateness = sorted(late for result in results for late in result["all_lateness_us"])
    burst_lateness = sorted(late for result in results for late in result["burst_lateness_us"])
    idle_lateness = sorted(late for result in results for late in result["idle_lateness_us"])

    overall_summary = summarize(all_lateness, late_threshold_ns, period_ns)
    burst_summary = summarize(burst_lateness, late_threshold_ns, period_ns)
    idle_summary = summarize(idle_lateness, late_threshold_ns, period_ns)

    payload = {
        "BURST_DURATION_SECONDS": f"{args.duration_seconds:.3f}",
        "BURST_PERIOD_US": str(args.period_us),
        "BURST_WORKERS": str(len(worker_cpus)),
        "BURST_CPUS": ",".join(str(cpu) for cpu in worker_cpus),
        "BURST_BURNER_CPUS": ",".join(str(cpu) for cpu in burner_cpus),
        "BURST_SETTLE_SECONDS": f"{args.settle_seconds:.3f}",
        "BURST_INTERVAL_MS": str(args.burst_interval_ms),
        "BURST_WINDOW_MS": str(args.burst_duration_ms),
        "BURST_WINDOW_COUNT": str(len(burst_windows)),
        "BURST_LATE_THRESHOLD_US": str(args.late_threshold_us),
        "BURST_TOTAL_SAMPLES": str(int(overall_summary["samples"])),
        "BURST_ACTIVE_SAMPLES": str(int(burst_summary["samples"])),
        "BURST_IDLE_SAMPLES": str(int(idle_summary["samples"])),
        "OVERALL_LATENCY_P95_US": str(int(overall_summary["p95_late_us"])),
        "OVERALL_LATENCY_P99_US": str(int(overall_summary["p99_late_us"])),
        "OVERALL_LATENCY_MAX_US": str(int(overall_summary["max_late_us"])),
        "BURST_LATENCY_P95_US": str(int(burst_summary["p95_late_us"])),
        "BURST_LATENCY_P99_US": str(int(burst_summary["p99_late_us"])),
        "BURST_LATENCY_MAX_US": str(int(burst_summary["max_late_us"])),
        "BURST_MEAN_LATE_US": f"{burst_summary['mean_late_us']:.2f}",
        "BURST_MISS_COUNT": str(int(burst_summary["miss_count"])),
        "BURST_MISS_RATIO_PCT": f"{burst_summary['miss_ratio_pct']:.4f}",
        "BURST_MISS_RATIO_RESOLUTION_PCT": f"{burst_summary['miss_ratio_resolution_pct']:.4f}",
        "BURST_LATE_OVER_THRESHOLD_COUNT": str(int(burst_summary["late_over_threshold_count"])),
        "BURST_LATE_OVER_THRESHOLD_RATIO_PCT": f"{burst_summary['late_over_threshold_ratio_pct']:.4f}",
        "IDLE_LATENCY_P95_US": str(int(idle_summary["p95_late_us"])),
        "IDLE_LATENCY_P99_US": str(int(idle_summary["p99_late_us"])),
        "IDLE_LATENCY_MAX_US": str(int(idle_summary["max_late_us"])),
    }

    if args.output_json:
        args.output_json.write_text(
            json.dumps(
                {
                    "summary": payload,
                    "workers": results,
                    "burst_windows": burst_windows,
                },
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )

    for key, value in payload.items():
        print(f"{key}={value}")


if __name__ == "__main__":
    main()
