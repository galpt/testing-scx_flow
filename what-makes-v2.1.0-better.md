# Why `scx_flow v2.1.0` Is the Current Recommended Release

`scx_flow v2.1.0` is the current recommended release because it delivered the
best overall balance between real-world smoothness, bounded scheduler behavior,
and maintainable internal design.

It is not presented as a claim that every single benchmark number is better
than every older release. The reason to prefer it is that it held up best as an
overall keeper.

## Release Checkpoints

- [`v2.0.2` baseline](https://github.com/galpt/scx/commit/a0c5b0e2)  
  First strong high-FPS `v2` baseline with the bounded direct-local front door.
- [`v2.0.3` release](https://github.com/galpt/scx/commit/bfdb2a5e)  
  Confidence-cleanup / IPC-continuity release and the main comparison point for
  the later live-gaming checks.
- [`v2.1.0` release](https://github.com/galpt/scx/commit/afc6fa11)  
  Hot-path cleanup and live-gaming polish release.

## What Improved in `v2.1.0`

### 1. Better real-world smoothness

`v2.1.0` was kept because it felt smoother in actual use than the GitHub
`v2.0.3` release.

The final live checks covered:

- visible stutter behavior
- alt-tab behavior
- background interference from apps such as Chrome, VS Code, and Discord

That made `v2.1.0` the strongest overall keeper even though some synthetic
results remained mixed.

### 2. Less repeated hot-path work

The release moves more task-local wake classification into cached wake-profile
state instead of rebuilding the same checks repeatedly during enqueue.

In practice this means:

- less repeated hot-path work
- clearer readiness bits
- explicit final routing still stays visible

So the scheduler becomes cleaner without turning into a black-box predictor.

### 3. Safer structural improvement over the failed earlier redesign

The earlier experimental `2.1.0` line regressed because it influenced too many
task classes too broadly, especially through wider periodic/refill behavior.

The final `v2.1.0` release keeps the good structural ideas:

- shared confidence-decay cleanup
- cleaner wake classification
- cached preempt-ready and reserved-head hints

But it avoids the broader periodic and refill shaping that made the failed
earlier redesign unstable.

### 4. Stronger production shape than `v2.0.2`

`v2.0.2` was a very important release because it established the first strong
high-FPS `v2` baseline.

`v2.1.0` builds on that by being more internally disciplined:

- more bounded confidence-driven state
- better separation between observed behavior and final policy
- more explicit cached readiness
- less repeated enqueue decision work

That makes it a better long-term production base than a simpler
gaming-oriented baseline alone.

## Comparison Summary

| Version | Main identity | Strength | Limitation |
| --- | --- | --- | --- |
| `v2.0.2` | direct-local baseline | first strong high-FPS `v2` baseline | less unified internally |
| `v2.0.3` | confidence cleanup release | cleaner and stronger than `v2.0.2` in several scripted cases | exact GitHub release felt weaker in manual gaming checks |
| `v2.1.0` | hot-path cleanup and gaming polish | best overall keeper for smoothness + bounded behavior | not a universal winner on every synthetic benchmark |

## What This Does Not Claim

To keep the claim honest:

- `v2.1.0` does not beat every older release on every benchmark
- automated Aquarium runs remained noisy and were not treated as the primary
  decision source
- app-launch behavior was still not a headline strength
- some mixed / mini results were not best-in-class

So the release claim is not:

- “`v2.1.0` wins every chart”

It is:

- “`v2.1.0` is the best overall release checkpoint for real-world use”

## Evidence Used Around the Release

### Manual validation

- live gaming session on the final candidate
- manual Aquarium checks, including `20000` fish
- comparison against the GitHub `v2.0.3` release

### Scripted validation

- `comparison-results/20260407_222304`
- `mixed-comparison-results/20260407_223328`
- `deadline-comparison-results/20260407_223701`
- `ipc-comparison-results/20260407_224321`
- `longrun-comparison-results/20260407_224639`
- `fork-thread-comparison-results/20260407_225141`
- `app-launch-comparison-results/20260407_225435`
- `burst-comparison-results/20260407_230325`

## Bottom Line

`scx_flow v2.1.0` is recommended because it is the first release that combined
the newer confidence-driven cleanup and hot-path simplification with a smoother
live gaming experience, without repeating the broader redesign mistakes that
made the earlier experimental `2.1.0` line unstable.
