# Advanced Octave Blocks extensions

Each builder returns an ordinary model for the `value` of a Subsystem
block. The editor can open the resulting diagram. These are Octave-native
models with fixed parameters.

| API | Supported behavior |
| --- | --- |
| `ob_pid_controller` | Parallel or ideal PID, continuous or forward Euler discrete, filtered derivative, two setpoint weights, output limits and back-calculation. A discrete output holds between its clock ticks. |
| `ob_zero_pole` | Proper real-coefficient SISO and shared-pole SIMO systems, including conjugate roots. A row of zeros with a vector gain assigns one zero per output. |
| `ob_discrete_state_space`, `ob_discrete_transfer_function` | Vector state-space and proper scalar transfer models, explicit periods and offsets or inherited timing. A zero feedthrough term leaves a state break in the diagram. |
| `ob_c2d_state_space` | ZOH via Octave's `expm`, or Tustin via linear solves. Returns matrices for the discrete builder; Tustin states use a different realization from the continuous states. |
| `ob_lookup_table_1d` | Piecewise linear interpolation, clipped or linearly extrapolated, elementwise on matrix inputs. |
| `ob_rate_limiter`, `ob_relay` | Scalar sampled slew limiting and sampled hysteresis, respectively. Both hold their outputs between clock ticks. The limiter uses its initial value and one period of allowance at the first hit; the relay starts off. |
| `ob_atomic_feedthrough` | Logical matrix indexed by numbered input and output ports. Nested controls are treated conservatively. This is structural analysis only; atomic scheduling is unchanged. |

## Transport Delay and Limited Integrator

These are primitive blocks, with editor buttons (**Transport Delay**,
**Limited Int.**) and Simulink-style parameters through
[the command API](SIMULINK_API.md).

**Transport Delay** outputs its input delayed by a fixed time `T > 0`. Its
value is `[T initial]` or `struct('delay', T, 'initial', Y0)` for a matrix
initial output. Before `start + T` it outputs the initial value; a scalar
initial value is broadcast to the input shape. It has no direct
feedthrough, so it breaks algebraic loops.

- The input history is recorded at every integration segment end and at
  accepted solver points. Each discontinuity is stored as a left and right
  limit, so a delayed step stays a step, and its delayed time becomes a
  solver boundary.
- Between samples the output uses cubic Hermite interpolation, with slopes
  from neighbouring samples in the same continuous piece. This is C1 and
  third-order accurate. Simulink interpolates linearly; the smoother form
  lets adaptive solvers take far fewer steps.
- No integration segment is longer than the shortest delay, so solver
  stages only read recorded history. Very short delays therefore shorten RK4
  steps (more than 10^6 sub-steps per output interval is rejected).
- History older than `time − T` is discarded.

**Limited Integrator** is a continuous integrator with optional output
limits and an external reset. Its value is a numeric initial state, or
`struct('initial', X0, 'lower', L, 'upper', U, 'reset', MODE)`.

- Limits may be scalars or match the state shape. An initial state outside
  them is clipped, as in Simulink.
- At a limit, outward integration stops and inward motion resumes
  immediately. Adaptive solvers decide saturation from each stage's state.
  RK4 decides it from the step's initial state, so a step that reaches a
  bound lands on it exactly.
- `MODE` is `none`, `rising`, `falling`, `either` or `level`; any mode other
  than `none` adds a scalar reset input on port 2. Edge resets use the same
  sign rules as triggered subsystems and are sampled at accepted hits
  (output times, sample hits and events). The first evaluation only records
  the reset signal. A triggered reset returns the state to its initial value
  before that hit's outputs are computed. A nonzero `level` signal also
  holds the state between hits.

Both blocks run with `rk4`, `ode45` and `ode15s` at the root and inside
virtual subsystems. Explicit errors reject them inside conditional
subsystem bodies, with `zero_crossings=true`, and in C export.

`test_ob_delay_integrator()` checks analytical traces (delayed ramps and
steps, a delay differential equation, delay-broken feedback, matrix shapes,
saturation and release, all reset modes, checkpoints, persistence and the
rejections). `test_ob_delay_matlab()` compares two delay differential
equations, `x' = −x(t−1)` and Mackey–Glass with a 17 s delay over 300 s,
against MATLAB `dde23` references recorded in
`matlab-dde-reference.json` by `reference_ob_dde.m`:

| Case | Octave Blocks error vs. dde23 | Octave time | dde23 time |
| --- | --- | --- | --- |
| `x' = −x(t−1)`, RK4 h = 0.1 | 2.1e-5 | 0.4 s | 0.76 s |
| `x' = −x(t−1)`, RK4 h = 0.01 | 2.1e-8 | 3.3 s | |
| `x' = −x(t−1)`, ode45 (1e-10) | 2.2e-7 | 4.7 s | |
| Mackey–Glass, RK4 h = 0.5 | 1.2e-5 | 4.8 s | 0.32 s |
| Mackey–Glass, RK4 h = 0.1 | 5.1e-8 | 23 s | |

Switching from linear to cubic history interpolation cut the RK4 h = 0.1
error from 1.0e-3 to 2.1e-5. It also cut ode45 from 1270 steps (22 s) to
464 steps. The remaining speed gap to `dde23` is the engine's interpreted
per-stage graph evaluation, which also applies to models without delays.

## Resettable subsystems

Set a discrete subsystem's execution mode to `reset_rising`,
`reset_falling`, or `reset_either` to reset its state on the corresponding
edge at a trailing scalar Reset port. At each subsystem sample the body
executes, including on a reset sample. Its initial state is visible on that
sample. An explicit sample period and offset can be set on the enclosing
Subsystem. Its body may contain virtual subsystems; body blocks inherit
the execution clock. Continuous states, continuous reset control, and
conditional descendants in the body remain open.

Behavior was compared with the public [PID](https://www.mathworks.com/help/simulink/slref/discretepidcontroller.html),
[Rate Limiter](https://www.mathworks.com/help/simulink/slref/ratelimiter.html),
[Relay](https://www.mathworks.com/help/simulink/slref/relay.html), and
[Resettable Subsystem](https://www.mathworks.com/help/simulink/slref/resettablesubsystem.html)
references. The supported subset and initial sample conventions above are
the Octave Blocks contract. No live Simulink comparison was performed.

Run `test_ob_advanced_simulink()` to check analytical traces in Octave.
`Test-CombinedCodegen.ps1 -AdvancedOnly` checks these models against generated
C99. The default run includes the existing combined and nested reset cases.

## Archive review

The optimization installers contain whole-file replacements for the runtime
and editor. The checkout already has indexed graph and event metadata,
cached editor wire adjacency, Octave `lookup`, standard C `bsearch`, and
the earlier PR audit changes. The replacement files predate parts of the
current conditional lifecycle and were not overlaid. The archive's original
PID test failed on a third Sum input; its feedthrough test failed because a
structural query was treated as a runnable model with missing input data.
The adapted builders use the existing two-input Sum, Octave built-ins,
and existing sampled output holds. The original reset patch replaced files
that already carried nested Enable fixes; sampled reset was integrated into
the current paths instead. The library backend suggestions are
roadmap items, not executable implementations. The installed Octave 11.3.0
has SUNDIALS IDA headers and a DLL, but no CVODE or ARKODE headers or DLLs in
the corresponding installation directories. Those targets need a separate
dependency check and build path.
