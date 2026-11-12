# Octave Blocks

An Octave-native block diagram editor and evaluator. Function blocks call ordinary
`.m` functions on Octave's path with `feval`, so block logic uses Octave's language.

The project is available under the [MIT license](LICENSE). See
[VALIDATION.md](VALIDATION.md) for the latest verification results, reproduction
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

Add this folder to Octave's path, then run `octave_blocks` for the editor. The
initial diagram is Time → Gain → Scope. Click a block face, label, port, or port
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
settings. Modes include virtual, enabled, and rising/falling/either trigger;
conditional modes add a last control input and support held initial outputs.
Control timing defaults to sampled. Choose continuous in **Edit** and enable
zero crossings in **Settings** to locate gate events between output requests;
see [CONTINUOUS_CONTROLS.md](CONTINUOUS_CONTROLS.md).
See [CONDITIONAL.md](CONDITIONAL.md) for state/output policies, sample clocks,
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
[ALGEBRAIC.md](ALGEBRAIC.md) and try `octave_blocks(ob_algebraic_example())`.

Save, Load, New, Settings, and Run apply to the whole model. Run includes scopes
inside subsystems. Edits inside a subsystem are saved in the root model and are
covered by undo/redo; undo/redo returns to the root view. After changing or
deleting interface port numbers, update affected wires in the parent diagram.

Root **Inport** blocks can receive external sampled signals. Use **Inputs** to
configure each numbered root port's times, sample rows, matrix shape, and `zoh`
or `linear` interpolation. **Input demo** loads an input-driven integrator.
Data is saved with the model and participates in Undo/Redo. See
[INPUTS.md](INPUTS.md) for matrix packing, endpoint holds, and examples.

**Export C** generates standalone C99 for supported fixed-size real-double
models, including matrices, state blocks, nested subsystems, and selected
builtin Function blocks. Sampled conditional Subsystems also export as typed
child contexts with retained/reset state and held outputs. Choose `rk4` in Settings before export. The generated
source has a reusable C API and an optional CSV runner; see [CODEGEN.md](CODEGEN.md)
for supported operations, compiler commands, return codes, and limitations.
Octave's workspace variable `ob_last_export` contains the export metadata.

**Rate Transition** adds a sampled hold block. Select a Unit Delay, Discrete
Integrator, or Rate Transition and use **Sample time** to set its period and
offset. A period of 0 retains the output-schedule clock. **Edit** changes its
initial value. **Rate demo** loads a sampled Time signal feeding a continuous
Integrator and sets the run interval to 0–1 seconds. See [MULTIRATE.md](MULTIRATE.md)
for independent clocks, simultaneous updates, rate crossings, and limitations.

**Saturation** clamps a signal to `[lower upper]` limits. **Dead Zone** emits
zero within those limits and the excess outside them. **Switch** routes
input 1 or input 3 according to whether input 2 is greater than or equal to
its scalar threshold. **Control demo** loads a connected example. These blocks
preserve matrix shapes and support C export. See [CONTROLS.md](CONTROLS.md)
for port order, shape requirements, and solver limitations at crossings.

**Settings → Locate zero crossings** enables event localization for Switch,
Saturation, and Dead Zone with RK4, ode45, or ode15s. It defaults to 0. Set it
to 1 to split integration at computed signal crossings; the maximum-step
setting also bounds the RK4 event search. Events appear in
`ob_last_result.events`. Event-enabled C export is currently rejected.
See [ZERO_CROSSINGS.md](ZERO_CROSSINGS.md) for initial-zero behavior, matrix
channels, event history, sampling rules, and remaining limitations.

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
context. See [RUNTIME.md](RUNTIME.md) for hierarchy-aware reads and MAT checkpoint
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
[MULTIOUTPUT.md](MULTIOUTPUT.md) for shapes, routing, and the C subset.
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
C export rejects them. See [ALGEBRAIC.md](ALGEBRAIC.md).
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
disabled; their enable gates default to sampled. See [CONDITIONAL.md](CONDITIONAL.md)
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
currently run in Octave only. Runtime execution also caches immutable routing
and conditional metadata; see [RUNTIME_PERFORMANCE.md](RUNTIME_PERFORMANCE.md)
for measured improvements and the cache/checkpoint contract.

Continuous state-space and proper SISO transfer-function builders are available
as `ob_state_space` and `ob_transfer_function`. Their virtual diagrams work in
the editor and C exporter; try `ob_linear_system_example`. See
[LINEAR_SYSTEMS.md](LINEAR_SYSTEMS.md) for equations and initial-state conventions.

Run `test_ob_run; test_ob_editor_core; test_ob_solvers; test_ob_subsystems; test_ob_inputs; test_ob_multirate; test_ob_controls; test_ob_runtime; test_ob_runtime_metadata; test_ob_conditional; test_ob_enabled_continuous; test_ob_enabled_multirate; test_ob_linear_systems; test_ob_matlab_numeric; test_ob_multioutput; test_ob_algebraic; test_ob_zero_crossings; test_ob_continuous_controls` in
Octave to check execution, editing rules, persistence, adaptive integration,
hierarchy, signal ports, external sampled inputs, multirate scheduling,
nonlinear control blocks, resumable execution, conditional subsystems, and
multiple Function outputs, algebraic loops, zero crossings, and recorded MATLAB numeric references. See
[SIMULINK_REFERENCE.md](SIMULINK_REFERENCE.md) for the feature cross-reference
and what the REA inspection established, and [ADVANCED_PLAN.md](ADVANCED_PLAN.md)
for the advanced functionality roadmap.

`Launch-Blocks.ps1 -SelfTest` also runs `Test-Codegen.ps1`, which compiles the C
exports and compares all signal channels against Octave references. A C99
compiler is required for those checks; the script uses Octave's bundled GCC
by default. It then runs the Qt retained-graphics checks in `Test-Editor.ps1`.
Verification artifacts are retained in the reported directories. See
[UI_PERFORMANCE.md](UI_PERFORMANCE.md) for measured editor improvements and
[REVIEW_GUIDE.md](REVIEW_GUIDE.md) for architecture and review instructions.
