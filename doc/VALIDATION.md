# Validation report

## 0.3.0 command API review follow-ups — 2026-11-22

Same tree and tools as the entry below. A review of the integration found
three important issues and four minor ones, all in the command API, and all
are fixed:

- a sample-based Pulse Generator is now held at its `[SampleTime 0]` rate
- Mux and Demux signals whose shape differs from the declared width are reported
- Dataset handles resolve through the public `ob_simulink`
- enumerated values are stored with Simulink's spelling
- sample-based `PulseWidth` errors are given in samples
- the MinMax/Logical `Inputs` 1 wording in the docs is corrected

`reference_ob_simulink_api.m` was run again in MATLAB R2026b / Simulink 26.2
(no other MATLAB running, caches redirected). It adds the scenario
`followup`, and every earlier entry is identical. `test_ob_simulink_api`
(72 cases, with new checks) and `test_ob_simulink_api_reference` (199
checks, up from 193) pass. The sample-based pulse also ran in accelerator
mode with output identical to normal mode, and its C export compiled
standalone with strict C99 flags.

## 0.3.0 builders, analysis and Dataset output — 2026-11-22

Uncommitted working tree on top of `f93be06`, GNU Octave 11.3.0 on Windows
with its bundled GCC; PowerShell 7 was not available, so the stages below
were run directly in `octave-cli` and bash (no full `Run-Tests.ps1` run).

- New suites: `test_ob_nonlinear_builders` (44 Simulink cases, 19 strict C99
  builds and 19 accelerated runs), `test_ob_routing_builders` (119 checks,
  71 recorded cases, 13 C/accelerated cases) and `test_ob_analysis` (9
  groups; Simulink linmod/trim, step and sine traces; four C exports) passed.
  They are registered in `Run-Tests.ps1` (`builders` stage; `systems` for
  `test_ob_analysis`).
- API: `test_ob_simulink_api` 72 cases; `test_ob_simulink_api_reference`
  193 checks against `simulink-api-reference.json`, re-recorded by
  `reference_ob_simulink_api.m` in MATLAB R2026b Update 1 / Simulink 26.2
  (every previously recorded entry was identical; added: nineteen library
  paths, eleven `built-in/<BlockType>` paths, the `newnonlinear`,
  `newrouting` and `dataset` scenarios).
- C gate (bash replication of `Test-Codegen.ps1`): 240 cases compiled with
  `-std=c99 -O2 -Wall -Wextra -Werror`, 227 compared models including 18 new
  builder cases, worst scaled error 3.33e-16.
- Installed package: a tarball of the working tree without `tests/`,
  `tools/` and `.git` installed, loaded and described (`pkg describe
  -verbose`) under a temporary prefix; `which`/`help` found every new public
  function in the installed tree and no private helper or test; a builder
  model, `ob_bode` and a `Dataset` API run worked; unload removed them.
- Unchanged suites rerun because they use the command API:
  `test_ob_simulink_delay_integrator` (22 agree, 29 documented),
  `test_ob_simulink_conditional` (304 matched), `test_ob_simulink_extended`
  (75 agree, 3 known), `test_ob_continuous_controls` and `test_ob_accelerate`.

## Advanced package integration — 2026-11-22

All twenty required stages are covered by successful runs on the integrated
Octave package. Portable [evidence](../tests/validation/pr4/README.md) includes
machine-readable results, final source hashes, both runs' manifests and logs.

The initial full run on `84c458e` passed seventeen stages. Three failed at
MEX compilation because Windows' linker split a spaced scratch path. The
only code changes in `7cc42c7` fix the compiler's relative scratch paths,
restore its directory/environment and add a spaced-path regression. API,
accelerator, package and shared benchmark stages were rerun and passed.
Source hashes stayed unchanged within each run and all other code hashes
match between revisions. This was two-run coverage, not one uninterrupted
all-pass gate; original failures are retained in the evidence.

- Accelerator: 74 cases, worst scaled error 1.97e-16, including callbacks,
  unsupported-mode fallback, cache reuse, spaced paths, capacity retries
  and failures. The final cleanup emits harmless missing-path warnings for
  temporary loaded-cache directories removed during the test.
- Installed package: isolated install/load, API wrappers, simulation,
  acceleration, GPL notices in adaptive C, strict C99 compilation/execution
  and unloading passed. No user package registry was changed.
- C gates: codegen 222 compiled cases/209 compared models, worst scaled
  error 3.33e-16; combined 175; event 94/89; edges 7/6; hierarchy 17/13.
  Event/combined comparisons had worst scaled error 0. Input lookup and
  numeric formatting oracles passed as well.
- Qt editor, advanced block dialogs and exact event exports passed.
- API: 69 cases and 158 recorded reference checks. Conditional references:
  304 matches, worst absolute error 1.25011e-13. Extended references:
  75 agree and 3 known differences. Delay/Integrator: 22 agree and 29 known
  differences. Shared benchmarks: 4 agree, 5 known differences, with compiled
  runs working for the eight supported models.
- Engine, systems, performance regression, metadata audit and embedded
  regression stages passed. Historical timing claims were not remeasured.

The combined distribution is GPL-3.0-or-later with original MIT notices
retained. See [solver provenance and generated-code terms](LICENSING.md).

Sections are dated and kept as recorded, newest first. Limits stated in older
sections may since have been lifted; current scope and gaps are in
[COMPATIBILITY_GAPS.md](COMPATIBILITY_GAPS.md).

## Final gate — 2026-11-22

This gate ran on the final code of the interpreter speed work, the
accelerator, flat `ode45` and Transport Delay/Limited Integrator C export,
the conditional Outport and initial-trigger work, and the extended Simulink
references. Environment: GNU Octave 11.3.0 on Windows with its bundled GCC.
PowerShell 7 was not available, so the `Launch-Blocks.ps1 -SelfTest` steps
were replicated in bash: Octave suites in `octave-cli`, and for each C gate
Octave preparation, gcc compile, run, then Octave verification. MATLAB was
not run by the tests.

References: on the evening of 2026-11-21 (local time) the 13 MATLAB
producers other than `reference_ob_simulink_benchmarks.m` were rerun in one MATLAB R2026b Update 1
session; every regenerated JSON was identical to the checked-in file except
wall-clock timing fields. `simulink-benchmark-reference.json` is kept from its
own producer run, because its timings need a quiet machine. See
[REFERENCE_EVIDENCE.md](REFERENCE_EVIDENCE.md#live-simulink-references).

Simulink comparisons:

| Suite | Result |
| --- | --- |
| `test_ob_simulink_conditional` | 304 cases matched (worst 1.25e-13), 0 documented differences |
| `test_ob_simulink_extended` | 78 cases: 75 agree, 3 documented differences (deterministic Rate Transition transfer; Rate Transition with data integrity off under ode4 and ode45) |
| `test_ob_simulink_delay_integrator` | 22 agree, 29 documented differences |
| `test_ob_simulink_api_reference` | 158 checks |
| `test_ob_simulink_benchmarks` | 4 agree, 5 documented differences (delay interpolation, chaos, ode4 Step), interpreted and accelerated |
| `test_ob_delay_matlab` | Passed against MATLAB `dde23` |

Other Octave suites, each of which printed its pass message (see the note on
job exit codes below):

- Engine and editor core: `test_ob_run`, `test_ob_editor_core`,
  `test_ob_solvers`, `test_ob_subsystems`, `test_ob_inputs`,
  `test_ob_multirate`, `test_ob_controls`, `test_ob_runtime`,
  `test_ob_runtime_metadata`.
- Conditional, algebraic and event suites: `test_ob_conditional`, `test_ob_enabled_continuous`,
  `test_ob_enabled_multirate`, `test_ob_linear_systems`,
  `test_ob_matlab_numeric`, `test_ob_multioutput`, `test_ob_combined_controls`,
  `test_ob_nested_reset` (38 cases), `test_ob_algebraic`,
  `test_ob_zero_crossings`, `test_ob_continuous_controls` (rk4, ode45, ode15s).
  `test_ob_zero_crossings` now also covers continuous controls that reach zero
  exactly at a stop: one record at the stop, merged arrival/departure, touch
  records, and time-ordered records when a departure at the stop and a later
  crossing are found by one search.
- Performance: `test_ob_performance_graph`, `test_ob_performance_metadata`,
  `test_ob_performance_events` and `test_ob_runtime_fast_paths` (golden
  fingerprints from the engine before the speed work; packed solver stages
  against the general cell path; the prepared plan against the general paths;
  the evaluation program against a plan without it, with identical errors).
- Code generation audit: `test_ob_codegen_metadata`,
  `test_ob_codegen_adjacency`, `test_ob_builtin_controls`,
  `test_ob_transfer_builtin`,
  `test_ob_advanced_simulink`, `test_ob_c_event_inventory`.
- Blocks and API: `test_ob_delay_integrator` (65 cases), `test_ob_simulink_api`
  (69 cases).
- Accelerator: `test_ob_accelerate`, 72 cases. 54 models are compared field by
  field with interpreted runs (eight benchmark cases, 14 further flat rk4, 9
  ode45, 17 typed rk4, 5 with user Functions and a delay feedback model that
  needs a capacity retry); worst scaled error 2.0e-16, 0 for all rk4 models.

BIST files, all passed: `ob_execution_order.m`, `ob_edges.m`,
`ob_block_parameters.m`, and with the private folder on the path
`private/ob_zc_snapshot.m`, `private/ob_transport_delay.m`,
`private/ob_ode_settings.m` and `private/ob_dormand_prince.m` (bit-identical
to Octave 11.3 `ode45`, including a monitor stop).

C gates, all compiled with `-std=c99 -O2 -Wall -Wextra -Werror`:

| Gate | Compiled cases | Compared models | Worst scaled error |
| --- | ---: | ---: | --- |
| codegen | 222 | 209 | 3.3e-16 (10 ode45 models at tolerance 1e-9; the 199 others 0) |
| combined | 175 | 175 | 0 |
| combined advanced | 26 | 26 | 0 |
| event | 94 | 89 (769 channels) | 0 |
| event edges | 7 | 6 (30 channels) | 0 |
| event hierarchy | 17 | 13 (96 channels) | 0 |

The codegen gate includes 34 Transport Delay/Limited Integrator models (30 rk4,
4 ode45), Transport Delay overflow and in-place rollback harnesses, and ode45
step-failure and rollback tests. The Qt editor suites (`Test-Editor.ps1`,
including `test_ob_editor_advanced`) and the C input-lookup gate were run
separately and passed.

Job exit codes: the gate's `summary.txt` records exit status 1 for three of
its 18 jobs. The engine/editor-core job and the code-generation-audit job
printed a pass for every suite in their command lists and then stopped on a
call to a function that is not in those lists and needs arguments (the
fixture `test_ob_multi_function` and the generator `test_ob_c_event_math`).
The codegen C job exited after 9 seconds; its log, rewritten at 00:30 after
the summary (00:26), records the full pass given in the table above, and the
audit job's log was likewise rewritten after the summary. `test_ob_dmperm_order`,
in the audit job's list, prints nothing, so the log does not confirm it
directly (the suites listed before and after it printed their passes).

Performance on the final code:

- Interpreter (`benchmarks/benchmark_ob_engine`, interleaved, bit-identical
  results): 2.74x geometric mean against the engine before the speed work,
  2.1–4.9x per case except `conditional_rk4` (1.5x); the second pass added
  1.28x over the first. See [RUNTIME_PERFORMANCE.md](RUNTIME_PERFORMANCE.md).
- Accelerator (`benchmarks/benchmark_ob_accelerator`): 8 of the 9 benchmark
  cases are accelerated (`control_zc_ode45`, ode45 with zero crossings, stays
  interpreted), 66–261 times faster than the interpreter, scaled error 0
  against interpreted runs. See [CODEGEN.md](CODEGEN.md#accelerated-simulation).
- Against Simulink 26.2 (`simulink-benchmark-reference.json`): warm `sim()`
  0.10–0.14 s, Fast Restart 0.026–0.046 s. The interpreter is roughly 25–165
  times slower than warm `sim()` (32–165 in this gate's run, 25–142 in
  [RUNTIME_PERFORMANCE.md](RUNTIME_PERFORMANCE.md) run D; Mackey-Glass is
  the slowest case). Warm accelerated calls take 0.14–0.30 times
  Simulink's warm `sim()` time, except Mackey-Glass, whose `.m` Function is
  called back into Octave (about 2.2 times).

Timings come from a shared machine; only the interleaved ratios are
meaningful.

## Live Simulink parity — 2026-11-21

Simulink 26.2 (MATLAB R2026b Update 1) is installed and licensed. These
Octave tests compare against references recorded in MATLAB by the checked-in
`reference_ob_*.m` producers. All of those producers were rerun in a single
MATLAB session to create the checked-in JSON. The tests themselves do not run
MATLAB; see [REFERENCE_EVIDENCE.md](REFERENCE_EVIDENCE.md#live-simulink-references-2026-11-21).

- `test_ob_simulink_conditional()`: the recorded conditional, combined, nested-reset and probe traces, sample by sample. 186 cases match (worst 5.7e-14), plus 6 documented compatibility-mode differences.
- `test_ob_simulink_delay_integrator()`: 51 Transport Delay and Integrator models. 22 agree; 29 show an asserted, documented difference.
- `test_ob_simulink_api_reference()`: the command API against recorded Simulink behaviour, in 154 checks.
- `test_ob_delay_matlab()`: delay differential equations against MATLAB `dde23`.

The C export checks include 40 Simulink-probe C cases, compared with the
Simulink traces, and an API-built Switch/Gain model (`ob_simulink_codegen_case`).
Full gate for this change: 35 Octave suites, 5 BIST files and the 3 Qt editor
suites passed. Six C gates ran 388 strict C99 compilation/execution cases
(`-std=c99 -O2 -Wall -Wextra -Werror`), with worst scaled error 0 for every
compared model:

| Gate | Compiled cases | Compared models |
| --- | --- | --- |
| codegen | 168 | 158 |
| combined | 123 | 123 |
| combined advanced | 26 | 26 |
| event | 49 | 44 (398 channels) |
| event edges | 7 | 6 (30 channels) |
| event hierarchy | 15 | 12 (84 channels) |

The C input lookup gate passed 115,368 checks. PowerShell 7 was not
available, so the `Test-*.ps1` steps were replicated in bash: Octave
preparation, gcc compile, run, then Octave verification. The Qt editor's own
export-compile step was not run in this pass.

## Combined enable and trigger controls — 2026-11-17

The registered checks passed using separate numerical/C and desktop-enabled
Qt runs against unchanged hashes of 158 source and test files:

- 27 Octave suites and 25 BIST checks.
- 269 strict C99 compilation/execution cases: 247 numerical models, seventeen
  API harnesses and five helper executables. Worst scaled numerical error: 0.
- The new combined-control subset comprises 27 C models and 172 numerical
  channels, covering trigger directions, held/reset policies, separate
  continuous guards, matrix data and a nested clocked ancestor.
- The runtime subset passed with RK4, ode45 and ode15s, including continuous
  analytical traces, sparse/dense requests, lazy reset, rollback and checkpoint
  continuation.
- Desktop-enabled `Test-Editor.ps1` passed, including both exact Qt-exported C
  models. A separate combined-block Qt probe passed selection on every block
  part, three input ports and model save/load round-trip.

The restricted `Launch-Blocks.ps1 -SelfTest` run passed all numerical/C stages
but its final Qt child remained idle before test startup. That verified test
child was stopped; the supervisor correctly recorded failure. The complete
editor stage was run separately with desktop access and passed with exit 0.
This is **not an uninterrupted single-process full-gate pass**.
Afterward, only trailing empty lines were removed from the new C test runner
and fixture file; their 27-case C gate was rerun successfully. Production
source files remained unchanged.

Evidence is retained under `.validation-artifacts/combined-controls-20261117/`:
`full-gate.log`, `full-gate-result.json` (restricted Qt failure),
`editor-full.log`, `combined-editor.log`, `full-gate-source-hashes.json` and
`validation-result.json` (combined stage results). MATLAB environment evidence
and the independent reference harness limits are described in
[COMBINED_CONTROLS.md](COMBINED_CONTROLS.md). No live Simulink parity is claimed.

## Expanded built-in/library review — 2026-11-16

The final `Launch-Blocks.ps1 -SelfTest` completed uninterrupted with exit 0:
26 Octave suites, 25 BIST checks and 242 strict C99 cases. All 220 numerical
models matched Octave with worst scaled error 0; seventeen API harnesses and
five helper executables passed. New coverage includes 1,320 exact historical
graph comparisons, matrix-control and transfer-state checks, 4,123 bitwise
C-number round trips, and the existing 222,775 lookup oracles now exercising
standard `bsearch`. Broyden acceleration retains the original checked-Jacobian
fallback, successful-status requirement, fresh residual and conditioning checks.

The final source hashes were unchanged throughout verification. Logs and result
metadata are in `.validation-artifacts/builtin-audit-20261116/`; the final log
ends with `FULL_GATE_COMPLETED_SUCCESSFULLY`. An earlier run was intentionally
superseded before adopting the validated standard-library lookup adapter.
Final Qt artifacts: `<TEMP>/octave-blocks-editor-eee29f3da33f4bac98b7d562b7c98bc8`.
Expected throwing-listener errors and ill-posed algebraic test warnings occur
inside intentional failure tests; the registered recovery assertions passed.
See [BUILTIN_REVIEW.md](BUILTIN_REVIEW.md) for accurate recommendations, installed
library availability, conditional backend proposals and measured scope.

## PR #2 audit verification — 2026-11-16

The final `Launch-Blocks.ps1 -SelfTest` completed uninterrupted with exit 0.
All 23 Octave suites and 25 graph/edge/snapshot BIST checks passed. The
registered C gates compiled/executed 241 strict C99 cases:

| Gate | Numeric models | API/helper executables | Result |
| --- | ---: | ---: | --- |
| Existing supported exports | 157 | 10 APIs | Every channel matched; worst scaled error 0 |
| Main event export | 44 | 3 APIs, 2 math helpers | 398 channels matched; worst scaled error 0 |
| Independent event edges | 6 | 1 API | 30 channels matched; worst scaled error 0 |
| Nested hierarchy | 11 | 3 APIs | 76 channels matched; worst scaled error 0 |
| Exact Qt exports | 2 | 0 | 16 channels matched; worst scaled error 0 |
| Generated input lookup helpers | 0 | 2 helpers | 222,775 independent oracle checks passed |

That is 220 numerical models, seventeen API harnesses and four helper
executables. Compilation uses `-std=c99 -O2 -Wall -Wextra -Werror`; focused
input/math checks additionally passed `-pedantic`. New tests cover provider
argument combinations, unused-probe avoidance, activity masks, common metadata,
source/proxy ordering and nested discrete-only event export. Expanded Qt checks
cover native motion, external state writes, conservative fallback, reentrant
listeners, stale targets, dirty/Undo behavior and exact exported C. The labelled
intentional throwing-listener error is expected; recovery assertions passed.

Local evidence is in `.validation-artifacts/pr2-audit-20261116/`: `full-gate.log`
ends with `FULL_GATE_COMPLETED_SUCCESSFULLY`; `full-gate-result.json` records
exit 0 and unchanged sources; `source-hashes.json` records SHA256 fingerprints.
Each C stage prints its artifact directory. Final Qt artifacts:
`<TEMP>/octave-blocks-editor-75bdfe052e824215af2a7ec6dbffef44`.
This fresh run supersedes the earlier staged verification for the updated code.
See [PR2_AUDIT.md](PR2_AUDIT.md) for disputed findings, measurements and limits.

## Event-enabled C milestone — 2026-11-14

The complete registered check set passed on `development/event-c-integration` through
the public exporter. No production changes followed these checks.

| Check | Result |
| --- | --- |
| Octave numerical/editor-core suites | All 21 passed, including zero crossings, continuous controls and three optimization suites |
| Graph/edge/snapshot BIST | 9/9, 4/4 and 12/12 |
| Existing supported C exports | 167 strict C99 cases: 157 numeric models and ten API harnesses; worst scaled error 0 |
| Main event C gate | 45 cases: 43 numeric models, 392 channels, two API harnesses; worst scaled error 0 |
| Independent event edge gate | Seven cases: six numeric models, 30 channels, guard-overflow API; worst scaled error 0 |
| Nested hierarchy/event metadata gate | Fourteen cases: eleven numeric models, 76 channels, three API harnesses; worst scaled error 0 |
| Qt editor and exact generated sources | Retained graphics and actual Export C callbacks passed; two exact C exports, sixteen channels, worst scaled error 0 |

In total, 235 C cases compiled/executed with `-std=c99 -O2 -Wall -Wextra
-Werror`: 219 numerical models and sixteen API harnesses. New coverage includes
multi-level active/dormant ancestors, sampled/continuous mixes, state/output
policies, inherited Euler intervals, private source jumps, coincident clocks,
simultaneous guards, plateau memory, guard-subtraction overflow, chatter,
rollback/retry and independent instances. Qt tests use scoped dialog responses
to invoke the actual callback, including export from an inner view, cancellation,
option propagation and protected-file failures. This is callback-level Qt
verification, not a new native mouse/dialog inspection.

`Launch-Blocks.ps1 -SelfTest` ran through all numerical/C stages and Qt callbacks;
its execution handle became unavailable before a unified exit status or the
final Qt-exported C comparison was retained. The complete final `Test-Editor.ps1`
stage and explicit BIST were then rerun successfully with exit 0. The completed
checks establish the registered set; no uninterrupted full-command exit is
claimed for that first run. Local logs:

- `.validation-artifacts/event-c-20261114-full-gate.log`: main completed stages.
- `.validation-artifacts/event-c-20261114-final-stage-checks-v2.log`: final BIST
  and Qt/C stage, including both exact GUI exports. The first focused BIST
  invocation omitted the private-helper path; the successful rerun uses the
  same setup as the registered launcher.
- Earlier independent probes: `event-c-20261114-integration.log`,
  `event-c-20261114-edges.log`, `event-c-20261114-hierarchy.log` and
  `event-c-20261114-editor.log` in the same ignored directory.

Final Qt/C artifacts are under
`<TEMP>/octave-blocks-editor-44e692c07119424d9adabf7a79d218f7`.
Each C gate prints its own artifact directory in the main log. The public
support contract is [CODEGEN.md](CODEGEN.md); remaining advanced work and
reference limits are in [COMPATIBILITY_GAPS.md](COMPATIBILITY_GAPS.md).

## Optimization verification — 2026-11-13

The complete updated `Launch-Blocks.ps1 -SelfTest` passed: 21 Octave suites,
9 graph BIST, 4 edge-expansion BIST, 12 snapshot BIST, all 167 strict C99 cases,
and expanded Qt editor checks. Every channel of 157 compiled numeric models
matched Octave with worst scaled error 0; all ten C model API harnesses passed.

New tests cover old/unknown/partial metadata, exact historical graph/port order,
mixed numeric input queries and left limits, finite/shape failures and rollback,
and editor cache/dirty/graphics/wire behavior. The registered gate includes the
three `test_ob_performance_*` suites. The public event-export guard remains.

The local full-gate/BIST logs are in
`.validation-artifacts/performance-audit-20261113/`. C artifacts:
`<TEMP>/octave-blocks-codegen-a7307632e8f0436e9225ce7e064e689e`; Qt log:
`<TEMP>/octave-blocks-editor-fc58d1bebb2f48548702f9e0439b0918/editor.log`.
See [OPTIMIZATION_AUDIT.md](OPTIMIZATION_AUDIT.md) for measured results and
[benchmarks/README.md](../tests/benchmarks/README.md) for reproducible timing comparisons.

The isolated publication branch `development/optimized-release`, based on `2ae43f3`
without the experimental C event-runtime changes, passed a fresh complete
`Launch-Blocks.ps1 -SelfTest` run with exit 0. This independently repeated all
21 suites, 25 BIST checks, 167 C cases and the expanded Qt editor checks; the
157 numerical models again had worst scaled error 0. Its local log is
`.validation-artifacts/optimization-publication-full-gate.log`; C artifacts:
`<TEMP>/octave-blocks-codegen-3ea941b1f7994c4fb328e6a595594de5`; Qt log:
`<TEMP>/octave-blocks-editor-6be2221a4eaa419cba4fa7f12428e4e6/editor.log`.

## Release verification — 2026-11-11

The documented, implemented feature set passed the complete application gate on
Windows with GNU Octave 11.3.0, GCC 15.2.0, and PowerShell 7.6.9. The supplemental
checks and live editor checks below also passed. This validates the exercised
cases; it does not establish full Simulink compatibility or every possible model.

## Results

| Check | Result |
| --- | --- |
| Full application gate: `Launch-Blocks.ps1 -SelfTest` | Exit 0; all 18 Octave suites, compiled-C checks and Qt editor checks passed |
| Supported C exports | 167 strict C99 compilation/execution cases: 157 numeric models and 10 API harnesses |
| C numerical comparison | Every exported numeric channel compared with Octave; worst observed scaled error 0, acceptance tolerance less than 1e-11 |
| C API behavior | Independent instances, external inputs, failures, retries, nested state, pending updates, clock timing and rollback passed |
| Supplemental C event inventory | `test_ob_c_event_inventory()` passed |
| Event-export analytical references | All 43 Octave fixture checks passed; two future C API specifications retained |
| Isolated event-math helper | Fresh populated and empty C harnesses compiled with warnings as errors and passed |
| PowerShell syntax | All four project PowerShell scripts parsed without errors |
| Live editor | Label/port selection, drag and wire updates, Undo, settings inspection and Run observed successfully |

C compilation used `-std=c99 -O2 -Wall -Wextra -Werror`. The event-math
harnesses test an unintegrated helper, separately from the 167 supported-export
cases. They do not prove event-enabled model export.

## Feature coverage

Each suite below passed in this run.

| Functionality exercised | Suite |
| --- | --- |
| Sources, finite values, matrix arithmetic, state and shortened final interval | `test_ob_run` |
| Connections, validation, editing, persistence and legacy model files | `test_ob_editor_core` |
| RK4, ode45, ode15s, stiff decay, discontinuities and matrix states | `test_ob_solvers` |
| Nested virtual subsystems and numbered ports | `test_ob_subsystems` |
| Root inputs, ZOH/linear interpolation and endpoint holds | `test_ob_inputs` |
| Independent rates, offsets, simultaneous updates and rate transitions | `test_ob_multirate` |
| Saturation, Dead Zone, Switch and matrix/equality cases | `test_ob_controls` |
| Resumable execution, independent copies, checkpoints, output reads and rollback | `test_ob_runtime` |
| Immutable metadata cache and legacy fallback equivalence | `test_ob_runtime_metadata` |
| Sampled enable/trigger modes, lazy initialization and state/output policies | `test_ob_conditional` |
| Joint parent/child continuous states, coupling and pause/reset | `test_ob_enabled_continuous` |
| Globally phased inner clocks, nested inactivity and skipped hits | `test_ob_enabled_multirate` |
| State-space and proper SISO transfer-function builders | `test_ob_linear_systems` |
| Recorded MATLAB builtin numeric comparisons | `test_ob_matlab_numeric` |
| Multiple Function returns, routing, hierarchy and shapes | `test_ob_multioutput` |
| Supported smooth algebraic components, convergence and rejection paths | `test_ob_algebraic` |
| Primitive guard localization, event history, solver cases and rollback | `test_ob_zero_crossings` |
| Continuous enable/trigger timing, plateaus and clock isolation | `test_ob_continuous_controls` |

`Test-Codegen.ps1` generated, compiled, executed and compared the supported C
models. `Test-Editor.ps1` exercised actual Qt callbacks, retained graphics,
selection ownership, drag/undo behavior and Run, including the continuous-control
example. The fixtures named `test_ob_multi_function.m` and
`test_ob_inner_clock_c_cases.m` are consumed by other suites; they are not
additional independent test suites.

In a fresh visible editor, clicking the Gain label highlighted its box; clicking
Time's output port selected Time. Dragging Gain moved its incident wires, and
Undo restored the diagram and cleared the unsaved marker. The settings dialog
displayed solver, tolerance, maximum-step and zero-crossing fields. Running the
default Time → Gain(2) → Scope model displayed the expected ramp from 0 at time 0
to 20 at time 10.

## Reproduce

Run the complete gate from the repository folder with PowerShell 7:

```powershell
./Launch-Blocks.ps1 -SelfTest
```

The launcher discovers standard Windows Octave installations. Supply
`-OctaveHome 'C:\path\to\Octave-11.3.0'` when needed. C checks require a C99
compiler; the scripts default to Octave's bundled GCC. The GUI checks require Qt
and run separately from the numerical CLI tests.

For supplemental checks, put the installed Octave/GCC bin directory on PATH and
run these commands from the repository folder:

```powershell
octave-cli --quiet --eval "addpath(pwd()); ob_setup('tests'); test_ob_c_event_inventory(); test_ob_event_codegen_cases(); test_ob_c_event_math('validation-out');"
gcc -std=c99 -O2 -Wall -Wextra -Werror validation-out/event_math.c -o validation-out/event_math.exe
./validation-out/event_math.exe
gcc -std=c99 -O2 -Wall -Wextra -Werror validation-out/event_math_empty.c -o validation-out/event_math_empty.exe
./validation-out/event_math_empty.exe
```

The helper writes standalone checks for the generated event-math operations.
`validation-out/` is ignored by Git. All commands must succeed; emitting source
alone is not a passing compiler or runtime test.

## Evidence retained locally

The scripts retained these artifact directories under the test machine's
temporary directory. They are not included in the repository:

- `<TEMP>/octave-blocks-codegen-c3937bfda51c438782dcc5aca5faf3b9`: generated C, expected/actual CSV traces, executables and manifest.
- `<TEMP>/octave-blocks-editor-df4bdf7403cf45a89115e1c67a7a58de`: Qt editor log.
- `<TEMP>/octave-blocks-supplemental-46bf057316f940e4944604eaabc82f5f`: fresh event-math C/executables and supplemental Octave log.

## Known limits and experimental work

- Event-enabled and continuous-control C model export remain unsupported and
  explicitly rejected before replacing an existing output file.
  `Test-EventCodegen.ps1` is an experimental future integration runner; its
  model exports and two event API harnesses have not passed compilation or
  execution. The 43 analytical fixtures run in Octave.
- Generated models use the supported static, real-double RK4 subset. Adaptive
  solver emission, arbitrary Octave-function translation, algebraic-loop C
  emission and deployment targets remain unfinished.
- The algebraic solver supports the smooth fixed-shape numeric components
  documented in [ALGEBRAIC.md](ALGEBRAIC.md), not general implicit DAEs.
  Automatic sample-time propagation, broader subsystem variants, additional
  signal types/toolboxes and Simulink model-file import/export remain gaps.
- Recorded MATLAB R2026b Update 1 results cover 26 single-output mappings,
  15 two-output cases, signed zero and rounding ties. This run checked the
  retained reference; it did not run a fresh MATLAB or Simulink comparison.
  The installed environment lacks a runnable Simulink engine.
- Event search needs an appropriate maximum step for oscillatory or multiple
  crossings. Custom functions must be deterministic; their external side
  effects cannot be rolled back.
- A Run is synchronous. Historical performance measurements in the performance
  documents are local measurements, not fresh benchmarks or universal guarantees.

See [CODEGEN.md](CODEGEN.md), [CONTINUOUS_CONTROLS.md](CONTINUOUS_CONTROLS.md),
[REFERENCE_EVIDENCE.md](REFERENCE_EVIDENCE.md) and
[ADVANCED_PLAN.md](ADVANCED_PLAN.md) for precise contracts and remaining work.
