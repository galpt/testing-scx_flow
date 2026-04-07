# Burst Benchmarker Report

This report aggregates sudden load-spike tail latency probe runs across the selected schedulers.

Run count summary: Averages over 2 runs per scheduler.
Probe period: 1000us
Burst window: 200ms every 1000ms

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Burst p95 (us) | Burst p99 (us) | Burst max (us) | Burst miss ratio (%) | Miss resolution (%) | Burst late > threshold (%) |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline (6.19.10-1-cachyos) | 2 | completed | disabled | none | 90.00 | 113.50 | 1712.50 | 0.0175 | 0.0050 | 0.0175 |
| scx_flow | 2 | completed | enabled | scx_flow_2.1.0_rc1_x86_64_unknown_linux_gnu | 62.50 | 76.00 | 4574.50 | 0.2850 | 0.0050 | 0.2850 |

## Notes

- Lower is better for all burst-tail metrics.
- `Burst miss ratio` counts burst-window probe samples that woke later than a full probe period.
- `Miss resolution` is the smallest non-zero miss ratio this run can observe from its active burst sample count.
- `Burst late > threshold` is a softer tail signal using the configured lateness threshold.
- Review the raw log and JSON paths from `burst_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
