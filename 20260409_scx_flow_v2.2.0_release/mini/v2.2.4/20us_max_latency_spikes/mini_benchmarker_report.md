# Mini Benchmarker Report

This report aggregates the latest comparison run across the selected schedulers.

Run count summary: Averages over 1 run per scheduler.

| Scheduler | Runs | Status | Total samples | Overflows >20us | Max latency (us) | Hackbench mean (s) | Sysbench events/s | Stress-ng bogo ops/s |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline (7.0.3-1-cachyos) | 1 | completed | n/a | 344 | 407.00 | 0.676 | n/a | 6684.47 |
| scx_cosmos | 1 | completed | n/a | 351 | 227.00 | 0.645 | n/a | 6585.06 |
| scx_bpfland | 1 | completed | n/a | 376 | 375.00 | 0.987 | n/a | 6614.65 |
| scx_flow | 1 | completed | n/a | 402 | 339.00 | 0.672 | n/a | 6611.98 |

## Notes

- Hard RT mode: FIFO priority 99, SMP, 200us interval, histogram up to 20us.
- `Overflows >20us` is the count of samples that exceeded the 20us threshold.
- An overflow count of 0 means all samples stayed under 20us (hard RT target satisfied).
- Lower is better for all latency and overflow metrics.
- Higher is better for sysbench events/s and stress-ng bogo ops/s.
- Review the raw log paths from `mini_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
