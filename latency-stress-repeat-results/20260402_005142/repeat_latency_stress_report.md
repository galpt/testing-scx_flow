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
- Total re-enable events: 4
- Total failed-to-run events: 5

## Aggregates

| Metric | Median | Worst |
| --- | ---: | ---: |
| Mixed max latency (us) | 177 | 213 |
| Mixed spikes >100us | 25 | 26 |
| RT max latency (us) | 7655443 | 7727735 |
| RT spikes >100us | 24 | 49 |

## Per-Run Table

| Run | Script exit | Overall status | Post state | Mixed max (us) | Mixed spikes >100us | RT max (us) | RT spikes >100us | Disable | Stall | Re-enable | Final mode |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| run01 | 1 | failed | disabled | 213 | 26 | 7530540 | 19 | 1 | 1 | 0 | latency |
| run02 | 1 | failed | disabled | 136 | 7 | 7664545 | 23 | 1 | 1 | 1 | latency |
| run03 | 1 | failed | disabled | 177 | 25 | 7727735 | 49 | 1 | 1 | 1 | latency |
| run04 | 1 | failed | disabled | 199 | 26 | 7582669 | 24 | 1 | 1 | 1 | latency |
| run05 | 1 | failed | disabled | 161 | 17 | 7655443 | 29 | 1 | 1 | 1 | latency |
