# Mixed-Workload Comparison

Generated: Thu Apr  9 02:08:24 AM WIB 2026

Artifacts:
- [mixed_benchmarker_comparison_summary.csv](mixed_benchmarker_comparison_summary.csv)
- [mixed_benchmarker_comparison.png](mixed_benchmarker_comparison.png)
- [mixed_benchmarker_comparison.svg](mixed_benchmarker_comparison.svg)

| Scheduler | Overall status | Note | Mixed p95 (us) | Mixed p99 (us) | Mixed max (us) | RT p95 (us) | RT p99 (us) | RT max (us) | Kernel stall events |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| scx_cosmos | completed |  | 918 | 930 | 947 | 942 | 947 | 1997945 | 0 |
| scx_pandemonium | completed |  | 481 | 2467 | 25168 | 62 | 328 | 1999220 | 0 |
| scx_flow | completed |  | 59 | 64 | 149 | 57 | 59 | 1998630 | 0 |

Raw per-scheduler env and log files are omitted from this archive snapshot.
