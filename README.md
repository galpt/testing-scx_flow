# scx_flow Testing Suite

Helper scripts for installing, enabling, monitoring, benchmarking, and
resetting `scx_flow` through the shared `scx.service` systemd unit.

## What You Should Care About

When checking whether `scx_flow` is healthy, focus on these signals first:

1. Is `sched_ext` enabled right now?
2. Is `scx_flow` the active scheduler right now?
3. Is `scx.service` still running, or is it crash-looping?
4. Are logs showing fresh runtime errors, or only old history from earlier runs?

Everything else is secondary.

In practice, trust the live kernel state before anything else:

```bash
cat /sys/kernel/sched_ext/state
cat /sys/kernel/sched_ext/root/ops
systemctl status scx.service
```

If those three look healthy, then `scx_flow` is running even if a helper script
or benchmark step prints a separate tooling error.

## Correct Behavior

Healthy `scx_flow` usually looks like this:

```bash
cat /sys/kernel/sched_ext/state
enabled

cat /sys/kernel/sched_ext/root/ops
scx_flow_1.0.0_x86_64_unknown_linux_gnu
```

And:

- `./status_scx_flow.sh` ends with `scx_flow is installed, configured, and currently active`
- `./monitor_scx_flow.sh` shows:
  - `sched_ext state: enabled`
  - `Service status: active (running)`
  - a current `Main PID`
- `systemctl status scx.service` shows `active (running)`
- `journalctl -u scx.service` shows a recent `Starting scx_flow scheduler` line and no new repeated runtime errors

If `sudo ./benchmark.sh` prints:

```bash
Current scheduler: scx_flow_1.0.0_x86_64_unknown_linux_gnu
```

that is already a healthy scheduler signal. The benchmark step itself is a
separate concern.

## Wrong Behavior

These are the main failure patterns to care about:

### `sched_ext` Is Not Enabled

Bad signs:

```bash
cat /sys/kernel/sched_ext/state
disabled
```

or:

```bash
cat /sys/kernel/sched_ext/root/ops
(empty)
```

This means the scheduler is not currently active.

### `scx.service` Is Failing or Restarting

Bad signs:

- `systemctl status scx.service` shows `failed`
- `status_scx_flow.sh` reports inactive/disabled/none
- `journalctl -u scx.service -f` keeps showing repeated start/fail/start/fail cycles

### Fresh Runtime Errors

Bad signs in logs:

- `runtime error`
- `invalid CPU ... from ops.select_cpu()`
- repeated `disabled (runtime error)` after the most recent start

Old errors in `dmesg` or `journalctl` do not matter by themselves if the
current service instance is healthy. Always check whether the latest run is
still active.

### Benchmarks Cannot Start

If you see:

```bash
cyclictest: command not found
```

that is not a scheduler failure. It means benchmark dependencies are not
installed yet.

Run:

```bash
sudo ./install_benchmark_deps.sh
```

before `sudo ./benchmark.sh`.

On Arch/CachyOS, `hackbench` and `lmbench` may not exist as standalone official
`pacman` package targets. That is expected here.

### Benchmark Tooling Failed But Scheduler Is Fine

This pattern is common and should not be mistaken for a scheduler failure:

```bash
Current scheduler: scx_flow_1.0.0_x86_64_unknown_linux_gnu
...
cyclictest: command not found
```

Meaning:

- `scx_flow` is active
- `sched_ext` is working
- the benchmark script stopped only because `rt-tests` is not installed

Fix:

```bash
sudo ./install_benchmark_deps.sh
sudo ./benchmark.sh
```

Only treat it as a scheduler problem if the live state also goes bad, for
example `sched_ext` becomes `disabled`, `root/ops` becomes empty, or
`scx.service` stops running.

### Optional Tool Missing On Arch/CachyOS

If `install_benchmark_deps.sh` reports package errors such as:

```bash
error: target not found: hackbench
error: target not found: lmbench
```

that is a packaging issue, not a scheduler issue.

What happens now:

- the dependency installer only installs the official packages that exist on
  your system
- `benchmark.sh` checks tool availability before each benchmark
- if `hackbench` is missing, the script falls back to `sysbench`

## Quick Workflow

### 1. Install or Reinstall

```bash
sudo ./install.sh --force
```

Expected:

- binary builds and installs
- `scx.service` restarts
- installer reports an active scheduler

### 2. Check Current Health

```bash
./status_scx_flow.sh
```

Expected:

- installed binary
- installed version
- `scx.service state: active`
- `scx.service enabled: enabled`
- active scheduler matches `scx_flow` or `scx_flow_*`

### 3. Monitor Live Behavior

```bash
./monitor_scx_flow.sh
```

Expected:

- current scheduler shown at top
- `sched_ext state: enabled`
- `scx.service` active
- logs from the current service activation, not stale old runs

### 4. Run Smoke Test

```bash
sudo ./test_scx_flow.sh
```

Expected:

- uninstall works
- reinstall works
- `sched_ext state` is `enabled`
- active scheduler is `scx_flow_*`
- status helper reports active

### 5. Run Benchmarks

```bash
sudo ./install_benchmark_deps.sh
sudo ./benchmark.sh
```

Expected:

- required benchmark tools exist
- benchmark log file is created
- no service crash during benchmark run

If the benchmark stops with `command not found`, install benchmark dependencies
first and rerun. That result does not mean `scx_flow` failed.

### 6. Validate Hook Coverage

```bash
sudo ./validate_hooks_scx_flow.sh
```

Expected:

- `runnable()` shows non-zero activity under the wake-heavy test
- `cpu_release()` may or may not trigger depending on RT pressure timing, but
  the script shows whether it was actually exercised
- the monitor excerpt contains `runnable=` and `cpu_release=` fields from
  `scx_flow --monitor`

Use this when broad benchmarks look healthy but you specifically want to verify
that newer `scx` hooks are doing real work instead of just compiling.

### 7. Validate Lifecycle Coverage

```bash
sudo ./validate_lifecycle_scx_flow.sh
```

Expected:

- `init_task()` should go non-zero under short-lived task bursts
- `enable()` / `exit_task()` may stay zero depending on kernel behavior, and
  the script explains that distinction explicitly
- the output helps separate “optional lifecycle hook not exercised” from
  “task creation path is broken”

Use this when you want to verify lifecycle coverage after changing
`init_task()`, `enable()`, or `exit_task()`.

### 8. Run Latency-Stress Validation

```bash
sudo ./latency_stress_scx_flow.sh
```

Expected:

- creates a timestamped result directory in `latency-stress-results/`
- keeps only the newest three latency-stress result directories automatically
- runs a mixed-load phase with `cyclictest`, wake storms, and short-lived task churn
- runs an RT-interference phase when `taskset`, `chrt`, and `timeout` are available
- captures `scx_flow --monitor` output and writes a machine-readable summary env file

Use this when the broad benchmark looks good but you want a more adversarial
latency-focused check before claiming the scheduler is review-ready.

### 9. Run Scheduler Comparison

```bash
sudo ./mini_benchmarker.sh
```

Expected:

- it compares `baseline`, `scx_cosmos`, `scx_bpfland`, and `scx_flow` by default
- each scheduler gets its own raw benchmark log and summary file
- a comparison CSV, PNG, SVG, and Markdown report are generated
- only the newest three comparison result directories are kept automatically
- if one scheduler fails to activate, the run continues and saves diagnostics in
  `comparison-results/.../diagnostics/`

If you only want `scx_cosmos` vs `scx_flow`:

```bash
sudo ./mini_benchmarker.sh --schedulers "scx_cosmos scx_flow"
```

### 10. Generate Review Bundle

```bash
./prepare_review_bundle.sh \
  --comparison-dir ./comparison-results/<timestamp> \
  --hook-log /path/to/hook-validation.log \
  --lifecycle-log /path/to/lifecycle-validation.log
```

Expected:

- generates a concise Markdown bundle with the latest comparison snapshot
- includes optional hook/lifecycle validation maxima when those logs are provided
- automatically includes the newest latency-stress summary when one exists
- keeps the claims and the known limits in one review-friendly place

Use this when you want one artifact to share with senior engineers instead of
pointing them at multiple directories and terminal transcripts.

Note:

- the example intentionally avoids placeholder paths like `<latest-timestamp>`
  because shells such as `fish` interpret angle brackets as redirection syntax
  rather than literal text
- if you do want to pass a specific latency-stress summary manually, use a real
  path, not a placeholder token

## Fast Interpretation Guide

Use this table when reading terminal output:

| What you see | What it means | What to do |
| --- | --- | --- |
| `state = enabled` and `root/ops = scx_flow_*` | Scheduler is healthy and active | Keep testing |
| `scx.service` is `active (running)` | Service is healthy right now | Keep monitoring |
| Old `invalid CPU ...` lines in older logs | Historical failure from a previous run | Ignore if current run is healthy |
| `cyclictest: command not found` | Missing benchmark dependency | Run `sudo ./install_benchmark_deps.sh` |
| `error: target not found: hackbench` | Arch/CachyOS package mismatch, not scheduler failure | Let the script use its fallback path |
| `state = disabled` or empty `root/ops` | Scheduler is not active | Reinstall or inspect logs |
| Repeated service restart/fail loops | Current runtime failure | Check `journalctl -u scx.service -f` immediately |

## Scripts

### `install.sh`

Builds `scx_flow`, installs `/usr/bin/scx_flow`, writes `scx.service`, updates
`/etc/default/scx`, restarts the service, and fails if `scx_flow` does not
become active.

### `enable_scx_flow.sh`

Rewrites `/etc/default/scx` for `scx_flow`, restarts `scx.service`, and fails
if the active scheduler does not match `scx_flow`.

### `status_scx_flow.sh`

Shows the installed binary, version, service state, configured scheduler,
configured flags, and active scheduler.

### `monitor_scx_flow.sh`

Shows current scheduler state, a short `systemctl status`, and follows
`scx.service` logs from the current activation time.

### `reset_sched_ext_state.sh`

Stops `scx.service`, kills leftover scheduler processes, and waits for
`sched_ext` to become idle.

### `benchmark.sh`

Runs `cyclictest`, a throughput benchmark (`hackbench` when available, otherwise
`sysbench`), `stress-ng`, and `uptime`, writing results to a timestamped log
file. It also supports machine-readable summary output for automation.

### `validate_hooks_scx_flow.sh`

Runs targeted wake-heavy and RT-pressure checks while capturing
`scx_flow --monitor` output, so you can confirm whether `runnable()` and
`cpu_release()` are actually being exercised on your machine.

### `validate_lifecycle_scx_flow.sh`

Runs short-lived task bursts while capturing `scx_flow --monitor` output so you
can verify the task-creation and lifecycle-related hooks separately from the
broad benchmark suite.

### `mini_benchmarker.sh`

Runs multi-scheduler comparisons using `benchmark.sh`, generates a CSV summary,
PNG/SVG charts, and a Markdown report, and rotates old comparison result
directories so only the latest three are kept by default.

### `latency_stress_scx_flow.sh`

Runs a targeted mixed-load and RT-interference latency check against the active
`scx_flow`, writes timestamped logs and a machine-readable summary env file,
captures `scx_flow --monitor` output, and rotates old result directories so
only the latest three are kept by default. It also records kernel
`sched_ext`/`scx_flow` events from the run window so runnable-task stalls are
called out explicitly instead of being mistaken for a clean pass.

### `latency_stress_compare.sh`

Runs the same latency-stress workload against multiple schedulers, currently
useful for direct `scx_cosmos` vs `scx_flow` comparisons, and writes a small
Markdown report plus CSV summary so you can see whether a stall is specific to
`scx_flow` or reproduces across schedulers.

### `mini_benchmarker_plot.py`

Reads the summary env files written by `mini_benchmarker.sh` and renders the
human-friendly comparison artifacts.

### `prepare_review_bundle.sh`

Builds a compact review-facing Markdown summary from a comparison result
directory and optional validation logs.

### `install_benchmark_deps.sh`

Installs the benchmark tools that are available from the local official package
repositories and leaves unsupported optional tools to graceful fallback logic in
`benchmark.sh`. It also installs `python-matplotlib` for chart generation.

### `test_scx_flow.sh`

Runs an uninstall/install cycle and prints only kernel log entries from the
current test window.

## Notes

- Active scheduler checks use `/sys/kernel/sched_ext/root/ops`.
- Your kernel may report the active scheduler as a fully qualified name such as
  `scx_flow_1.0.0_x86_64_unknown_linux_gnu`; that is still correct.
- `scx_flow` is currently experimental. Treat these scripts as validation tools,
  not proof of production readiness.
