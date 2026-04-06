# Mixed-Workload Comparison

Generated: Mon Apr  6 09:39:05 PM WIB 2026

Artifacts:
- [mixed_benchmarker_comparison_summary.csv](mixed_benchmarker_comparison_summary.csv)
- [mixed_benchmarker_comparison.png](mixed_benchmarker_comparison.png)
- [mixed_benchmarker_comparison.svg](mixed_benchmarker_comparison.svg)

| Scheduler | Overall status | Note | Mixed p95 (us) | Mixed p99 (us) | Mixed max (us) | RT p95 (us) | RT p99 (us) | RT max (us) | Kernel stall events |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| scx_cosmos | completed |  | 911 | 930 | 2941 | 351 | 363 | 1999596 | 0 |
| scx_pandemonium | completed |  | 634 | 3339 | 18083 | 74 | 631 | 1999436 | 0 |
| scx_flow | completed |  | 59 | 64 | 146 | 57 | 61 | 1998700 | 0 |

- Raw per-scheduler env and log files were not archived in this branch.
