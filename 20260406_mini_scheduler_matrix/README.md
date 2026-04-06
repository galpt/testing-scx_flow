# Mini Scheduler Matrix Snapshot

This snapshot archives the `mini_benchmarker.sh` run collected at:

- local result bundle: `comparison-results/20260406_225638`
- kernel: `6.19.10-1-cachyos`
- power profile: `Balanced`

Schedulers included:

- `baseline`
- `scx_cosmos`
- `scx_cake`
- `scx_pandemonium`
- `scx_flow`

Headline:

- `scx_flow` led this matrix on both max latency and hackbench time in the archived run
- this snapshot is especially useful because it confirms the mini benchmarker path works cleanly with `scx_pandemonium`

Included files:

- `mini/mini_benchmarker_report.md`
- `mini/mini_benchmarker_summary.csv`
- `mini/mini_benchmarker_comparison.png`
- `mini/mini_benchmarker_comparison.svg`
