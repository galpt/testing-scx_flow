# testing-scx_flow Benchmark Archives

Curated benchmark snapshots for `testing-scx_flow`.

This branch is intentionally separate from `main`:

- `main` stays focused on harness code, scripts, and docs
- `benchmark-archives` keeps selected benchmark snapshots that are worth preserving
- not every local run belongs here; this branch is for curated checkpoints only

## Archived Snapshots

### `20260406_scx_flow_v2.0.3_freeze`

Frozen benchmark snapshot for the `scx_flow v2.0.3` line associated with the
confidence-cleanup / IPC-continuity work in the scheduler repo.

Context:

- scheduler repo branch: `scx_flow_v2`
- scheduler commit: `bfdb2a5e`
- benchmark harness repo branch at publication time: `main`
- machine profile during most runs: `Balanced`
- Aquarium is included only as a coarse sanity check because browser/GPU/power
  state can move it around more than the tighter synthetic probes

Key results:

| Benchmark | Snapshot | Headline |
| --- | --- | --- |
| IPC | `20260406_212708` | `scx_flow` improved to `p99 179us`, but still trails baseline |
| Mixed | `20260406_213701` | `scx_flow` strongly leads with `p99 64us` |
| Deadline | `20260406_214106` | `scx_flow` strongly leads with `0.0000%` miss ratio and `jitter p99 46us` |
| Longrun | `20260406_154902` | `scx_flow` strongly beats cosmos and pandemonium |
| Fork/thread | `20260406_155210` | `scx_flow` is fastest in the archived bundle |
| Aquarium | `20260406_201346` | included as a sanity snapshot, not the primary tuning signal |

Browse the snapshot here:

- [20260406_scx_flow_v2.0.3_freeze](/home/galpt/Desktop/Disk_D/sched-research/.testing-scx_flow-benchmark-archives/20260406_scx_flow_v2.0.3_freeze)

## Notes

- Reports here are archival artifacts, not live generated outputs.
- Small run-to-run movement is expected, especially under the `Balanced` power profile.
- If a future checkpoint is archived, add a new top-level snapshot directory instead of overwriting this one.
