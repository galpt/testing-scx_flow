# Mixed-Workload Comparison

Generated: Tue Apr  7 10:35:32 PM WIB 2026

Artifacts:
- [mixed_benchmarker_comparison_summary.csv](mixed_benchmarker_comparison_summary.csv)
- [mixed_benchmarker_comparison.png](mixed_benchmarker_comparison.png)
- [mixed_benchmarker_comparison.svg](mixed_benchmarker_comparison.svg)

| Scheduler | Overall status | Note | Mixed p95 (us) | Mixed p99 (us) | Mixed max (us) | RT p95 (us) | RT p99 (us) | RT max (us) | Kernel stall events |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| scx_cosmos | completed |  | 908 | 927 | 1935 | 931 | 939 | 1999321 | 0 |
| scx_pandemonium | completed |  | 541 | 3869 | 16389 | 86 | 489 | 1998871 | 0 |
| scx_flow | completed |  | 203 | 701 | 3224 | 59 | 62 | 1999199 | 0 |

Run-specific env and log paths were omitted from the archive copy because they pointed back to local absolute paths in the original generated report.
