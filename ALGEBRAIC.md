# Algebraic-loop simulation

Octave Blocks can solve supported direct-feedthrough feedback equations instead
of rejecting every cycle. The compiler groups cyclic dependencies into strongly
connected components and evaluates those components in dependency order. A
component is solved simultaneously as `z - F(z) = 0`, using Octave's `fsolve`.
This supports noncontractive feedback as well as smooth nonlinear equations;
it is not limited to repeatedly substituting a previous output into an input.

```octave
model = ob_algebraic_example ();
result = ob_run (model, 0:.05:5);
octave_blocks (model);
```

The example couples an Integrator to the constraint `z = u - x - z`, with
`x' = z` and a Step source for u. Eliminating z gives `x' = (u-x)/2`. The
algebraic constraint must be solved again for each continuous solver stage.
This is index-1 algebraic elimination around an ODE solver, not a general DAE
or descriptor-system solver.

## Supported components

A cyclic component may contain Gain, Sum, Product, single-output Function,
Scope, Inport, and Outport blocks. Every signal in that component must remain
a nonempty, finite, real, full double matrix with a fixed shape. Existing
matrix multiplication and addition rules still apply.

Virtual subsystem boundaries are flattened, so a supported loop can cross
them. A supported loop wholly inside an enabled or triggered subsystem is
solved when that body's runtime evaluates it. A loop crossing a conditional
subsystem boundary is rejected: its lifecycle and structured outputs are not
part of the numeric constraint solver.

Cycles containing Rate Transition, Saturation, Dead Zone, Switch, or
multiple-output Function cores/proxies are also rejected. Those blocks can
still appear outside the solved component. Integrator, Unit Delay, and
Discrete Integrator outputs break current-input dependencies and retain their
existing state and sampling behavior. An acyclic model follows the existing
execution path without calling the algebraic solver.

Function blocks inside a loop must represent smooth, deterministic functions
without side effects. Residual and finite-difference Jacobian evaluation can
call them many times at trial inputs. The runtime cannot detect or undo file
writes, global changes, random-number consumption, or other effects of a user
function. Successful evaluation at one sample does not establish smoothness
or convergence elsewhere.

## Initial guesses and signal dimensions

Set `algebraic_initial` on an original block to choose its initial algebraic
signal estimate. A missing or empty field defaults to scalar double zero.
The nonempty value must be a finite, real, full double matrix. Its shape is
the required output shape for that cyclic block for the entire runtime.

For example, if blocks 2 and 3 are the Sum and Gain in a vector feedback
component, specify both signal shapes:

```octave
model.blocks(2).algebraic_initial = zeros (2, 1);
model.blocks(3).algebraic_initial = zeros (2, 1);
```

Every cyclic signal needs a suitable guess; a vector guess on only one block
does not propagate dimensions to the others. Specify guesses inside the
original child model for hierarchical blocks. Accepted solutions become the
next guesses in that runtime context. Initial guesses can select different
roots when a nonlinear equation has several solutions; no uniqueness or root
selection guarantee is made.

Model save/load preserves `algebraic_initial`. Runtime copies and MAT
checkpoints preserve accepted guesses independently, along with the existing
states and clock captures. The editor can run a model prepared this way, but
this milestone adds no guess dialog or algebraic solver settings to the UI.

## Convergence and state ownership

The current settings are fixed in `private/ob_algebraic_solve.m`:

| Setting | Value |
| --- | --- |
| `TolX`, `TolFun` | `1e-12` |
| Maximum iterations | 100 |
| Maximum function evaluations | `max(200, 100*(N+1))`, for N scalar unknowns |
| Automatic scaling / Jacobian updating | Both off |
| Final acceptance | Positive solver status and maximum absolute residual at most `1e-9` |

The evaluation limit is `fsolve`'s budget; Jacobian probes also evaluate block
functions while computing a requested Jacobian.

The runtime supplies a forward finite-difference Jacobian. A nonfinite
Jacobian or reciprocal condition estimate `rcond <= eps` causes an error.
This check applies during solver Jacobian evaluation and at the final
candidate, including a candidate whose initial residual is already zero.
A positive `fsolve` status alone is insufficient: the independent absolute
residual check also has to pass. Large signal magnitudes can make these fixed
tolerances unsuitable; rescale the signals and equations when necessary.

Candidate residuals use immutable candidate signals and current upstream
values. They do not advance discrete state, consume sample hits, or update
trigger/enable history. RK4, ode45, and ode15s stage evaluations solve the
constraint from accepted guesses without committing those trial guesses or
lifecycle histories. Successful scheduled evaluations retain their accepted
guesses. A failed runtime step leaves the caller's original context intact.

An unsupported component, shape mismatch, invalid value, singular Jacobian,
or failed convergence raises an error. Solve errors identify the original
component block paths (slash-separated inside hierarchy) and evaluation time.
Convergence is not guaranteed even
when a solution exists. A regular Jacobian check is a numerical guard, not a
proof of global uniqueness or mathematical well-posedness. General
broader reset/event variants and automatic recovery from failed constraints
remain outside this milestone. Optional control-primitive event localization
was added subsequently; see [ZERO_CROSSINGS.md](ZERO_CROSSINGS.md).

The Jacobian is dense, using quadratic storage and additional residual
evaluations for every scalar unknown. This implementation targets small and
moderate feedback systems; sparse/analytic Jacobians and large-loop performance
remain future work.

## Verification and reference scope

Run the focused numerical regression from the project directory:

```octave
test_ob_algebraic ();
```

The suite exercises noncontractive affine feedback, nonlinear cosine feedback,
initial-guess selection between roots, ordered and independent components,
vector/matrix signals, virtual hierarchy, and continuous dynamics under all
three solvers, including Step and external ZOH input boundaries. Enabled and
triggered child-body checks verify outputs and execution timestamps.
It also checks hidden discrete hits, independent context
copies, checkpoint/model roundtrips, rollback after failure, singular and
inconsistent constraints, shape errors, invalid guesses, and nonreal domains.
These numerical checks establish the tested scope of this implementation.

MathWorks describes algebraic loops as direct-feedthrough constraints and
requires smooth real double signals for its iterative solver. Its documented
limitations also exclude code generation for models with algebraic loops;
Octave Blocks therefore continues to reject such C exports. This milestone
does not reproduce Simulink's automatic trust-region/line-search selection
or its full diagnostic and hierarchy analysis facilities.
See [MathWorks algebraic-loop concepts](https://www.mathworks.com/help/simulink/ug/algebraic-loops.html).

Octave documents `fsolve` as an iterative nonlinear equation solver whose
starting guess and tolerances affect convergence. Small-step and small-
improvement termination codes motivate the additional residual check here.
See [GNU Octave solver documentation](https://docs.octave.org/latest/Solvers.html).

Live Simulink execution was unavailable in the installed MATLAB environment.
The compatibility comparison above uses official documentation and analytic
numerical reference cases, not a live Simulink trajectory comparison. Existing
C export restrictions are documented in [CODEGEN.md](CODEGEN.md); resumable
contexts and checkpoints are described in [RUNTIME.md](RUNTIME.md).
