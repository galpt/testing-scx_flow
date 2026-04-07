# Longrun Benchmarker Report

This report aggregates sustained periodic latency probe runs under continuous background load.

Run count summary: Averages over 1 run per scheduler.
Target rate: 1000.00 Hz
Soft lateness threshold: 500us

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Miss ratio (%) | Late > threshold (%) | p95 late (us) | p99 late (us) | Max late (us) |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| baseline (6.19.10-1-cachyos) | 1 | completed | disabled | none | 1.8188 | 3.2788 | 221.00 | 1194.00 | 7454.00 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 11.5075 | 28.2333 | 1005.00 | 1019.00 | 17340.00 |
| scx_flow | 1 | completed | enabled | scx_flow_2.1.0_rc1_x86_64_unknown_linux_gnu | 1.7812 | 6.1558 | 964.00 | 1990.00 | 13419.00 |
| scx_pandemonium | 1 | completed | enabled | pandemonium | 24.3567 | 25.8012 | 19861.00 | 30058.00 | 123825.00 |

## Notes

- Lower is better for miss ratio and all lateness metrics.
- Long-run mode keeps the background CPU load active for the full probe duration.
- Review the raw log and JSON paths from `longrun_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
