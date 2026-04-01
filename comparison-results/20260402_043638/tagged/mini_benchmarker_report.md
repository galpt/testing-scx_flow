# Mini Benchmarker Report

This report aggregates the latest comparison run across the selected schedulers.

Run count summary: Averages over 2 runs per scheduler.

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Max latency (us) | Spikes >100us | Hackbench mean (s) | Sysbench events/s | Stress-ng bogo ops/s |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| scx_cosmos | 2 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 1972.50 | 5059.50 | 0.659 | n/a | 4621.27 |
| scx_bpfland | 2 | completed | enabled | bpfland_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 10156.00 | 3937.50 | 0.919 | n/a | 6233.65 |
| scx_cake | 2 | completed | enabled | cake | 3795.00 | 10884.50 | 6.755 | n/a | 6265.07 |
| scx_flow | 2 | completed | enabled | scx_flow_2.0.0_x86_64_unknown_linux_gnu | 1030.50 | 576.00 | 0.635 | n/a | 6158.56 |

## Notes

- Lower is better for latency and hackbench time.
- Higher is better for sysbench events/s and stress-ng bogo ops/s.
- Review the raw log paths from `mini_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
