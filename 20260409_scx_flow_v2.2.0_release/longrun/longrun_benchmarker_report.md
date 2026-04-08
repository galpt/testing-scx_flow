# Longrun Benchmarker Report

This report aggregates sustained periodic latency probe runs under continuous background load.

Run count summary: Averages over 1 run per scheduler.
Target rate: 1000.00 Hz
Soft lateness threshold: 500us

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Miss ratio (%) | Late > threshold (%) | p95 late (us) | p99 late (us) | Max late (us) |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| baseline (6.19.10-1-cachyos) | 1 | completed | disabled | none | 1.4358 | 2.5579 | 182.00 | 1177.00 | 3250.00 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 1.4446 | 10.5762 | 995.00 | 1004.00 | 16308.00 |
| scx_flow | 1 | completed | enabled | scx_flow_2.2.0_x86_64_unknown_linux_gnu | 0.0071 | 0.0075 | 66.00 | 68.00 | 5999.00 |
| scx_pandemonium | 1 | completed | enabled | pandemonium | 26.3325 | 27.7446 | 23167.00 | 71724.00 | 273818.00 |

## Notes

- Lower is better for miss ratio and all lateness metrics.
- Long-run mode keeps the background CPU load active for the full probe duration.
- Review the raw log and JSON paths from `longrun_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
