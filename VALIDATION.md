# Validation report

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

The complete registered check set passed on `codex/event-c-integration` through
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
[benchmarks/README.md](benchmarks/README.md) for reproducible timing comparisons.

The isolated publication branch `codex/optimized-release`, based on `2ae43f3`
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
octave-cli --quiet --eval "addpath(pwd()); test_ob_c_event_inventory(); test_ob_event_codegen_cases(); test_ob_c_event_math('validation-out');"
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
