# Repeated Latency-Stress Report

This report aggregates repeated `latency_stress_scx_flow.sh` runs for
`scx_bpfland` so scheduler decisions can use medians and worst cases
instead of single-run noise.

## Summary

- Scheduler: `scx_bpfland`
- Binary: `/usr/bin/scx_bpfland`
- Activation mode: `manual`
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
| Mixed max latency (us) | 14489 | 17722 |
| Mixed spikes >100us | 20840 | 21062 |
| RT max latency (us) | 7244411 | 7373688 |
| RT spikes >100us | 120 | 130 |

## Per-Run Table

| Run | Script exit | Overall status | Post state | Mixed max (us) | Mixed spikes >100us | RT max (us) | RT spikes >100us | Disable | Stall | Re-enable | Final mode |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| run01 | 1 | failed | disabled | 14489 | 20763 | 7373688 | 130 | 1 | 1 | 1 |  |
| run02 | 1 | failed | disabled | 13811 | 20814 | 7276678 | 120 | 1 | 1 | 1 |  |
| run03 | 1 | failed | disabled | 13251 | 21062 | 7221050 | 99 | 1 | 1 | 1 |  |
| run04 | 1 | failed | disabled | 17722 | 20944 | 7244411 | 92 | 1 | 1 | 1 |  |
| run05 | 1 | failed | disabled | 15923 | 20840 | 6967260 | 126 | 1 | 1 | 0 |  |
