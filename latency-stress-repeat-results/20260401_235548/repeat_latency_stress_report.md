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
| Mixed max latency (us) | 108 | 163 |
| Mixed spikes >100us | 2 | 3 |
| RT max latency (us) | 7660097 | 7754148 |
| RT spikes >100us | 35 | 51 |

## Per-Run Table

| Run | Script exit | Overall status | Post state | Mixed max (us) | Mixed spikes >100us | RT max (us) | RT spikes >100us | Disable | Stall | Re-enable | Final mode |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| run01 | 1 | failed | disabled | 129 | 2 | 7754148 | 24 | 1 | 1 | 1 | latency |
| run02 | 1 | failed | disabled | 163 | 3 | 7595904 | 51 | 1 | 1 | 1 | latency |
| run03 | 1 | failed | disabled | 82 | 0 | 7660097 | 17 | 1 | 1 | 1 | latency |
| run04 | 1 | failed | disabled | 108 | 2 | 7680809 | 46 | 1 | 1 | 0 | latency |
| run05 | 1 | failed | disabled | 83 | 0 | 7633622 | 35 | 1 | 1 | 1 | latency |
