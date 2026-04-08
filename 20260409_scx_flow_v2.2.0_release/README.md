# `20260409_scx_flow_v2.2.0_release`

Curated benchmark snapshot for the `scx_flow v2.2.0` release line.

Context:

- scheduler repo branch: [`scx_flow_v2_2_scalability`](https://github.com/galpt/scx/tree/scx_flow_v2_2_scalability)
- scheduler commits:
  - [`4bedb478`](https://github.com/galpt/scx/commit/4bedb478) `scx_flow: prepare v2.2.0 scalability redesign and completions support`
  - [`69a02a4b`](https://github.com/galpt/scx/commit/69a02a4b) `scx_flow: move v2.2.0 under scheds/experimental`
  - [`b44d2975`](https://github.com/galpt/scx/commit/b44d2975) `Cargo: move experimental scx_flow below scx_wd40`
- benchmark harness repo branch: `main`
- machine profile during most scripted runs: `Balanced`
- automated Aquarium was intentionally skipped for this release snapshot because the browser harness remained noisy
- final release confidence also included manual Aquarium checks:
  - `20000` fish at roughly `100-120 FPS`
  - `30000` fish at roughly `70-80 FPS`

Important note:

- these scripted artifacts came from the final `v2.2.0` candidate immediately before the hidden `--completions` compatibility addition for upstream PR [`#3495`](https://github.com/sched-ext/scx/pull/3495)
- the archived reports and CSVs were normalized so the public snapshot reflects the released `scx_flow_2.2.0_*` ops name

Snapshot layout:

- [mini/](mini/)
- [mixed/](mixed/)
- [deadline/](deadline/)
- [ipc/](ipc/)
- [longrun/](longrun/)
- [fork_thread/](fork_thread/)
- [app_launch/](app_launch/)
- [burst/](burst/)

Headline results:

| Benchmark | Snapshot | Headline |
| --- | --- | --- |
| Mini | `20260409_014229` | `scx_flow` holds `173us` max latency and only `12` spikes over `100us` |
| Mixed | `20260409_020622` | `scx_flow` leads clearly with `p95 59us` and `p99 64us` |
| Deadline | `20260409_021205` | `scx_flow` keeps `0.0000%` miss ratio with `p99 late 82.5us` |
| IPC | `20260409_023017` | `scx_flow` lands at `p99 76us`, a strong improvement over the earlier `v2.1.0` release line |
| Longrun | `20260409_023839` | `scx_flow` keeps `miss 0.0071%` and `p99 68us` under sustained load |
| Fork/thread | `20260409_030010` | `scx_flow` remains faster than baseline and far ahead of pandemonium |
| App launch | `20260409_030314` | still not the strongest area, but `p95 619us` remains usable |
| Burst | `20260409_030611` | burst tails are weaker than baseline and kept here for honesty |

## What This Means In Practice

For normal users, these results mostly translate to a machine that stays more
responsive when foreground work and background CPU load happen at the same
time.

- strong `mixed`, `deadline`, and `longrun` results usually mean fewer visible
  hiccups when games, desktop apps, or short interactive tasks compete with
  heavier background work
- strong `IPC` results usually mean better behavior for wake-heavy and
  coordination-heavy workloads instead of those tasks getting delayed behind
  bulk CPU activity
- good `mini` spike control usually means the system feels steadier in short
  bursts instead of only looking good on average throughput
- weaker `app launch` or `burst` numbers mean this release should not be read
  as "best at every latency shape", only as a stronger overall balance for the
  intended general-purpose use case

Notes:

- `v2.2.0` was kept because it combined the scalability redesign work with strong scripted deadline, mixed, IPC, and longrun results while also passing manual Aquarium checks.
- The burst snapshot is included on purpose because this release was not chosen by ignoring weaker signals.
