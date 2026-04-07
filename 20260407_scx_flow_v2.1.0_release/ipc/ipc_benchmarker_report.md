# IPC Benchmarker Report

This report aggregates IPC round-trip ping-pong probe runs under background CPU load.

Run count summary: Averages over 1 run per scheduler.
Worker pairs: 2
Message bytes: 64
Soft RTT threshold: 500us

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Over threshold (%) | p95 RTT (us) | p99 RTT (us) | Max RTT (us) |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: |
| baseline (6.19.10-1-cachyos) | 1 | completed | disabled | none | 0.0271 | 10.00 | 17.00 | 4165.00 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 0.1092 | 12.00 | 14.00 | 3993.00 |
| scx_flow | 1 | completed | enabled | scx_flow_2.1.0_rc1_x86_64_unknown_linux_gnu | 0.7635 | 24.00 | 292.00 | 7879.00 |
| scx_pandemonium | 1 | completed | enabled | pandemonium | 0.0226 | 19.00 | 20.00 | 25910.00 |

## Notes

- Lower is better for all IPC round-trip metrics.
- This mode measures Unix socket ping-pong round trips between paired worker CPUs.
- Review the raw log and JSON paths from `ipc_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
