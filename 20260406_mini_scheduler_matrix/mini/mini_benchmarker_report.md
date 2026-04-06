# Mini Benchmarker Report

This report aggregates the latest comparison run across the selected schedulers.

Run count summary: Averages over 1 run per scheduler.

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Max latency (us) | Spikes >100us | Hackbench mean (s) | Sysbench events/s | Stress-ng bogo ops/s |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| baseline (6.19.10-1-cachyos) | 1 | completed | disabled | none | 1125.00 | 2398.00 | 0.817 | n/a | 6424.46 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 2199.00 | 6193.00 | 0.663 | n/a | 6426.64 |
| scx_cake | 1 | completed | enabled | cake | 9131.00 | 12889.00 | 6.998 | n/a | 6517.95 |
| scx_flow | 1 | completed | enabled | scx_flow_2.0.3_x86_64_unknown_linux_gnu | 460.00 | 12.00 | 0.651 | n/a | 6343.53 |
| scx_pandemonium | 1 | completed | enabled | pandemonium | 25957.00 | 3016.00 | 3.965 | n/a | 6437.74 |

## Notes

- Lower is better for latency and hackbench time.
- Higher is better for sysbench events/s and stress-ng bogo ops/s.
- Review the raw log paths from `mini_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
