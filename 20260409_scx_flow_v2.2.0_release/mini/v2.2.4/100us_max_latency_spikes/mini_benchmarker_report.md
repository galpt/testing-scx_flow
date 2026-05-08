# Mini Benchmarker Report

This report aggregates the latest comparison run across the selected schedulers.

Run count summary: Averages over 1 run per scheduler.

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Max latency (us) | Spikes >100us | Hackbench mean (s) | Sysbench events/s | Stress-ng bogo ops/s |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| baseline (7.0.3-1-cachyos) | 1 | completed | disabled | none | 1106.00 | 304.00 | 0.691 | n/a | 6673.91 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 852.00 | 821.00 | 0.649 | n/a | 6596.25 |
| scx_bpfland | 1 | completed | enabled | bpfland_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 2724.00 | 222.00 | 0.962 | n/a | 6611.24 |
| scx_flow | 1 | completed | enabled | scx_flow_2.2.4_x86_64_unknown_linux_gnu | 142.00 | 2.00 | 0.663 | n/a | 6596.78 |

## Notes

- Lower is better for latency and hackbench time.
- Higher is better for sysbench events/s and stress-ng bogo ops/s.
- Review the raw log paths from `mini_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
