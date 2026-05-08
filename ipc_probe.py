#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Galih Tama <galpt@v.recipes>
#
"""Run an IPC ping-pong round-trip probe and emit env-style summary fields."""

from __future__ import annotations

import argparse
import json
import multiprocessing as mp
import os
import queue
import socket
import sys
import time
from pathlib import Path


def percentile(sorted_values: list[int], pct: float) -> int:
    if not sorted_values:
        return 0
    rank = max(1, (len(sorted_values) * int(pct * 100) + 99) // 100)
    return sorted_values[min(rank - 1, len(sorted_values) - 1)]


def recv_exact(sock: socket.socket, size: int) -> bytes:
    chunks: list[bytes] = []
    remaining = size
    while remaining > 0:
        chunk = sock.recv(remaining)
        if not chunk:
            return b""
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def responder(fd: int, close_fd: int, cpu: int, message_bytes: int) -> None:
    os.close(close_fd)
    os.sched_setaffinity(0, {cpu})
    sock = socket.socket(fileno=fd)
    try:
        while True:
            payload = recv_exact(sock, message_bytes)
            if not payload:
                break
            sock.sendall(payload)
    finally:
        sock.close()


def worker_pair(
    requester_cpu: int,
    responder_cpu: int,
    duration_ns: int,
    message_bytes: int,
    late_threshold_ns: int,
    queue: mp.Queue,
) -> None:
    os.sched_setaffinity(0, {requester_cpu})
    left, right = socket.socketpair()
    proc = mp.Process(target=responder, args=(right.fileno(), left.fileno(), responder_cpu, message_bytes))
    proc.start()
    right.close()

    message = b"x" * message_bytes
    rtt_us_values: list[int] = []
    over_threshold_count = 0
    end_ns = time.monotonic_ns() + duration_ns

    try:
        while time.monotonic_ns() < end_ns:
            start_ns = time.monotonic_ns()
            left.sendall(message)
            reply = recv_exact(left, message_bytes)
            if len(reply) != message_bytes:
                raise RuntimeError("short IPC reply")
            end_rtt_ns = time.monotonic_ns()
            rtt_ns = end_rtt_ns - start_ns
            rtt_us = rtt_ns // 1_000
            rtt_us_values.append(rtt_us)
            if rtt_ns > late_threshold_ns:
                over_threshold_count += 1
    finally:
        try:
            left.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        left.close()
        proc.join(timeout=5)
        if proc.is_alive():
            proc.kill()
            proc.join(timeout=1)

    if proc.exitcode not in (0, None):
        raise SystemExit(f"ipc responder exited non-zero: {proc.exitcode}")

    queue.put(
        {
            "requester_cpu": requester_cpu,
            "responder_cpu": responder_cpu,
            "samples": len(rtt_us_values),
            "over_threshold_count": over_threshold_count,
            "rtt_us": rtt_us_values,
        }
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duration-seconds", type=float, default=20.0)
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--message-bytes", type=int, default=64)
    parser.add_argument("--late-threshold-us", type=int, default=500)
    parser.add_argument("--cpus", default="")
    parser.add_argument("--output-json", type=Path)
    return parser.parse_args()


def choose_cpu_pairs(online_cpus: list[int], workers: int) -> list[tuple[int, int]]:
    if len(online_cpus) == 1:
        return [(online_cpus[0], online_cpus[0])]

    pair_count = max(1, min(workers, len(online_cpus) // 2))
    pairs: list[tuple[int, int]] = []
    for index in range(pair_count):
        first = online_cpus[(index * 2) % len(online_cpus)]
        second = online_cpus[(index * 2 + 1) % len(online_cpus)]
        pairs.append((first, second))
    return pairs


def main() -> None:
    try:
        mp.set_start_method("fork")
    except RuntimeError:
        pass

    args = parse_args()
    online_cpus = sorted(os.sched_getaffinity(0))
    if not online_cpus:
        raise SystemExit("No online CPUs available for IPC probe")

    if args.cpus:
        cpu_tokens = [int(part) for part in args.cpus.split(",") if part.strip()]
        if len(cpu_tokens) == 1:
            cpu_pairs = [(cpu_tokens[0], cpu_tokens[0])]
        else:
            cpu_pairs = [
                (cpu_tokens[index], cpu_tokens[min(index + 1, len(cpu_tokens) - 1)])
                for index in range(0, min(len(cpu_tokens), args.workers * 2), 2)
            ]
    else:
        cpu_pairs = choose_cpu_pairs(online_cpus, args.workers)

    duration_ns = int(args.duration_seconds * 1_000_000_000)
    late_threshold_ns = args.late_threshold_us * 1_000

    ctx = mp.get_context("fork")
    queue: mp.Queue = ctx.Queue()
    processes = [
        ctx.Process(
            target=worker_pair,
            args=(requester_cpu, responder_cpu, duration_ns, args.message_bytes, late_threshold_ns, queue),
        )
        for requester_cpu, responder_cpu in cpu_pairs
    ]

    for process in processes:
        process.start()

    results = []
    get_timeout = args.duration_seconds + 30.0
    for p in processes:
        try:
            results.append(queue.get(timeout=get_timeout))
        except queue.Empty:
            print(f"ERROR: worker pid={p.pid} did not produce results within {get_timeout:.0f}s",
                  file=sys.stderr)
            for q in processes:
                q.kill()
            sys.exit(1)

    exit_code = 0
    for process in processes:
        process.join()
        if process.exitcode not in (0, None):
            exit_code = process.exitcode

    if exit_code != 0:
        raise SystemExit(f"ipc probe worker exited non-zero: {exit_code}")

    all_rtt_us = sorted(value for result in results for value in result["rtt_us"])
    samples = len(all_rtt_us)
    over_threshold_count = sum(int(result["over_threshold_count"]) for result in results)
    mean_rtt_us = (sum(all_rtt_us) / samples) if samples else 0.0

    payload = {
        "IPC_DURATION_SECONDS": f"{args.duration_seconds:.3f}",
        "IPC_WORKERS": str(len(cpu_pairs)),
        "IPC_CPUS": ",".join(f"{requester}-{responder}" for requester, responder in cpu_pairs),
        "IPC_MESSAGE_BYTES": str(args.message_bytes),
        "IPC_SAMPLES": str(samples),
        "IPC_MEAN_RTT_US": f"{mean_rtt_us:.2f}",
        "IPC_P95_RTT_US": str(percentile(all_rtt_us, 0.95)),
        "IPC_P99_RTT_US": str(percentile(all_rtt_us, 0.99)),
        "IPC_MAX_RTT_US": str(all_rtt_us[-1] if all_rtt_us else 0),
        "IPC_LATE_THRESHOLD_US": str(args.late_threshold_us),
        "IPC_OVER_THRESHOLD_COUNT": str(over_threshold_count),
        "IPC_OVER_THRESHOLD_RATIO_PCT": f"{(over_threshold_count * 100.0 / samples) if samples else 0.0:.4f}",
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
