# App Launch Benchmarker Report

This report aggregates repeated app-launch latency probe runs under background CPU load.

Run count summary: Averages over 1 run per scheduler.
Workers: 4
Command: /usr/bin/true
Soft launch threshold: 5000us

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Over threshold (%) | p95 launch (us) | p99 launch (us) | Max launch (us) |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: |
| baseline (6.19.10-1-cachyos) | 1 | completed | disabled | none | 0.0000 | 564.00 | 663.00 | 3184.00 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 0.0260 | 2992.00 | 3015.00 | 7004.00 |
| scx_flow | 1 | completed | enabled | scx_flow_2.2.0_x86_64_unknown_linux_gnu | 0.1271 | 619.00 | 1767.00 | 19216.00 |
| scx_pandemonium | 1 | completed | enabled | pandemonium | 0.0333 | 605.00 | 967.00 | 15495.00 |

## Notes

- Lower is better for all app-launch metrics.
- This mode repeatedly launches a configured command under background CPU load and measures launch-to-exit latency.
- Review the raw log and JSON paths from `app_launch_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
