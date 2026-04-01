# Repeated Latency-Stress Report

This report aggregates repeated `latency_stress_scx_flow.sh` runs for
`scx_flow` so scheduler decisions can use medians and worst cases
instead of single-run noise.

## Summary

- Scheduler: `scx_flow`
- Binary: `/usr/bin/scx_flow`
- Activation mode: `install`
- Runs: 5
- Failed runs: 5
- Runs ending with `sched_ext=disabled`: 5
- Total stall events: 5
- Total disable events: 5
- Total re-enable events: 5
- Total failed-to-run events: 5

## Aggregates

| Metric | Median | Worst |
| --- | ---: | ---: |
| Mixed max latency (us) | 189 | 245 |
| Mixed spikes >100us | 20 | 25 |
| RT max latency (us) | 7425836 | 7475940 |
| RT spikes >100us | 52 | 58 |

## Per-Run Table

| Run | Script exit | Overall status | Post state | Mixed max (us) | Mixed spikes >100us | RT max (us) | RT spikes >100us | Disable | Stall | Re-enable | Final mode |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| run01 | 1 | failed | disabled | 160 | 12 | 7475940 | 46 | 1 | 1 | 1 | latency |
| run02 | 1 | failed | disabled | 189 | 25 | 7383492 | 56 | 1 | 1 | 1 | latency |
| run03 | 1 | failed | disabled | 245 | 23 | 7418266 | 58 | 1 | 1 | 1 | latency |
| run04 | 1 | failed | disabled | 155 | 14 | 7425836 | 52 | 1 | 1 | 1 | latency |
| run05 | 1 | failed | disabled | 215 | 20 | 7442757 | 43 | 1 | 1 | 1 | latency |
