# testing-scx_flow Benchmark Archives

Curated benchmark snapshots for `testing-scx_flow`.

This branch is intentionally separate from `main`:

- `main` stays focused on harness code, scripts, and docs
- `benchmark-archives` keeps selected benchmark snapshots that are worth preserving
- not every local run belongs here; this branch is for curated checkpoints only

## Archived Snapshots

### `20260409_scx_flow_v2.2.0_release`

Frozen release snapshot for the `scx_flow v2.2.0` line associated with the
scalability redesign work and hidden shell-completions compatibility for the
upstream CLI-completions PR. This snapshot now also contains the `v2.2.3`
hard RT update below.

Context:

- scheduler repo branch: [`scx_flow_v2_2_scalability`](https://github.com/galpt/scx/tree/scx_flow_v2_2_scalability)
- scheduler commits:
  - `v2.2.3`: [`26d4f26b`](https://github.com/galpt/scx/commit/26d4f26b)
  - `v2.2.0`: [`4bedb478`](https://github.com/galpt/scx/commit/4bedb478)
- benchmark harness repo branch at publication time: `main`
- machine profile during most scripted runs: `Balanced`

Key results:

| Benchmark | Snapshot | Headline |
| --- | --- | --- |
| Mini (v2.2.0) | `20260409_014229` | `scx_flow` keeps `173us` max latency with only `12` spikes over `100us` |
| **Mini (v2.2.4, 100us mode)** | `20260508_174204` | **`scx_flow v2.2.4` achieves `142us` max latency with only `2` spikes over `100us` — vs cosmos `852us`, bpfland `2724us`** |
| **Mini (v2.2.4, 20us hard RT)** | `20260508_175030` | **`scx_flow v2.2.4` holds `339us` max latency with `402` overflows — vs baseline `407us`, cosmos `227us`, bpfland `375us`** |
| Mixed | `20260409_020622` | `scx_flow` strongly leads with `p99 64us` |
| Deadline | `20260409_021205` | `scx_flow` strongly leads with `0.0000%` miss ratio and `p99 late 82.5us` |
| IPC | `20260409_023017` | `scx_flow` improves to `p99 76us` in the archived bundle |
| Longrun | `20260409_023839` | `scx_flow` keeps `miss 0.0071%` and `p99 68us` |
| Fork/thread | `20260409_030010` | `scx_flow` remains faster than baseline |
| App launch | `20260409_030314` | still a weaker spot; kept in the archive for honesty |
| Burst | `20260409_030611` | included because the release decision did not ignore weaker tails |

Browse the snapshot here:

- [20260409_scx_flow_v2.2.0_release](20260409_scx_flow_v2.2.0_release/)

### `20260407_scx_flow_v2.1.0_release`

Frozen release snapshot for the `scx_flow v2.1.0` line associated with the
hot-path cleanup and live-gaming polish release in the scheduler repo.

Context:

- scheduler repo branch: `scx_flow_v2`
- scheduler commit: `afc6fa11`
- benchmark harness repo branch at publication time: `main`
- machine profile during most scripted runs: `Balanced`
- Aquarium is included only as a coarse sanity check; the final release call
  also used a manual Aquarium check and a live gaming session
- the archived raw artifacts came from the final `2.1.0-rc1` validation pass
  immediately before the version-only bump to `2.1.0`, so some CSV ops-name
  fields still include the `rc1` suffix

Key results:

| Benchmark | Snapshot | Headline |
| --- | --- | --- |
| Mini | `20260407_222304` | `scx_flow` stays strong on hackbench and spike control, though not best-ever on every mini metric |
| Deadline | `20260407_223701` | `scx_flow` keeps `0.0000%` late-over-threshold with `jitter p99 47us` |
| IPC | `20260407_224321` | `scx_flow` lands around `p99 292us`, roughly keeper-class for the release line |
| Longrun | `20260407_224639` | `scx_flow` recovers to `miss 1.7812%`, much healthier than the earlier failed redesign |
| Fork/thread | `20260407_225141` | `scx_flow` is fastest and also leads cache misses / IPC in the archived bundle |
| App launch | `20260407_225435` | still a weak spot; kept in the archive for honesty |
| Burst | `20260407_230325` | `scx_flow` keeps very strong `p95/p99` latency |
| Aquarium | `20260407_225638` | kept as a sanity artifact, but the final release decision leaned more on manual testing |

Browse the snapshot here:

- [20260407_scx_flow_v2.1.0_release](20260407_scx_flow_v2.1.0_release/)

### `20260407_longrun_threshold_fix`

Curated longrun snapshot captured after lowering the default soft lateness threshold from `1000us` to `500us`.

Browse the snapshot here:

- [20260407_longrun_threshold_fix](20260407_longrun_threshold_fix/)

### `20260406_mini_scheduler_matrix`

Curated mini benchmark matrix covering `baseline`, `scx_cosmos`, `scx_cake`, `scx_pandemonium`, and `scx_flow`.

Browse the snapshot here:

- [20260406_mini_scheduler_matrix](20260406_mini_scheduler_matrix/)

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

- [20260406_scx_flow_v2.0.3_freeze](20260406_scx_flow_v2.0.3_freeze/)

## Notes

- Reports here are archival artifacts, not live generated outputs.
- Small run-to-run movement is expected, especially under the `Balanced` power profile.
- If a future checkpoint is archived, add a new top-level snapshot directory instead of overwriting this one.
