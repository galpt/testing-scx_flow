# Fork/Thread Benchmarker Report

This report aggregates `perf bench sched messaging` throughput runs and supporting `perf stat` counters.

Run count summary: Averages over 1 run per scheduler.
Groups: 24
Loops: 6000

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Time (sec) | vs baseline (%) | IPC | Cache Misses | Cache References |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| baseline (6.19.10-1-cachyos) | 1 | completed | disabled | none | 13.433 | +0.00 | 0.413 | 2469668898 | 26006081827 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 10.835 | -19.34 | 0.431 | 2289158778 | 24934634228 |
| scx_flow | 1 | completed | enabled | scx_flow_2.2.0_x86_64_unknown_linux_gnu | 12.612 | -6.11 | 0.415 | 2586277559 | 25503071194 |
| scx_pandemonium | 1 | completed | enabled | pandemonium | 25.233 | +87.84 | 0.353 | 7473550955 | 59381387444 |

## Notes

- Lower is better for time and cache misses.
- Higher is better for IPC.
- This mode wraps `perf bench sched messaging` with `perf stat` so throughput and cache behavior are captured together.
- Review the raw log and perf paths from `fork_thread_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
