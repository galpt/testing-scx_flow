# scx_flow v3.0.0 — 2-Lane Dispatch

> [!NOTE]
> scx_flow is a budget-based sched_ext CPU scheduler in use at
> [v.recipes](https://v.recipes).  v3.0.0 replaces the 5-lane
> classification system (temporal urgency, containment, score-based
> signals) with a minimal 2-lane architecture: a priority wakeup lane
> using `FLOW_DSQ_LOCAL_ON` (atomic local-DSQ insert with immediate
> CPU reschedule) and a budget-based vtime ordered normal lane.  Net
> change: **−2,363 lines of code (−70%) vs v2.3.0**.

## Results

| Scheduler | Max latency | Spikes >100μs | Hackbench mean (s) | Stress-ng bogo ops/s |
|-----------|------------|---------------|-------------------|---------------------|
| EEVDF (CachyOS tuned) | 986μs | 304 | 0.666 | 6683 |
| scx_cosmos | 5101μs | 966 | 0.870 | 6603 |
| scx_bpfland | 2284μs | 580 | 1.014 | 6585 |
| **scx_flow v3.0.0** | **505μs** | **15** | **0.969** | **6583** |

![Latency and throughput comparison across schedulers](mini_benchmarker_comparison.png)

scx_flow v3.0.0 achieves **505μs max latency** with **15 spikes over 100μs** — best-in-test on both metrics.  Throughput is competitive with other SCX schedulers.  The next-best on max latency is the tuned EEVDF baseline at 986μs (304 spikes).  Hackbench throughput falls within the typical range for a vtime-based SCX scheduler.

> [!NOTE]
> These results reflect one CPU microarchitecture and workload mix.
> Every scheduler in the sched-ext ecosystem targets different trade-offs.
> Take the numbers as a reference, not a ranking; the right choice
> depends on your hardware and what you are running.

### Historical Comparison

| Version | Max latency | Spikes >100μs | Lines of code | Change from previous |
|---------|-------------|---------------|---------------|---------------------|
| v2.2.3 | 476μs | 28 | 3,713 | — |
| v2.2.4 | 142μs | 2 | — | −70% max, −93% spikes |
| v2.3.0 | 79μs | 0 | 3,373 | −44% max |
| **v3.0.0** | **505μs** | **15** | **1,010** | **−70% code, 6× simpler** |

| Benchmark run | Baseline | cosmos | bpfland | **flow** | flow ver |
|---|---|---|---|---|---|
| [v2.2.3](https://github.com/galpt/testing-scx_flow/tree/benchmark-archives/20260409_scx_flow_v2.2.0_release/mini/v2.2.3/100us_max_latency_spikes) | 1113μs / 579 | 880μs / 1117 | 3182μs / 846 | **476μs / 28** | v2.2.3 |
| [v2.3.0](https://github.com/galpt/testing-scx_flow/tree/benchmark-archives/20260530_scx_flow_v2.3.0/mini/v2.3.0/0_max_latency_spikes) | 1001μs / 524 | 4833μs / 1324 | 3465μs / 707 | **79μs / 0** | v2.3.0 |
| **v3.0.0 (this run)** | 986μs / 304 | 5101μs / 966 | 2284μs / 580 | **505μs / 15** | **v3.0.0** |

## Why the 2-Lane Design Wins

The old 5-lane system tracked thirteen wake_profile bits across five classification
signals — temporal urgency, latency allowance, containment score, locality score,
IPC confidence — each with its own raise/decay/escape helpers and per-CPU burst
counters.  That is ~1,650 lines of BPF code for the question "which of five lanes
does this task belong to?"

v3.0.0 replaces the entire 5-lane pipeline with two lanes:

| Lane | Mechanism | Trigger |
|------|-----------|---------|
| **Priority (wakeup)** | `FLOW_DSQ_LOCAL_ON \| target_cpu` | `SCX_ENQ_WAKEUP` |
| **Normal** | Budget-based vtime to `FLOW_NORMAL_DSQ` | Re-enqueue (non-wakeup) |

The priority lane uses the kernel's built-in `SCX_DSQ_LOCAL_ON` mechanism —
the same path v2.3.0 used for urgent-latency tasks — but applied to all
wakeup tasks unconditionally.  No urgency signal, no temporal buckets,
no score thresholds.

| Problem with v2.3.0's 5-lane system | How the 2-lane system fixes it |
|--------------------------------------|--------------------------------|
| **Containment traps legitimate threads.** Pipeline threads (game, audio, compositor) that exhaust budget enter containment with 50μs slices, causing multi-second freezes. | **No containment.** Budget-exhausted tasks go to the Normal DSQ with higher vtime (lower priority) but are never frozen.  Forward progress guaranteed. |
| **Score interaction bugs.** 13 wake_profile bits, 3 starvation counters, 4 burst limits — changing one threshold cascades unpredictably. | **2 bits, 0 counters.** Lane choice is binary: wakeup or not.  No starvation counters, no burst limits. |
| **Temporal urgency regresses on back-to-back dispatch.** Pipeline threads that stay runnable across quanta have 1:1 bucket growth → urgency stuck at 0 → trapped in containment. | **No temporal buckets.** Classification uses a single question ("did the task wake up?") answered by the kernel, not a heuristic. |
| **~2,900 lines of BPF and Rust for five lanes.** Every new lane adds enqueue paths, dispatch checks, starvation recovery, and per-CPU state. | **~1,000 lines total.** 541 lines of BPF, 262 of Rust, 103 of stats.  The dispatch function has 3 DSQ checks vs v2.3.0's 9–12. |
| **Containment bandaids compound.** Affinity escape (v2.3.5), dispatch priority fix (v2.3.6), containment count tuning (v2.3.7) — three fixes for one flawed lane. | **Zero bandaids.** The two-lane architecture removed containment, not patched it. |

## Architecture

```
Enqueue:
  SCX_ENQ_WAKEUP  → FLOW_DSQ_LOCAL_ON | target_cpu  (50μs slice, immediate reschedule)
  !SCX_ENQ_WAKEUP → FLOW_NORMAL_DSQ                  (budget-based vtime ordering)

Dispatch:
  1. FLOW_NORMAL_DSQ  (vtime-ordered, any non-wakeup task)
  2. Re-run prev if queued

  (The priority wakeup lane is handled by the kernel automatically —
   SCX_DSQ_LOCAL_ON inserts directly to the target CPU's local DSQ with
   an atomic reschedule, bypassing flow_dispatch entirely.)
```

### Budget-Based vtime

The Normal DSQ uses a novel vtime formula derived entirely from the task's
remaining budget, avoiding the unbounded-growth problem of flat runtime
accumulation:

```
vtime = FLOW_BUDGET_MAX_NS - max(0, budget_ns)
```

| Condition | budget_ns | vtime | Priority |
|-----------|-----------|-------|----------|
| Task just woke up (budget refilled) | +500μs | **1.5ms** | Highest |
| Task ran briefly | +100μs | **1.9ms** | Medium |
| Task exhausted budget | −500μs | **2.0ms** | Lowest |

Sleep refills budget → vtime drops → task is dispatched sooner relative
to CPU hogs.  Budget is bounded to [−BUDGET_MAX, BUDGET_MAX], so vtime
never grows unbounded — a task that sleeps once an hour doesn't accumulate
infinite vtime.

### Kernel ABI Constants

All kernel ABI constants are defined directly in `intf.h` to bypass the
BTF-dependent weak-volatile compat layer that defaults to 0 on some
kernels:

| Constant | Value | Purpose |
|----------|-------|---------|
| `FLOW_DSQ_LOCAL` | `0x8000000000000002` | Per-CPU local DSQ |
| `FLOW_DSQ_LOCAL_ON` | `0xC000000000000000` | Local DSQ + atomic reschedule |
| `FLOW_ENQ_WAKEUP` | `0x0000000000000001` | Enqueue wakeup flag |
| `FLOW_ENQ_HEAD` | `0x0000000000010000` | Insert at DSQ head |
| `FLOW_ENQ_PREEMPT` | `0x0000000100000000` | Preemption flag on insert |
| `FLOW_KICK_IDLE` | `0x0000000000000001` | Kick idle CPU |
| `FLOW_KICK_PREEMPT` | `0x0000000000000002` | Kick busy CPU (IPI) |

### Code Reduction

```
File            v2.3.0    v3.0.0       Δ
main.bpf.c      1,614      541    −1,073
intf.h            166       77       −89
main.rs         1,043      262      −781
stats.rs          523      103      −420
Cargo.toml         27       27         0
Total            3,373    1,010    −2,363 (−70%)
```

### What Was Removed

- Containment lane (CONTAINED_DSQ, containment_score, 10+ starvation counters)
- Temporal urgency (3 decaying buckets, urgency ratio, recompute_wake_profile)
- Score-based classification (latency_allowance, locality_score, ipc_confidence)
- Autotuner (AutoTuneMode, RuntimeTunables, write_runtime_tunables)
- 40+ volatile counters (starvation rounds, burst counters, rescue dispatches)
- 13 wake_profile bits (URGENT_LATENCY, LATENCY_LANE, RESERVED_PRIORITY, etc.)
- 12 internal tuning parameters (contained_starvation_max, urgent_burst_max, etc.)

## Benchmark Conditions

| Component | Detail |
|-----------|--------|
| CPU | AMD Ryzen 7 6800H (8C/16T, 3.2 GHz) |
| Memory | 58 GB DDR5 |
| Kernel | `7.0.10-2-cachyos`, PREEMPT_DYNAMIC, sched_ext enabled |
| Platform | CachyOS Linux |
| cyclictest | 30s, 4 threads, CPU 0 affinity, 1000μs interval |
| hackbench | 5 runs via `perf bench sched messaging` |
| stress-ng | 4 CPU workers @ 80% load, 60s |

## Files

### Charts and reports

- [mini_benchmarker_report.md](./mini_benchmarker_report.md) — per-scheduler report
- [mini_benchmarker_summary.csv](./mini_benchmarker_summary.csv) — raw metrics
- [mini_benchmarker_comparison.png](./mini_benchmarker_comparison.png) — bar chart
- [mini_benchmarker_comparison.svg](./mini_benchmarker_comparison.svg) — vector chart

### Raw per-scheduler logs

| Scheduler | Console log | Benchmark log | Summary |
|-----------|-------------|---------------|---------|
| EEVDF (baseline) | — | [logs/baseline_run1.log](./logs/baseline_run1.log) | [summaries/baseline_run1.env](./summaries/baseline_run1.env) |
| scx_cosmos | [console/scx_cosmos_scx_cosmos_run01.log](./console/scx_cosmos_scx_cosmos_run01.log) | [logs/scx_cosmos_run1.log](./logs/scx_cosmos_run1.log) | [summaries/scx_cosmos_run1.env](./summaries/scx_cosmos_run1.env) |
| scx_bpfland | [console/scx_bpfland_scx_bpfland_run01.log](./console/scx_bpfland_scx_bpfland_run01.log) | [logs/scx_bpfland_run1.log](./logs/scx_bpfland_run1.log) | [summaries/scx_bpfland_run1.env](./summaries/scx_bpfland_run1.env) |
| scx_flow | [console/scx_flow_scx_flow_run01.log](./console/scx_flow_scx_flow_run01.log) | [logs/scx_flow_run1.log](./logs/scx_flow_run1.log) | [summaries/scx_flow_run1.env](./summaries/scx_flow_run1.env) |

Console logs capture each scheduler's own stdout/stderr during the run.
Benchmark logs capture the full `benchmark.sh` output (cyclictest, hackbench,
stress-ng).  Summary env files contain the machine-readable metrics parsed
from the raw output.
