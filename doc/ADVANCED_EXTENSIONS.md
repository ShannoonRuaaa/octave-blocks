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

## Simulink library builders (0.3.0)

These builders reproduce Simulink library blocks from native primitives
(Gain, two-input Sum, Switch, Dead Zone, Unit Delay, Rate Transition,
Constant, Time, Integrator and C-mapped Function blocks), so every model
built from them runs with all solvers, zero crossings, strict C99
`ob_codegen` and `ob_accelerate`. Defaults are Simulink's. Each is checked
against recorded Simulink 26.2 traces (`tests/reference/reference_ob_nonlinear_builders.m`,
`reference_ob_routing_builders.m`) and through the
[command API](SIMULINK_API.md#library-blocks), which maps the library blocks
to them.

| API | Simulink block | Supported behavior and limits |
| --- | --- | --- |
| `ob_backlash(width, y0, Ts, offset)` | Backlash | Play of total `width` (scalar) centred on the output; `Ts > 0` clocks and holds the output. A vector signal needs a `y0` of its shape. With an inherited rate the state updates on the output grid. |
| `ob_quantizer(q, Ts, offset)` | Quantizer | `q*round(u/q)` with a true division (half-way quotients round away from zero as in Simulink); `q` scalar or array; optional held sample time (the hold starts at `zeros(size(q))`). |
| `ob_minmax(func, n)` | MinMax | Element-wise `min`/`max` of `n >= 2` inputs with scalar expansion. `n = 1` (Simulink's element reduction) is an error; the command API realizes it with Octave-only `vec`/`min` Functions. |
| `ob_saturation_dynamic()`, `ob_dead_zone_dynamic()` | Saturation Dynamic, Dead Zone Dynamic | Bounds as signals on ports `up`, `u`, `lo`, Simulink's priority when the bounds cross, scalar bounds expand; the dead zone never outputs −0. |
| `ob_sign()` | Sign | +1/0/−1 levels shaped like the input, with zero-crossing guards. |
| `ob_coulomb_viscous_friction(offset, gain)` | Coulomb & Viscous Friction | `gain.*u + offset.*sign(u)`, defaults `[1 3 2 0]` and 1, element-wise vectors. |
| `ob_relational_operator(op)` | Relational Operator | `==`, `~=` (`!=`), `<`, `<=` (default), `>=`, `>`; double 0/1 output; no `isInf`/`isNaN`/`isFinite`; a difference that overflows stops the run. |
| `ob_logical_operator(op, n)` | Logical Operator | `AND`, `OR`, `NAND`, `NOR`, `XOR`, `NXOR` over `n` inputs and `NOT`; nonzero is true; double 0/1 output; no zero-crossing guards, like Simulink's Logic block; no single-input reduction. |
| `ob_mux(n, widths)`, `ob_demux(n, width)` | Mux, Demux | Column vectors from `n` inputs of declared widths (a chain of two-input Sums), and Simulink's uneven split back; widths are not propagated, so non-scalar parts must be declared. |
| `ob_multiport_switch(n, order, default)` | Multiport Switch | One- or zero-based data ports, control truncated toward zero, last or additional default port; `DiagnosticForDefault` `Error` is not modelled (always `None`); NaN controls are rejected. |
| `ob_pulse_generator(amp, period, width, delay)` | Pulse Generator | Time-based pulse on simulation time with few-ulp edge tolerance; use `zero_crossings = true` for exact edges in downstream integrators. Sample-based pulses are mapped by the command API. |
| `ob_chirp(f1, T, f2)` | Chirp Signal | Linear swept sine `sin(2*pi*(f1*t + (f2-f1)/(2*T)*t^2))`, vector parameters with scalar expansion. |
| `ob_second_order_integrator(x0, dxdt0)` | Integrator, Second-Order | Two Integrators; outputs x and dx/dt; only the default options (no limits, wrapping, reset or external initial conditions). |
| `ob_rate_transition(in, out, ic, det, integrity)` | Rate Transition (modes) | Simulink's Integrity/Deterministic semantics between explicit rates (see [MULTIRATE.md](MULTIRATE.md#rate-transition)). |
| `ob_first_order_filter(kind, tau, gain, Ts, method, x0, offset)` | (wrapper) | Continuous or ZOH/Tustin-discretized first-order low-pass, high-pass or lead-lag filter; `x0` is the lag state. Not a Simulink block. |

Not provided: Zero-Order Hold (use a native Rate Transition), Moving
Average, and Bus Creator/Selector (use `ob_mux`/`ob_demux`, which carry no
element names).

## Linearization and analysis

Four analysis functions (0.3.0) work on ordinary models and simulation
results. They are not blocks and are not in the command API library.

| Function | MATLAB/Simulink counterpart | Purpose |
| --- | --- | --- |
| `ob_linearize` | `linmod(sys, x, u, para)` | State-space linearization about an operating point |
| `ob_findop` | `trim(sys, x0, u0, y0, ix, iu, iy)` | Steady-state operating point |
| `ob_bode` | `bode(sys, w)`, `margin`, `allmargin` | Frequency response and stability margins |
| `ob_stepinfo` | `stepinfo(y, t, yfinal, yinit, ...)` | Step-response characteristics of sampled data |

```octave
sys = ob_linearize (model);                     % about the initial states, u = 0, t = 0
op = ob_findop (model, [], 0.5, [], [], 1, []); % hold input 1 at 0.5, solve dx/dt = 0
sys = ob_linearize (model, op.x, op.u);
resp = ob_bode (sys);                           % resp.Gm, resp.Pm, resp.Wcg, resp.Wcp
result = ob_run (model, 0:0.01:10);
info = ob_stepinfo (ob_scope_data (result, 3), result.t);
```

- **States** are the elements of every continuous Integrator in depth-first
  block order (Simulink orders states differently; `state_names`,
  `state_paths` and `state_index` identify each row). **Inputs** are the
  root Inports in port order; a port's shape comes from its `model.inputs`
  dataset or from a cell `U0 = {u1, u2, ...}`, and is scalar otherwise.
  **Outputs** are the root Outports only, in port order.
- The model is compiled once and each perturbation is one evaluation of the
  compiled graph, so a linearization costs 2(n + m) + 1 evaluations. Each
  element is perturbed by `Perturbation*(1 + |x|)` with central differences
  (default 1e-5, linmod's level).
- Supported states: continuous Integrators, and Limited Integrators strictly
  inside their limits without a reset port. Unit Delay, Discrete
  Integrator, Transport Delay, Rate Transition and conditional-subsystem
  states raise `ob_linearize:unsupported` with the block path.
- Discontinuities are judged at the operating point, like linmod's
  numerical `'v5'` method: a Saturation beyond its limit has zero gain,
  where Simulink's default linmod keeps unity gain (recorded B = 1).
- `ob_findop` follows trim's arguments and defaults (states and inputs free
  unless listed in IX/IU; outputs in IY must equal Y0), but its
  specifications are hard constraints rather than trim's "as close as
  possible" targets, and trim's DX0/IDX derivative targets are not
  supported. `converged` reports `max|r| <= AbsTol + RelTol*max|[x; u]|`.
- `ob_bode` returns `w`, `H`, `mag` (absolute), `mag_db`, `phase` (degrees)
  and `Gm`, `Pm`, `Wcg` (phase crossover), `Wcp` (gain crossover) as MATLAB
  `margin` names them, plus allmargin's fields in `margins`. The phase is
  unwrapped from the low-frequency asymptote: k poles at s = 0 give −90k
  degrees and the gain sign plus the other poles and zeros are wrapped into
  (−180, 180], so 1/s² starts at −180, −1/(s+1) at +180, 1/(s−1) at −180 and
  (1−s)/(s+1)² at 0. `Gm` is the margin closest to 0 dB and `Pm` the one of
  least magnitude. Continuous time only; no delay margin or stability flag;
  MIMO margins are NaN.
- `ob_stepinfo` uses MATLAB's definitions with `yinit` defaulting to 0
  (RiseTime, TransientTime, SettlingTime, SettlingMin/Max, Overshoot,
  Undershoot, Peak, PeakTime, SteadyState); crossings are interpolated
  linearly and levels never reached give NaN.

`tests/test_ob_analysis.m` compares with Simulink 26.2 `linmod`/`trim`
results and Simulink step and sine traces recorded by
`tests/reference/reference_ob_analysis.m`, and exports a model built from
each function's result with strict C99 `ob_codegen`. MATLAB `bode`,
`margin`, `stepinfo`, `linearize` and `findop` were not installed when the
reference was recorded, so `ob_bode`'s phase-branch convention for negative
gains, RHP poles and non-minimum-phase zeros is documented rather than
machine-checked; the producer records those functions when they are
available.

## Transport Delay and Limited Integrator

These are primitive blocks, with editor buttons (**Transport Delay**,
**Limited Int.**) and Simulink-style parameters through
[the command API](SIMULINK_API.md).

**Transport Delay** outputs its input delayed by a fixed time `T > 0`. Its
value is `[T initial]` or `struct('delay', T, 'initial', Y0)` for a matrix
initial output. It has no direct feedthrough, so it breaks algebraic loops.

- Before `start + T` it outputs the initial value. From `start + T` on it
  outputs `u(t − T)`, so at exactly `start + T` the output is already
  `u(start)` (right-continuous). The left limit there is still the initial
  value. Solver stages that end at `start + T` use that left limit: the RK4
  end stage, adaptive end stages, and the left sample that downstream delays
  record. Integrating across `start + T` is therefore exact, even when the
  initial value differs from `u(start)`.
- A scalar initial value is broadcast to the input shape from the very
  first sample. Before the first committed evaluation, a side-effect-free
  probe evaluation learns the input shape; its states are discarded. A
  scalar input with a matrix initial value is expanded to that matrix's
  shape, as in Simulink. Any other shape mismatch is an error.
- The input history is recorded at every integration segment end, at
  accepted solver points, and as a right limit at every interior segment
  boundary (such as a Step time between output times). Each discontinuity
  is stored as a left and right limit, so a delayed step stays a step, and
  its delayed time becomes a solver boundary. The first recorded time is
  kept separately, so pruning never moves the end of the initial interval.
- Times a few ulps apart are the same instant, with the engine's tolerance
  for clock hits: a Step at 0.7 and the output time `7 * 0.1`, or a delayed
  jump `0.1 + 0.2` and the output time `3 * 0.1`. Such samples merge into
  one stored jump. A query there reads that jump's left or right limit,
  and no separate solver boundary is added for it.
- Between samples the output uses cubic Hermite interpolation, with slopes
  from neighbouring samples in the same continuous piece. This is C1 and
  third-order accurate. Simulink interpolates linearly; the smoother form
  lets adaptive solvers take far fewer steps. Only value jumps are stored
  exactly; a kink in the input is smoothed over one sample interval.
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
- `MODE` is `none`, `rising`, `falling`, `either`, `level` or `level hold`
  (Simulink's ExternalReset names). Any mode other than `none` adds a
  scalar reset input on port 2. Resets are sampled at accepted hits (output
  times, sample hits and events). A reset returns the state to its initial
  value before that hit's outputs are computed.
  - Edge modes use the same sign rules as triggered subsystems. The first
    evaluation only records the reset signal.
  - In both level modes a nonzero signal also holds the state between hits.
  - `level hold` resets only while the signal is nonzero.
  - `level` follows Simulink's definition: it resets while the signal is
    nonzero, and also when the signal changes from nonzero to zero. With
    `rk4` that change is sampled at the next hit, as Simulink ode4 does at
    its next major step. This discards the integration between the release
    and that hit: compared with a reset located at the release, up to one
    output interval times the input. Adaptive solvers need no sampled reset
    for it: the hold ends when the signal becomes zero (exactly, for a gate
    built from Step blocks), with the state still at its initial value from
    the last nonzero hit. A reset at that instant, where Simulink's
    variable-step solvers apply it, would change nothing.

Both blocks run with `rk4`, `ode45` and `ode15s` at the root and inside
virtual subsystems. Explicit errors reject them inside conditional
subsystem bodies and with `zero_crossings=true`. Flat C export (`rk4` or
`ode45`) and the accelerator support both blocks
([CODEGEN.md](CODEGEN.md#transport-delay-and-limited-integrator)); the
conditional/event C exporter rejects them.

`test_ob_delay_integrator()` checks analytical traces: delayed ramps and
steps, integration across `start + T` with an initial value different from
`u(start)` (also from start time 0.1, where `(0.1 + 0.2) − 0.2` misses 0.1
by an ulp), delayed jumps that meet the output grid only up to rounding,
Steps between output times, a delay differential equation, delay-broken
feedback read by a second delay, matrix shapes from the first sample,
scalar-input expansion, saturation and release, and all reset modes,
including the `level` nonzero-to-zero reset for each solver and
`level hold`. It also checks checkpoints, persistence and the rejections.
`test_ob_delay_matlab()` compares two delay differential
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

### Comparison with Simulink

`test_ob_simulink_delay_integrator()` rebuilds 51 models recorded in
Simulink 26.2 (R2026b) and runs them on Simulink's output times: 21 Transport
Delay models and 30 Integrator models with `LimitOutput` and
`ExternalReset`. The traces and each model's Simulink parameters are in
`simulink-delay-integrator-reference.json`. Its producer is
`reference_ob_simulink_delay_integrator.m`; the checked-in file was
regenerated by that producer in MATLAB R2026b Update 1 on 2026-11-21. Each
case either agrees, or shows one of the differences below,
which the test asserts on both sides. 22 cases agree and 29 show a
documented difference.

These agree to 1e-12 (fixed step) or to the solver tolerance (ode45, at
most 2e-7):

- delays of a ramp away from `start + T`
- vector and matrix signals, and scalar initial values broadcast to them,
  away from `start + T`. The vector cases differ at that one sample (first
  row of the table below). The matrix case agrees everywhere only because
  its initial value 0 equals `u(start)`.
- delayed steps and delay-fed integrators with ode45
- every edge reset mode with edges on the RK4 grid, including the sign
  rules through zero, resets while saturated, and resets to a clipped
  initial state
- `level` resets with ode4, including the sampled nonzero-to-zero reset
- `level` with ode45 and zero crossings, including the nonzero-to-zero
  reset that Simulink locates where the gate closes
- `level hold` with ode45
- release from saturation for `cos t` within [−0.5, 0.5]

The intentional differences:

| Situation | Simulink | Octave Blocks | Measured |
| --- | --- | --- | --- |
| Sample at exactly `start + T` | Initial output, until time *exceeds* `start + T` | `u(start)`, right-continuous | One sample: 7 vs. 0 for a clock through `TD(0.5, 7)`. In `y = 1 − 0.5 y(t−1)` each jump is reported one step late; at h = 0.5 Simulink gives `[1 1 1 .5 .5 .75 .75]`, Octave `[1 1 .5 .5 .75 .75 .625]`. |
| ode4 step starting at `start + T`, initial value ≠ `u(start)` | k1 stage sees the initial value | Previous end stage sees the initial value, next step starts from `u(start)` | Simulink's integral is off by `h/6 (Y0 − u(start))`: 0.1167 for `Clock → TD(0.5, 7) → Integrator`. Octave is exact. Off the grid (T = 0.35) Simulink does not split the step: 0.234. |
| History interpolation | Linear | Cubic Hermite | `x' = −x(t−1)`, h = 0.1, vs. dde23: 1.0e-3 vs. 2.1e-5. Delay 0.35: 4.2e-4 vs. 6e-7. A sine through `TD(0.25)`: 1.25e-3 (h²/8) vs. 6e-5. Mackey–Glass, h = 0.5: 5.1e-3 vs. 1.2e-5. Simulink ode45 at RelTol 1e-10 keeps a 1.0e-3 floor; Octave reaches 2.2e-7. |
| Delayed step, fixed step | One sample per major step, so the step becomes a one-step ramp | Left and right limits stored, also for a Step between output times; solver boundary | Integral offset h/2 (0.05 at h = 0.1). ode45 agrees to 8e-8. |
| Delay shorter than the fixed step | Extrapolates and warns | Splits the step; exact | One sample: 0 vs. 0.07 for a clock through `TD(0.03)`. |
| ode4 step that reaches a limit | Gates each stage on its own state; stops short and reaches the bound one step later | Gates on the step's initial state; lands on the bound | One sample, e.g. 0.958 vs. 1 (h = 0.25), up to 0.083. |
| ode4 with a Step transition inside a step | Samples the Step in its stages | Splits the RK4 step at the Step time; exact | Step input 1 → 3 at 0.55, h = 0.1: offset 0.067. Level pulse on [1.02, 1.07): 0.017. |
| ode4 with a Step transition exactly on the grid | k4 stage sees the new value | End stage uses the left limit | `level hold` gate closing at t = 2: offset h/6 = 0.017. |
| Edge resets (`rising`, `falling`, `either`) between output samples, ode45 with zero crossings | Located at the edge | Sampled at the next accepted hit | The error is the input times (next hit − edge time), up to one output interval: 0.05 for edges 0.05 before a sample. A reset pulse entirely between samples is missed: 1.02. |
| `level` gate closing between samples, ode45 without zero crossings | Releases the hold within its step tolerance after the gate closes | Releases exactly at the Step time | 3.6e-6 at RelTol 1e-8. |

Timings from the delay comparison run, with the engine as it was before the
2026-11-21 speed work, on a heavily loaded machine (about 80% CPU, another
MATLAB session running part of the time):

- Simulink `sim()` after a warm-up call took 0.19–0.23 s for
  `x' = −x(t−1)` and 0.22–0.37 s for Mackey–Glass. Fast restart took
  0.07–0.40 s (0.40 s on the first warm call of `x' = −x(t−1)` with ode4
  h = 0.1). The first simulation of the session took 15.4 s.
- MATLAB `dde23` (1e-10 / 1e-12) took 0.16 s for `x' = −x(t−1)` (4764 steps)
  and 0.65 s for Mackey–Glass (26668 steps).
- Octave Blocks `ob_run` took, for `x' = −x(t−1)`: 0.74 s with RK4 h = 0.1
  (60 steps), 5.2 s with h = 0.01, and 6.6 s with ode45 at 1e-10 (464
  steps). For Mackey–Glass: 6.0 s with RK4 h = 0.5, 36–42 s with h = 0.1,
  53 s with ode45 at 1e-6 (3368 steps), and 219 s at 1e-10 (5331 steps).
- Octave Blocks is therefore about 4 times (DDE, RK4 h = 0.1) to 600 times
  (Mackey–Glass, ode45 1e-10) slower than Simulink's warm `sim()`. It is
  1.5 to 4 orders of magnitude more accurate against `dde23`.

#### Shared benchmark cases

`reference_ob_simulink_benchmarks.m` times the nine shared benchmark cases
([benchmarks/ob_benchmark_models.m](../tests/benchmarks/ob_benchmark_models.m)) as
equivalent Simulink models. Medians of 7 warm `sim()` runs take 0.10–0.14 s,
and 0.026–0.046 s with Fast Restart (`simulink-benchmark-reference.json`).
After the speed work the interpreter is roughly 25–165 times slower than warm
`sim()` (25–142 in [RUNTIME_PERFORMANCE.md](RUNTIME_PERFORMANCE.md) run D,
32–165 in the final gate of [VALIDATION.md](VALIDATION.md)). Warm accelerated
calls (`ob_accelerate`) take 0.14–0.30 times Simulink's warm `sim()` time;
the Mackey-Glass cases, whose production term is an `.m` Function called back
into Octave, take about 2.2 times. `control_zc_ode45` is not accelerated.
The first accelerated call adds 0.15–0.3 s of export and 2–5 s of
compilation. See [CODEGEN.md](CODEGEN.md#accelerated-simulation).

`test_ob_simulink_benchmarks` checks that the outputs are equivalent work:
identical RK4 steps agree to rounding (3e-15). Five cases differ for
documented reasons, in interpreted and accelerated runs alike. The two DDE
cases differ by Simulink's linear history interpolation (Simulink is 1.0e-5
and 1.0e-3 from the exact solution, Octave 2.1e-8 and 2.2e-7). Mackey-Glass
agrees until t = 17, when the delayed history is first read; chaos then
amplifies that difference. `linear10_rk4` differs by 10 h/6 because Simulink
ode4 samples the Step at t = 1 in the last stage of the step that ends there,
while Octave matches the exact response to 5e-11.

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
the Octave Blocks contract. Through the [command API](SIMULINK_API.md),
`test_ob_simulink_api_reference()` checks these builders' Simulink parameter
names and defaults against Simulink 26.2, and compares a PID Controller loop,
a Transfer Fcn step response and the 1-D Lookup Table default with recorded
Simulink traces. The PID loop agrees to 2e-3 under ode4 because Simulink's
fixed-step stages sample the Step at its grid time. The Rate Limiter and
Relay are sampled here but continuous by default in Simulink (documented in
SIMULINK_API.md). The resettable-subsystem traces are not yet compared live.

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
