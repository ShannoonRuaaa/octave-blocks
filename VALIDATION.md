# Validation report

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
