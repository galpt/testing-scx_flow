# Mini Benchmarker Report

This report aggregates the latest comparison run across the selected schedulers.

Run count summary: Averages over 1 run per scheduler.

| Scheduler | Runs | Status | Total samples | Overflows >20us | Max latency (us) | Hackbench mean (s) | Sysbench events/s | Stress-ng bogo ops/s |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline (7.0.3-1-cachyos) | 1 | completed | n/a | 822 | 542.00 | 0.787 | n/a | 6679.28 |
| scx_cosmos | 1 | completed | n/a | 619 | 579.00 | 0.664 | n/a | 6560.57 |
| scx_bpfland | 1 | completed | n/a | 589 | 447.00 | 1.061 | n/a | 6600.15 |
| scx_flow | 1 | completed | n/a | 610 | 388.00 | 0.675 | n/a | 6624.46 |

## Notes

- Hard RT mode: FIFO priority 99, SMP, 200us interval, histogram up to 20us.
- `Overflows >20us` is the count of samples that exceeded the 20us threshold.
- An overflow count of 0 means all samples stayed under 20us (hard RT target satisfied).
- Lower is better for all latency and overflow metrics.
- Higher is better for sysbench events/s and stress-ng bogo ops/s.
- Review the raw log paths from `mini_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
