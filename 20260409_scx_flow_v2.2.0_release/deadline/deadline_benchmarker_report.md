# Deadline Benchmarker Report

This report aggregates periodic frame-target deadline probe runs across the selected schedulers.

Run count summary: Averages over 2 runs per scheduler.
Target FPS: 60.00
Soft lateness threshold: 1000us

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Miss ratio (%) | Late > threshold (%) | p95 late (us) | p99 late (us) | Jitter p99 (us) | Max late (us) |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline (6.19.10-1-cachyos) | 2 | completed | disabled | none | 0.0000 | 2.1389 | 798.00 | 1207.50 | 1502.50 | 2967.00 |
| scx_cosmos | 2 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 0.0000 | 0.8541 | 857.50 | 994.50 | 875.50 | 2390.50 |
| scx_flow | 2 | completed | enabled | scx_flow_2.2.0_x86_64_unknown_linux_gnu | 0.0000 | 0.0209 | 78.00 | 82.50 | 43.50 | 1334.00 |
| scx_pandemonium | 2 | completed | enabled | pandemonium | 8.4861 | 26.6181 | 20973.50 | 31849.00 | 24723.50 | 144896.00 |

## Notes

- Lower is better for miss ratio, jitter, and all lateness metrics.
- Miss ratio counts samples that woke later than a full frame period.
- `Late > threshold` is a softer tail signal using the configured lateness threshold.
- `Jitter p99` is the p99 of the absolute change in lateness between consecutive wakeups.
- Review the raw log and JSON paths from `deadline_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
