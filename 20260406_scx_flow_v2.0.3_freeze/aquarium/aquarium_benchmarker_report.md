# Aquarium Benchmarker Report

This report aggregates the latest Aquarium comparison run across the selected schedulers.

Run count summary: Averages over 2 runs per scheduler. Each scheduler had 1 uncounted warmup run first.
Fish count(s): 2000

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Avg FPS | 1% low FPS | p95 frame ms | Jank >33ms | Stress-ng bogo ops/s |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| scx_cosmos | 2 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 112.17 | 56.19 | 9.15 | 24.00 | 153602.45 |
| scx_flow | 2 | completed | enabled | scx_flow_2.0.2_x86_64_unknown_linux_gnu | 114.26 | 78.00 | 12.90 | 0.00 | 158029.60 |

## Notes

- Higher is better for Aquarium FPS and 1% low FPS.
- Lower is better for frame time and jank counts.
- Stress-ng bogo ops/s is a rough background throughput sanity check.
- Review the raw log paths from `aquarium_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
