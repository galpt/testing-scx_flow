# App Launch Benchmarker Report

This report aggregates repeated app-launch latency probe runs under background CPU load.

Run count summary: Averages over 1 run per scheduler.
Workers: 4
Command: /usr/bin/true
Soft launch threshold: 5000us

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Over threshold (%) | p95 launch (us) | p99 launch (us) | Max launch (us) |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: |
| baseline (6.19.10-1-cachyos) | 1 | completed | disabled | none | 0.0000 | 575.00 | 695.00 | 3542.00 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 0.0408 | 3000.00 | 3025.00 | 6043.00 |
| scx_flow | 1 | completed | enabled | scx_flow_2.1.0_rc1_x86_64_unknown_linux_gnu | 0.2335 | 631.00 | 2448.00 | 26212.00 |
| scx_pandemonium | 1 | completed | enabled | pandemonium | 0.0586 | 617.00 | 969.00 | 26478.00 |

## Notes

- Lower is better for all app-launch metrics.
- This mode repeatedly launches a configured command under background CPU load and measures launch-to-exit latency.
- Review the raw log and JSON paths from `app_launch_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
