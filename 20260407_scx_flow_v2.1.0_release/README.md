# `20260407_scx_flow_v2.1.0_release`

Curated benchmark snapshot for the `scx_flow v2.1.0` release line.

Context:

- scheduler repo branch: `scx_flow_v2`
- scheduler commit: `0b071b4f`
- benchmark harness repo branch: `main`
- machine profile during most scripted runs: `Balanced`
- final release decision also included a manual Aquarium check and a live gaming session
- the archived raw artifacts came from the last `2.1.0-rc1` validation pass
  immediately before the version-only bump to `2.1.0`, so some CSV fields
  still contain the `rc1` suffix

Snapshot layout:

- [mini/](mini/)
- [mixed/](mixed/)
- [deadline/](deadline/)
- [ipc/](ipc/)
- [longrun/](longrun/)
- [fork_thread/](fork_thread/)
- [app_launch/](app_launch/)
- [burst/](burst/)
- [aquarium/](aquarium/)

Notes:

- `scx_flow v2.1.0` was kept because it felt smoother than the GitHub `v2.0.3` release in live gaming despite some synthetic tradeoffs.
- Aquarium remains a coarse sanity check only; browser, GPU, and power-profile state can move it around a lot more than the tighter probes.
