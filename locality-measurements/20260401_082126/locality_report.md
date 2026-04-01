# scx_flow Locality Measurement

Generated: Wed Apr  1 08:21:47 AM WIB 2026

This run is intended to answer one narrow question before changing scheduler
policy: does the current workload show enough migration and cross-LLC movement
to justify locality-aware CPU preference as the next step?

## Inputs

- scheduler: scx_flow
- duration: 20s
- sampling interval: 20ms
- stress-ng workers: 4 @ 80%

## Key Signals

| Metric | Value |
| --- | ---: |
| cyclictest thread samples | 12498 |
| cyclictest threads observed | 17 |
| total CPU changes | 609 |
| total LLC changes | 0 |
| system LLC domains observed | 1 |
| CPU changes / 1000 samples | 48.73 |
| LLC changes / 1000 samples | 0.00 |
| LLC changes / CPU changes | 0.00 |
| max per-thread CPU changes | 609 |
| max per-thread LLC changes | 0 |
| final autotune mode | latency |
| final autotune generation | 3 |

## Scheduler Monitor Peaks

- reserve_local: 2441
- reserve_global: 461
- shared_wake: 2742
- wake_preempt: 1

## Perf Stat Snapshot

- cycles: 1419290453770
- instructions: 769192643670
- cache references: 34018700971
- cache misses: 9243915806
- cpu migrations: 79582
- context switches: 862616

## How To Read This

- If the system LLC domain count is 1, this machine cannot validate cross-LLC benefits directly.
- If CPU changes are low and LLC changes are also low, locality is probably not the first missing lever.
- If CPU changes are high but LLC changes stay low, the workload is moving but mostly within a shared cache domain.
- If LLC changes rise with CPU changes, locality-aware placement becomes a stronger candidate.
- High cache misses alone do not prove a topology problem; they only tell us locality is still worth examining.

## Artifacts

- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_082126/cpu_topology.csv](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_082126/cpu_topology.csv)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_082126/cyclictest_samples.csv](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_082126/cyclictest_samples.csv)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_082126/cyclictest_thread_locality.csv](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_082126/cyclictest_thread_locality.csv)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_082126/scx_flow_monitor.log](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_082126/scx_flow_monitor.log)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_082126/cyclictest.out](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_082126/cyclictest.out)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_082126/perf_stat.csv](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_082126/perf_stat.csv)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_082126/locality_measurement.log](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_082126/locality_measurement.log)
