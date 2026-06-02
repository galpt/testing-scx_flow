# Mini Benchmarker Report

This report aggregates the latest comparison run across the selected schedulers.

Run count summary: Averages over 1 run per scheduler.

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Max latency (us) | Spikes >100us | Hackbench mean (s) | Sysbench events/s | Stress-ng bogo ops/s |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| baseline (7.0.10-2-cachyos) | 1 | completed | disabled | none | 1255.00 | 297.00 | 0.672 | n/a | 6702.06 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.1_x86_64_unknown_linux_gnu | 4807.00 | 274.00 | 0.922 | n/a | 6566.17 |
| scx_bpfland | 1 | completed | enabled | bpfland_1.1.1_x86_64_unknown_linux_gnu | 2388.00 | 489.00 | 0.993 | n/a | 6609.48 |
| scx_flow | 1 | completed | enabled | scx_flow_3.0.0_x86_64_unknown_linux_gnu | 272.00 | 16.00 | 0.799 | n/a | 6628.39 |

## Notes

- Lower is better for latency and hackbench time.
- Higher is better for sysbench events/s and stress-ng bogo ops/s.
- Review the raw log paths from `mini_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
