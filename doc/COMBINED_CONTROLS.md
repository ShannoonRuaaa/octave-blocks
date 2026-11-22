# Combined enable and trigger controls

Execution modes `enabled_rising`, `enabled_falling`, and `enabled_either`
require two scalar control inputs after the numbered data inputs: enable,
then trigger. The body executes on the selected trigger edge while enable is
positive. Both controls must be finite real scalars.

The first evaluation of the trigger never executes the body. It records the
sample as the prior trigger value, so `initial_control` has no effect in
these modes. Simulink's Enabled and Triggered Subsystem behaves the same way:
zero, positive, negative and compatibility InitialTriggerSignalState values
give identical traces. The first evaluation is the context's first major hit.
It happens even while enable is false, and it may come later, when a disabled
ancestor or a trigger-only wrapper first runs the subsystem. A zero first
sample therefore still allows the next positive sample to fire a rising edge.
An ancestor reset never re-arms this rule. Trigger-only modes follow the same
rule when `initial_control = 'compatibility'`, Simulink's default trigger
state (see [CONDITIONAL.md](CONDITIONAL.md#initial-trigger-control)).

`states` and `outputs` independently accept `held` or `reset`. State reset is
pending after re-enabling and consumed by the next body execution. Enabling
alone does not execute or initialize the body. Output reset takes effect while
disabled. Trigger history advances even while this subsystem's own enable is
false. An inactive ancestor suspends descendant execution and history.

The body follows triggered-body restrictions: discrete blocks and inherited
rates, with no continuous Integrator or continuous-control descendant.
Sampled controls use the enclosing execution clock. Explicit
`control='continuous'` requires `zero_crossings=true`; enable and trigger have
separate guard channels (1 and 2). The trigger guard retains side `control`;
the enable guard has side `enable`. The continuous example is exportable with
the public RK4 C generator:

```octave
model = ob_combined_continuous_example ();
options = struct ('zero_crossings', true, 'maxstep', .08);
result = ob_run (model, [0 1.8], options);
ob_codegen (model, 'combined.c', [0 1.8 1.8], options);
```

The final Scope value is 1.44, sampled at the trigger at 1.2. The separate
sampled example is `ob_combined_control_example()`.

## Reference evidence and limits

MathWorks documents [combined execution](https://www.mathworks.com/help/simulink/ug/triggered-and-enabled-subsystems.html),
[trigger initialization](https://www.mathworks.com/help/simulink/slref/trigger.html),
and [disabled output policies](https://www.mathworks.com/help/simulink/ug/set-output-values-when-conditional-subsystem-is-disabled.html).
Own-disabled trigger tracking follows the documented trigger-then-enable
ordering.

Simulink 26.2 (MATLAB R2026b Update 1) traces now cover these rules. The 18
records of `reference_ob_combined.m` (`simulink-combined-reference.json`)
match exactly: the policy matrix, the enable-only reset lifecycle, own-disabled
trigger history and all four initial trigger states. The probes of
`reference_ob_conditional_probes.m` (`simulink-conditional-probes-reference.json`)
settle the first-evaluation rule above. They show a zero first sample firing
on the next rising sample and a first evaluation while disabled. They also
show a first evaluation delayed by a disabled ancestor (rising, falling and
either) or by a trigger-only wrapper that has not fired yet, and they cover
coincident enable and trigger edges. `test_ob_simulink_conditional` checks every record, and
[CONDITIONAL.md](CONDITIONAL.md#matlab-and-simulink-evidence) lists the
producers. Combined continuous controls under a variable-step solver have
not been compared live (only root trigger-only ones have, under ode45), so
this does not establish full Simulink parity.

For nested subsystems, MathWorks documents that the [child Enable setting
takes precedence](https://www.mathworks.com/help/simulink/ug/enabled-subsystems.html).
Octave Blocks treats an ancestor disable as an effective disable for each
descendant Enable. On reactivation, a `held` child resumes its own state
and a `reset` child returns to its initial state, regardless of the parent's
setting. For a combined child, reset waits for its next accepted trigger;
its held output remains available until that trigger. Trigger history stays
frozen while the ancestor is disabled. An ancestor reset keeps a combined
child's trigger history, whether or not the child has executed yet.

A trigger-only child behaves differently under an ancestor reset. Its states
restart, but its held outputs remain until its next trigger, even across
repeated resets. Its trigger history depends on `initial_control`:

- A numeric value restarts the history from that value. After the reset, a
  sample that is an edge from that value fires.
- `'compatibility'` keeps the history. The last evaluated sample stays the
  previous value, with its edge flags, and a first evaluation that has not
  happened yet stays pending. The no-trigger rule is not re-armed, and the
  history does not restart from zero.

The `D` probes separate these rules. They execute twice before each reset, so
an execution at the re-enabling sample changes the held output. Under
`'compatibility'` (D1, D2), a re-enabling sample that matches the last
evaluated one does not fire, while `negative` and `zero` (D3, D4) fire on the
edge from their configured value. The `E` probes show that a re-enabling
sample that is an edge from the last evaluated one does fire, so the rule
was not re-armed. The `F` probes isolate the edge flags: the last evaluated
transition is a rise or fall into zero, and the re-enabling sample continues
it (0 to +1, or 0 to -1). That continuation is a new edge only if the flags
were cleared. Under `'compatibility'`
nothing fires there (F1 to F3), as under a `held` outer (F5), so the flags are
kept with the previous value. `zero` restarts with cleared flags and fires
(F4).

An Enabled grandchild inside a trigger-only child keeps its own policy. A
combined grandchild inside it keeps its trigger history, states and held
output, so it is not re-armed for a first evaluation either. A trigger-only
grandchild inside a trigger-only wrapper first evaluates when the wrapper
first executes (V1 to V3). An outer reset does not re-arm it either (V4).
A `'compatibility'` trigger-only wrapper around an Enabled body keeps its
history under an outer reset too (`nested_compat_wrapper_*` and
`N2_wrapper_retrigger_compat_*`, the topology of the `test_ob_nested_reset`
compat wrapper cases).
Simulink 26.2 traces confirm all of these lifecycle details:
`reference_ob_nested_reset.m` for Enable nesting, and the nested probes of
`reference_ob_conditional_probes.m` for combined and trigger-only children.

## Verification

`test_ob_combined_controls()` exercises all three Octave solvers, directional
triggers, held/reset policies, lazy activation, continuous guard localization,
sparse/dense output requests, rollback, and checkpoint continuation.
`Test-CombinedCodegen.ps1` compiles strict C99 with warnings treated as errors
and compares every numerical channel against Octave. It includes the policy
matrix, continuous sine guards, matrix data, and a nested clocked ancestor.
`test_ob_nested_reset()` checks independent Unit Delay traces for two and
three levels of Enable nesting, nested combined controls, and enabled
subsystems inside trigger-only wrappers, with numeric and `'compatibility'`
wrapper trigger states. The cases cover both sampled and continuous outer
Enable handling and also run in C.
`test_ob_simulink_conditional()` compares every recorded Simulink trace. The
C test also compiles the Simulink probes for first evaluation, delayed first
evaluation, kept combined history, held trigger-only outputs and combined
grandchildren of trigger-only wrappers. It also compiles the trigger-only
`'compatibility'` probes: root first samples, delayed and wrapped first
evaluations, ancestor resets with kept edge flags, and two continuous
triggers. It checks them in
both C emitters against the Simulink trace; the continuous ones, exported
with RK4, are checked against Octave.
`Launch-Blocks.ps1 -SelfTest` runs these checks; `test_ob_simulink_conditional`
is not yet registered there.
