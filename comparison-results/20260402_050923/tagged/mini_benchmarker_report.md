# Mini Benchmarker Report

This report aggregates the latest comparison run across the selected schedulers.

Run count summary: Averages over 1 run per scheduler.

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Max latency (us) | Spikes >100us | Hackbench mean (s) | Sysbench events/s | Stress-ng bogo ops/s |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 1949.00 | 8081.00 | 0.658 | n/a | 5234.45 |
| scx_bpfland | 1 | completed | enabled | bpfland_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 7760.00 | 3236.00 | 0.914 | n/a | 6224.91 |
| scx_cake | 1 | completed | enabled | cake | 4222.00 | 4347.00 | 6.790 | n/a | 6290.01 |
| scx_flow | 1 | completed | enabled | scx_flow_2.0.0_x86_64_unknown_linux_gnu | 141.00 | 11.00 | 0.645 | n/a | 6184.62 |

## Notes

- Lower is better for latency and hackbench time.
- Higher is better for sysbench events/s and stress-ng bogo ops/s.
- Review the raw log paths from `mini_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
