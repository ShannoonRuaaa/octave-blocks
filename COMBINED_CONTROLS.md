# Combined enable and trigger controls

Execution modes `enabled_rising`, `enabled_falling`, and `enabled_either`
require two scalar control inputs after the numbered data inputs: enable,
then trigger. The body executes on the selected trigger edge while enable is
positive. `initial_control` is the prior trigger value, defaulting to zero.
Both controls must be finite real scalars.

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
ordering. Ancestor suspension and the exact enable-only reset lifecycle are
project contracts awaiting direct reference traces.

On 2026-11-17 MATLAB R2026b Update 1 ran locally, but `load_system` was absent:
the Simulink engine is not installed. A positive license test did not establish
engine availability. `reference_ob_combined.m` retains 18 independent cases;
MATLAB syntax checks and missing-engine rejection passed, but no Simulink trace
was produced. This feature does not establish full Simulink parity.

For nested subsystems, MathWorks documents that the [child Enable setting
takes precedence](https://www.mathworks.com/help/simulink/ug/enabled-subsystems.html).
Octave Blocks treats an ancestor disable as an effective disable for each
descendant Enable. On reactivation, a `held` child resumes its own state
and a `reset` child returns to its initial state, regardless of the parent's
setting. For a combined child, reset waits for its next accepted trigger;
its held output remains available until that trigger. Trigger history stays
frozen while the ancestor is disabled. These lifecycle details and the
explicit prior trigger value still await direct Simulink comparison.
`reference_ob_nested_reset.m` is a standalone harness for that comparison.

## Verification

`test_ob_combined_controls()` exercises all three Octave solvers, directional
triggers, held/reset policies, lazy activation, continuous guard localization,
sparse/dense output requests, rollback, and checkpoint continuation.
`Test-CombinedCodegen.ps1` compiles strict C99 with warnings treated as errors
and compares every numerical channel against Octave. It includes the policy
matrix, continuous sine guards, matrix data, and a nested clocked ancestor.
`test_ob_nested_reset()` checks independent Unit Delay traces for two and
three levels of Enable nesting, nested combined controls, and enabled
subsystems inside trigger-only wrappers. The cases cover both sampled and
continuous outer Enable handling and also run in C.
These checks are registered in `Launch-Blocks.ps1 -SelfTest`.
