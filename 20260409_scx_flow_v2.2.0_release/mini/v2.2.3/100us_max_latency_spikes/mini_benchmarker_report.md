# Mini Benchmarker Report

This report aggregates the latest comparison run across the selected schedulers.

Run count summary: Averages over 1 run per scheduler.

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Max latency (us) | Spikes >100us | Hackbench mean (s) | Sysbench events/s | Stress-ng bogo ops/s |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| baseline (7.0.3-1-cachyos) | 1 | completed | disabled | none | 1113.00 | 579.00 | 0.671 | n/a | 6628.57 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 880.00 | 1117.00 | 0.649 | n/a | 6478.71 |
| scx_bpfland | 1 | completed | enabled | bpfland_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 3182.00 | 846.00 | 0.951 | n/a | 6564.79 |
| scx_flow | 1 | completed | enabled | scx_flow_2.2.3_x86_64_unknown_linux_gnu | 476.00 | 28.00 | 0.666 | n/a | 6620.78 |

## Notes

- Lower is better for latency and hackbench time.
- Higher is better for sysbench events/s and stress-ng bogo ops/s.
- Review the raw log paths from `mini_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
