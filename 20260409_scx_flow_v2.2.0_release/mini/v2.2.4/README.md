# scx_flow v2.2.4 — Mini Benchmark Snapshots

The v2.2.4 release fixes the rt_sensitive_ready predicate regression
introduced in v2.2.3 and restores the latency lane for periodic tasks
by reverting the idle-CPU local-reserved path. See the
[scheduler commit](https://github.com/galpt/scx/commit/d082cce3) for
details.

## Benchmark Modes

| Directory | Mode | Parameters |
| --- | --- | --- |
| [100us_max_latency_spikes/](100us_max_latency_spikes/) | Normal | cyclictest `-D 30 -t 4 -a 0 -m -v` (100us interval) |
| [20us_max_latency_spikes/](20us_max_latency_spikes/) | Hard RT | cyclictest `--priority=99 --smp --interval=200 --histogram=20` |

## Summary

| Mode | Max latency | Spikes | Comparison |
| --- | ---: | ---: | --- |
| Normal (100us) | **142us** | **2 over 100us** | vs v2.2.0 `173us` / `12 spikes` |
| Hard RT (20us) | **339us** | **402 overflows** | vs v2.2.3 `388us` / `610 overflows` |

The normal mode result is an improvement over the v2.2.0 baseline — lower
max latency and fewer spikes. The hard RT result is also an improvement
over v2.2.3, with lower max latency and fewer overflows.

## Machine

- Kernel: `7.0.3-1-cachyos`
- CPU: 16-core AMD
- Power profile: `Balanced`
- Run date: `2026-05-08`
