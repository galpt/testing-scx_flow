# Mini Benchmarker Report

This report aggregates the latest comparison run across the selected schedulers.

Run count summary: Averages over 2 runs per scheduler.

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Max latency (us) | Spikes >100us | Hackbench mean (s) | Sysbench events/s | Stress-ng bogo ops/s |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| scx_cosmos | 2 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 1889.50 | 6210.50 | 0.649 | n/a | 5852.91 |
| scx_flow | 2 | completed | enabled | scx_flow_2.0.1_x86_64_unknown_linux_gnu | 171.00 | 4.00 | 0.630 | n/a | 6190.41 |

## Notes

- Lower is better for latency and hackbench time.
- Higher is better for sysbench events/s and stress-ng bogo ops/s.
- Review the raw log paths from `mini_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
