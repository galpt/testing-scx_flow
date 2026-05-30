# Mini Benchmarker Report

This report aggregates the latest comparison run across the selected schedulers.

Run count summary: Averages over 1 run per scheduler.

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Max latency (us) | Spikes >100us | Hackbench mean (s) | Sysbench events/s | Stress-ng bogo ops/s |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| baseline (7.0.10-2-cachyos) | 1 | completed | disabled | none | 1001.00 | 524.00 | 0.689 | n/a | 6709.08 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.1_x86_64_unknown_linux_gnu | 4833.00 | 1324.00 | 0.922 | n/a | 6583.78 |
| scx_bpfland | 1 | completed | enabled | bpfland_1.1.1_x86_64_unknown_linux_gnu | 3465.00 | 707.00 | 0.987 | n/a | 6618.47 |
| scx_flow | 1 | completed | enabled | scx_flow_2.3.0_x86_64_unknown_linux_gnu | 79.00 | 0.00 | 0.631 | n/a | 6627.90 |

## Notes

- Lower is better for latency and hackbench time.
- Higher is better for sysbench events/s and stress-ng bogo ops/s.
- Review the raw log paths from `mini_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
