# Deadline Benchmarker Report

This report aggregates periodic frame-target deadline probe runs across the selected schedulers.

Run count summary: Averages over 2 runs per scheduler.
Target FPS: 60.00
Soft lateness threshold: 1000us

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Miss ratio (%) | Late > threshold (%) | p95 late (us) | p99 late (us) | Jitter p99 (us) | Max late (us) |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline (6.19.10-1-cachyos) | 2 | completed | disabled | none | 0.0000 | 2.4236 | 834.50 | 1298.50 | 1473.00 | 3439.50 |
| scx_cosmos | 2 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 0.0000 | 0.8611 | 867.00 | 993.00 | 912.50 | 1891.50 |
| scx_flow | 2 | completed | enabled | scx_flow_2.0.2_x86_64_unknown_linux_gnu | 0.0000 | 0.0347 | 87.50 | 123.00 | 46.00 | 1279.00 |
| scx_pandemonium | 2 | completed | enabled | pandemonium | 5.4306 | 21.5347 | 17192.50 | 23604.50 | 22712.50 | 36173.50 |

## Notes

- Lower is better for miss ratio, jitter, and all lateness metrics.
- Miss ratio counts samples that woke later than a full frame period.
- `Late > threshold` is a softer tail signal using the configured lateness threshold.
- `Jitter p99` is the p99 of the absolute change in lateness between consecutive wakeups.
- Review the raw log and JSON paths from `deadline_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
