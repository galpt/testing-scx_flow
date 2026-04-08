# IPC Benchmarker Report

This report aggregates IPC round-trip ping-pong probe runs under background CPU load.

Run count summary: Averages over 1 run per scheduler.
Worker pairs: 2
Message bytes: 64
Soft RTT threshold: 500us

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Over threshold (%) | p95 RTT (us) | p99 RTT (us) | Max RTT (us) |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: |
| baseline (6.19.10-1-cachyos) | 1 | completed | disabled | none | 0.0116 | 10.00 | 15.00 | 4311.00 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 0.9159 | 10.00 | 21.00 | 3079.00 |
| scx_flow | 1 | completed | enabled | scx_flow_2.2.0_x86_64_unknown_linux_gnu | 0.5345 | 11.00 | 76.00 | 5912.00 |
| scx_pandemonium | 1 | completed | enabled | pandemonium | 0.0199 | 19.00 | 20.00 | 62774.00 |

## Notes

- Lower is better for all IPC round-trip metrics.
- This mode measures Unix socket ping-pong round trips between paired worker CPUs.
- Review the raw log and JSON paths from `ipc_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
