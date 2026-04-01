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
| Mixed max latency (us) | 1290 | 4451 |
| Mixed spikes >100us | 37 | 8268 |
| RT max latency (us) | 7287494 | 7346006 |
| RT spikes >100us | 52 | 61 |

## Per-Run Table

| Run | Script exit | Overall status | Post state | Mixed max (us) | Mixed spikes >100us | RT max (us) | RT spikes >100us | Disable | Stall | Re-enable | Final mode |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| run01 | 1 | failed | disabled | 994 | 44 | 7075587 | 26 | 1 | 1 | 1 | latency |
| run02 | 1 | failed | disabled | 4451 | 8268 | 7346006 | 59 | 1 | 1 | 0 | latency |
| run03 | 1 | failed | disabled | 1291 | 37 | 7251886 | 40 | 1 | 1 | 1 | latency |
| run04 | 1 | failed | disabled | 1290 | 27 | 7293438 | 61 | 1 | 1 | 1 | latency |
| run05 | 1 | failed | disabled | 153 | 21 | 7287494 | 52 | 1 | 1 | 1 | latency |
