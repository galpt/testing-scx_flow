# v2.2.4 Normal Mode — 100us Max Latency Spikes

| Scheduler | Max latency | Spikes >100us |
| --- | ---: | ---: |
| baseline (CFS/EEVDF) | 1106us | 304 |
| scx_cosmos | 852us | 821 |
| scx_bpfland | 2724us | 222 |
| **scx_flow v2.2.4** | **142us** | **2** |

scx_flow achieves 142us max latency with only 2 spikes over 100us,
improving on the v2.2.0 baseline (173us / 12 spikes).

## Files

- [mini_benchmarker_report.md](mini_benchmarker_report.md) — full report
- [mini_benchmarker_summary.csv](mini_benchmarker_summary.csv) — raw metrics
- [mini_benchmarker_comparison.png](mini_benchmarker_comparison.png) — chart
- [mini_benchmarker_comparison.svg](mini_benchmarker_comparison.svg) — vector chart
