# Mini Benchmarker Report

This report aggregates the latest comparison run across the selected schedulers.

Run count summary: Averages over 3 runs per scheduler.

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Max latency (us) | Spikes >100us | Schbench wakeup P99 (us) | Schbench wakeup max (us) | Hackbench mean (s) | Sysbench events/s | Stress-ng bogo ops/s | Schbench RPS |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline (7.0.11-1-cachyos) | 3 | completed | disabled | none | 1132.00 | 288.00 | 4136.00 | 7219.00 | 0.673 | n/a | 6660.34 | 1421.66 |
| scx_cosmos | 3 | completed | enabled | cosmos_1.1.1_x86_64_unknown_linux_gnu | 5946.00 | 624.00 | 2324.00 | 12002.00 | 0.920 | n/a | 6602.63 | 1233.41 |
| scx_bpfland | 3 | completed | enabled | bpfland_1.1.1_x86_64_unknown_linux_gnu | 3017.00 | 461.00 | 4052.00 | 29512.00 | 1.028 | n/a | 6621.96 | 1130.53 |
| scx_flow | 3 | completed | enabled | scx_flow_3.1.0_x86_64_unknown_linux_gnu | 658.00 | 33.00 | 1846.00 | 6996.00 | 1.451 | n/a | 6284.66 | 1132.52 |

## Notes

- Lower is better for latency, spikes, hackbench time, and schbench wakeup latency.
- Higher is better for sysbench events/s, stress-ng bogo ops/s, and schbench RPS.
- Schbench measures scheduler tail wakeup latency (Facebook/Meta standard metric).
  Lower P99 and max indicate better scheduler responsiveness under load.
- Review the raw log paths from `mini_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
