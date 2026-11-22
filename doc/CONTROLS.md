# Nonlinear control blocks

Saturation, Dead Zone, and Switch are direct-feedthrough blocks. They evaluate
at requested outputs and at intermediate continuous-solver stages, preserving
the incoming signal shape. They also work inside virtual subsystems and before
or after independently clocked discrete blocks.

| Block | `block.value` | Output |
| --- | --- | --- |
| Saturation | `[lower upper]` | Clamp each input element to the inclusive interval. |
| Dead Zone | `[lower upper]` | Zero inside the inclusive interval; subtract the nearest boundary outside it. |
| Switch | Scalar threshold | Select data input 1 where control input 2 is greater than or equal to the threshold; select data input 3 elsewhere. |

Limits must be finite real scalars with `lower <= upper`. Equal limits are
allowed. A Switch threshold must be a finite real scalar. Switch data inputs
must have identical shapes. Its control may be a scalar, selecting one entire
data input, or a matrix with the same shape, selecting per element. Port
numbers determine input order, even if connection rows are rearranged.

All inputs must be nonempty finite real numeric scalars, vectors, or matrices.
The Octave evaluator converts these block inputs to full double arrays. Both
Switch data branches are evaluated by the graph and must be valid, including
the branch that is not selected. Switch does not suspend state updates in
upstream blocks. All three inputs contribute direct dependencies, so a loop
through any of them requires a stateful block.

Logical arrays are currently rejected at these inputs. A custom Octave
function producing a logical mask can return `double(mask)` to supply numeric
control values; the configured numeric threshold still applies.

In the editor, use **Saturation**, **Dead Zone**, or **Switch** to add a block.
**Edit** changes its limits or threshold. Connect a Switch using destination
ports 1, 2, and 3 as described above. **Control demo** loads an example with
these blocks. Parameters and connections are saved with the model and covered
by Undo/Redo.

The same blocks can be built in Octave:

```octave
model = ob_example ();
model.blocks(2).type = 'Saturation';
model.blocks(2).value = [0.25 0.75];
result = ob_run (model, [0 0.5 1]);
assert (isequal (ob_scope_data (result, 3), [0.25; 0.5; 0.75]));

model.blocks(2).type = 'Dead Zone';
result = ob_run (model, [0 0.5 1]);
assert (isequal (ob_scope_data (result, 3), [-0.25; 0; 0.25]));
```

## Integration and compatibility

Known Step transitions and external-input knots split integration intervals.
Set `options.zero_crossings = true`, or enable **Locate zero crossings** in
Settings, to locate computed Switch thresholds and both Saturation/Dead Zone
limits. The runtime freezes the incoming piecewise formula during trial
integration, locates a guard crossing, then resumes in its outgoing regime.
RK4, ode45, and ode15s support this mode, including matrix controls and active
enabled bodies. Events do not create discrete clock hits. See
[ZERO_CROSSINGS.md](ZERO_CROSSINGS.md) for history, precision, and detection
limits. The option defaults to false; without it, computed crossings are
resolved through the solver's ordinary stages and accuracy depends on the
step size and tolerances.

The piecewise definitions follow the public MathWorks references for
[Saturation](https://www.mathworks.com/help/simulink/slref/saturation.html),
[Dead Zone](https://www.mathworks.com/help/simulink/slref/deadzone.html), and the
`u2 >= Threshold` criterion of
[Switch](https://www.mathworks.com/help/simulink/slref/switch.html). Verification
uses analytical expected values and comparisons between Octave and generated
C; it does not establish a comparison with a running Simulink model.
The current subset has scalar limits/thresholds, one output per block, and
the single Switch criterion above. Additional selection criteria, data-branch
scalar expansion, saturation status ports, dynamic limits, fixed-point and
Boolean-specific behavior, and broader reset/event variants remain compatibility gaps.
Continuous enable/trigger controls are available through the explicit setting
described in [CONTINUOUS_CONTROLS.md](CONTINUOUS_CONTROLS.md).

All three blocks support C export with event detection disabled, statically
checked shapes and finite full real-double parameters. Event-enabled export
fails before replacing the destination. Generated runtime failures preserve the model
context as described in [CODEGEN.md](CODEGEN.md).
