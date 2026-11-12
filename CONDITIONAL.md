# Conditional subsystem execution

A Subsystem can now own an execution context instead of being flattened into
its parent. Configure it with **Edit** after selecting the Subsystem. The
dialog sets its name, mode, state policy, output policy, initial outputs,
initial trigger control, and control timing. **Enter** still edits the child diagram. A label shows
the mode and the last input's control-port number.

| Mode | Execution rule at each configured sample hit |
| --- | --- |
| `virtual` | Ordinary subsystem flattening; no control port. |
| `enabled` | Execute while the scalar control is positive. |
| `rising` | Execute on a rise through or to zero. |
| `falling` | Execute on a fall through or to zero. |
| `either` | Execute on either trigger direction. |

Data input ports retain their Inport numbers. The extra, last input is the
control signal. It must be a finite real scalar; logical controls are also
accepted. On trigger modes, consecutive rises or falls through a zero sample
are suppressed; a plateau can rearm that direction. `initial_control` sets the
previous control value at initialization and defaults to zero.
This selects explicit zero initialization. Simulink's separate first-evaluation
compatibility mode is still a gap; the comparison harness explicitly selects
`zero` in its [Trigger configuration](https://www.mathworks.com/help/simulink/slref/trigger.html).

Conditional execution defaults to sampled: use **Sample time** on the selected Subsystem
to set its control-sampling period and offset. `[0 0]` retains the requested
output schedule for bodies without inner clocks. When enabled bodies contain
inner clocks, inherited control also samples at their union of hit times.
An explicit clock is processed even between sparse output requests. Control
changes between hits are not located as zero-crossing events.

Set `child.execution.control='continuous'` to locate enable/trigger changes
between output requests. This requires `options.zero_crossings=true` and no
explicit enclosing control period. The editor exposes the timing setting in
**Edit** and clears that Subsystem's explicit rate when continuous is selected.
See [CONTINUOUS_CONTROLS.md](CONTINUOUS_CONTROLS.md) for lifecycle, clocks,
initialization, plateau rules and current C restrictions.

## States and outputs

Enabled mode supports independent `held`/`reset` policies. `states='reset'`
reinitializes the child on its next activation after a disabled hit.
`outputs='reset'` uses the declared initial output while disabled. Trigger
modes require held states and outputs. The child initializes lazily on its
first execution, so inactive Function blocks are not evaluated.

Declare one finite real numeric initial output per numbered Outport. These
values define the output shapes; all subsequent outputs must match them.
The default is a scalar zero for each port. Matrix signals therefore need
matching matrix initial outputs.

```octave
model = ob_conditional_example ();
result = ob_run (model, 0:6);
assert (isequal (ob_scope_data(result,4)', [-1 0 1 1 1 2 5]));

child = model.blocks(3).value;
child.execution.states = 'reset';
model.blocks(3).value = child;
result = ob_run (model, 0:6);
assert (isequal (ob_scope_data(result,4)', [-1 0 1 1 1 0 5]));
```

`child.execution` accepts `mode`, `states`, `outputs`, `initial_outputs` (a cell
array), `initial_control`, and `control` (`sampled` or `continuous`). When adding a conditional mode, connect its new
control input. Converting back to virtual in the editor removes that control
wire and clears the Subsystem's explicit rate; Undo restores the change.
Virtual mode ignores conditional state/output settings, so unused initial
output metadata does not constrain later edits to its interface.

Discrete blocks with `[0 0]` use inherited execution. A Unit Delay advances once
per execution. Enabled Euler uses the first sample interval following its
previous execution, retaining that interval through a disabled pause. Triggered
Euler uses elapsed time between executions. Enabled descendants inherit their
parent's active interval so a disabled ancestor cannot advance their state.
When an ancestor disables, active descendants cache the interval from their
last sample to that boundary without taking a new sample. Reenabling consumes
that interval rather than integrating the disabled wall-time gap. Explicit
descendant control periods retain their configured step.
Both emit their initial condition
on first execution. Rate Transition samples the current input on execution.
Enabled bodies also support continuous Integrator states, including inside
nested virtual and enabled children. All active continuous states share the
parent's RK4, ode45, or ode15s solver stages. Current parent stage inputs feed
child derivatives and instantaneous outputs; a child is not separately advanced
using old inputs at the next sample hit. While disabled, its continuous states
freeze. Reenabling retains or resets them according to the state policy.
The disabled output policy remains independent of the retained state.
Resetting an enclosing body currently reconstructs its nested contexts.
Independent descendant overrides of an ancestor's reset policy remain a
compatibility gap.

With the default sampled timing, the enable gate follows the enclosing
Subsystem's configured clock. Minor solver stages do not toggle it or advance child sample histories. An
enabled continuous body's outputs can change between hits; the hit controls
activation, rather than sample-and-hold of the entire continuous body. General
enable/trigger crossings are available through the explicit continuous control
setting. Triggered bodies continue to reject
continuous Integrator states and independent inner clocks.

```octave
model = ob_enabled_continuous_example ();
result = ob_run (model, [0 0.5 1 1.5 2 2.5 3]);
assert (max(abs(ob_scope_data(result,4)' - [0 .5 1 1 1 1.5 2])) < 1e-10);
octave_blocks (model);
```

## Independent clocks in enabled bodies

In Octave simulation, inner Unit Delay, Discrete Integrator, Rate Transition,
and conditional Subsystem blocks may have independent periods and offsets.
Configure them with **Enter**, select the inner block, then **Sample time**.
Every inner offset is relative to the root simulation start, including through
virtual/enabled nesting. Clocks advance while disabled, but inactive blocks
skip their hits. Reenabling never replays missed updates or rephases a clock
to the activation time. An explicit-rate Euler update uses its own period.
An independently clocked nested enabled Subsystem also supplies its own period
to inherited Euler blocks, rather than the faster ancestor's interval.

An explicit enclosing Subsystem clock samples only its enable/trigger control;
active inner clocks can execute between those control samples. This is a local
schema choice, not Simulink's `SystemSampleTime` parameter. With an inherited
enabled control, inner hits join requested output times as control sampling
points. Continuous states share the root solver between these hidden hits.
Minor stages evaluate active flow graphs without executing discrete updates.

```octave
model = ob_enabled_multirate_example ();
result = ob_run (model, [0 1]);
assert (isequal(ob_scope_data(result,4)', [0 .375]));
assert (isequal(ob_scope_data(result,5)', [0 .25]));
octave_blocks (model);
```

The example enables execution on `[.375,.875)`. Its `.25` inner clock runs at
`.5` and `.75`, retaining its global phase. This follows the discrete-clock
rule illustrated by [MathWorks' enabled subsystem example](https://www.mathworks.com/help/simulink/ug/enabled-subsystems.html).
The checks use analytical traces; a live Simulink engine is still unavailable.
Automatic sample-time propagation to all algebraic blocks and Outports remains
open; these ports retain this simulator's inherited evaluation contract.
Generated C supports the same inner clocks through a root-owned inventory
and transient event frames. Clock phase and pending captures survive inactive
periods; initialization/reset affects child state, not global ticks.
That C support uses sampled controls; continuous-control models are rejected
before replacing an export file.

## Hierarchy, scopes, and checkpoints

Nested virtual and conditional children retain their own contexts. Read an
inner signal with `ob_signal_values`, `ob_scope_data`, or `ob_runtime_outputs`
and its ordinary hierarchical path. Historical inner signals before the first
execution are represented as `NaN` gaps once a sample shape is known. A child
that never executes reports that no sample exists. The editor skips those
scopes and can still show scopes with available samples.

Model files save configuration. Runtime MAT checkpoints also save nested
states, pending updates, trigger history, and held output buffers. Failed
execution preserves the prior parent and child contexts. Function side effects
outside these contexts cannot be rolled back.

Compiled atomic cores use internal paths ending in zero and store structured
snapshots in `result.flat_values`; their numeric output proxies also have
internal paths. Use ordinary positive block paths through the signal APIs
instead of treating every compiled value as a numeric signal.

## Compatibility and verification

The reference behaviors are tracked against MathWorks documentation for
[enabled subsystems](https://www.mathworks.com/help/simulink/ug/enabled-subsystems.html)
and [triggered subsystems](https://www.mathworks.com/help/simulink/ug/triggered-subsystems.html).
`test_ob_conditional` verifies analytical traces, zero plateaus, reset/hold
policies, matrices, multiple outputs, nested execution, sparse output clocks,
continuous parent integration, inactive invalid functions, checkpoints, and
rollback. `test_ob_enabled_continuous` additionally checks shared parent/child
oscillator dynamics, matrix states, sampled gating, pause/resume, nested
ancestor pauses, output/state reset, and runtime checkpoint/error rollback
with all three solvers. `test_ob_enabled_multirate` additionally checks global
phase/offsets, skipped and hidden hits, inherited control-clock unions, pause
and reset behavior, matrix-compatible contexts, nested clock routing, mixed
continuous/discrete bodies, checkpoints, and transactional failures.
Current limitations include combined enable-and-trigger variants, general event location,
and data feedback across an atomic boundary (currently conservatively treated
as a direct dependency).

Conditional C generation uses recursive typed child contexts and numeric
output proxies. The same sampled mode, reset/hold, and inherited-interval rules
apply; inactive children stay unevaluated and nested failures roll back the
parent context. Static shapes and the existing C builtin-function subset are
required, including inside inactive children. Enabled continuous bodies share
the parent's RK4 stages in generated C, including nested active states, matrix
states, current parent stage inputs, and endpoint output snapshots. The C
exporter preserves a separate major-hit snapshot for discrete Delay/Euler
captures. Host-input errors and nonfinite derivatives roll back the entire
parent/child context. Adaptive solver emission remains unsupported.
Unsupported models are rejected
before replacing an existing source. See [CODEGEN.md](CODEGEN.md) for metadata
and API details. The broader milestone remains open in
[ADVANCED_PLAN.md](ADVANCED_PLAN.md).

## MATLAB and REA evidence

The installed MATLAB R2026b Update 1 was launched for comparison. Its recorded
[environment probe](matlab-environment.json) reports no installed Simulink and
no `load_system` function, despite a successful feature-license test. A live
Simulink trace comparison is therefore still pending.
[reference_ob_conditional.m](reference_ob_conditional.m) builds temporary
comparison models when a local Simulink engine is available; it does not alter
existing models.

MATLAB's native math runtime did run successfully: 26 single-output builtin
Function mappings, 15 two-output cases, signed-zero `atan2`, and rounding ties were recorded and
checked against Octave Blocks. See the [numeric cross-reference](SIMULINK_REFERENCE.md)
for the retained fixture and its tested scope.

REA 6.8.0 performed a bounded read-only inspection of the installed Simulink
support directory. Its [sanitized inspection summary](REFERENCE_EVIDENCE.md#rea-installation-inspection)
records 237 entries and zero runtime candidates. This is installation evidence,
not proof of engine behavior; runtime behavior and unread bytes remain unknown.
