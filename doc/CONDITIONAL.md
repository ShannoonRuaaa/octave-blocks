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
are suppressed; a plateau can rearm that direction.

### Initial trigger control

`initial_control` sets the previous control value at initialization. It is
either a finite real scalar, whose sign is used, or the string
`'compatibility'`. The default stays 0. The values map onto Simulink's
[InitialTriggerSignalState](https://www.mathworks.com/help/simulink/slref/trigger.html):

| `initial_control` | InitialTriggerSignalState | First evaluation |
| --- | --- | --- |
| `0` (default) | `zero` | An edge from 0 can execute the body. |
| positive | `positive` | An edge from +1 can execute the body. |
| negative | `negative` | An edge from -1 can execute the body. |
| `'compatibility'` | `compatibility (no trigger on first evaluation)`, Simulink's default | Never executes; it only records the sample as the previous value. |

The first evaluation is the context's first major hit. It happens at the start
time, or later when a disabled Enabled ancestor first activates or a
trigger-only wrapper first executes. A zero first sample under
`'compatibility'` therefore lets the next positive sample fire a rising edge.
At the root, `'compatibility'` behaves like `sign(first sample)`. The Simulink
API maps the Trigger block's `InitialTriggerSignalState` onto this field (see
[SIMULINK_API.md](SIMULINK_API.md)). Resettable modes accept only numeric
values, because Simulink's Reset block has no such setting.

Simulink 26.2 traces confirm every row for trigger-only subsystems. They cover
first samples that are negative, zero and positive, in rising, falling and
either modes. They also cover delayed first evaluations, wrapped
grandchildren, ancestor resets (see below) and continuous triggers located by
ode45. Combined enable-and-trigger modes always behave like `'compatibility'`
and ignore the numeric values; see [COMBINED_CONTROLS.md](COMBINED_CONTROLS.md).

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
`outputs='reset'` uses the declared initial output while disabled. Like
Simulink's per-Outport `OutputWhenDisabled`, `outputs` may also be a cell
with one `'held'` or `'reset'` per numbered Outport, in port order, for
example `{'held','reset','held'}`; a single string applies to every port.
Trigger modes without an enable require held states and outputs (every
listed policy `'held'`). Combined modes support independent policies, also
per port; see [COMBINED_CONTROLS.md](COMBINED_CONTROLS.md). The child initializes lazily on its
first execution, so inactive Function blocks are not evaluated.

Declare one finite real numeric initial output per numbered Outport. The
default is a scalar zero for each port. A matrix initial output fixes its
port's shape. A scalar initial output is expanded to the shape of the
port's signal, as Simulink expands a scalar `InitialOutput`: a 2-element
port with initial output `-4` shows `[-4 -4]`, both before its first
execution and when a reset port returns to it. The shape comes from static
shape propagation through the body with the shapes of its inputs
(`ob_expand_initial_outputs`, the rule the C exporters use) at the body's
first evaluation. Each body the runtime initializes has the scalar initial
outputs of the conditional subsystems inside it expanded the same way, so a
nested port holds its full shape before the nested body first runs. A
subsystem whose first evaluation comes after the start (an explicit sample
offset) also holds the expanded value from `t = 0`: the root runtime
initialization (`ob_run`, `ob_runtime_init`) applies `ob_expand_initial_outputs`
to the root model, as the editor and `sim` do before a run.
A port behind a block whose result shape is only known by evaluating it (a
Function block) is found by a discarded trial initialization of the body
while it is disabled, or by its first execution. A scalar value fixes the
shape only when it is not the still-unexpanded initial output of a nested
subsystem. Once known, every later output must keep it.

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
array), `initial_control` (a scalar or `'compatibility'`), and `control` (`sampled` or `continuous`). When adding a conditional mode, connect its new
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
Resetting an enclosing body rebuilds its nested contexts under each
descendant's own policy. Enabled and combined descendants keep their whole
context and apply their own Enable setting when they next activate. A
combined descendant's trigger history is neither reset nor re-armed for a
first evaluation. A trigger-only descendant restarts its states, but keeps
its held outputs until its next trigger, even across repeated resets. With a
numeric `initial_control` its trigger history also restarts from that value.
With `'compatibility'` the trigger history is kept instead: the last evaluated
sample stays the previous value, together with its edge flags, and a first
evaluation that has not happened yet stays pending. So a rise into zero just
before the reset, followed by a positive sample after it, does not fire again.
The no-trigger rule is not re-armed. The rules apply recursively: an Enabled
or combined context inside a reset trigger-only descendant keeps its whole
context too. Simulink 26.2 traces confirm each of these rules, including the
kept edge flags (see [COMBINED_CONTROLS.md](COMBINED_CONTROLS.md)).

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

### When the Outports of a body with inner clocks update

Simulink runs each Outport at the sample time it inherits from its source,
so it copies a new value only when that source executes while enabled, and
a clocked block that drives an Outport directly writes into that
Outport's signal buffer. Octave Blocks applies both rules in enabled
bodies with inner clocks; every recorded Simulink 26.2 trace
(`simulink-inner-clocks-reference.json`,
`simulink-conditional-outputs-reference.json`) agrees exactly:

- A port's *gates* are the Unit Delays, Discrete Integrators and Rate
  Transitions with their own period that drive it, through blocks without a
  period of their own. A port that also depends on an Inport, Time,
  Constant, continuous Integrator, inherited-rate state or nested
  conditional output follows the body's own rate.
- The port takes a new value only when one of its gates hits, or, for a
  port following the body's rate, at every evaluation of the body. Between
  those it keeps its held value, or its initial output before its first
  update. So at activation a port fed by a 0.25 s Unit Delay shows its
  initial output until the delay's first hit, not the delay's initial
  condition; after a `states='reset'` reactivation between hits it keeps
  its held value until the reset block executes. A port with an offset
  clock waits for its first offset hit.
- A gate that drives a port directly (through Outport/Inport copies only)
  shares that port's buffer: until it executes after the body is
  (re)initialized, every block that reads it sees the port's value, not
  the gate's initial condition: the `InitialOutput` at first, the old
  output after a `states='reset'` reactivation, and the initial output
  again after an `OutputWhenDisabled='reset'`. In the recorded traces a
  Sum of a 0.125 s delay (initial condition -1) and a 0.25 s delay that
  drives a reset port with `InitialOutput` -9 shows -1 + -9 = -10 at the
  0.375 s activation, and 0.75 + -9 = -8.25 at a held reactivation after
  that port was reset. A gate driving several ports shares the
  lowest-numbered one. A gate that drives no port directly shows its own
  initial condition until it executes; Simulink was not probed for that
  case. Readers of an inherited-rate block that drives a port (a Gain of a
  0.25 s delay read at 0.125 s, say) see the Gain's current value, also
  not probed.
- `OutputWhenDisabled='reset'` acts at the port's own rate: a port fed only
  by gates returns to its initial output at the first hit of one of their
  clocks after the body is disabled (a 0.25 s port disabled at 0.875 resets
  at 1.0); other ports reset at once. Reenabling before that hit cancels it.

Octave Blocks keeps a shared gate's real state as its pending update while
its output shows the port's value (`ob_conditional_buffers`), so flows,
checkpoints and the gate's next hit see the same buffer.
`ob_gated_outputs_example` shows each case. Bodies without inner clocks are
unchanged: every port follows the body's rate.

Sample-time propagation itself is not general: blocks without an explicit
period still evaluate at every evaluation of their body.
Generated C supports the same inner clocks through a root-owned inventory
and transient event frames. Clock phase and pending captures survive inactive
periods; initialization/reset affects child state, not global ticks. Both C
exporters apply the same Outport rule, shared buffers, per-port reset
policies and scalar initial-output expansion (`ob_conditional_gating`,
compared with Octave in `test_ob_inner_clock_c_cases` and
`test_ob_event_codegen_cases`). An inherited-rate enabled control is
sampled at its body's inner clock hits in both exporters.
RK4 C export also supports declared continuous controls with
`zero_crossings=true`; omitting the required option fails before replacement.

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
continuous/discrete bodies, Outport timing of clocked sources with per-port
reset at the port's clock (`ob_gated_outputs_example`), checkpoints, and
transactional failures.
Current limitations include resettable variants,
broader event classes beyond registered primitive and continuous-control
guards, and data feedback across an atomic boundary (currently conservatively
treated as a direct dependency). Full sample-time propagation remains a gap.
See [nested Enable state policies](COMBINED_CONTROLS.md) for the reset
precedence rules.

Conditional C generation uses recursive typed child contexts and numeric
output proxies. The same sampled mode, reset/hold, and inherited-interval rules
apply; inactive children stay unevaluated and nested failures roll back the
parent context. Static shapes and the existing C builtin-function subset are
required, including inside inactive children. Enabled continuous bodies share
the parent's RK4 stages in generated C, including nested active states, matrix
states, current parent stage inputs, and endpoint output snapshots. The C
exporter preserves a separate major-hit snapshot for discrete Delay/Euler
captures. Host-input errors and nonfinite derivatives roll back the entire
parent/child context. With `zero_crossings=true`, RK4 C generation also locates
registered primitives and explicitly continuous enable/trigger controls in
active enabled descendants. Accepted lifecycle changes preserve clock phase;
trial stages cannot commit child execution. Generated contexts retain event
counts/latest time rather than an unbounded event log. Continuous controls
require the event option. Conditional exports are RK4 only; `ode45` and
`ode15s` exports of conditional models fail before source replacement. See [CONTINUOUS_CONTROLS.md](CONTINUOUS_CONTROLS.md)
for initialization, plateau and event-search limits.
Unsupported models are rejected
before replacing an existing source. See [CODEGEN.md](CODEGEN.md) for metadata
and API details. The broader milestone remains open in
[COMPATIBILITY_GAPS.md](COMPATIBILITY_GAPS.md).

## MATLAB and Simulink evidence

Simulink 26.2 (MATLAB R2026b Update 1) is now installed and licensed. The
earlier [environment probe](../tests/reference/matlab-environment.json), which found no
`load_system`, predates the installation. The reference harnesses had never
produced a trace before: R2026b rejects a From Workspace block with
`Interpolate='off'` and the default extrapolation after the final value. Each
harness now sets `OutputAfterFinalValue='Holding final value'`. This is neutral
because every harness stops at its last data time.

Four MATLAB producers build unsaved temporary models, close them without
saving, and write the checked-in references:

| Producer | Reference file | Content |
| --- | --- | --- |
| [reference_ob_conditional.m](../tests/reference/reference_ob_conditional.m) | `simulink-conditional-reference.json` | Enabled and trigger-only policies, 6 records |
| [reference_ob_combined.m](../tests/reference/reference_ob_combined.m) | `simulink-combined-reference.json` | Enabled and Triggered policy matrix and initial states, 18 records |
| [reference_ob_nested_reset.m](../tests/reference/reference_ob_nested_reset.m) | `simulink-nested-reset-reference.json` | Nested Enable policies, discrete and continuous, 14 records |
| [reference_ob_conditional_probes.m](../tests/reference/reference_ob_conditional_probes.m) | `simulink-conditional-probes-reference.json` | Trigger initial states (72), combined first evaluation (22), nested ancestor cases (64), continuous ode45 triggers (24): 182 records, plus the Trigger block's InitialTriggerSignalState values |

Run each one in MATLAB with its file name and the `reference/` folder as the
current folder (the tests read only `reference/`), for example
`reference_ob_conditional_probes ('simulink-conditional-probes-reference.json')`.
`test_ob_simulink_conditional` rebuilds every record as an Octave Blocks model
(`ob_simulink_conditional_cases`) and compares it sample by sample. Each nested
probe runs twice, with sampled and with continuous outer control. The six
`reference_ob_conditional` records and the continuous nested-reset records run
under rk4 and ode45. The 24 continuous-trigger probes run under ode45 with
zero-crossing location. Their held Clock values are the located crossing
times, and `test_ob_continuous_controls` also runs them under rk4 and ode15s.
All 304 cases match, with no listed differences: discrete traces exactly,
ode45 within 1.3e-13. The six trigger-only `compatibility` records that used
to be excused now match through `initial_control = 'compatibility'`. The
probes behind the rules in this document are also compiled to C by
`test_ob_combined_codegen`, in both C emitters. Those C cases are checked
against the Simulink trace as well as against Octave.

`test_ob_simulink_extended` compares further Simulink 26.2 recordings:
continuous controls under ode45/ode15s, multiple and vector outputs with
per-port `OutputWhenDisabled` and scalar `InitialOutput` expansion, inner
clocks, and [reference_ob_conditional_outputs.m](../tests/reference/reference_ob_conditional_outputs.m)
(`simulink-conditional-outputs-reference.json`): the Outport timing probes
above (mixed rates, inherited Gains, a constant, an inherited Euler, a held
Rate Transition, per-port reset, a continuous body under ode4, a vector
port, a Triggered Subsystem whose `OutputWhenDisabled='reset'` Simulink
ignores, and mixed policies in an Enabled and Triggered Subsystem). The
per-port, expansion, inner-clock timing and shared-buffer cases agree
exactly; the only remaining differences there are the Rate Transition
transfer modes in [MULTIRATE.md](MULTIRATE.md). Function-call triggers are
not covered.

MATLAB's native math runtime did run successfully: 26 single-output builtin
Function mappings, 15 two-output cases, signed-zero `atan2`, and rounding ties were recorded and
checked against Octave Blocks. See the [numeric cross-reference](SIMULINK_REFERENCE.md)
for the retained fixture and its tested scope.

REA 6.8.0 performed a bounded read-only inspection of the installed Simulink
support directory. Its [sanitized inspection summary](REFERENCE_EVIDENCE.md#rea-installation-inspection)
records 237 entries and zero runtime candidates. This is installation evidence,
not proof of engine behavior; runtime behavior and unread bytes remain unknown.
