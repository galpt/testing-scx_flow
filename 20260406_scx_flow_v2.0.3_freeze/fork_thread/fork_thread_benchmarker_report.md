# Fork/Thread Benchmarker Report

This report aggregates `perf bench sched messaging` throughput runs and supporting `perf stat` counters.

Run count summary: Averages over 1 run per scheduler.
Groups: 24
Loops: 6000

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Time (sec) | vs baseline (%) | IPC | Cache Misses | Cache References |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| baseline (6.19.10-1-cachyos) | 1 | completed | disabled | none | 12.607 | +0.00 | 0.405 | 2670289743 | 25434804192 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 10.758 | -14.67 | 0.428 | 2465106887 | 24650809431 |
| scx_flow | 1 | completed | enabled | scx_flow_2.0.2_x86_64_unknown_linux_gnu | 10.345 | -17.94 | 0.430 | 2544595263 | 25084460992 |
| scx_pandemonium | 1 | completed | enabled | pandemonium | 90.907 | +621.08 | 0.295 | 24746800826 | 181676683610 |

## Notes

- Lower is better for time and cache misses.
- Higher is better for IPC.
- This mode wraps `perf bench sched messaging` with `perf stat` so throughput and cache behavior are captured together.
- Review the raw log and perf paths from `fork_thread_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
