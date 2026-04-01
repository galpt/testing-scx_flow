# Repeated Latency-Stress Report

This report aggregates repeated `latency_stress_scx_flow.sh` runs for
`scx_cosmos` so scheduler decisions can use medians and worst cases
instead of single-run noise.

## Summary

- Scheduler: `scx_cosmos`
- Binary: `/usr/bin/scx_cosmos`
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
| Mixed max latency (us) | 6951 | 13339 |
| Mixed spikes >100us | 29621 | 34528 |
| RT max latency (us) | 7613877 | 7811633 |
| RT spikes >100us | 200 | 324 |

## Per-Run Table

| Run | Script exit | Overall status | Post state | Mixed max (us) | Mixed spikes >100us | RT max (us) | RT spikes >100us | Disable | Stall | Re-enable | Final mode |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| run01 | 1 | failed | disabled | 13339 | 34528 | 7811633 | 195 | 1 | 1 | 1 |  |
| run02 | 1 | failed | disabled | 8766 | 28621 | 7537155 | 200 | 1 | 1 | 1 |  |
| run03 | 1 | failed | disabled | 6951 | 34413 | 7613877 | 159 | 1 | 1 | 1 |  |
| run04 | 1 | failed | disabled | 4790 | 26282 | 7662781 | 295 | 1 | 1 | 0 |  |
| run05 | 1 | failed | disabled | 3339 | 29621 | 7511961 | 324 | 1 | 1 | 1 |  |
