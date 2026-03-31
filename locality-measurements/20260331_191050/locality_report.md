# scx_flow Locality Measurement

Generated: Tue Mar 31 07:11:11 PM WIB 2026

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
| cyclictest thread samples | 12532 |
| cyclictest threads observed | 17 |
| total CPU changes | 632 |
| total LLC changes | 0 |
| system LLC domains observed | 1 |
| CPU changes / 1000 samples | 50.43 |
| LLC changes / 1000 samples | 0.00 |
| LLC changes / CPU changes | 0.00 |
| max per-thread CPU changes | 632 |
| max per-thread LLC changes | 0 |
| final autotune mode | latency |
| final autotune generation | 3 |

## Scheduler Monitor Peaks

- reserve_local: 3462
- reserve_global: 821
- shared_wake: 2461
- wake_preempt: 0

## Perf Stat Snapshot

- cycles: 1421604187214
- instructions: 792814792738
- cache references: 36915530239
- cache misses: 11039586598
- cpu migrations: 96095
- context switches: 1080591

## How To Read This

- If the system LLC domain count is 1, this machine cannot validate cross-LLC benefits directly.
- If CPU changes are low and LLC changes are also low, locality is probably not the first missing lever.
- If CPU changes are high but LLC changes stay low, the workload is moving but mostly within a shared cache domain.
- If LLC changes rise with CPU changes, locality-aware placement becomes a stronger candidate.
- High cache misses alone do not prove a topology problem; they only tell us locality is still worth examining.

## Artifacts

- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_191050/cpu_topology.csv](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_191050/cpu_topology.csv)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_191050/cyclictest_samples.csv](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_191050/cyclictest_samples.csv)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_191050/cyclictest_thread_locality.csv](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_191050/cyclictest_thread_locality.csv)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_191050/scx_flow_monitor.log](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_191050/scx_flow_monitor.log)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_191050/cyclictest.out](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_191050/cyclictest.out)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_191050/perf_stat.csv](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_191050/perf_stat.csv)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_191050/locality_measurement.log](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_191050/locality_measurement.log)
