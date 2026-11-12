# Zero-crossing simulation

Octave Blocks can locate computed Switch, Saturation, and Dead Zone transitions
between requested output times. Enable the feature with
`options.zero_crossings = true`; its default is `false`.

The opt-in default preserves the existing fixed-step and generated-C execution
mode. It is a compatibility choice for the current implementation, not full
Simulink zero-crossing parity. Explicit continuous enable/trigger controls are
also supported; see [CONTINUOUS_CONTROLS.md](CONTINUOUS_CONTROLS.md).
Event-enabled C generation and broader event registration remain advanced-goal work.

## Run the example

From this project directory in Octave:

```octave
addpath (pwd ());
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

`ob_codegen` explicitly rejects `zero_crossings = true` before replacing a C
output file. Disabling the option selects the existing numerical mode; it does
not establish equality with an event-enabled run. No event-enabled generated-C
parity is claimed. See [CODEGEN.md](CODEGEN.md).

Run `test_ob_zero_crossings()` for the feature's numerical regression coverage.
The suite checks analytic rising/falling and state-defined Switch transitions,
Saturation/Dead Zone integrals, matrix/simultaneous guards, bounded oscillatory
searches, zero plateaus, exact output boundaries, clock coincidences, runtime
forks/checkpoints, hierarchy, small/large time scales, failure rollback,
chattering, guard-layout changes, persistence, and protected C-file rejection.
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
The MathWorks comparison uses public documentation, not a running Simulink
trajectory; live Simulink is unavailable in the installed MATLAB environment.
