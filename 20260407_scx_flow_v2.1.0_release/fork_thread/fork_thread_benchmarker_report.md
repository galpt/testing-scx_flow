# Fork/Thread Benchmarker Report

This report aggregates `perf bench sched messaging` throughput runs and supporting `perf stat` counters.

Run count summary: Averages over 1 run per scheduler.
Groups: 24
Loops: 6000

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Time (sec) | vs baseline (%) | IPC | Cache Misses | Cache References |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| baseline (6.19.10-1-cachyos) | 1 | completed | disabled | none | 12.890 | +0.00 | 0.405 | 2650092632 | 25417766161 |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 10.723 | -16.81 | 0.424 | 2480398687 | 24710255706 |
| scx_flow | 1 | completed | enabled | scx_flow_2.1.0_rc1_x86_64_unknown_linux_gnu | 9.851 | -23.58 | 0.435 | 2445433548 | 24762489012 |
| scx_pandemonium | 1 | completed | enabled | pandemonium | 95.273 | +639.12 | 0.293 | 27392889787 | 196672222870 |

## Notes

- Lower is better for time and cache misses.
- Higher is better for IPC.
- This mode wraps `perf bench sched messaging` with `perf stat` so throughput and cache behavior are captured together.
- Review the raw log and perf paths from `fork_thread_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
