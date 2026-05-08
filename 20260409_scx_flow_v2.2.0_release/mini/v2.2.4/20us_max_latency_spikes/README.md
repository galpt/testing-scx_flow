# v2.2.4 Hard RT Mode — 20us Max Latency Spikes

Hard RT mode: FIFO priority 99, SMP, 200us interval, histogram up to 20us.

| Scheduler | Overflows >20us | Max latency |
| --- | ---: | ---: |
| baseline (CFS/EEVDF) | 344 | 407us |
| scx_cosmos | 351 | 227us |
| scx_bpfland | 376 | 375us |
| **scx_flow v2.2.4** | **402** | **339us** |

scx_flow v2.2.4 improves over v2.2.3 (388us max, 610 overflows),
with both lower max latency and fewer overflows.

## Files

- [mini_benchmarker_report.md](mini_benchmarker_report.md) — full report
- [mini_benchmarker_summary.csv](mini_benchmarker_summary.csv) — raw metrics
- [mini_benchmarker_comparison.png](mini_benchmarker_comparison.png) — chart
- [mini_benchmarker_comparison.svg](mini_benchmarker_comparison.svg) — vector chart
