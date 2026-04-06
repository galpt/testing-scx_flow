# Longrun Benchmarker Report

This report aggregates sustained periodic latency probe runs under continuous background load.

Run count summary: Averages over 1 run per scheduler.
Target rate: 1000.00 Hz
Soft lateness threshold: 500us

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Miss ratio (%) | Late > threshold (%) | p95 late (us) | p99 late (us) | Max late (us) |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 1.7196 | 18.6771 | 994.00 | 1002.00 | 43101.00 |
| scx_flow | 1 | completed | enabled | scx_flow_2.0.3_x86_64_unknown_linux_gnu | 1.4363 | 4.6363 | 304.00 | 1828.00 | 14821.00 |
| scx_pandemonium | 1 | completed | enabled | pandemonium | 22.6108 | 23.8600 | 20316.00 | 30582.00 | 192810.00 |

## Notes

- Lower is better for miss ratio and all lateness metrics.
- Long-run mode keeps the background CPU load active for the full probe duration.
- Review the raw log and JSON paths from `longrun_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
