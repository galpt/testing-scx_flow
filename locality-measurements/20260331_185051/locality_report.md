# scx_flow Locality Measurement

Generated: Tue Mar 31 06:51:12 PM WIB 2026

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
| cyclictest thread samples | 13132 |
| cyclictest threads observed | 1 |
| total CPU changes | 13130 |
| total LLC changes | 0 |
| CPU changes / 1000 samples | 999.85 |
| LLC changes / 1000 samples | 0.00 |
| LLC changes / CPU changes | 0.00 |
| max per-thread CPU changes | 13130 |
| max per-thread LLC changes | 0 |
| final autotune mode | latency |
| final autotune generation | 3 |

## Scheduler Monitor Peaks

- reserve_local: 751
- reserve_global: 104
- shared_wake: 85
- wake_preempt: 0

## Perf Stat Snapshot

- cycles: 1432796048419
- instructions: 614839267056
- cache references: 23384370298
- cache misses: 5785648178
- cpu migrations: 17168
- context switches: 569656

## How To Read This

- If CPU changes are low and LLC changes are also low, locality is probably not the first missing lever.
- If CPU changes are high but LLC changes stay low, the workload is moving but mostly within a shared cache domain.
- If LLC changes rise with CPU changes, locality-aware placement becomes a stronger candidate.
- High cache misses alone do not prove a topology problem; they only tell us locality is still worth examining.

## Artifacts

- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_185051/cpu_topology.csv](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_185051/cpu_topology.csv)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_185051/cyclictest_samples.csv](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_185051/cyclictest_samples.csv)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_185051/cyclictest_thread_locality.csv](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_185051/cyclictest_thread_locality.csv)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_185051/scx_flow_monitor.log](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_185051/scx_flow_monitor.log)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_185051/cyclictest.out](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_185051/cyclictest.out)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_185051/perf_stat.csv](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_185051/perf_stat.csv)
- [/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_185051/locality_measurement.log](/home/galpt/Desktop/Disk_D/sched-research/testing-scx_flow/locality-measurements/20260331_185051/locality_measurement.log)
