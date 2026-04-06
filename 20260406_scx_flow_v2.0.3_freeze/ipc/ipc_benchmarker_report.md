# IPC Benchmarker Report

This report aggregates IPC round-trip ping-pong probe runs under background CPU load.

Run count summary: Averages over 1 run per scheduler.
Worker pairs: 2
Message bytes: 64
Soft RTT threshold: 500us

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Over threshold (%) | p95 RTT (us) | p99 RTT (us) | Max RTT (us) |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: |
| baseline (6.19.10-1-cachyos) | 1 | completed | disabled | none | 0.0160 | 10.00 | 14.00 | 4345.00 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 0.0978 | 12.00 | 13.00 | 3004.00 |
| scx_flow | 1 | completed | enabled | scx_flow_2.0.2_x86_64_unknown_linux_gnu | 0.6943 | 15.00 | 179.00 | 5352.00 |
| scx_pandemonium | 1 | completed | enabled | pandemonium | 0.0166 | 19.00 | 20.00 | 25969.00 |

## Notes

- Lower is better for all IPC round-trip metrics.
- This mode measures Unix socket ping-pong round trips between paired worker CPUs.
- Review the raw log and JSON paths from `ipc_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
