# Zero-crossing simulation

Octave Blocks can locate computed Switch, Saturation, and Dead Zone transitions
between requested output times. Enable the feature with
`options.zero_crossings = true`; its default is `false`.

The opt-in default preserves the ordinary fixed-step and generated-C execution
mode. It is a compatibility choice for the current implementation, not full
Simulink zero-crossing parity. Explicit continuous enable/trigger controls are
also supported; see [CONTINUOUS_CONTROLS.md](CONTINUOUS_CONTROLS.md).
RK4 C generation supports the same registered guards; broader event
registration remains advanced-goal work.

## Run the example

From this project directory in Octave:

```octave
addpath (pwd ());
ob_setup ();
model = ob_zero_crossing_example ();
options = struct ('solver', 'rk4', 'zero_crossings', true);
result = ob_run (model, [0 1], options);
assert (abs (ob_scope_data(result, 6)(end) - 1.25) < 1e-8);
result.events
```

The example starts with state zero and derivative -2. A Time-driven Switch
changes the derivative to 3 at time .35. Its final state is
`-2*.35 + 3*(1-.35) = 1.25`, even with only two requested output samples. The
event record identifies block 4, channel 1, at approximately .35.

To use the editor, run `octave_blocks(ob_zero_crossing_example())`. In
**Settings**, set start 0, stop 1, output interval 1, and solver `rk4`, `ode45`,
or `ode15s`. Set the eighth field, **Locate zero crossings (0 or 1)**, to 1.
**Run** plots the Scope and stores the run as `ob_last_result`; inspect
`ob_last_result.events` in Octave. Saved models retain the option.

Scopes plot the requested output rows; hidden event boundaries do not add
plot samples. Use a finer output interval to display the bend in this example's
trajectory as well as its final value.

## Registered guards and hierarchy

| Block | Guard values |
| --- | --- |
| Switch | Control input 2 minus the configured threshold. |
| Saturation | Input minus lower limit; input minus upper limit. |
| Dead Zone | Input minus lower limit; input minus upper limit. |

Each guard is a scalar expression. Matrix signals register one guard per
element at each boundary, using one-based column-major channel numbers.
A scalar Switch control registers one guard even when it selects matrix data;
a matrix control registers one per control element. Equal lower and upper
limits retain distinct lower/upper records. Several records can share one
event time.

Virtual subsystem boundaries are flattened. Registered primitives inside
active enabled bodies participate in the root's event search and shared
continuous state integration. Inactive bodies contribute no inner guards.
Enable and trigger gates default to sampled execution. A child declaring
`execution.control='continuous'` registers its scalar gate and dispatches only
accepted transitions, including changes driven by an upstream primitive.
See [CONTINUOUS_CONTROLS.md](CONTINUOUS_CONTROLS.md). Explicit and inherited
discrete clocks retain the rules in [MULTIRATE.md](MULTIRATE.md) and
[CONDITIONAL.md](CONDITIONAL.md).

Guard descriptors and signal shapes must remain fixed within a searched
interval. A channel-count or layout change raises an error. Active guard
sets can change at scheduled conditional execution boundaries; a newly active
guard has no prior continuous history. Guards must evaluate to finite real
values. Custom Function blocks used to compute them must be deterministic
and avoid external side effects.

## Integration and step size

All three numerical solvers support event mode: `rk4`, `ode45`, and `ode15s`.
The engine integrates trial trajectories using frozen piecewise regimes:
Switch keeps its selected branch, while Saturation and Dead Zone keep their
incoming piecewise formula. Guard values still use the current raw input
signals. This prevents a trial stage from applying the post-crossing dynamics
before the incoming trajectory has reached the event.

The search monitors accepted flow samples and brackets detected transitions.
Localization reconstructs retained candidates from the immutable search origin
at each candidate's physical time, rather than reusing a state whose adaptive
timestamp rounded differently. After accepting a crossing, the engine settles
the outgoing regimes and resumes the remainder of the interval. Native
adaptive solvers run on local elapsed time, avoiding an IDA failure where a
short physical interval at a large absolute origin appears to have coincident
endpoints.

Incoming guard signs from the accepted search samples remain the reference
for arming transitions, including returns to zero. Physical left, right, and
midpoint states are reconstructed from the same origin; bounded bracket
adjustments reconcile an accepted sample with its rounded physical timestamp.
At large absolute origins, double-precision time can quantize the event. For
example, around `1e15` a state-defined mathematical crossing at relative .4 can
first be represented on its outgoing side at .5. The reported event and
subsequent integration use that representable time, not an unrepresentable
ideal timestamp.

`maxstep` bounds event-search intervals for RK4 and native adaptive step sizes.
For example:

```octave
options = struct ('solver', 'ode45', 'zero_crossings', true, ...
                  'maxstep', .01, 'reltol', 1e-8, 'abstol', 1e-10);
result = ob_run (model, [0 1], options);
```

The default `maxstep = Inf` adds no search-size bound. Sign-based detection
cannot guarantee finding tangential roots or an arbitrary number of crossings
between monitored samples. In particular, an even number of crossings can
leave matching endpoint signs. Choose an appropriate maximum step for the
signal's frequency and model dynamics. Smaller steps can also improve RK4's
smooth-trajectory accuracy; event localization does not replace ODE error
control or make a coarse nonlinear RK4 trajectory exact.

Known Step transitions and external input knots already split integration
intervals. Those source discontinuities and sampled-state jumps themselves are
not logged as continuous zero-crossing events. The following interval uses the
new source values and regimes. A guard that remains exactly zero for a plateau
is handled when it departs onto a side inconsistent with its incoming regime.
An initial zero selects its outgoing regime without fabricating a startup event.

## Event records, clocks, and checkpoints

`result.events` and `runtime.events` contain cumulative struct arrays:

| Field | Meaning |
| --- | --- |
| `time` | Physical simulation time of the detected transition. |
| `path` | Public one-based block path; a vector identifies hierarchy. |
| `type` | `Switch`, `Saturation`, `Dead Zone`, or `Conditional Subsystem`. |
| `channel` | One-based column-major input/control element index. |
| `side` | `threshold`, `lower`, `upper`, or `control`. |
| `direction` | +1 for an increasing guard, -1 for a decreasing guard. |
| `boundary` | Configured threshold or limit for that guard. |

Event boundaries are internal integration points. They do not add output rows,
consume unrelated Unit Delay/Euler captures or sample a Rate Transition.
Continuous gates accept lifecycle changes; triggered bodies intentionally
execute their own clock once per trigger. A coincident scheduled clock hit still occurs
once under the ordinary scheduler. Trial evaluation cannot commit discrete or
conditional lifecycle changes.

Runtime contexts preserve incoming guard regimes, endpoint values, and
deduplication history in the implementation-owned `event_memory` field. Copies
and compatible MAT checkpoints retain that history independently. A failed
step leaves the caller's states, pending captures, and accepted event history
unchanged. External side effects of a custom function cannot be rolled back;
see [RUNTIME.md](RUNTIME.md).

A zero plateau may end exactly at a requested stop. The next successful advance
can establish its outgoing side and append an event whose timestamp equals
that previous stop. The engine does not evaluate beyond the requested stop
just to report that departure immediately. Guard identity and exact endpoint
values preserve continuity across output/search boundaries, while already
reported crossings are not duplicated. Reads of cached outputs do not perform
this additional search.

The same holds when a guard reaches exactly zero at a stop and leaves it at
once, as a continuous enable or trigger control does when its zero falls on
an output time. The search after the stop brackets the departure between the
stop and its first sample. When every bisection midpoint is already past
zero, the departure lies within the time tolerance of the stop, and its
record uses the stop's exact timestamp, not the bisection's upper bound.
If the stop already recorded the guard's arrival at zero and the guard
continues through it, that arrival record describes the crossing and no
second record is added. A guard that touches zero and returns to its incoming
side keeps a second record, in the opposite direction, at the same timestamp.
For example, a continuous enable driven by `sin(2*pi*(t-0.2))` on the output
grid `0:0.1:1` records one rising event at exactly 0.2 and one falling event
near 0.7. Before this rule it also recorded a rising event at
0.2000000000007276. The subsystem's activation is unchanged: it is still
dispatched at the bisected time, the first time at which the control is
positive.

Records are kept in time order. One search can find such a departure at the
stop together with another guard's crossing located just after it, for
example an enable `-(t-0.2)^2` that touches zero at the stop 0.2 next to an
enable `t-0.2-1e-13`. The departure, at exactly 0.2, is listed before the
crossing, at 0.2000000000007276. Records with the same time keep the guards'
order.

## Work limits and failures

| Mechanism | Current bound |
| --- | --- |
| Event instants | At most 1,000 per internal event-integration call; continuous-control scheduling also bounds accepted event/reconciliation stops to 1,000 per requested advance. Simultaneous channel records share an instant. |
| Outgoing-mode settling | At most `max(16, 2*active_control_blocks + 2)` iterations, including active enabled descendants. |
| Reconstructed-bracket adjustment | At most 32 attempts in each direction. |
| Bisection | At most 64 iterations. |
| Time convergence | `1e-11` times the reconstructed local bracket width, or the point where double-precision time cannot represent another midpoint. |

Invalid/nonfinite guards, changing layouts, unresolved brackets, unrepresentable
time progress, and nonsettling/chattering regimes raise errors. The solver does
not invent delayed feedback or a sliding-mode solution when opposing vector
fields have no stable outgoing branch. These limits do not implement Simulink's
adaptive zero-crossing guard bands or all its Zeno-handling policies.

## C generation and verification scope

`ob_codegen` accepts `zero_crossings=true` with `solver='rk4'`, selecting a
typed event runtime with frozen incoming regimes, raw guards and accepted
outgoing-mode reconciliation. Pass an appropriate `maxstep` to bound searched
segments; it cannot guarantee arbitrary multiple or tangential roots. Event
exports are RK4 only: `ode45` export is limited to flat models without zero
crossings ([CODEGEN.md](CODEGEN.md#adaptive-ode45-export)), so `ode45` or
`ode15s` with `zero_crossings=true` fails before replacing an output file.
The accelerator likewise runs zero-crossing models compiled with `rk4` only.

Generated contexts retain cumulative `event_count` and `last_event_time`, not
an unbounded copy of Octave's detailed event array. Output reads do not search
beyond the accepted time; a later advance can report a plateau departure at
the previous stop. A continuous control that reaches exactly zero at a stop
follows the same rule as Octave: its departure is counted at the stop, or
merged into the arrival counted there, so `event_count` matches the length of
Octave's event array (4 records for the `sin(2*pi*(t-0.2))` example on
`0:0.1:2`). In the time-order case above, `last_event_time` keeps the latest
counted time (0.2000000000007276, the time of Octave's last record) although
the guards are counted in index order, and the accelerator (`ob_accelerate`)
lists the departure before the crossing, as `ob_run` does. Nonsettling/chattering behavior
returns `OB_EVENT_ERROR=4` without committing caller state. See [CODEGEN.md](CODEGEN.md) for metadata,
other return codes, transactional APIs and export options.

Run `test_ob_zero_crossings()` for the feature's numerical regression coverage.
The suite checks analytic rising/falling and state-defined Switch transitions,
Saturation/Dead Zone integrals, matrix/simultaneous guards, bounded oscillatory
searches, zero plateaus, exact output boundaries (including continuous controls
that reach zero exactly at a stop, and the time order of their records), clock
coincidences, runtime forks/checkpoints, hierarchy, small/large time scales,
failure rollback, chattering, guard-layout changes, persistence, event-export
metadata and protected invalid C-export rejection. Run `Test-EventCodegen.ps1`,
`Test-EventCodegenEdges.ps1` and `Test-EventCodegenHierarchy.ps1` for strict
compiled full-channel comparisons and API checks. Current completed results
belong in [VALIDATION.md](VALIDATION.md).
The tests and independent probes use analytic expectations and native Octave.

MathWorks describes zero-crossing detection as bracketing registered guard
expressions, including Switch conditions and Saturation/Dead Zone limits. Its
adaptive algorithm adds guard-band and repeated-crossing policies beyond this
implementation. See [zero-crossing detection](https://www.mathworks.com/help/simulink/ug/zero-crossing-detection.html),
[algorithms](https://www.mathworks.com/help/simulink/ug/zero-crossing-algorithms.html),
and [fixed-step support](https://www.mathworks.com/help/simulink/ug/zero-crossing-detection-with-fixed-step-simulation.html).

Octave provides `Events` callbacks and event time/state/index outputs, but local
Octave 11.3 probes showed that a terminal event on the first accepted step can
be reported while integration continues. MATLAB documents the same caveat.
This implementation therefore monitors accepted outputs through `OutputFcn`
and controls localization/restarts itself. See
[Octave's MATLAB-compatible solvers](https://docs.octave.org/latest/Matlab_002dcompatible-solvers.html)
and [MATLAB event-location limitations](https://www.mathworks.com/help/matlab/math/ode-event-location.html).
Simulink 26.2 traces (`reference_ob_simulink_continuous.m`) of Switch,
Saturation and Dead Zone crossings feeding Integrators agree within 2e-8 with
ode45 and ode15s, and the crossing times Simulink locates match
`result.events` (`test_ob_simulink_extended`). Simulink's guard bands and
repeated-crossing policies are not compared. See
[REFERENCE_EVIDENCE.md](REFERENCE_EVIDENCE.md#live-simulink-references) for the
evidence limits.
