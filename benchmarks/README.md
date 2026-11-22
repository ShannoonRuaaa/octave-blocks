# Benchmarks and measurements

The [shared engine benchmark set](#shared-engine-benchmark-set-2026-11-21) at the end
of this file is the current one. The sections before it record earlier
measurements.

## Optimization measurements (2026-11-13)

`optimization-20261113.json` contains the recorded timing samples, analytical
checksums, CPU times, integration steps and event counts used in
[OPTIMIZATION_AUDIT.md](../docs/OPTIMIZATION_AUDIT.md). Version 1 is baseline `8aeec48`;
version 2 is the optimized source. The baseline's benchmarked runtime, graph,
input and editor files also match the published `2ae43f3` release. Use that public
commit as the reproduction baseline; `8aeec48` identifies the original local
measurement checkout. The optimized production files on `codex/optimized-release`
are identical to the measured development version.

Three rounds alternate A/B/B/A and B/A/A/B, giving six samples for each version
and workload. The comparison scripts clear functions and assert the loaded
source path between versions. Runtime cases warm up before every timed run.
UI cases warm up both versions initially, create fresh hidden figures, and
exclude initial figure creation/drawing from each twelve-click measurement.

Use a fresh Octave process and two source directories. For example, in Octave:

```octave
baseline_source = '/path/to/baseline';
optimized_source = '/path/to/optimized';
output_directory = fullfile (optimized_source, 'validation-out');
run (fullfile (optimized_source, 'benchmarks', 'compare_runtime.m'));
```

Run `compare_ui.m` the same way under Octave's Qt GUI runtime. The figures are
hidden and cleaned up. For a focused runtime check, set `comparison_cases` to
a subset such as `{'sampled','input100000'}` before running the script.

For simpler measurements in separate processes, use
`benchmark_ob_optimizations(source, output_json, repetitions)` from the optimized
source directory. Separate-process wall times showed substantial drift on the
test machine, so the final report uses the interleaved measurements instead.
Avoid concurrent tests or benchmarks. Small differences and these few models
do not establish universal speed guarantees.

## PR #2 audit measurements

`pr2-audit-20261116-ui.json` retains all 36 same-process motion samples, their
order, source SHA256 hashes and summary. Version labels identify the exact
`39fc357` editor and the final working-tree editor. The candidate source hash
identifies the measured file independently of its later Git commit.

Use `benchmark_ob_editor_drag([10 40 100],12,1)` under Qt for these workloads.
For comparisons, load only the baseline `octave_blocks.m` from an isolated
directory, keep the shared benchmark/helper path available, close its figures,
clear functions and assert `which('octave_blocks')` whenever switching sources.
Use the recorded three ABBA/BAAB rounds, including each helper's warmup, rather
than comparing two long-running processes. Repeat with the updated source.
Capture every returned sample, including stalls. Small diagrams had overhead
in the recorded run; these measurements are not a universal gain claim.

`pr2-audit-20261116-codegen.json` records an isolated adjacency overlay comparison
and the printed sample precision. It shows an indexing improvement but no
material total generation gain. The overlay isolates indexing from the event,
input and UI changes; it does not benchmark the whole PR as one transformation.
See [PR2_AUDIT.md](../docs/PR2_AUDIT.md) for findings and measured scope.

## Shared engine benchmark set (2026-11-21)

[ob_benchmark_models.m](ob_benchmark_models.m) defines nine cases used by the
interpreter benchmark, the accelerator benchmark and the recorded Simulink
timings: `oscillator_rk4`, `oscillator_ode45`, `dde_rk4`, `dde_ode45`,
`mackey_rk4`, `mackey_ode45` (its production term is the `.m` Function
[ob_bench_mackey_term.m](ob_bench_mackey_term.m)), `control_zc_ode45`,
`conditional_rk4` and `linear10_rk4`. Run from the repository root after
`addpath (pwd ()); ob_setup ('tests');`, which puts this folder, `src/` and
`examples/` on the path.

### Interpreter

`benchmark_ob_engine (SOURCE)` times the nine cases for one source tree.
`benchmark_ob_engine ({TREE1, TREE2, ...}, 'rounds', N, 'output', FILE)`
interleaves any number of source trees in one Octave process: with two trees
each round runs them A B B A (B A A B in even rounds), with three or more in
the order 1 2 ... n n ... 2 1, clearing functions and rebuilding the
path before every run. Use several rounds: on a shared machine single-round
ratios moved by up to about 0.15 (`conditional_rk4` read 1.10 in one round and
1.01 over three).

Each run is fingerprinted. The fingerprint walks every numeric and logical
value of `flat_values`, including conditional snapshots, together with a
structure signature, the output times, the integration steps and the event
times. Fields named in `'ignore_fields'` (default `runtime_info` and
`options`, which are configuration) are left out. The report gives median wall
times, ratios, the geometric-mean speedup and whether the versions were
bit-identical.

Final measurements are in [RUNTIME_PERFORMANCE.md](../docs/RUNTIME_PERFORMANCE.md):
2.74x geometric mean against the engine before the speed work (2.1–4.9x per
case, 1.5x for `conditional_rk4`), 1.28x for the second pass over the first,
bit-identical results.

### Accelerator

`benchmark_ob_accelerator (repeats, FILE)` compiles each case into a fresh
temporary cache, reports export and compile time separately, interleaves
interpreted and accelerated runs (A B B A) and takes the median of `repeats`
warm accelerated calls. When `simulink-benchmark-reference.json` exists it
adds Simulink's recorded `sim()` times and the largest difference from
Simulink's outputs. Eight of the nine cases are accelerated
(`control_zc_ode45`, ode45 with zero crossings, stays interpreted), 66–261
times faster than the interpreter with identical results; see
[CODEGEN.md](../docs/CODEGEN.md#accelerated-simulation).
