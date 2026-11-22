# Continuous linear-system builders

`ob_state_space(A,B,C,D,x0)` and `ob_transfer_function(num,den,x0)` create
ordinary virtual subsystem models from Integrator, Gain, Sum, and interface
blocks. Their diagrams remain inspectable and editable, require no control
package, and use the existing solvers and C exporter.

```octave
model = ob_linear_system_example ();
result = ob_run (model, 0:.05:5);
octave_blocks (model);
```

This example drives `1/(s+1)^2` with a delayed unit step. Enter the plant in
the editor to inspect its realization. To reuse a builder, assign its returned
model to a Subsystem block's `value` field. To run it directly, configure its
root input data with the ordinary [Inport API](INPUTS.md).

## State-space equations

The builder implements `x' = A*x + B*u`, `y = C*x + D*u`, and initial state
x0. Dimensions are A(n,n), B(n,m), C(p,n), D(p,m), and x0(n,1); initial state
defaults to zero. One vector input port carries m-by-1 data when m is positive,
and one output port carries p-by-1 data. These equations and dimensions follow
the [State-Space reference](https://www.mathworks.com/help/simulink/slref/statespace.html).

```octave
plant = ob_state_space ([-1 0;0 -2], eye(2), [1 2;3 -1], ...
                        [.5 0;0 -.25], [.2;-.3]);
oscillator = ob_state_space ([0 1;-1 0], [], eye(2), [], [1;0]);
```

Empty B and D select an autonomous system with no input port. Zero states
produce pure feedthrough, or constant zero for an autonomous system. An
exactly zero D branch is omitted so an unnecessary dependency does not turn
state-breaking feedback into an apparent algebraic loop.

Parameters are finite, full, real numeric matrices converted to double. The
builder uses constant matrices. Sparse systems, time-varying parameters,
descriptor equations, and native Simulink block/file compatibility remain
outside this builder's scope.

## Transfer functions

The SISO builder accepts coefficient vectors in descending powers of s,
removes leading zeros, normalizes by the first nonzero denominator coefficient,
and requires a proper transfer function. Constant gain, direct terms, and zero
numerators are supported; common factors are not cancelled. These conventions
match the [Transfer Fcn reference](https://www.mathworks.com/help/simulink/slref/transferfcn.html).

```octave
plant = ob_transfer_function (1, [1 2 1]);   % 1/(s+1)^2
lead = ob_transfer_function ([2 1], [1 3]); % (2s+1)/(s+3)
```

For normalized denominator `[1 a1 ... an]`, the controllable realization uses
`x = [z z' ... z^(n-1)]'`, a superdiagonal of ones in A, last row
`[-an ... -a1]`, and B equal to the last coordinate vector. Padding the
numerator to `[b0 b1 ... bn]` gives D=b0 and
`C=[bn ... b1]-b0*[an ... a1]`.

Optional x0 refers to this realization's state, rather than output derivatives.
It is a builder extension: the native Simulink Transfer Fcn block uses zero
initial states. Internal state ordering is not promised to match `tf2ss`.
SIMO transfer functions and discrete/descriptor realizations remain extensions
to implement.

## Verification

`test_ob_linear_systems` checks analytical first/second-order responses, an
oscillator, MIMO feedthrough, autonomous/zero-state systems, zero numerators,
nonzero state, feedback, invalid parameters, and model persistence. State-space
cases run with RK4, ode45, and ode15s. Compiled fixtures separately compare
linear models under the existing static-double RK4 C subset.
