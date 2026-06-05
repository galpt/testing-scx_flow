# Mini Benchmarker Report

This report aggregates the latest comparison run across the selected schedulers.

Run count summary: Averages over 1 run per scheduler.

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Max latency (us) | Spikes >100us | Schbench wakeup P99 (us) | Schbench wakeup max (us) | Hackbench mean (s) | Sysbench events/s | Stress-ng bogo ops/s | Schbench RPS |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline (7.0.11-1-cachyos) | 1 | completed | disabled | none | 1115.00 | 371.00 | 4152.00 | 26800.00 | 0.678 | n/a | 6697.63 | 1415.10 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.1_x86_64_unknown_linux_gnu | 2687.00 | 644.00 | 1938.00 | 9003.00 | 0.931 | n/a | 6636.38 | 1226.93 |
| scx_bpfland | 1 | completed | enabled | bpfland_1.1.1_x86_64_unknown_linux_gnu | 3183.00 | 304.00 | 3972.00 | 14316.00 | 0.997 | n/a | 6578.52 | 1107.67 |
| scx_flow | 1 | completed | enabled | scx_flow_3.0.3_x86_64_unknown_linux_gnu | 351.00 | 26.00 | 1302.00 | 3029.00 | 0.719 | n/a | 6653.99 | 1158.67 |

## Notes

- Lower is better for latency, spikes, hackbench time, and schbench wakeup latency.
- Higher is better for sysbench events/s, stress-ng bogo ops/s, and schbench RPS.
- Schbench measures scheduler tail wakeup latency (Facebook/Meta standard metric).
  Lower P99 and max indicate better scheduler responsiveness under load.
- Review the raw log paths from `mini_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
