# Simulink-style command API

Octave Blocks can be built and run from scripts with Simulink's programmatic
commands. The commands produce ordinary Octave Blocks models, so the editor,
all three solvers, save/load and the supported C exporter work on them.

```octave
addpath (fullfile (fileparts (which ('ob_simulink')), 'simulink'));
new_system ('loop');
add_block ('simulink/Sources/Step', 'loop/Ref');
add_block ('simulink/Math Operations/Subtract', 'loop/Err');
add_block ('simulink/Continuous/PID Controller', 'loop/PID', 'P', '2', 'I', '1');
add_block ('simulink/Continuous/Transfer Fcn', 'loop/Plant', 'Denominator', '[1 3 2]');
add_block ('simulink/Sinks/Out1', 'loop/y');
add_line ('loop', 'Ref/1', 'Err/1');   add_line ('loop', 'Plant/1', 'Err/2');
add_line ('loop', 'Err/1', 'PID/1');   add_line ('loop', 'PID/1', 'Plant/1');
add_line ('loop', 'Plant/1', 'y/1');
out = sim ('loop', 'StopTime', '10');
plot (out.tout, out.yout);
```

The Simulink-named functions live in the `simulink/` folder and are only
visible after `addpath`. They are thin wrappers around
`ob_simulink (command, ...)`, which can be called directly instead.

## Commands

| Command | Behavior |
| --- | --- |
| `new_system(name)`, `bdIsLoaded(name)` | Create or query a system in the session registry. |
| `load_system(file)`, `save_system(name[, file])` | Read/write Octave Blocks `.mat` models with their run settings. `.slx`/`.mdl` are rejected. |
| `open_system(name)` | Open the system in the Octave Blocks editor. |
| `close_system(name[, save])`, `bdclose(name)`, `bdclose('all')` | Unload systems. |
| `add_block(source, dest, 'Param', value, ...)` | Add a library block or copy a block from a loaded system. `'MakeNameUnique','on'` is supported. |
| `delete_block(path)` | Remove a block and its lines. Deleting an In1/Out1 renumbers the remaining ports and the parent's wires, as Simulink does. |
| `add_line(sys, 'A/1', 'B/2')`, `delete_line(...)` | Connect numbered ports. Subsystem control inputs are named `Enable`, `Trigger` or `Reset`. |
| `set_param(obj, 'Param', value, ...)` | Model configuration or block dialog parameters, plus `Name` and `Position`. Errors leave the system unchanged. |
| `get_param(obj, 'Param')` | Parameters as text, plus `BlockType`, `Name`, `Parent`, `Position`, `Ports`, `DialogParameters`. |
| `find_system(sys, 'Param', value, ..., 'SearchDepth', n)` | Paths of matching blocks, including Enable/Trigger/Reset blocks. |
| `sim(name, ...)` | Run the system. Accepts `[start stop]`, an output-time vector, name/value configuration overrides, or a parameter struct. |

`sim` returns a struct with `tout`, `yout` (root Out1 ports in port order; a
matrix when all are scalar, otherwise a cell per port), one field per **To
Workspace** variable (`time` and `signals.values`), `logsout` entries for
Scope blocks, `SimulationMetadata` and the full `ob_run` result. The legacy
`[t, x, y] = sim(...)` form returns an empty `x`.

Block parameters are Octave expressions evaluated in the base workspace at
`set_param` and again at `sim`, so workspace variables can be changed between
runs.

## Model configuration

| Parameter | Mapping |
| --- | --- |
| `StartTime`, `StopTime` | Simulation interval. |
| `Solver` | `ode4`/`FixedStepAuto` → RK4; `ode45`/`ode23`/`VariableStepAuto` → ode45; `ode15s`/`ode23t`/`ode23tb` → ode15s. |
| `FixedStep` | Output interval and RK4 step. `auto` is (stop − start)/50, bounded by `MaxStep`. |
| `RelTol`, `AbsTol`, `MaxStep` | Adaptive solver tolerances (`AbsTol` `auto` → 1e-6). |
| `ZeroCrossControl` | `EnableAll` turns on event localization. |

## Library blocks

The last element of the library path selects the block, so
`'simulink/Math Operations/Gain'` and `'built-in/Gain'` are equivalent.

| Library block | Parameters | Octave Blocks realization |
| --- | --- | --- |
| Constant, Clock, Ground, Step | `Value`; —; —; `Time`, `Before`, `After` | Native sources |
| Sine Wave, Ramp | `Amplitude`, `Bias`, `Frequency` (rad/s), `Phase`; `Slope`, `Start`, `InitialOutput` | Virtual subsystems of native blocks |
| Gain | `Gain` | Gain (matrix gains multiply) |
| Sum, Add, Subtract | `Inputs` (`'+-+'`, `'|++'`, or a count) | Sum, or a virtual subsystem of Gain(−1) and Sum blocks |
| Product, Divide | `Inputs` (`'**/'` or a count), `Multiplication` | Element-wise `times`/`rdivide` Functions; `Matrix(*)` with two inputs uses Product |
| Abs, Sqrt, Math Function, Trigonometric Function | `Operator` | Function block calling the Octave function |
| MATLAB Fcn, Interpreted MATLAB Function, Fcn | `MATLABFcn`, `Expr` | Function block; the expression must be `name` or `name(u)` |
| Integrator | `InitialCondition`, `LimitOutput`, `UpperSaturationLimit`, `LowerSaturationLimit`, `ExternalReset` | Integrator, or Limited Integrator with limits/reset port |
| Transport Delay | `DelayTime`, `InitialOutput` | Transport Delay |
| Unit Delay, Discrete-Time Integrator | `InitialCondition`, `SampleTime` | Unit Delay, forward-Euler Discrete Integrator |
| Rate Transition | `OutPortSampleTime`, `InitialCondition` | Rate Transition |
| Saturation, Dead Zone, Switch | `UpperLimit`/`LowerLimit`; `LowerValue`/`UpperValue`; `Threshold` (`Criteria` must be `u2 >= Threshold`) | Native blocks |
| Transfer Fcn, State-Space, Zero-Pole | Simulink coefficient and matrix parameters | `ob_transfer_function`, `ob_state_space`, `ob_zero_pole` |
| Discrete Transfer Fcn, Discrete State-Space | as above plus `SampleTime` | `ob_discrete_transfer_function`, `ob_discrete_state_space` |
| PID Controller, Discrete PID Controller | `P`, `I`, `D`, `N`, `Form`, `TimeDomain`, `SampleTime`, `LimitOutput`, limits | `ob_pid_controller` |
| 1-D Lookup Table | `BreakpointsForDimension1`, `Table`, `ExtrapMethod` (Clip/Linear) | `ob_lookup_table_1d` |
| Rate Limiter, Relay | slew limits / switch points, outputs, `SampleTime` | Sampled `ob_rate_limiter`, `ob_relay` |
| Scope, Display, Terminator, To Workspace | `VariableName` (To Workspace) | Scope; logged by `sim` |
| In1, Out1 | `Port` (automatic when omitted) | Inport, Outport |
| Subsystem, Enabled/Triggered/Enabled and Triggered/Resettable Subsystem | — | Editable subsystem with In1 → Out1 and its control block |
| Enable, Trigger, Reset | `TriggerType`, `ResetTriggerType` | Set the parent subsystem's execution mode |

Library-built linear and controller subsystems behave like masked blocks:
their contents are generated from the parameters and cannot be edited by path.

## Differences from Simulink

- Systems are Octave Blocks models, not `.slx`/`.mdl` files, and commands
  return paths rather than numeric handles.
- Only the blocks and parameters above are recognized; anything else is an
  error that names the supported parameters. There is no Mux/Demux, bus,
  Stateflow, model reference or variant support.
- Rate Limiter and Relay are sampled, with an explicit `SampleTime`.
- Integrator `ExternalReset` resets are sampled at accepted solver hits and
  `level hold` is not supported.
- Variable-step runs report outputs on the `FixedStep` grid rather than at
  every solver step.
- `ode23`, `ode23t` and `ode23tb` are mapped to the nearest available solver
  rather than implemented.

No live Simulink comparison was possible: the installed MATLAB R2026b has no
Simulink. `test_ob_simulink_api()` checks each command against analytical
results and direct Octave Blocks models, including C export of an
API-built model.
