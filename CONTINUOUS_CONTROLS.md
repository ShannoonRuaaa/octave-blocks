# Continuous conditional controls

Conditional Subsystems can locate enable and trigger transitions between
requested output times. Set the child model's `execution.control` to
`'continuous'` and enable `options.zero_crossings`. The default control timing
is `'sampled'`, preserving the existing rules in [CONDITIONAL.md](CONDITIONAL.md).

This is an explicit Octave Blocks configuration. It does not implement
Simulink's automatic sample-time propagation or establish full subsystem parity.

## Run the example

```octave
[model, options] = ob_continuous_control_example ();
result = ob_run (model, [0 1], options);
assert (abs (ob_scope_data(result, 6)(end) - .5) < 2e-8);
result.events
```

The example integrates `x' = 1` while `(t-.2)*(.7-t) > 0`. Its initial state is
zero, and the held final output is .5. Only the requested times appear in
`result.t`; internal gate events do not add output rows. Use a finer output
grid to display the active interval in a Scope plot.

For an existing child model:

```octave
child.execution.mode = 'enabled';
child.execution.control = 'continuous';
child.execution.states = 'held';
child.execution.outputs = 'held';
child.execution.initial_outputs = {0};
options = struct ('solver', 'ode45', 'zero_crossings', true, ...
                  'maxstep', .05, 'reltol', 1e-8, 'abstol', 1e-10);
```

Assign the child back to its enclosing Subsystem block before running. The last
input remains the scalar control port; preceding inputs are numbered data ports.
Finite real numeric and logical scalar controls are accepted. Initial output
cells continue to define the shape of each numbered output.

In the editor, select the Subsystem and choose **Edit**. Set **Control timing:
sampled or continuous** to `continuous`, then enable **Locate zero crossings**
in the root **Settings** dialog. Changing to continuous timing clears that
Subsystem's enclosing explicit sample-time row to `[0 0]`; Undo restores the
whole edit. Direct model construction with continuous control and a nonzero
enclosing sample period is rejected. Independent rates inside an enabled body
remain supported. Saving and loading retain both the control timing and solver
option.

## Activation and execution

| Mode | Accepted control behavior |
| --- | --- |
| `enabled` | Activate while the scalar control is strictly positive; deactivate at zero or below. |
| `rising` | Execute on a negative-to-zero/positive or zero-to-positive transition, subject to the continuous plateau rule below. |
| `falling` | Execute on the corresponding decreasing transition. |
| `either` | Execute on either direction. |

RK4, ode45, and ode15s support this timing mode. Trial stages evaluate guards
and active flow graphs without changing activation, trigger history, or clocks.
Lifecycle changes occur only after an accepted event or scheduled boundary.
After an enable change, the runtime recomputes the active continuous-state paths
before integrating the remaining interval.

An enabled child's continuous Integrators share the parent's solver stages.
While active, its current data inputs also refresh pure feedthrough outputs,
even when the child has no Integrator or independent clock. Disabling freezes
its continuous states. `states='reset'` reconstructs the child on reactivation;
`states='held'` retains it. Disabled outputs independently hold their last value
or reset to `initial_outputs`. A left-limit output snapshot is retained before
deactivation, so a held feedthrough output reflects the disable boundary.

Inactive ancestors suppress descendant integration and inner guard evaluation.
Active enabled ancestors propagate current inputs into nested continuous
controls. Resetting an ancestor currently reconstructs nested contexts;
independent descendant reset-policy precedence remains a compatibility gap.

Triggered bodies hold their states and outputs between executions. A trigger
executes its body once using data evaluated at the accepted event time. The
body still cannot contain continuous Integrators, independent sample clocks,
or descendants configured with continuous control. Combined enable-and-trigger,
function-call, and other atomic variants remain outside this implementation.

## Discrete clocks and elapsed active time

An enable transition is distinct from a child discrete sample. Gate-only
activation/deactivation does not capture or commit inherited Unit Delay/Euler
state, sample a Rate Transition, or create an unrelated parent clock hit.
Ordinary requested-output executions still provide the inherited discrete
clock. A triggered body intentionally uses each trigger execution as its own
discrete clock.

For inherited Euler state in a continuously enabled body, the runtime tracks
elapsed active duration between ordinary inherited executions, excluding
disabled pauses. It applies that duration to the derivative captured at the
previous discrete execution, retained in `major_current`. Flow refreshes and
gate observations do not replace that capture. Retained activation intervals
survive pauses; reset activation reconstructs the state and interval metadata.
These are the project's explicit Euler semantics, not a claim covering every
Simulink Discrete-Time Integrator method.

Independent inner clocks keep their phase relative to the root start time.
Disabled intervals skip hits without replaying them or resetting their origin.
An accepted frame reconciles a continuous enable before deciding whether a
coincident inner hit may execute. Each due clock is processed once.

The public Switch rule remains `control >= threshold`. If a Switch produces a
positive enable at an exact crossing/clock coincidence, the child can initialize
and execute that due inner clock. For example, a Switch-controlled positive
pulse with exact boundaries .25 and .75 and an inner period .25 executes inner
hits at .25, .5, and .75. Its outgoing disabled regime is reconciled before any
further physical time is integrated. A raw enable value of zero remains
disabled under the strict-positive rule; this differs from a Switch output
whose equality branch is positive.

## Trigger initialization and zero plateaus

`initial_control` is a numeric prior-control convention and defaults to zero.
An initially negative signal can therefore execute a `falling` or `either`
body at the start time. Set `initial_control = -1` when a matching negative
prior sign should suppress that startup edge. Matching positive initialization
can similarly prearm a positive initial signal.

Continuous timing preserves the most recent edge across unchanged control
signs. Extra requested outputs or unrelated clock hits on a zero plateau do
not rearm it. A same-direction arrival at zero and subsequent departure from
zero are suppressed until an opposite transition is observed. The sampled
mode retains its existing sample-based plateau convention.

This continuous plateau policy is a defined project behavior. MathWorks'
documented consecutive-step suppression concerns discrete-time triggering;
live continuous-plateau compatibility has not been established. The separate
Simulink first-evaluation compatibility option is also not implemented here.

## Event ordering and records

The event kernel returns accepted continuous-gate roots to the scheduler.
In models containing continuous controls, it also returns primitive
Switch/Saturation/Dead Zone roots: changing an upstream primitive can change
a gate discontinuously at that same physical time.

At an exact primitive root, public equality can still describe the incoming
branch. Before advancing farther, outgoing-mode settling can request a
zero-time reconciliation using the settled flow. This pass accepts gate changes
while skipping clock rebasing, due masks, tick advancement, state capture and
commit, and sample-hit recording. It does not repeat a coincident clock.
Event/reconciliation dispatch is bounded to 1,000 calls per requested runtime
advance; unresolved/chattering behavior raises an error.

`runtime.events` and `result.events` use the fields documented in
[ZERO_CROSSINGS.md](ZERO_CROSSINGS.md). Gate records have `type='Conditional
Subsystem'`, `side='control'`, channel 1, boundary 0, and an ordinary positive
public block path. Direction records the sign change of the control. A record
does not necessarily mean that a rising-only or falling-only body executed;
opposite transitions still update its trigger history.

Known Step transitions and external input knots return to accepted scheduling
boundaries so their current values reach the gate. Such source jumps dispatch
controls even when no smooth root record is produced. Inspect a conditional
snapshot's `executions` for actual body dispatches and the appropriate
`sample_hits` for discrete timing, rather than inferring either from event count.

The search inherits the limits in [ZERO_CROSSINGS.md](ZERO_CROSSINGS.md): choose
an appropriate `maxstep` for oscillatory controls. Arbitrary multiple crossings,
tangencies, and unrepresentable ideal times are not guaranteed. Localization
does not make a coarse nonlinear RK4 trajectory exact.

## Contexts, validation, and export

Runtime copies and compatible MAT checkpoints preserve activation, trigger
history, elapsed active intervals, major discrete captures, held outputs,
clocks, event history, and boundary memory independently. A failed advance
leaves the caller's context unchanged. Cached output reads do not dispatch
events or execute a body. External side effects performed by custom functions
cannot be rolled back; those functions must be deterministic and avoid effects
outside the runtime.

Compiled runtime metadata caches structural classifications, input routing,
validated execution options, and port maps as ordinary serializable data. The
graph, execution parameters, and input definitions are immutable for public
context use: reinitialize after edits. Internal input-table isolation tests
verify cache behavior; they do not define a public context-editing API. Compatible legacy contexts
without the metadata use the validation/classification fallback. Dynamic
control/data values, shapes, finite domains, and times remain checked during
execution.

A continuous control requires `zero_crossings=true`; runtime initialization
rejects the model otherwise. C generation rejects a model containing continuous
controls even if the caller turns that global option off. Turning it off does
not silently convert the declared model to sampled timing. Generated event
code remains future work; see [CODEGEN.md](CODEGEN.md).

## Verification and reference scope

Run `test_ob_continuous_controls()` for the feature regression suite. Its cases
cover analytical enabled-state traces, held/reset policies, pure feedthrough
integration, repeated triggers with current data, triggered Delay capture,
zero endpoints/plateaus, logical controls, global inner clocks, root clock
isolation, source jumps, primitive-to-gate ordering, coincident activation,
nested inactivity, forks/checkpoints, rollback, persistence, and rejection paths.
These are the intended checks; this document does not assert a final full-gate
result. Verification status belongs in [ADVANCED_PLAN.md](ADVANCED_PLAN.md).

MathWorks describes enabled activation at major evaluations, inner discrete
sample timing, and retained/reset behavior in
[Using Enabled Subsystems](https://www.mathworks.com/help/simulink/ug/enabled-subsystems.html).
The held-state/output contract and inherited-clock restrictions for triggered
bodies are described in
[Using Triggered Subsystems](https://www.mathworks.com/help/simulink/ug/triggered-subsystems.html).
Simulink derives subsystem timing from controls or contents; this project's
explicit declaration is not equivalent to that propagation. See
[Sample Times in Subsystems](https://www.mathworks.com/help/simulink/ug/managing-sample-times-in-subsystems.html).
Its trigger-initialization options are described in the
[Trigger reference](https://www.mathworks.com/help/simulink/slref/trigger.html).

The comparison uses official documentation, analytic reference values, and
Octave execution. The installed MATLAB environment lacks a runnable Simulink
engine, so no live Simulink trajectory or full nested-policy comparison is
claimed. Automatic rate propagation, nested reset-policy overrides, broader
gate variants, implicit DAE support, and event-enabled C export remain tracked
advanced-goal work.
