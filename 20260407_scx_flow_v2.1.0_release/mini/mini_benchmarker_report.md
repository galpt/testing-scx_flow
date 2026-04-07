# Mini Benchmarker Report

This report aggregates the latest comparison run across the selected schedulers.

Run count summary: Averages over 1 run per scheduler.

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Max latency (us) | Spikes >100us | Hackbench mean (s) | Sysbench events/s | Stress-ng bogo ops/s |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| baseline (6.19.10-1-cachyos) | 1 | completed | disabled | none | 1625.00 | 2437.00 | 0.816 | n/a | 6314.09 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 2778.00 | 10469.00 | 0.681 | n/a | 5470.80 |
| scx_cake | 1 | completed | enabled | cake | 17843.00 | 10567.00 | 6.879 | n/a | 6520.31 |
| scx_flow | 1 | completed | enabled | scx_flow_2.1.0_rc1_x86_64_unknown_linux_gnu | 1358.00 | 21.00 | 0.633 | n/a | 6340.82 |
| scx_pandemonium | 1 | completed | enabled | pandemonium | 145434.00 | 2513.00 | 3.949 | n/a | 6402.61 |

## Notes

- Lower is better for latency and hackbench time.
- Higher is better for sysbench events/s and stress-ng bogo ops/s.
- Review the raw log paths from `mini_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
