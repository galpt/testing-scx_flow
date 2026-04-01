# scx_flow Locality Measurement

Generated: Wed Apr  1 09:05:40 AM WIB 2026

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
| cyclictest thread samples | 12548 |
| cyclictest threads observed | 17 |
| total CPU changes | 606 |
| total LLC changes | 0 |
| system LLC domains observed | 1 |
| CPU changes / 1000 samples | 48.29 |
| LLC changes / 1000 samples | 0.00 |
| LLC changes / CPU changes | 0.00 |
| max per-thread CPU changes | 606 |
| max per-thread LLC changes | 0 |
| final autotune mode | latency |
| final autotune generation | 3 |

## Scheduler Monitor Peaks

- reserve_local: 1611
- reserve_global: 450
- shared_wake: 4448
- wake_preempt: 1

## Perf Stat Snapshot

- cycles: 1416639065553
- instructions: 761850934518
- cache references: 31479039324
- cache misses: 7636175614
- cpu migrations: 65647
- context switches: 787956

## How To Read This

- If the system LLC domain count is 1, this machine cannot validate cross-LLC benefits directly.
- If CPU changes are low and LLC changes are also low, locality is probably not the first missing lever.
- If CPU changes are high but LLC changes stay low, the workload is moving but mostly within a shared cache domain.
- If LLC changes rise with CPU changes, locality-aware placement becomes a stronger candidate.
- High cache misses alone do not prove a topology problem; they only tell us locality is still worth examining.

## Artifacts

- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_090519/cpu_topology.csv](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_090519/cpu_topology.csv)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_090519/cyclictest_samples.csv](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_090519/cyclictest_samples.csv)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_090519/cyclictest_thread_locality.csv](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_090519/cyclictest_thread_locality.csv)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_090519/scx_flow_monitor.log](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_090519/scx_flow_monitor.log)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_090519/cyclictest.out](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_090519/cyclictest.out)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_090519/perf_stat.csv](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_090519/perf_stat.csv)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_090519/locality_measurement.log](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260401_090519/locality_measurement.log)
