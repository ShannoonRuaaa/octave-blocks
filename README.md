# Octave Blocks

An Octave-native block diagram editor and evaluator. Function blocks call ordinary
`.m` functions on Octave's path with `feval`, so block logic uses Octave's language.

The project is available under the [MIT license](LICENSE). See
[VALIDATION.md](docs/VALIDATION.md) for the latest verification results, reproduction
commands, and known limits. This is an experimental independent implementation;
full Simulink compatibility remains unfinished.

Requires GNU Octave with the Qt graphics toolkit for the editor. Verified on
GNU Octave 11.3.0 on Windows. The numerical engine also runs without the GUI.

On Windows, launch directly from PowerShell 7:

```powershell
./Launch-Blocks.ps1
./Launch-Blocks.ps1 -SelfTest
```

The launcher finds installed Octave in the standard per-user or Program Files
GNU Octave folders. Supply `-OctaveHome 'C:\path\to\Octave-11.3.0'` for another
installation. On the first GUI launch, Octave may show its welcome wizard.

In Octave, put the project on the path with `ob_setup` from this folder, then
run `octave_blocks` for the editor:

```octave
addpath ('/path/to/octave-blocks');
ob_setup ();            % src and examples
octave_blocks ();
```

`ob_setup ('simulink')` also adds the Simulink-named commands (see below),
`ob_setup ('tests')` adds the tests, benchmarks and tools, `ob_setup ('all')`
adds everything, and `ob_setup ('remove')` removes the folders it added. See
[Project layout](#project-layout) for what each folder holds.

The editor's initial diagram is Time → Gain → Scope. Click a block face, label, port, or port
number to select its box; drag it to move. Box edges have a small click tolerance.
Add blocks with the buttons, then click **Connect** and click source and
destination blocks. **Disconnect** removes a connection by the same two-click
sequence. The editor prevents duplicate connections and reports full inputs.
**Edit** changes the selected block's parameter. **Settings**
sets simulation start, stop, output interval, solver, and error tolerances.
Choose `rk4` for fixed-step simulation, `ode45` for adaptive nonstiff simulation,
or `ode15s` for stiff ODEs. **Run** plots scalar, vector, and
matrix signals through Scope blocks and places the complete result in the
Octave workspace as `ob_last_result`. If the fixed step does not divide the
simulation interval, the last step is shortened to reach the exact stop time.
**Oscillator** loads a continuous feedback example. **Save** and **Load** use a
MATLAB-compatible `.mat` file.
Files are Octave Blocks models; they are not Simulink `.slx` or `.mdl` files.
**New** starts a blank diagram. **Undo** and **Redo** recover up to 50 edits,
including block moves, connections, parameters, settings, and diagram replacement.
An asterisk in the window title indicates unsaved changes; the editor asks before
discarding them. Undo history is kept for the current editor session.

**Subsystem** adds an editable subsystem containing Inport 1 → Gain → Outport 1.
Select it and use **Enter** to edit its contents; **Up** returns to its parent.
The status line shows the current path. **Edit** changes its name and execution
settings. Modes include virtual, enabled, rising/falling/either trigger, and combined enabled_rising/enabled_falling/enabled_either (see [combined controls](docs/COMBINED_CONTROLS.md));
conditional modes add a last control input and support held initial outputs.
Control timing defaults to sampled. Choose continuous in **Edit** and enable
zero crossings in **Settings** to locate gate events between output requests;
see [CONTINUOUS_CONTROLS.md](docs/CONTINUOUS_CONTROLS.md).
See [CONDITIONAL.md](docs/CONDITIONAL.md) for state/output policies, sample clocks,
matrix shapes, and current restrictions.
**Inport** and **Outport** add numbered interface blocks; use **Edit** to change
their port numbers. Port numbers of each kind must be unique and consecutive
from 1 before a model can be saved or run. Ports may carry scalar or matrix
signals. **Nested demo** loads an oscillator with both states inside subsystems.

Signals have explicit source and destination port numbers. Connect prompts for
ports when either block has multiple ports; a destination port can receive one
wire, and a source port can branch to several destinations (including different
ports on the same block). Disconnect identifies the wire automatically when
there is only one between the selected blocks, otherwise it asks for ports.
Smooth numeric algebraic feedback is solved during simulation, including loops
through virtual subsystem boundaries. Matrix loops use explicit initial signal
guesses; nonsmooth or lifecycle-containing loops remain unsupported. See
[ALGEBRAIC.md](docs/ALGEBRAIC.md) and try `octave_blocks(ob_algebraic_example())`.

Save, Load, New, Settings, and Run apply to the whole model. Run includes scopes
inside subsystems. Edits inside a subsystem are saved in the root model and are
covered by undo/redo; undo/redo returns to the root view. After changing or
deleting interface port numbers, update affected wires in the parent diagram.

Root **Inport** blocks can receive external sampled signals. Use **Inputs** to
configure each numbered root port's times, sample rows, matrix shape, and `zoh`
or `linear` interpolation. **Input demo** loads an input-driven integrator.
Data is saved with the model and participates in Undo/Redo. See
[INPUTS.md](docs/INPUTS.md) for matrix packing, endpoint holds, and examples.

**Export C** generates standalone C99 for supported fixed-size real-double
models, including matrices, state blocks, nested subsystems, and selected
builtin Function blocks. Conditional Subsystems export as typed child contexts
with their supported state/output policies. With zero crossings enabled, RK4
exports also locate registered primitives and declared continuous controls.
Choose `rk4` in Settings before export, or `ode45` for flat models. The generated
source has a reusable C API and an optional CSV runner; see [CODEGEN.md](docs/CODEGEN.md)
for supported operations, compiler commands, return codes, and limitations.
Octave's workspace variable `ob_last_export` contains the export metadata.

**Accelerated runs.** `ob_run (model, t, struct ('accelerate', true))`, or
`ob_accelerate`, compiles the model's C export once into a per-user cache
(`mkoctfile --mex`) and runs it as compiled code. Supported: flat `rk4` and
`ode45` models; `rk4` models with conditional subsystems, multiple-output
Functions or zero crossings; and, in flat models, user `.m` Function blocks,
which Octave evaluates. Results equal the interpreted run, including sample
hits and event records. With `'auto'` a model outside that subset runs
interpreted instead. Eight of the nine shared benchmark cases are
accelerated, 66–261 times faster than the interpreter. See
[CODEGEN.md](docs/CODEGEN.md#accelerated-simulation).

**Rate Transition** adds a sampled hold block. Select a Unit Delay, Discrete
Integrator, or Rate Transition and use **Sample time** to set its period and
offset. A period of 0 retains the output-schedule clock. **Edit** changes its
initial value. **Rate demo** loads a sampled Time signal feeding a continuous
Integrator and sets the run interval to 0–1 seconds. See [MULTIRATE.md](docs/MULTIRATE.md)
for independent clocks, simultaneous updates, rate crossings, and limitations.

**Saturation** clamps a signal to `[lower upper]` limits. **Dead Zone** emits
zero within those limits and the excess outside them. **Switch** routes
input 1 or input 3 according to whether input 2 is greater than or equal to
its scalar threshold. **Control demo** loads a connected example. These blocks
preserve matrix shapes and support C export. See [CONTROLS.md](docs/CONTROLS.md)
for port order, shape requirements, and solver limitations at crossings.

**Settings → Locate zero crossings** enables event localization for Switch,
Saturation, and Dead Zone with RK4, ode45, or ode15s. It defaults to 0. Set it
to 1 to split integration at computed signal crossings; the maximum-step
setting also bounds the RK4 event search. Events appear in
`ob_last_result.events`. RK4 C export accepts this option and stores cumulative
event count/latest time in each generated context; it does not keep an unbounded
event log. Continuous controls require the option. Flat models (no conditional
subsystems, multiple-output Functions or zero crossings) also export with
adaptive `ode45`, a port of Octave's own algorithm ([CODEGEN.md](docs/CODEGEN.md#adaptive-ode45-export));
conditional and event exports remain RK4 only, and `ode15s` is interpreted only.
See [ZERO_CROSSINGS.md](docs/ZERO_CROSSINGS.md) for initial-zero behavior, matrix
channels, event history, sampling rules, and remaining limitations.

**Transport Delay** delays a signal by a fixed time, and **Limited Int.** adds
an integrator with output limits and an optional reset input. Both run with
all three solvers; see [advanced extensions](docs/ADVANCED_EXTENSIONS.md) for
their interpolation, reset timing, MATLAB `dde23` and Simulink comparisons
and current restrictions. Both export to C on the flat path (`rk4` or `ode45`,
see [CODEGEN.md](docs/CODEGEN.md#transport-delay-and-limited-integrator)); they are
not yet supported with zero crossings or in conditional bodies.

Models can also be built from scripts with Simulink's commands
(`new_system`, `add_block`, `add_line`, `set_param`, `sim`, ...) after
`ob_setup ('simulink')`; see [SIMULINK_API.md](docs/SIMULINK_API.md).
Inside conditional subsystems the API sets each Outport's
`OutputWhenDisabled` and `InitialOutput` (per port) and the Enable block's
`StatesWhenEnabling`; scalar initial outputs take their port's width from the
start. The Trigger block's `InitialTriggerSignalState` accepts all four
Simulink values, including the default `compatibility` (no trigger on the
first evaluation), through the subsystem's `initial_control`
([CONDITIONAL.md](docs/CONDITIONAL.md#initial-trigger-control)). `SimulationMode`
`accelerator` and `rapid-accelerator` run the compiled accelerator and fall
back to interpretation with a note.

Behaviour is checked against live Simulink 26.2 through references recorded by
the `reference_ob_*.m` producers in MATLAB; the Octave tests
`test_ob_simulink_conditional`, `test_ob_simulink_extended`,
`test_ob_simulink_delay_integrator`, `test_ob_simulink_api_reference` and
`test_ob_simulink_benchmarks` compare against them without MATLAB. See
[REFERENCE_EVIDENCE.md](docs/REFERENCE_EVIDENCE.md#live-simulink-references)
for what is covered and [COMPATIBILITY_GAPS.md](docs/COMPATIBILITY_GAPS.md) for
what is not.

If an older editor window is already open, close that window and run
`clear octave_blocks; octave_blocks` to load the latest version.

The evaluator can also be used without the GUI:

```octave
model = ob_example ();
result = ob_run (model, 0:0.1:10);
plot (result.t, cell2mat (result.values(:, 3)));

oscillator = ob_oscillator ();
result = ob_run (oscillator, 0:0.1:10);
plot (result.t, cell2mat (result.values(:, 4)));

custom = ob_function_example ();
result = ob_run (custom, 0:0.1:10);
plot (result.t, ob_scope_data (result, 3));

ob_save_model ('my-model.mat', custom, [0 10 0.1]);
[custom, settings] = ob_load_model ('my-model.mat');
```

For stepping and checkpointing from Octave host code, use `ob_runtime_init`,
`ob_runtime_step`, and `ob_runtime_outputs`. Each context owns its states and
clocks; copies can continue independently and failed steps preserve the prior
context. See [RUNTIME.md](docs/RUNTIME.md) for hierarchy-aware reads and MAT checkpoint
examples. `ob_run` collects samples using this same scheduler.

Variable-step simulation uses Octave's built-in ODE solvers. Supply output
sample times independently of the solver's internal steps:

```octave
options = struct ('solver', 'ode45', 'reltol', 1e-8, ...
                  'abstol', 1e-10, 'maxstep', 0.2);
result = ob_run (ob_oscillator (), [0 0.5 4 10], options);
plot (result.t, ob_scope_data (result, 4));
ob_save_model ('adaptive.mat', ob_oscillator (), [0 10 0.5], options);
[model, settings, options] = ob_load_model ('adaptive.mat');
```

```octave
options = struct ('zero_crossings', true);
result = ob_run (ob_zero_crossing_example (), [0 1], options);
assert (abs (ob_scope_data(result, 6)(end) - 1.25) < 1e-8);
disp (result.events); % Switch crossing near t = 0.35
```

Subsystem models can also be built directly in Octave. A Subsystem block stores
its child model in `block.value`; Inport and Outport blocks store their port
number there. An explicit edge row is `[source source_port target target_port]`.
Older `[source target]` rows remain supported and assign target ports in wire
row order. `ob_edges(model)` returns the canonical four-column representation.

```octave
model = ob_subsystem_example ();
result = ob_run (model, 0:0.1:10, struct ('solver', 'ode45'));
plot (result.t, ob_scope_data (result, [1 2])); % state inside subsystem 1
child = ob_model_at (model, 1);
child.blocks(2).value = 2;                    % change its initial condition
model = ob_set_model_at (model, 1, child);
```

`result.values{sample, block}` retains the first output of each root block.
Use `ob_signal_values(result, path, port)` for cell samples at any output port,
or `ob_scope_data(result, path, port)` for numeric traces. For example, `[1 2]`
identifies block 2 inside root subsystem 1. `result.flat_values`, `block_paths`,
`signal_map`, and `compiled_model` expose the flattened execution graph.

Supported solver options are `solver` (`rk4` by default), `reltol` (1e-6),
`abstol` (1e-9), `maxstep` (Inf), and `zero_crossings` (false). Tolerances
must be positive finite scalars; `maxstep` may also be Inf. Tolerances apply to
adaptive solvers. Maximum step also bounds zero-crossing search segments,
including event-enabled RK4. RK4 subdivides output intervals at scheduled
discrete hits and known source transitions. Results include the
normalized `solver_options`, solver name, and `integration_steps` (the number of
integration intervals reported by the solver, summed across restarts).

Solver options are saved with the model and included in undo/redo. Older model
files load with the RK4 default. Adaptive solvers restart at requested output
times, known Step transitions, and external input knots; continuous state is
preserved across restarts.
Discrete blocks with explicit sample times update on independent clocks;
blocks with `[0 0]` sample-time rows retain output-time updates. Their outputs
hold between hits. `ode15s` currently solves the
explicit ODEs represented by Integrator blocks, without mass matrices or DAE
constraints.

`ob_demo_function.m` is an example of a custom Function block. Add your own
`.m` file to Octave's path, add a Function block, and enter the function name
without `.m`. Each incoming connection supplies an argument in destination-port
order. Add/Edit also sets the output count; returned values feed their numbered
output ports. Missing output metadata preserves one output in older models.
`ob_multioutput_example` demonstrates maximum values and their indices, and
`ob_demo_multi_function` is an ordinary three-output `.m` function. See
[MULTIOUTPUT.md](docs/MULTIOUTPUT.md) for shapes, routing, and the C subset.
Functions should be deterministic
and avoid side effects: continuous integration evaluates them at intermediate
solver times as well as output times.

After a GUI run, inspect or reuse the same data in Octave:

```octave
plot (ob_last_result.t, cell2mat (ob_last_result.values(:, 3)));
```

Current scope: requested output sample points, multiple Function and subsystem
outputs, and one output per other primitive block. Unit Delay,
continuous Integrator (RK4, ode45, or ode15s), and Discrete Integrator (forward Euler)
hold state and permit feedback loops.
Known Step transitions and external input knots split continuous integration intervals so jumps do not
smear into the preceding interval. Discrete blocks update on their configured
or inherited clocks and hold their state during continuous integration.
Supported smooth, fixed-shape numeric algebraic loops are solved in Octave;
C export rejects them. See [ALGEBRAIC.md](docs/ALGEBRAIC.md).
Explicit destination port numbers determine
input order; legacy two-column connections assign ports in wire-row order.
Independent numerical clocks and single-thread sample/hold rate transitions
are supported; asynchronous tasks and target-specific transfer policies remain
compatibility work.

Constant, Gain, Step, and initial state values must be finite real numeric
values. Gain and Product use matrix multiplication (`*`); Sum uses `+`.
Scope samples must keep the same shape; matrix elements become separate traces
in Octave column order. Choose initial state dimensions to match the signal.
The last successful GUI simulation replaces `ob_last_result`; failed runs leave
the previous result available. `values{sample, block}` contains each root block's
first output, and `t` contains the output times. Virtual subsystems are
flattened before dependency sorting and simulation, so their states share the
root solver while preserving each inner block's explicit clock. Conditional
subsystems retain separate contexts and explicit sampled/continuous control timing.
Enabled continuous bodies share the parent solver stages and freeze while
disabled; their enable gates default to sampled. See [CONDITIONAL.md](docs/CONDITIONAL.md)
and `ob_enabled_continuous_example`. Generated C supports the same enabled
continuous bodies using joint RK4 stages. Octave enabled bodies also support
independent inner clocks; `ob_enabled_multirate_example` demonstrates their
phase across disabled intervals. Generated C supports the same inner clocks
and skipped-hit behavior. Arbitrary Octave function translation remains future
work. Root Inports receive configured
sampled data; nested Inports receive their enclosing subsystem connections.
Nesting is limited to 32 levels.

`ob_continuous_control_example` returns a model and event-enabled options for
an enable interval between sparse output requests. Continuous-control models
run in Octave and export through the RK4 event runtime with
`zero_crossings=true`. Runtime execution also caches immutable routing
and conditional metadata; see [RUNTIME_PERFORMANCE.md](docs/RUNTIME_PERFORMANCE.md)
for measured improvements and the cache/checkpoint contract. Interpreted runs
are about 2.7 times faster than the engine before the 2026-11-21 speed work
(2.74x geometric mean over the shared nine-case benchmark, with bit-identical
results; the second pass added 1.28x over the first). Models with conditional
bodies gained least (1.5x). The interpreter remains roughly 25–165 times
slower than Simulink's warm `sim()` (the upper end is Mackey-Glass). Warm accelerated calls took 0.14–0.30
times Simulink's warm `sim()` time, except for the Mackey-Glass cases, whose
`.m` Function is called back into Octave (about 2.2 times Simulink's).

Continuous state-space and proper SISO transfer-function builders are available
as `ob_state_space` and `ob_transfer_function`. Their virtual diagrams work in
the editor and C exporter; try `ob_linear_system_example`. See
[LINEAR_SYSTEMS.md](docs/LINEAR_SYSTEMS.md) for equations and initial-state conventions.
See [ADVANCED_EXTENSIONS.md](docs/ADVANCED_EXTENSIONS.md) for PID, discrete linear
systems, lookup tables, sampled rate limiting and relay, feedthrough
diagnostics, and sampled resettable subsystems.

Run `test_ob_run; test_ob_editor_core; test_ob_solvers; test_ob_subsystems; test_ob_inputs; test_ob_multirate; test_ob_controls; test_ob_runtime; test_ob_runtime_metadata; test_ob_conditional; test_ob_enabled_continuous; test_ob_enabled_multirate; test_ob_linear_systems; test_ob_matlab_numeric; test_ob_multioutput; test_ob_algebraic; test_ob_zero_crossings; test_ob_continuous_controls` in
Octave to check execution, editing rules, persistence, adaptive integration,
hierarchy, signal ports, external sampled inputs, multirate scheduling,
nonlinear control blocks, resumable execution, conditional subsystems, and
multiple Function outputs, algebraic loops, zero crossings, and recorded MATLAB numeric references. See
[SIMULINK_REFERENCE.md](docs/SIMULINK_REFERENCE.md) for the feature cross-reference
and what the REA inspection established, and [ADVANCED_PLAN.md](docs/ADVANCED_PLAN.md)
for the advanced functionality roadmap.

`Launch-Blocks.ps1 -SelfTest` also runs `Test-Codegen.ps1`, which compiles the C
exports and compares all signal channels against Octave references. A C99
compiler is required for those checks; the script uses Octave's bundled GCC
by default. It then runs the Qt checks in `Test-Editor.ps1` (`test_ob_editor_graphics`,
`test_ob_editor_advanced` and the editor event export).
The full gate also runs the focused event-export checks in `Test-EventCodegen.ps1`,
`Test-EventCodegenEdges.ps1` and `Test-EventCodegenHierarchy.ps1`; each compiles
and compares event-enabled models through the public exporter. See
[EVENT_CODEGEN_DEVELOPMENT.md](docs/EVENT_CODEGEN_DEVELOPMENT.md) for runtime
architecture and [COMPATIBILITY_GAPS.md](docs/COMPATIBILITY_GAPS.md) for open milestones.
The full gate now includes the three `test_ob_performance_*` compatibility
suites, `test_ob_runtime_fast_paths` (golden fingerprints of the engine before
the speed work, packed solver stages against the general cell path, and the
prepared evaluation plan and program against the general paths), the
accelerator suites `test_ob_accelerate` and `test_ob_simulink_benchmarks`,
the Simulink reference suites, and graph/edge/snapshot/ODE BIST checks
(including `src/private/ob_ode_settings.m` and `src/private/ob_dormand_prince.m`). See
[OPTIMIZATION_AUDIT.md](docs/OPTIMIZATION_AUDIT.md) for corrected audit findings and
measured results, and [benchmarks/README.md](benchmarks/README.md) to reproduce
the before/after comparisons.
Codegen metadata and source/proxy-order regressions and `Test-CInputLookup.ps1`
are registered in the full gate as well. The latter strictly compiles generated
sampling/boundary helpers and compares them against independent scan oracles.
See [PR2_AUDIT.md](docs/PR2_AUDIT.md) for the subsequent report review, including
disproven claims, confirmed changes and verification scope.
The expanded built-in and solver/library recommendations are assessed in
[BUILTIN_REVIEW.md](docs/BUILTIN_REVIEW.md), including unsafe shape substitutions
and the actual installed backend availability.
Verification artifacts are retained in the reported directories. See
[UI_PERFORMANCE.md](docs/UI_PERFORMANCE.md) for measured editor improvements and
[REVIEW_GUIDE.md](docs/REVIEW_GUIDE.md) for architecture and review instructions.

## Project layout

| Path | Contents |
| --- | --- |
| `ob_setup.m` | Puts the project on Octave's path (see above) |
| `Launch-Blocks.ps1` | Windows launcher; `-SelfTest` runs the full verification gate |
| `src/` | The library and editor (`octave_blocks`, `ob_run`, `ob_codegen`, `ob_accelerate`, `ob_simulink`, ...). `src/private/` holds runtime internals that only functions in `src/` can call |
| `examples/` | Example and demo models (`ob_oscillator`, `ob_control_example`, `ob_conditional_example`, ...) |
| `simulink/` | Simulink-named command wrappers (`new_system`, `add_block`, `sim`, ...), added by `ob_setup ('simulink')` |
| `tests/` | Test suites (`test_ob_*`), their case builders and helpers, `verify_ob_codegen` and the `Test-*.ps1` C and Qt gates |
| `reference/` | MATLAB and Simulink reference producers (`reference_ob_*.m`, run in MATLAB from this folder with an output file argument) and the recorded JSON the tests compare against |
| `benchmarks/` | Benchmark models, scripts and recorded measurements; see [benchmarks/README.md](benchmarks/README.md) |
| `tools/` | Developer utilities (`ob_trace_editor_clicks`) |
| `docs/` | Design notes, validation records and reviews |

To run individual suites, set up with the tests on the path, for example
`ob_setup ('tests'); test_ob_run ()`. The `tests/Test-*.ps1` scripts can be run
directly from PowerShell (for example `./tests/Test-Codegen.ps1`); they find the
project from their own location.
