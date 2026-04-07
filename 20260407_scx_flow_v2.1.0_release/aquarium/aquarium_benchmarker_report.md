# Aquarium Benchmarker Report

This report aggregates the latest Aquarium comparison run across the selected schedulers.

Run count summary: Averages over 2 runs per scheduler. Each scheduler had 1 uncounted warmup run first.
Fish count(s): 2000

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Avg FPS | 1% low FPS | p95 frame ms | Jank >33ms | Stress-ng bogo ops/s |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| scx_cosmos | 2 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 105.70 | 43.20 | 15.17 | 30.50 | 153089.57 |
| scx_flow | 2 | completed | enabled | scx_flow_2.1.0_rc1_x86_64_unknown_linux_gnu | 71.86 | 36.62 | 34.30 | 358.50 | 137081.73 |

## Notes

- Higher is better for Aquarium FPS and 1% low FPS.
- Lower is better for frame time and jank counts.
- Stress-ng bogo ops/s is a rough background throughput sanity check.
- Review the raw log paths from `aquarium_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
