# Simulink cross-reference for Octave Blocks

Target: MATLAB/Simulink R2026b concepts. The implementation uses original
Octave code; it does not use MATLAB source or Simulink binaries.

| Simulink basic | Documented behavior | Octave Blocks status |
| --- | --- | --- |
| Diagram editor | Blocks have ports and signal lines; one output can branch to several inputs. [Connect Blocks](https://www.mathworks.com/help/simulink/ug/connect-blocks.html) | Explicit source/target ports and numbered pins; branching to multiple targets/ports; click to connect and drag to move. |
| Sources | Constant and Step generate signals; Step uses time, initial and final values. [Step](https://www.mathworks.com/help/simulink/slref/step.html) | Constant, Time, Step. |
| Math blocks | Gain, Sum and Product depend on current inputs. [Execution Order](https://www.mathworks.com/help/simulink/ug/controlling-and-displaying-the-sorted-order.html) | Gain, Sum and Product evaluated in topological order. |
| Function return ports | MATLAB functions can return multiple values, including dimensions and reduction indices. [size](https://www.mathworks.com/help/matlab/ref/double.size.html), [max](https://www.mathworks.com/help/matlab/ref/double.max.html), [min](https://www.mathworks.com/help/matlab/ref/double.min.html) | Function blocks call ordinary Octave functions with an explicit output count and route each return by numbered port. C export supports the two-output, one-input builtin size/max/min signatures. This is not full Simulink MATLAB Function block support. See [MULTIOUTPUT.md](MULTIOUTPUT.md). |
| Limits and dead zones | Clamp at limits or emit excess outside a zero region. [Saturation](https://www.mathworks.com/help/simulink/slref/saturation.html), [Dead Zone](https://www.mathworks.com/help/simulink/slref/deadzone.html) | Matrix-preserving primitives with fixed scalar lower/upper limits; numerical behavior follows the piecewise definitions. Optional computed guard localization under all three solvers; additional status ports remain gaps. |
| Zero crossings | Registered guards identify discontinuities and piecewise boundaries. [Zero-crossing detection](https://www.mathworks.com/help/simulink/ug/zero-crossing-detection.html) | Optional Switch/Saturation/Dead Zone localization with frozen regimes, matrix guards, event history and rollback. Explicit continuous enable/trigger controls are supported in Octave; reset variants and generated event code remain gaps. See [ZERO_CROSSINGS.md](ZERO_CROSSINGS.md). |
| Signal selection | A middle control input chooses between the first and third data inputs. [Switch](https://www.mathworks.com/help/simulink/slref/switch.html) | The `u2 >= Threshold` criterion with scalar threshold and scalar or per-element control. Additional criteria, data expansion, and Boolean-specific semantics remain gaps. |
| Stateful blocks | Unit Delay emits an initial condition, then the previous input; integrators hold continuous or discrete state. [Unit Delay](https://www.mathworks.com/help/simulink/slref/unitdelay.html), [Integrator](https://www.mathworks.com/help/simulink/slref/integrator.html), [Discrete-Time Integrator](https://www.mathworks.com/help/simulink/slref/discretetimeintegrator.html) | Unit Delay, RK4/ode45/ode15s continuous Integrator, and forward Euler discrete integrator; stateful feedback allowed. |
| Linear systems | Explicit state-space equations and proper Laplace-domain transfer functions. [State-Space](https://www.mathworks.com/help/simulink/slref/statespace.html), [Transfer Fcn](https://www.mathworks.com/help/simulink/slref/transferfcn.html) | Editable virtual-diagram builders for continuous MIMO/autonomous state-space and proper SISO transfer functions; analytical and C comparisons. Sparse/time-varying/descriptor systems and native block/file parity remain gaps. See [LINEAR_SYSTEMS.md](LINEAR_SYSTEMS.md). |
| Execution order | Direct-feedthrough dependencies determine output order; stateful blocks can break a loop. [Simulation Concepts](https://www.mathworks.com/help/simulink/slref/simulink-concepts-simulation.html) | Topological order for acyclic graphs; supported numeric feedback components solved simultaneously. |
| Algebraic loops | Smooth real-double constraints are solved at derivative evaluations; loop code generation is unsupported. [Algebraic loops](https://www.mathworks.com/help/simulink/ug/algebraic-loops.html) | Octave `fsolve` for supported fixed-shape numeric components, singularity and residual checks, warm starts, no C export. See [ALGEBRAIC.md](ALGEBRAIC.md); this is a documentation comparison, not a live Simulink trace. |
| Simulation configuration | Start/stop time and solver step settings govern simulation. [Run Simulations](https://www.mathworks.com/help/simulink/ug/controlling-execution-of-a-simulation.html) | Editable start/stop, output interval, RK4 or Octave adaptive ODE solver, tolerances, adaptive/event maximum step and optional zero-crossing detection. |
| Scope | Shows signals over simulation time. [View Data](https://www.mathworks.com/help/simulink/view-simulation-results.html) | Plots real scalar, vector, and matrix signals after a run; results available as `ob_last_result`. |
| Subsystems | Group blocks behind input/output ports. [Subsystems](https://www.mathworks.com/help/simulink/ug/creating-subsystems.html) | Editable nested virtual subsystems with numbered Inport/Outport interfaces, multiple outputs, shared state integration, and hierarchy-aware results. |
| Conditional execution | Enable/trigger controls determine when a child executes and how it retains state and output. [Enabled](https://www.mathworks.com/help/simulink/ug/enabled-subsystems.html), [Triggered](https://www.mathworks.com/help/simulink/ug/triggered-subsystems.html) | Sampled or explicitly continuous enabled/rising/falling/either controls with lazy child contexts, reset/held policies, explicit clocks, nested snapshots, and editor settings. Enabled continuous bodies share the parent Octave solver or generated RK4 stages. Octave and C support globally aligned enabled inner clocks; continuous controls remain Octave-only, with nested policy parity and broader event semantics still gaps. See [CONTINUOUS_CONTROLS.md](CONTINUOUS_CONTROLS.md). |
| Sample times | Periods and offsets define discrete hit times; inherited rates propagate through the compiled model. [Types of Sample Time](https://www.mathworks.com/help/simulink/ug/types-of-sample-time.html) | Explicit per-block periods/offsets for Delay, Euler, and sample/hold transitions; the local `[0 0]` value retains output-schedule behavior. This schema is not a Simulink sample-time encoding. |
| Rate transitions | Behavior depends on rates, task priorities, integrity/determinism settings, and target configuration. [Rate Transition](https://www.mathworks.com/help/simulink/slref/ratetransition.html) | Current Rate Transition is a deterministic single-thread sample-and-hold at its destination clock. Target-specific buffering and transfer-latency policies remain compatibility gaps. |

The multirate implementation uses offsets relative to this simulator's start
time and explicitly configured discrete clocks. Simulink's full sample-time
propagation, asynchronous timing, and additional sample-time classes
are not yet implemented. See the linked [sample-time documentation](https://www.mathworks.com/help/simulink/ug/types-of-sample-time.html).
Simulink Rate Transition can select hold, delay, or buffering behavior according
to its configuration; this implementation currently provides the hold behavior
described in [MULTIRATE.md](MULTIRATE.md), with broader transfer semantics still
tracked against the [official reference](https://www.mathworks.com/help/simulink/slref/ratetransition.html).

## REA evidence

The official [Reverse Engineer Anything](https://github.com/morluto/rea) CLI
was run with `inspect-desktop-application` against the installed
`C:\Program Files\MATLAB\R2026b\toolbox\simulink` directory. Its read-only
[inspection summary](REFERENCE_EVIDENCE.md#rea-installation-inspection) records 237 directory entries.
This scan found installation files but did not observe execution or establish
how the simulation engine works. The behavioral statements above come from the
linked MathWorks documentation. A deeper REA study should use a small,
specific feature and compare its behavior against a running Simulink model.

The conditional milestone attempted that live comparison. MATLAB R2026b
Update 1 runs locally, but its [environment probe](matlab-environment.json)
reports no installed Simulink and no `load_system`, even though the feature
license test succeeds. [reference_ob_conditional.m](reference_ob_conditional.m)
is a reproducible comparison harness for an installation with Simulink.
Its trace comparison has not run successfully here.

A fresh REA 6.8.0 [bounded inspection summary](REFERENCE_EVIDENCE.md#rea-installation-inspection)
records 237 support-directory entries, zero runtime candidates, and explicit
limitations about unobserved execution. Current conditional checks therefore
combine the linked public behavior definitions with analytical Octave traces;
they do not claim a live Simulink match.

## Live MATLAB numeric reference

MATLAB R2026b Update 1 successfully produced native results for all 26
Function operations currently mapped by the C exporter (19 unary and seven
binary), plus signed-zero `atan2` and rounding ties. It also produced 15
two-output cases for `size`, `max`, and `min`, covering scalars, rows, columns,
matrices, ties, and signed zero. The retained
[numeric reference](matlab-numeric-reference.json) records the actual inputs,
shapes, outputs, indices, and MATLAB version. Separate input/output zero-sign
flags preserve information that JSON numeric serialization would erase.
`test_ob_matlab_numeric` checks Octave
Blocks against those values; it passed at a scaled tolerance of 1e-13.
The C verification suite separately compares the supported builtin mappings
and signed-zero downstream behavior with Octave.

Regenerate the fixture in MATLAB using
`reference_ob_matlab_numeric('matlab-numeric-reference.json')` from this folder.
Its producer refuses to run under Octave. Routine tests use the retained
fixture and do not require MATLAB. These finite scalar/matrix cases establish
measured numeric agreement for their inputs; they do not establish full
MATLAB compatibility or Simulink execution agreement.
