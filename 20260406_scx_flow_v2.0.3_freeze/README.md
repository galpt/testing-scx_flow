# scx_flow v2.0.3 Freeze Snapshot

This directory archives a curated set of benchmark outputs used to freeze the
`scx_flow v2.0.3` line.

Scheduler context:

- scheduler repo: `galpt/scx`
- branch: `scx_flow_v2`
- commit: `bfdb2a5e`

Benchmark context:

- harness repo: `galpt/testing-scx_flow`
- most runs were collected under the `Balanced` power profile
- Aquarium is archived with an explicit caveat: treat it as a coarse regression
  signal, not the main source of truth for scheduler tuning

Included benchmarks:

- `ipc/`
- `mixed/`
- `deadline/`
- `longrun/`
- `fork_thread/`
- `aquarium/`

These subdirectories keep the public-facing reports, charts, and summaries for
the freeze checkpoint rather than every raw transient log collected during
development.

Note:

- some copied Markdown reports still contain the original local filesystem
  paths from the machine that generated them
- treat the tables and charts in this branch as the durable archive surface
