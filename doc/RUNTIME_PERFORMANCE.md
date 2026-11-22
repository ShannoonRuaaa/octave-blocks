# Runtime metadata and measured performance

Runtime initialization now prepares immutable graph metadata after validation
and flattening. The cache contains input-source indices in port order, algebraic
loop membership, normalized conditional options, interface indices and flow/clock
classification. Evaluation reuses these descriptors instead of repeatedly
normalizing the same child configuration and searching the edge table.

The cache does not contain input values, state, guard values, candidate outputs
or dynamic signal shapes. Finite-value, derivative-shape, conditional output
shape and control checks still run. New initialization rebuilds metadata from
the validated graph. Reinitialize after model/parameter/settings changes;
mutating a runtime's implementation fields is not a public editing API.

Missing or unknown-version metadata uses the legacy validation/classification
path. Same-version cache contents are trusted implementation data, not a
general corruption-repair format. Compatible checkpoints preserve the cache as
ordinary structs/cells; the interpreter keeps no persistent/global process
cache of model data. Its only persistent values are constants of the code or
the Octave installation: a copy of `odeset`'s default record, the
Dormand–Prince coefficient tables and Octave-version flag of
`ob_dormand_prince`, and the context field list that `validate_context`
checks (see below). Two front ends outside the interpreter do keep session
state: `ob_accelerate` remembers exports by a digest of the model and its
settings (`clear ob_accelerate` forgets them; see
[CODEGEN.md](CODEGEN.md#accelerated-simulation)), and `ob_simulink` keeps its
registry of open systems. The
metadata regression strips caches recursively, saves/loads the legacy context,
and compares complete future contexts after removing metadata from both sides.
Internal input-table isolation tests also retain finite/shape failure rollback.
See [RUNTIME.md](RUNTIME.md) for the public context contract.

## Interpreter hot paths, second pass (2026-11-21)

A second profiling pass started from the first pass's code (next section). It
found that most of the remaining time was function-call and statement
overhead, not arithmetic. Each Octave statement that calls a builtin costs a
few microseconds, and a call to an m-file function costs more. Every
right-hand side made four to six such calls before reaching the block
expressions. The changes below remove that overhead. Every value, solver step
and right-hand-side call stays the same, in the same order.

- **ode45 without per-call option handling.** Octave's `ode45` runs
  `odedefaults`, `odeset` (an `inputParser`), `rmfield` and `odemergeopts`
  (`validateattributes`) on every call. That is about 5 ms once per solver
  segment, which dominated adaptive runs with short output intervals.
  `private/ob_dormand_prince.m` is the same algorithm, written out for the
  one configuration the engine uses: a two-element time span, double scalar
  tolerances, no events, mass matrix or NonNegative, normal error control and
  Refine 1. It uses the same expressions as `ode45`, `starting_stepsize`,
  `integrate_adaptive` (with its Kahan time sum), `runge_kutta_45_dorpri` and
  `AbsRel_norm`, in the same order and with the same operand shapes. So it
  gives the same bits, calls the right-hand side with the same arguments in
  the same order, and passes accepted steps to the flow monitor exactly as
  the `OutputFcn` did. It omits the `OutputFcn` 'init' and 'done' calls,
  which the engine's monitors ignore. It keeps `integrate_adaptive`'s
  warning and error texts. It is used only on Octave 11.3.0 (the version
  reproduced here) and when `reltol`, `abstol` and the step bound are doubles.
  Anything else calls `ode45` itself, and `ode15s` is unchanged. A BIST
  compares it with `ode45` on nonlinear systems, including a monitor stop.
- **Evaluation program.** When the engine prepares a context it passes its
  execution order to `ob_prepare_runtime_model`. For models without algebraic
  loops, conditional bodies, Rate Transitions or unknown blocks, the plan
  then carries `plan.program`, which splits that order into groups:
  - state outputs, copied first;
  - input-free Constant and Time blocks, assigned next;
  - Scope, Inport and Outport blocks that nothing reads, copied last;
  - all remaining blocks, as slots with their codes and sources.

  `private/ob_program_eval.m` evaluates the program with `ob_runtime_eval`'s
  block expressions. Saturation, Dead Zone and Switch bodies are inlined for
  finite real double scalar inputs; any other input goes to
  `ob_control_output`. None of the grouped blocks can fail, so errors come
  from the same block with the same message. `ob_runtime_eval` uses the
  program whenever the plan has one. It does not compare `order` with the
  program's order, because that comparison cost as much as the evaluation
  saved. Every caller passes its context's order, and for these acyclic
  graphs any topological order gives the same values. The plan keeps the
  dispatch loop of the first pass for everything else. Contexts saved
  before programs existed (a v1 plan without `program`) take that loop and
  give identical results.
- **Direct program calls in the hot loops.** The engine's single-hit step and
  accepted hits, the RK4 stages, the adaptive right-hand side, flow segments
  and every zero-crossing search evaluation look up the program once per call
  and call `ob_program_eval` directly. They skip `ob_runtime_eval`'s argument
  defaults and cache checks.
- **One-call RK4 step.** For flat scalar double states with a program,
  `packed_rk4` makes the whole RK4 step in one call. It inlines the
  derivative checks for finite real double scalars. Any other derivative takes
  the original per-integrator checks and cell arithmetic for that stage, so
  errors are reported as before.
- **Zero-crossing snapshots and searches.** With a plan, `ob_zc_snapshot`
  computes the regimes, guard values and descriptors of guards with finite
  real double scalar inputs directly, without calling `ob_control_output`.
  That function's checks pass for such inputs, and it still runs to report a
  nonfinite output. Such a snapshot, with no conditional block, is *simple*:
  its layout depends only on the model. The search therefore skips layout
  checks between two simple snapshots of one call, and compares their regimes
  by their scalar modes. Comparisons with event memory from earlier calls keep
  the full checks.
- **Transport Delay.** Evaluators call `private/ob_delay_output.m` directly,
  without `ob_transport_delay`'s operation switch. That switch now tests
  'record' first, since records are its most frequent remaining operation.
  Delay records and boundaries read the plan's source map and parameters.
- **Engine step.** `advance` inlines its time and plan checks.
  `validate_context` keeps its constant field list in a persistent variable.

### Second-pass method

Bit identity was checked against a reference tree built at the same moment as
the measured tree. The reference is a snapshot of the repository with every
file of this track replaced by its start-of-round version plus the event-record
fix. Both trees therefore contain the same concurrent edits of the other
tracks:

- **Benchmarks.** All nine benchmark cases were fingerprinted with
  `benchmark_ob_engine`'s deep walk, on full grids.
- **Wider capture.** 476 configurations were run as `ob_run` and as stepwise
  contexts: every example with six solver variants, the benchmark models,
  adversarial classes and shapes, and every conditional and nested-reset
  reference model. 467 checkpoints saved by the reference tree (plans
  without a program) were also resumed in both trees. All results were compared with `isequaln`.
- **Tests.** `test_ob_runtime_fast_paths` also checks that a plan without its
  program gives identical contexts, and that the inline control outputs
  report `ob_control_output`'s errors.

Timings interleave the pre-speed tree, the first-pass tree and the new tree in
one Octave process (`benchmark_ob_engine` with three sources).

### Second-pass results

The final measurements were made after review, with the final code. They
use two to four interleaved rounds, so each median has four to eight samples
per version and case. The event-order fix of that review changes no benchmark
path.

- **Run D**, three versions. `benchmark_ob_engine` with the pre-speed tree,
  the first-pass tree and the new tree, two rounds of the order 1 2 3 3 2 1
  (four samples per version and case):

  | Case | Steps | Pre-speed | First pass | New | New vs first pass | New vs pre-speed |
  | --- | ---: | ---: | ---: | ---: | ---: | ---: |
  | oscillator_rk4 | 2000 | 10.73 s | 3.43 s | 2.81 s | 1.22 | 3.81 |
  | oscillator_ode45 | 1000 | 13.74 s | 5.44 s | 2.81 s | 1.94 | 4.89 |
  | dde_rk4 | 600 | 10.35 s | 4.25 s | 3.66 s | 1.16 | 2.83 |
  | dde_ode45 | 464 | 8.03 s | 4.08 s | 2.93 s | 1.39 | 2.74 |
  | mackey_rk4 | 3000 | 37.55 s | 19.42 s | 16.04 s | 1.21 | 2.34 |
  | mackey_ode45 | 2059 | 29.67 s | 17.63 s | 13.88 s | 1.27 | 2.14 |
  | control_zc_ode45 | 1000 | 23.01 s | 10.95 s | 7.84 s | 1.40 | 2.94 |
  | conditional_rk4 | 0 | 6.86 s | 4.30 s | 4.50 s | 0.96 | 1.52 |
  | linear10_rk4 | 1000 | 7.77 s | 3.47 s | 2.94 s | 1.18 | 2.65 |

  The geometric means are 1.28 against the first pass and 2.74 against the
  pre-speed tree. The first pass itself measured 2.14 against the pre-speed
  tree in this run.
- **Run E**, this track's changes alone. The reference tree is the same
  repository snapshot with this track's files at their start-of-round
  versions plus the event-record fix, so both trees hold the same concurrent
  edits of the other tracks. Three rounds, six samples each. Per case: 1.25,
  1.98, 1.17, 1.41, 1.19, 1.39, 1.44, 1.01 and 1.18, with a geometric mean
  of 1.31.
- **Run F**, `conditional_rk4` alone, four rounds (eight samples each) of the
  same-snapshot reference, the first-pass tree and the new tree. Medians:
  4.45 s, 4.12 s and 4.26 s. The new tree is 1.05 against the reference and
  0.97 against the first pass.

`conditional_rk4` is unchanged by this pass. Its ratios (0.96, 1.01, 1.05 and
0.97 above) scatter around 1.0 by about as much as its samples do, which
ranged from 3.3 s to 6.1 s in run F. Its model has a conditional body, so it
gets no evaluation program, and its time goes to code this pass did not
change (see the limits below). An earlier one-round run before review had
reported 1.10 for it. That figure was noise.

Bit identity:

- Eight cases were bit-identical to both earlier trees in run D.
- `conditional_rk4` gives the same `result.values`, output times, events and
  step count as the first-pass tree. Its fingerprint differs only because the
  conditional state snapshots in `flat_values` carry five fields that Track
  F1 added concurrently (`gating`, `initial_outputs`, `output_shaped`,
  `reset_due`, `shapes_probed`). The same-snapshot reference has the same
  fingerprint as the new tree (runs E and F).
- In run E all nine cases were bit-identical, with a maximum relative
  difference of 0.
- The 476-configuration capture gave 952 of 952 results identical: 476
  `ob_run` results and 476 stepwise contexts, including 18 identical expected
  errors. 467 of 467 checkpoints saved by the reference tree (plans without
  a program) resumed identically. After the event-order fix, the same capture
  was repeated with and without that fix and again gave 952 of 952 identical
  results.
- The test suites give the same verdicts as before. The golden fingerprints
  in `test_ob_runtime_fast_paths` still pass, including the eight
  environment-gated ode45 and BLAS cases.

The largest gains are in the adaptive cases, which no longer pay `ode45`'s
option handling per segment, and in `control_zc_ode45` (zero-crossing
snapshots and layout checks). Fixed-step cases gain 1.15–1.25: each RK4 step
still runs five model evaluations of a few interpreted statements per
block.

Simulink's warm `sim()` timings were recorded on this machine at another time
(`simulink-benchmark-reference.json`). Against them, run D's new times are
25–35 times slower for the oscillator, delay, conditional and linear cases,
55 times for `control_zc_ode45` and 131–142 times for Mackey-Glass. Before
this round the range was 34–190.

Earlier runs before review, with one or two rounds, gave geometric means of
1.29–1.31 against the first pass and 2.55–2.74 against the pre-speed tree.

### Second-pass limits

- All runs shared the machine with other tracks' work. Only the interleaved
  ratios carry meaning. Individual samples varied by up to about 1.8 times
  within one run.
- `ob_dormand_prince` reproduces Octave 11.3.0's `ode45`. On another Octave
  version the engine calls that version's `ode45`, so results follow its
  implementation, as before.
- The evaluation program covers models without algebraic loops, conditional
  bodies or Rate Transitions. Inside conditional models, it covers the child
  contexts whose bodies qualify. Other models keep the first pass's dispatch
  loop.
- Conditional bodies are not faster. A profile of `conditional_rk4` over 501
  outputs (1.05 s) shows where the time goes:
  - the body itself, 0.39 s: `ob_conditional_eval` (Track F1's code),
    including its child context's engine call;
  - the statements of the engine's `advance` and `process_hits`, 0.23 s;
  - `ob_runtime_eval`'s dispatch loop and conditional branch, 0.16 s;
  - `ob_continuous_paths` (0.10 s) and the integration endpoint refresh
    (0.06 s). Both run every step although the model has no continuous
    state, and about half of their time is the descriptor validation of
    `ob_runtime_execution`.

  Validating each descriptor once per step and sharing it between these
  callers would remove part of that time. It would need care to keep the
  fallback for invalid cached descriptors that the tests check.
- Other remaining costs: five evaluations per RK4 step with per-call setup,
  Transport Delay interpolation and history records, zero-crossing snapshots
  (built on every search sample) and `ob_run`'s per-output loop.

## Interpreter hot paths (2026-11-21)

Profiling showed that interpreter overhead, not numerics, dominated: a 4-block
oscillator spent about 3.4 ms per RK4 step on a quiet machine, mostly on cache
validation, string dispatch, struct indexing, `isequal`, `ismember` and
`odeset` calls repeated at every solver stage. The changes below remove that
overhead without reordering any arithmetic.

- `ob_prepare_runtime_model` adds an optional `runtime_info.plan`: numeric
  dispatch codes per block, the model's own index lists (`*_blocks`, named
  apart from the optional `*_ids` category fields so tools that strip or
  corrupt those cannot half-fill it), its own copies of the source map, loop
  map and block parameters, resettable Limited Integrators and a `lite` flag.
  The plan is self-contained, so stripping other cache fields cannot leave it
  half-usable. Hot paths trust it only when `runtime_info.kind` is
  `octave-blocks-runtime-info-v1`. Without it (older checkpoints), or in a
  cache of another kind even if that cache has a `plan` field, they use the
  general validated paths. Block values are still read live.
- `ob_runtime_eval` dispatches on the codes. Gain, Sum, Scope/Inport/Outport,
  Product, Constant, Time and Step are evaluated inline, with the same
  input-count messages as before. State outputs (Integrator, Unit Delay,
  Discrete Integrator) are assigned together, because the execution order
  already puts each one before its readers.
- `advance` has a single-hit step for models without clocks, discrete or
  conditional blocks, resettable integrators, zero crossings or unlearned
  delay shapes. For those models the general loop makes one integration and
  one hit, and the hit's only effects are the output evaluation, the delays'
  right-limit records and the time update. The single-hit step does exactly
  that, in the same order.
- Flat RK4 and adaptive segments without limits pack scalar double states
  into vectors. Element-wise IEEE operations give the same bits as the
  per-integrator scalar expressions. Derivative checks run vectorized first.
  If one fails, or a value is not a finite full double scalar, the
  per-integrator checks run instead and report the same first error. Any
  other state keeps the cell path.
- `private/ob_ode_settings.m` builds `odeset` records from a persistent copy
  of `odeset ()`'s default record. Its field set and order match `odeset`, as
  a BIST checks. This avoids about 2.5 ms of `inputParser` work per segment.
  It was the only persistent value after this pass. It is a constant of the
  Octave installation, not model data; the second pass added two more such
  constants (see the top of this file).
- Zero crossings: guard descriptors and regime records are first compared
  directly (`same_descriptors`, `same_flow`). Only a result that is not
  certainly equal falls back to `isequal`. Before this, `isequal` took about
  30% of `control_zc_ode45`. `ob_control_output` skips per-port conversion
  for finite full double scalars and uses `size_equal` for Switch shapes.
  `ob_zc_snapshot` reads the plan.
- Transport Delay output inlines its same-instant tests. Interior intervals
  compute both Hermite slopes with `slope ()`'s own expressions, sharing the
  middle difference quotient. `isequal` on rows and shapes is replaced by the
  equivalent `size_equal`/`==` test.
- `ob_model_inputs` uses `strcmp` instead of `ismember`. It passes complete
  signal records to `ob_input_signal` positionally, which skips that
  function's `ismember` field check while applying the same checks and
  errors. `unique ()` is skipped for boundaries that are already sorted.
  Parameter, type-index, source and continuous-path lookups read the plan.

### Method

`benchmarks/benchmark_ob_engine.m` runs the shared set in
`benchmarks/ob_benchmark_models.m`, either for one source tree or interleaved
over several. With two trees it alternates A/B/B/A and B/A/A/B rounds in one
Octave process. Before every run it clears functions, rebuilds the path,
asserts which `ob_run` is loaded and warms up on the first output times of the
same case. Each run is fingerprinted. The fingerprint holds every numeric and
logical value of `flat_values`, the output times, the integration steps and
the event times. Struct and cell values, such as conditional state snapshots,
are walked depth-first. A signature of the walked structure (classes, sizes,
field names and char values) is hashed with the values. By default the walk
leaves out fields named `runtime_info` and `options`, which conditional
snapshots carry inside their child contexts. They hold the prepared cache and
the normalized solver settings, which are configuration rather than results
and gain fields between versions (this track's `plan`, Track S2's
`accelerate`). The `ignore_fields` option changes the list. The report gives
median wall times, ratios, the geometric mean and whether the fingerprints
were bit-identical. For example:

```octave
addpath (fullfile (repo, 'benchmarks'));
report = benchmark_ob_engine ({baseline_tree, repo}, 'rounds', 2, ...
                              'output', 'engine.json');
```

`test_ob_runtime_fast_paths` checks the fast paths in three ways:

- **Golden fingerprints.** Several paths do not depend on the plan: the packed
  solver stages, the flat zero-crossing right-hand side, the scalar
  control-output path, the inlined Transport Delay interpolation, the guard
  comparisons, the held state outputs and the positional input records.
  Seventeen `ob_run` fingerprints recorded from the pre-change tree cover
  them. Nine RK4 cases use only element-wise IEEE arithmetic and are checked
  everywhere. The ode45 cases depend on the Octave version's step-size
  control, and the state-space case depends on BLAS. Those eight are checked
  only in the recording environment (Octave version, platform and BLAS
  configuration).
- **Packed against cell path.** A Limited Integrator with infinite limits and
  no reset evaluates the same arithmetic as an Integrator, but through the
  general cell path. The oscillator, delay and switched models are run both
  ways with RK4 and ode45 and must agree bit for bit. This check does not
  depend on the platform.
- **Plan against general paths.** The test steps 19 configurations with the
  plan and with it stripped. They cover flat and matrix states,
  single-precision derivatives, delays, resettable limited integrators, inputs,
  multirate clocks, multiple outputs, algebraic loops, zero crossings and
  conditional bodies. Complete contexts are compared with `isequaln`, and both
  variants must raise the same errors. Nine of the configurations are also
  stepped with three altered caches, which must give the same results:
  - a cache of an unknown kind with a foreign `plan` field;
  - a cache of an unknown kind with a real plan but no parameters;
  - a same-version cache whose non-plan source, loop, parameter and category
    fields are stripped.

### Results

The final code was measured after the review fixes. All nine cases ran over
their full output grids in two interleaved rounds, giving four samples per
version, and each was compared with the frozen pre-change tree:

| Case | Integration steps | Baseline median | New median | Speedup |
| --- | ---: | ---: | ---: | ---: |
| oscillator_rk4 | 2000 | 17.18 s | 6.18 s | 2.78 |
| oscillator_ode45 | 1000 | 18.39 s | 6.08 s | 3.03 |
| dde_rk4 | 600 | 7.79 s | 4.95 s | 1.57 |
| dde_ode45 | 464 | 11.51 s | 5.29 s | 2.18 |
| mackey_rk4 | 3000 | 41.54 s | 21.22 s | 1.96 |
| mackey_ode45 | 2059 | 34.54 s | 16.67 s | 2.07 |
| control_zc_ode45 | 1000 | 37.63 s | 13.25 s | 2.84 |
| conditional_rk4 | 0 | 11.89 s | 8.88 s | 1.34 |
| linear10_rk4 | 1000 | 13.32 s | 5.42 s | 2.46 |

The geometric-mean speedup was 2.18. An earlier full run, before the review
fixes, gave 1.99, with per-case speedups between 1.51 and 3.00.

All nine fingerprints were bit-identical, with maximum relative difference 0.
`conditional_rk4` needed one correction to the tool first. Its snapshots
first differed only in the child context's `runtime_info.plan` and
`options.accelerate` fields, so those configuration fields are now left out
(see Method). A rerun of that case with the corrected tool hashed 666,806
values, including its conditional snapshots, and was bit-identical, with a
speedup of 1.46.

### Limits

The machine was heavily loaded by concurrent work during both runs. Baseline
timings were 2–4 times slower than on a quiet machine (oscillator_rk4 ran in
6.86 s quiet), and samples of one version varied by up to a factor of 2.2
(control_zc_ode45 baseline: 24.0–48.5 s). Per-case ratios moved by up to 0.8
between the two runs (oscillator_ode45: 2.22, then 3.03). Only the
interleaved ratios carry meaning, and they are local measurements, not
guarantees. The baseline tree was frozen. The new side also contained the
other tracks' concurrent edits to conditional execution, `ob_run` and solver
options.

Several costs remained after this first pass:

- Octave's `ode45` calls `odeset` internally once per output interval, which
  bounded the adaptive cases. The second pass removed this (see above).
- Every solver stage still runs one interpreted statement sequence per block.
- `conditional_rk4` is dominated by conditional-body code and by
  `ob_input_signal`, which are outside these hot paths.

Further gains would need fewer evaluations per step, which would change
results (for example, user Function blocks with side effects would be called
fewer times), or compiled execution (see `ob_accelerate` in CODEGEN.md).

## Audited optimization measurements (2026-11-13)

Further profiling removed repeated immutable routing/category scans, duplicate
option normalization, interpreted cache-tag/shape comparisons, growing state
vectors and redundant output lookups. Optional category indexes retain legacy
fallbacks. Dynamic domains/shapes and public context validation remain checked.
The input lookup also preserves mixed numeric query and exact left-limit rules.

Interleaved ABBA/BAAB measurements in a single process, with functions cleared
between source versions, produced six samples per version/case:

| Workload | Baseline median | Optimized median | Change |
| --- | ---: | ---: | ---: |
| Sampled enabled, 101 outputs | 1.0361 s | .7414 s | 28.4% lower |
| Continuous enabled/events, 101 outputs | 2.2869 s | 1.7563 s | 23.2% lower |
| Primitive event, two outputs | .1828 s | .1642 s | 10.2% lower |
| Graph ordering, 10,000 blocks | .46164 s | .12999 s | 71.8% lower |
| 500 input queries, 100,000 rows | .03300 s | .02242 s | 32.1% lower |

Analytical outputs and counts remained 2/72/0, 2/102/0, and 1.25/2/1 for
output/integration-steps/events respectively. CPU medians corroborated the
runtime improvements. Small input-table cases had approximately 3–4% overhead
in this run, under .001 seconds per 500 queries. No universal gain is claimed.

Separate-process timings drifted substantially, so they were retained but not
used for these conclusions. See [OPTIMIZATION_AUDIT.md](OPTIMIZATION_AUDIT.md)
for corrected report claims, complete verification and limits, and
[benchmarks/README.md](../tests/benchmarks/README.md) for data and reproduction.

## Earlier cache integration measurements

Matched Windows/Octave 11.3 CLI measurements used one warm-up and the median of
three unprofiled runs for each model. All runs checked analytical outputs and
retained their integration-step/event counts. The final rerun measured:

| Model | Before cache integration | Final median | Final three runs |
| --- | ---: | ---: | --- |
| Sampled enabled, 101 outputs | 2.938 s | .903 s | .897, .924, .903 s |
| Continuous enabled with events, 101 outputs | 6.035 s | 2.221 s | 2.092, 2.221, 2.255 s |
| Primitive Switch event, two outputs | .318 s | .258 s | .231, .258, .281 s |

The outputs were 2, 2 and 1.25 respectively; accepted integration steps were
72, 102 and 2, with 0, 0 and 1 event records. Local system load and timing spread
matter. An earlier matched post-cache run measured 1.110, 2.850 and .344 s;
the small primitive case did not improve in that run. These are representative
local measurements, not a speed guarantee or an isolated attribution of every
gain to one code edit. Editor input/rendering has a separate benchmark in
[UI_PERFORMANCE.md](UI_PERFORMANCE.md).

Three profiled runs were used separately to identify costs, not as wall-time
speed measurements. In the sampled enabled model, execution-option normalization
calls fell from 4,986 to 252 and their self-time share from 17.4% to 2.0%.
For continuous enabled execution they fell from 9,015 to 342, with self-time
share changing from 15.9% to 1.2%. RHS evaluation counts stayed unchanged.

Retained reports:

- `<TEMP>/ob-runtime-cache-profile-e8977bdfa9c04b048f26df0a79590008.txt`
- `<TEMP>/ob-runtime-cache-final-97bb3c98046644db9041a9a94be18b64.txt`

Further candidates include changing-layout descriptor matching and remaining
evaluator/graphics work. Stable-layout guard comparisons and several evaluator
scans were addressed in the audit above. Any further caching must retain
guard layout-change detection, input/value validation, external graphics
invalidation and checkpoint compatibility. The numerical/C and Qt regression
gates remain required when changing those boundaries.
