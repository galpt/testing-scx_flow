# Longrun Benchmarker Report

This report aggregates sustained periodic latency probe runs under continuous background load.

Run count summary: Averages over 1 run per scheduler.
Target rate: 1000.00 Hz
Soft lateness threshold: 1000us

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Miss ratio (%) | Late > threshold (%) | p95 late (us) | p99 late (us) | Max late (us) |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 9.1829 | 9.1829 | 2622988.00 | 7381998.00 | 8570999.00 |
| scx_flow | 1 | completed | enabled | scx_flow_2.0.2_x86_64_unknown_linux_gnu | 1.1438 | 1.1438 | 95.00 | 1844.00 | 16882.00 |
| scx_pandemonium | 1 | completed | enabled | pandemonium | 19.9604 | 19.9604 | 17770.00 | 24226.00 | 48635.00 |

## Notes

- Lower is better for miss ratio and all lateness metrics.
- Long-run mode keeps the background CPU load active for the full probe duration.
- Review the raw log and JSON paths from `longrun_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
