# scx_flow v3.0.3 — Hybrid Topology Awareness and Cross-CPU Preemption

> [!NOTE]
> v3.0.3 extends the budget-driven architecture with P-core/E-core
> awareness (heterogeneous CPU topologies) and a cross-CPU preemption
> kick mechanism that bypasses the softirq processing gap for same-CPU
> wakeups.  Net change: **+157 lines** vs v3.0.2.

## Results

| Scheduler | Max latency | Spikes >100μs | Schbench wakeup P99 | Schbench wakeup max | Hackbench mean (s) | Stress-ng bogo ops/s |
|-----------|------------|---------------|---------------------|---------------------|-------------------|---------------------|
| EEVDF (CachyOS tuned) | 1115μs | 371 | 4152μs | 26800μs | 0.678 | 6698 |
| scx_cosmos | 2687μs | 644 | 1938μs | 9003μs | 0.931 | 6636 |
| scx_bpfland | 3183μs | 304 | 3972μs | 25424μs | 0.997 | 6579 |
| **scx_flow v3.0.3** | **351μs** | **26** | **1302μs** | **3048μs** | **0.719** | **6654** |

scx_flow v3.0.3 achieves **351μs max latency** with **26 spikes over 100μs** — best-in-test on both latency metrics by a wide margin (3.2× better max latency than baseline). Hackbench throughput at 0.719s is within 6% of the tuned EEVDF baseline. Schbench wakeup latency P99 at **1302μs** and max at **3048μs** are the lowest among all schedulers — 3.2× better P99 and 8.8× better max than baseline.

> [!NOTE]
> These results reflect one CPU microarchitecture and workload mix.
> Every scheduler in the sched-ext ecosystem targets different trade-offs.
> Take the numbers as a reference, not a ranking; the right choice
> depends on your hardware and what you are running.

### Historical Comparison

| Version | Max latency | Spikes >100μs | Hackbench (s) | Schbench P99 (μs) | Lines of code |
|---------|-------------|---------------|---------------|-------------------|--------------|
| v2.3.0 | 79μs | 0 | 0.860 | 1157 | 3,373 |
| v3.0.0 | 272μs | 16 | 0.799 | — | 1,008 |
| v3.0.1 | 132μs | 9 | 0.797 | — | 1,010 |
| v3.0.2 | 333μs | 44 | 0.838 | 1582 | 1,102 |
| **v3.0.3** | **351μs** | **26** | **0.719** | **1302** | **1,259** |

| Benchmark run | Baseline | cosmos | bpfland | **flow** | flow ver |
|---|---|---|---|---|---|
| [v2.3.0](https://github.com/galpt/testing-scx_flow/tree/benchmark-archives/20260530_scx_flow_v2.3.0/mini/v2.3.0/0_max_latency_spikes) | 1001μs / 524 | 4833μs / 1324 | 3465μs / 707 | **79μs / 0** | v2.3.0 |
| [v3.0.2](https://github.com/galpt/testing-scx_flow/tree/benchmark-archives/20260601_scx_flow_v3.0.0/mini/v3.0.0/0_max_latency_spikes) | 1138μs / 295 | 5980μs / 807 | 3112μs / 959 | **333μs / 44** | **v3.0.2** |
| [v3.0.3](https://github.com/galpt/testing-scx_flow/tree/benchmark-archives/20260601_scx_flow_v3.0.0/mini/v3.0.3) | 1115μs / 371 | 2687μs / 644 | 3183μs / 304 | **351μs / 26** | **v3.0.3** |

## Changes from v3.0.2 to v3.0.3

| Commit | Change | Purpose |
|--------|--------|---------|
| **Step 1** | Cargo.toml version bump, branch scaffold | Foundation for v3.0.3 development |
| **Step 2** | P-core/E-core awareness | `cpu_capacity` map populated from sysfs, `has_hybrid_cpus` detection, select_cpu capacity-biased placement for tasks with positive budget on hybrid topologies |
| **Step 3** | Local DSQ re-check | `scx_bpf_dsq_nr_queued(SCX_DSQ_LOCAL)` re-checks the local DSQ within dispatch, catching wakeups that propagated during the kernel's dispatch call without starving the global DSQ |
| **Step 3** | Cross-CPU preempt kick | `preempt_kick_target` + CAS-based dispatch IPI for same-CPU PREEMPT wakeups. Bypasses the softirq processing gap by having dispatch on ANY OTHER CPU send a real `RESCHEDULE_VECTOR` IPI that triggers immediate `__schedule()` |
| **Step 3** | Audit findings cleanup | Remove dead constants/fields (shared-slice, autotune, kick flags, `prio_dispatches` from `flow_cpu_state`, 4 dead BSS volatiles). Fix `is_pinned_kthread` enqueue using `FLOW_DSQ_LOCAL` for cross-CPU wakeups. Rename `quick_disp=` to `wake_enq=`. Simplify `FLOW_CPUSTAT_INC` macro |

### Cross-CPU Preemption Kick

The key noise immunity feature: `scx_bpf_kick_cpu(self, PREEMPT)` is architecturally a noop — it calls `resched_curr()` which only sets `TIF_NEED_RESCHED`, waiting for the next preemption point (return from softirq/interrupt). The max latency outlier occurs when other softirqs delay the `need_resched` check.

The fix: in enqueue, store the target CPU number in `preempt_kick_target`. In dispatch on ANY OTHER CPU, atomically claim the target via CAS and send `scx_bpf_kick_cpu(target, PREEMPT)` — a real IPI whose handler calls `__schedule()` immediately, preempting whatever the target CPU is doing including softirq processing. Bounds latency to approximately the dispatch interval (~50μs) of the next busy CPU.

The monitor line shows `kick_ipi=2` for this run — 2 cross-CPU preempt IPIs sent.

### P-core/E-core Awareness

On hybrid Intel CPUs (Alder Lake, Raptor Lake), P-cores report capacity ~1024 and E-cores report ~400-600 in sysfs `cpu_capacity`. `select_cpu` now checks `has_hybrid_cpus` and, for tasks with positive budget (latency-sensitive), biases placement toward higher-capacity CPUs. This is a no-op on uniform-core systems (the `has_hybrid_cpus` flag stays 0).

## Architecture (unchanged from v3.0.2)

```
Enqueue:
  SCX_ENQ_WAKEUP  → budget ≥ 50μs → FLOW_DSQ_LOCAL_ON | target_cpu + SCX_ENQ_PREEMPT
                   budget < 50μs → FLOW_DSQ_LOCAL_ON | target_cpu (head-of-queue only)
  !SCX_ENQ_WAKEUP → vtime = FLOW_BUDGET_MAX_NS - max(0, budget_ns)
                     → FLOW_NORMAL_DSQ (vtime-ordered, 50μs slice)

  Non-migratable  → FLOW_PINNED_DSQ_BASE | cpu (per-CPU FIFO, checked first)

Dispatch:
  1. Cross-CPU preempt kick     (if another CPU has a pending same-CPU PREEMPT wakeup)
  2. FLOW_PINNED_DSQ_BASE | cpu  (pinned tasks)
  3. Local DSQ re-check          (scx_bpf_dsq_nr_queued)
  4. FLOW_NORMAL_DSQ             (vtime-ordered, all tasks)
  5. Re-run prev if queued
```

## Benchmark Conditions

| Component | Detail |
|-----------|--------|
| CPU | AMD Ryzen 7 6800H (8C/16T, 3.2 GHz) — uniform cores |
| Memory | 58 GB DDR5 |
| Kernel | `7.0.11-1-cachyos`, PREEMPT_DYNAMIC, sched_ext enabled |
| Platform | CachyOS Linux |
| cyclictest | 30s, 4 threads, CPU 0 affinity, 1500/2000/2500/3000μs intervals |
| hackbench | `-l 1000 -g 10` (process mode, UNIX sockets) |
| schbench | `-m 2 -t 16 -r 30` (2 message threads × 16 workers, 30s) |
| stress-ng | 4 CPU workers @ 80% load, 60s |

## Files

Raw per-scheduler logs and summaries are available alongside this directory:

- `logs/` — cyclictest, hackbench, schbench, stress-ng output per scheduler
- `summaries/` — parsed metric files per scheduler
- `console/` — console output logs

Raw logs for this run are also available in the
[comparison-results archive](https://github.com/galpt/testing-scx_flow/tree/benchmark-archives/20260605_172916).
