# Mini Benchmarker Report

This report aggregates the latest comparison run across the selected schedulers.

Run count summary: Averages over 1 run per scheduler.

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Max latency (us) | Spikes >100us | Hackbench mean (s) | Sysbench events/s | Stress-ng bogo ops/s |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| baseline (6.19.10-1-cachyos) | 1 | completed | disabled | none | 1948.00 | 2129.00 | 0.838 | n/a | 6355.62 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 2015.00 | 4819.00 | 0.704 | n/a | 5313.16 |
| scx_cake | 1 | completed | enabled | cake | 14162.00 | 20921.00 | 6.542 | n/a | 6403.73 |
| scx_flow | 1 | completed | enabled | scx_flow_2.2.0_x86_64_unknown_linux_gnu | 173.00 | 12.00 | 0.713 | n/a | 6316.68 |
| scx_pandemonium | 1 | completed | enabled | pandemonium | 25961.00 | 1998.00 | 1.643 | n/a | 6378.15 |

## Notes

- Lower is better for latency and hackbench time.
- Higher is better for sysbench events/s and stress-ng bogo ops/s.
- Review the raw log paths from `mini_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
