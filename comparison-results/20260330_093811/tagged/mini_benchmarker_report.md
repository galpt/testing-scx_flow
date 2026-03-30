# Mini Benchmarker Report

This report aggregates the latest comparison run across the selected schedulers.

| Scheduler | Runs | Status | sched_ext state | Current scheduler | Max latency (us) | Spikes >100us | Hackbench mean (s) | Sysbench events/s | Stress-ng bogo ops/s |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| scx_cosmos | 1 | completed | enabled | cosmos_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 2851.00 | 3761.00 | 0.660 | n/a | 6212.96 |
| scx_bpfland | 1 | completed | enabled | bpfland_1.1.0_gc505008f_x86_64_unknown_linux_gnu | 4498.00 | 2475.00 | 0.886 | n/a | 6265.44 |
| scx_flow | 1 | completed | enabled | scx_flow_1.0.0_x86_64_unknown_linux_gnu | 2676.00 | 2872.00 | 0.631 | n/a | 6238.07 |

## Notes

- Lower is better for latency and hackbench time.
- Higher is better for sysbench events/s and stress-ng bogo ops/s.
- Review the raw log paths from `mini_benchmarker_summary.csv` when a row shows `failed` or `skipped`.
