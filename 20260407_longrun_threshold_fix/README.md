# Longrun Threshold Fix Snapshot

This snapshot archives the first longrun comparison run after the default
soft lateness threshold was changed from `1000us` to `500us`.

Why this snapshot exists:

- the earlier longrun default used the same value for probe period and soft threshold
- that made `Long-Run Miss Ratio` and `Late Over Threshold Ratio` collapse into the same metric
- this run verifies the corrected default produces meaningfully different ratios

Source run:

- local result bundle: `longrun-comparison-results/20260407_063136`
- kernel: `6.19.10-1-cachyos`
- power profile: `Balanced`

Headline:

- `scx_flow` now shows distinct longrun ratios: `miss 1.4363%` vs `late-over-threshold 4.6363%`
- `scx_cosmos` also separates clearly: `1.7196%` vs `18.6771%`
- this confirms the previous identical percentages were a configuration problem, not a plotting bug

Included files:

- `longrun/longrun_benchmarker_report.md`
- `longrun/longrun_benchmarker_summary.csv`
- `longrun/longrun_benchmarker_comparison.png`
- `longrun/longrun_benchmarker_comparison.svg`
