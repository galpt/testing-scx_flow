# Mini Benchmarker Report

This report aggregates the latest comparison run across the selected schedulers.

Run count summary: Averages over 1 run per scheduler.

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Max latency (us) | Spikes >100us | Schbench wakeup P99 (us) | Schbench wakeup max (us) | Hackbench mean (s) | Sysbench events/s | Stress-ng bogo ops/s | Schbench RPS |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline (7.0.10-2-cachyos) | 1 | completed | disabled | none | 1138.00 | 295.00 | 4120.00 | 22126.00 | 0.674 | n/a | 6680.68 | 1410.37 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.1_x86_64_unknown_linux_gnu | 5980.00 | 807.00 | 2092.00 | 16003.00 | 0.920 | n/a | 6606.06 | 1220.37 |
| scx_bpfland | 1 | completed | enabled | bpfland_1.1.1_x86_64_unknown_linux_gnu | 3112.00 | 959.00 | 4060.00 | 26793.00 | 1.020 | n/a | 6610.46 | 1125.20 |
| scx_flow | 1 | completed | enabled | scx_flow_3.0.2_x86_64_unknown_linux_gnu | 333.00 | 44.00 | 1582.00 | 2994.00 | 0.838 | n/a | 6620.99 | 1148.90 |

## Notes

- Lower is better for latency, spikes, hackbench time, and schbench wakeup latency.
- Higher is better for sysbench events/s, stress-ng bogo ops/s, and schbench RPS.
- Schbench measures scheduler tail wakeup latency (Facebook/Meta standard metric).
  Lower P99 and max indicate better scheduler responsiveness under load.
- Review the raw log paths from `mini_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
