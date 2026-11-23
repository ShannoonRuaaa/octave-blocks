# Simulink-style command API

Octave Blocks can be built and run from scripts with Simulink's programmatic
commands. The commands produce ordinary Octave Blocks models, so the editor,
all three solvers, save/load and the supported C exporter work on them.

```octave
pkg load octave-blocks;  % installed package
ob_simulink_setup ();    % or, in a source checkout: ob_setup ('simulink')
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

The Simulink-named functions live in the package's `simulink/` folder
(`inst/simulink/` in a source checkout) and are only
visible after `ob_simulink_setup ()`, which adds that folder to the path. In
an installed package, call it after `pkg load octave-blocks`; in a source
checkout, `ob_setup ('simulink')` adds the package folders and then calls it.
The wrappers deliberately take precedence over same-named functions already
on the path. They are thin wrappers around `ob_simulink (command, ...)`, which
can be called directly instead without enabling them.

## Commands

| Command | Behavior |
| --- | --- |
| `new_system(name)`, `bdIsLoaded(name)` | Create or query a system in the session registry. |
| `load_system(file)`, `save_system(name[, file])` | Read/write Octave Blocks `.mat` models with their run settings (times, solver, tolerances). `.slx`/`.mdl` are rejected. `save_system` clears the dirty flag. |
| `open_system(name)` | Open the system in the Octave Blocks editor. |
| `close_system(name[, save])`, `bdclose(name)`, `bdclose('all')` | Unload systems. Like Simulink, `close_system(name)` errors on a modified (dirty) system; `close_system(name, 0)` discards the changes, `close_system(name, 1)` saves them first (to the system's file, or `name.mat`), and `close_system(name, file)` saves to `file`. `bdclose` always discards. `close_system('sys/Block')` closes only that block's window, so the system stays loaded. |
| `add_block(source, dest, 'Param', value, ...)` | Add a library block (exact paths below) or copy a block from a loaded system. `'MakeNameUnique','on'` is supported. |
| `delete_block(path)` | Remove a block and its lines. Deleting an In1/Out1 renumbers the remaining ports and the parent's wires, as Simulink does. |
| `add_line(sys, 'A/1', 'B/2')`, `delete_line(...)` | Connect numbered ports. Subsystem control inputs are named `Enable`, `Trigger` or `Reset`. |
| `set_param(obj, 'Param', value, ...)` | Model configuration or block dialog parameters, plus `Name` and `Position`. Setting an In1/Out1 `Port` renumbers the other ports like Simulink; the parent's lines stay on their port numbers. `set_param(sys, 'Dirty', 'off')` clears the dirty flag. Errors leave the system unchanged. |
| `get_param(obj, 'Param')` | Parameters as text, plus `BlockType`, `MaskType`, `Mask`, `Name`, `Parent`, `Position`, `Ports`, `DialogParameters`, and for a system `Dirty` (`'on'`/`'off'`). |
| `find_system(sys, 'Param', value, ..., 'SearchDepth', n)` | Paths of matching blocks, including Enable/Trigger/Reset blocks. |
| `sim(name, ...)` | Run the system. Accepts `[start stop]`, an output-time vector, name/value configuration overrides, or a parameter struct. |

Every command that changes a system (`add_block`, `delete_block`,
`add_line`, `delete_line`, `set_param`) marks it dirty; failed commands and
`sim` do not.

`get_param(block, 'Ports')` returns Simulink's ten-element vector
`[in out enable trigger state lconn rconn ifaction reset event]`, where
`in` counts data inputs only: an enabled subsystem with one In1 reports
`[1 1 1 0 0 0 0 0 0 0]`, a Resettable Subsystem `[1 1 0 0 0 0 0 0 1 0]`,
and sinks (Scope, To Workspace, Out1, ...) have no outputs.

### Simulation output

`sim` returns a struct (Simulink returns a `Simulink.SimulationOutput`
object) with:

- `tout`, and `yout` with the root Out1 ports in port order, in the model's
  `SaveFormat`: `'Array'` (the Octave Blocks default) is a matrix with one
  column per signal element, like Simulink's Array format (ports carrying
  matrices fall back to a cell per port); `'Structure'` and
  `'StructureWithTime'` give Simulink's `yout.time` and
  `yout.signals(k).values/dimensions/label/blockName` layout; `'Dataset'`
  gives a Dataset-like struct (see [Dataset output](#dataset-output)). `yout`
  is `[]` (an empty Dataset with `'Dataset'`) when the model has no root Out1.
- one field per **To Workspace** variable, in the block's `SaveFormat`:
  `'Structure With Time'` (the Octave Blocks default; Simulink's layout
  `time`, `signals.values/dimensions/label`, `blockName`), `'Structure'`
  (empty `time`) or `'Array'` (values only).
- `logsout` entries for Scope blocks, an Octave Blocks extension in the same
  layout; with `SaveFormat` `'Dataset'`, `logsout` is a Dataset-like struct
  with one element per Scope. Display and Terminator log nothing, like
  Simulink.
- `who`: the sorted names of the logged variables (`tout`, `yout` when there
  are root Out1 ports, To Workspace variables, and `logsout` when a Scope
  was logged), like `SimulationOutput.who`.
- `ErrorMessage`, and `SimulationMetadata` with the Octave Blocks fields
  (`ModelName`, `Solver` = the Octave Blocks solver that ran,
  `IntegrationSteps`, `Events`) plus Simulink's `ModelInfo.ModelName`,
  `ModelInfo.StartTime/StopTime`, `ModelInfo.SolverInfo.Type/Solver/
  MaxStepSize` (or `FixedStepSize`), with Simulink solver names, and
  `TimingInfo` (wall-clock timestamps and elapsed seconds). `ModelInfo.SimulationMode` is
  the requested mode; `Accelerated` (an Octave Blocks field) tells whether
  the compiled accelerator ran, and `ExecutionInfo.WarningDiagnostics(k).
  Diagnostic.message` explains a fallback to interpretation. As in Simulink,
  `SolverInfo.Solver` is `FixedStepDiscrete` (fixed-step) or
  `VariableStepDiscrete` (variable-step) for a model without continuous
  states, whatever solver was chosen; otherwise it is the chosen solver,
  with `FixedStepAuto` reported as `ode4` and `VariableStepAuto` as `ode45`.
- `result`, the full `ob_run` result.

### Dataset output

With `set_param(name, 'SaveFormat', 'Dataset')` (or `sim(name, 'SaveFormat',
'Dataset')`), `out.yout` and `out.logsout` follow
`Simulink.SimulationData.Dataset`. Octave Blocks has no classdef objects for
them, so they are structs whose fields give the same access syntax:

```octave
set_param ('loop', 'SaveFormat', 'Dataset');
out = sim ('loop');
out.yout.numElements              % number of elements (a field, not a method)
out.yout.getElementNames ()       % names, one per element (column cell)
e = out.yout.getElement (1);      % by index; also getElement ('name'), get (1)
plot (e.Values.Time, e.Values.Data);
```

| Field | Content |
| --- | --- |
| `Name` | `'yout'` or `'logsout'`, like the Dataset's `Name` |
| `numElements` | element count |
| `Elements` | struct array of the elements (Octave Blocks only; Simulink keeps them internal) |
| `getElement(k)`, `get(k)` | element `k`; an index outside 1..`numElements` errors with Simulink's message ("To access an element by index, use a scalar numeric integer from 1 to N.") |
| `getElement('name')` | the element with that name; a Dataset of every match when names repeat; `[]` with Simulink's warning ("Did not find any Dataset element using 'name'.", identifier `ob_simulink:DatasetElementNotFound`) when none matches |
| `getElementNames()` | column cell of element names |

Each element is a `Simulink.SimulationData.Signal`-like struct with `Name`,
`PropagatedName`, `BlockPath`, `PortType`, `PortIndex` and `Values`, and
`Values` a `timeseries`-like struct with `Name`, `Time` (column), `Data`,
`IsTimeFirst` and `Length`. `BlockPath` is the block's path as text (Simulink
returns a `BlockPath` object whose `getBlock(1)` is that text). `Data` has
Simulink's layout: N-by-1 for a scalar, N-by-n for a vector (row or column),
and r-by-c-by-N (time last, `IsTimeFirst` false) for a matrix.

- `yout` elements are the root Out1 ports in port order: `BlockPath` is the
  Out1 path (`'loop/y'`), `PortType` `'inport'`, `PortIndex` 1, and `Name`
  (and `Values.Name`) the name of the line, which is always `''` because
  Octave Blocks lines have no names, as Simulink reports for unnamed lines.
  As in Simulink, `getElement('y')` does not find an Out1 by its block name.
- `logsout` elements are the Scopes anywhere in the virtual hierarchy, with
  the layout Simulink uses for a logging Scope: `BlockPath` is the Scope path
  (`'loop/Sub/Scope'`), `PortType` `'inport'`, `PortIndex` 1. Since lines
  have no names, `Name` is the Scope's own name, so `getElement('Scope')`
  finds it (Simulink names the element after the signal line, `''` when it
  is unnamed, and puts Scope logging in a separate `ScopeData` variable).
- To Workspace blocks keep their own `SaveFormat` (Timeseries is still not
  available).

The layout, access functions and messages were recorded in Simulink 26.2 by
`reference_ob_simulink_api.m` (scenario `dataset`) and are checked by
`test_ob_simulink_api_reference`. The function handles capture the elements
when `sim` returns, so editing `Elements` afterwards does not change what
`getElement` returns. Indexing with braces (`out.yout{1}`) and the function
forms `numElements(ds)` or `getElement(ds, k)` are not available.

The `getElement` and `get` handles call the public
`ob_simulink ('dataset_element', ...)`, so a Dataset keeps working after
`clear functions` and after Octave's `-binary` or `-text` `save` and `load`.
MAT files (`-v7`, `-v6`) cannot hold function handles: remove them before
saving and rebuild them after loading with `ob_simulink ('dataset', s)`:

```matlab
plain = rmfield (out.yout, {'getElement', 'get', 'getElementNames'});
save ('-v7', 'run.mat', 'plain');
s = load ('run.mat');
yout = ob_simulink ('dataset', s.plain);   % Name and Elements -> full Dataset
```

As in Simulink, the legacy `[t, x, y] = sim(...)` form needs
`ReturnWorkspaceOutputs` `'off'` (as a model parameter or in the options
struct) and the `sim(name[, timespan[, options]])` form; otherwise it errors
with "Too many output arguments". With `ReturnWorkspaceOutputs` `'off'`, a
single output is `t`. The name/value form always returns the struct.

Block parameters are Octave expressions evaluated in the base workspace at
`set_param` and again at `sim`, so workspace variables can be changed between
runs.

## Model configuration

| Parameter | Mapping |
| --- | --- |
| `StartTime`, `StopTime` | Simulation interval. |
| `Solver` | `ode4`/`FixedStepAuto` → RK4; `ode45`/`VariableStepAuto` → ode45; `ode15s` → ode15s. `ode23` and `ode113` run on ode45, `ode23s`, `ode23t` and `ode23tb` on ode15s, as the nearest available solvers. Other Simulink solvers are rejected. |
| `FixedStep` | Output interval and RK4 step. `auto` is the fundamental sample time (GCD of every explicit discrete period and offset, including those inside library-built blocks) for a model without continuous states, and otherwise (stop − start)/50 bounded by `MaxStep`. The Rate Limiter's Octave-only `OctaveSampleTime` does not count, because Simulink's Rate Limiter has no discrete rate of its own. |
| `RelTol`, `AbsTol`, `MaxStep` | Adaptive solver tolerances (`AbsTol` `auto` → 1e-6). |
| `ZeroCrossControl` | `EnableAll` turns on event localization; `UseLocalSettings` (the default) and `DisableAll` run without it. |
| `SaveFormat` | `Array` (default), `Structure`, `StructureWithTime` or `Dataset` for `yout` (and, with `Dataset`, `logsout`). Simulink defaults to `Dataset`; the Octave Blocks default stays `Array`, as in 0.2. |
| `ReturnWorkspaceOutputs` | `on` (default) or `off`, which enables the legacy `[t, x, y] = sim(...)` outputs. |
| `SimulationMode` | `normal` (default) interprets the model. `accelerator` and `rapid-accelerator` run it as compiled C through `ob_accelerate` (`ob_run` option `accelerate`; see [CODEGEN.md](CODEGEN.md)); a model outside the accelerator's subset, or a missing compiler, runs interpreted instead and `SimulationMetadata.ExecutionInfo.WarningDiagnostics` says why. Values are case-insensitive and stored in lower case, as in Simulink. Also a `sim` name/value option. |

## Library blocks

`add_block` accepts exactly the Simulink R2026b library paths below, plus
`built-in/<BlockType>` for every BlockType listed. Runs of whitespace,
including the newlines inside Simulink library names, compare as one space.
Any other path errors like Simulink ("There is no block named ..."); a few
known Simulink blocks that cannot be realized (Signal Builder, Bus Creator,
Zero-Order Hold, Integrator, Second-Order Limited, ...) report that they are
not supported instead. `get_param`
returns the BlockType and MaskType Simulink reports, and parameter names and
defaults are Simulink's (checked by `test_ob_simulink_api_reference`).
Parameter names are case-insensitive. The enumerated parameters of the
0.3.0 blocks (MinMax `Function`, Logical and Relational `Operator`, Pulse
Generator `PulseType`/`TimeSource`, Multiport Switch `DataPortOrder`,
`DataPortForDefault` and `DiagnosticForDefault`, Sign `ZeroCross`, Mux and
Demux `DisplayOption`, and the `Integrator, Second-Order` options) are also
case-insensitive and stored with Simulink's spelling (`'MAX'` reads back as
`'max'`, `'nxor'` as `'NXOR'`, as recorded in Simulink 26.2).

| Library paths | BlockType | Parameters (default) | Octave Blocks realization |
| --- | --- | --- | --- |
| `Sources/Constant`, `Commonly Used Blocks/Constant` | Constant | `Value` (1) | Constant |
| `Sources/Clock`; `Sources/Ground`, `Commonly Used Blocks/Ground` | Clock; Ground | — | Time; Constant 0 |
| `Sources/Step` | Step | `Time` (1), `InitialValue` (0), `FinalValue` (1), `SampleTime` (0; also −1, both continuous-time; a discrete period is rejected); `Before`/`After` are accepted aliases, as in Simulink | Step |
| `Sources/Sine Wave` | Sin | `Amplitude`, `Bias`, `Frequency` (rad/s), `Phase` | Virtual subsystem of native blocks |
| `Sources/Ramp` | SubSystem, MaskType `Ramp` | `slope` (1), `start` (0), `InitialOutput` (0) | Virtual subsystem of native blocks |
| `Math Operations/Gain`, `Commonly Used Blocks/Gain` | Gain | `Gain` (1), `Multiplication` (`Element-wise(K.*u)`; also `Matrix(K*u)`, `Matrix(u*K)`, `Matrix(K*u) (u vector)`) | Gain for scalar K or `Matrix(K*u)`; otherwise a subsystem: Constant K into a `times` Function (K.*u), a Product (u*K), or a `vec` Function before the Gain (K*u(:)) |
| `Math Operations/Sum`, `Commonly Used Blocks/Sum` (`|++`); `Math Operations/Add`, `built-in/Sum` (`++`); `Math Operations/Subtract` (`+-`) | Sum | `Inputs` (`'+-+'`, `'|++'`, or a count) | Sum, or a virtual subsystem of Gain(−1) and Sum blocks |
| `Math Operations/Product`, `Commonly Used Blocks/Product`; `Math Operations/Divide` | Product | `Inputs` (2; `*/`), `Multiplication` (`Element-wise(.*)`) | Element-wise `times`/`rdivide` Functions; `Matrix(*)` with two inputs uses Product |
| `Math Operations/Abs`, `Sqrt`, `Math Function`, `Trigonometric Function` | Abs, Sqrt, Math, Trigonometry | `Operator` | Function block calling the Octave function |
| `User-Defined Functions/MATLAB Fcn`, `Interpreted MATLAB Function`; `User-Defined Functions/Fcn` | MATLABFcn; Fcn | `MATLABFcn` (sin); `Expr` (`sin(u)`) | Function block; the expression must be `name` or `name(u)` |
| `Continuous/Integrator`, `Commonly Used Blocks/Integrator`; `Continuous/Integrator Limited` | Integrator | `InitialCondition`, `LimitOutput`, `UpperSaturationLimit`, `LowerSaturationLimit`, `ExternalReset` (`none`, `rising`, `falling`, `either`, `level`, `level hold`) | Integrator, or Limited Integrator with limits/reset port |
| `Continuous/Transport Delay` | TransportDelay | `DelayTime`, `InitialOutput` | Transport Delay |
| `Discrete/Unit Delay`; `Discrete/Discrete-Time Integrator`, `Commonly Used Blocks/Discrete-Time Integrator` | UnitDelay; DiscreteIntegrator | `InitialCondition`, `SampleTime` (−1) | Unit Delay, forward-Euler Discrete Integrator |
| `Signal Attributes/Rate Transition` | RateTransition | `OutPortSampleTime`, `InitialCondition`, `Integrity` (`on`), `Deterministic` (`on`), `OctaveInputSampleTime` (−1; Octave extension) | Native hold by default; with explicit input/output rates, `ob_rate_transition` modes |
| `Discontinuities/Saturation`, `Commonly Used Blocks/Saturation`; `Discontinuities/Dead Zone` | Saturate; DeadZone | `UpperLimit`/`LowerLimit`; `LowerValue`/`UpperValue` | Native blocks |
| `Signal Routing/Switch`, `Commonly Used Blocks/Switch` (`u2 > Threshold`); `built-in/Switch` (`u2 >= Threshold`) | Switch | `Criteria` (`u2 >= Threshold`, `u2 > Threshold`, `u2 ~= 0`), `Threshold` (0) | Native Switch for `>=`; the other criteria negate the control (`u2 > T` is `!(−u2 >= −T)`, `u2 ~= 0` is `!(−|u2| >= 0)`) and swap the data inputs of a native Switch, so they export to C |
| `Continuous/Transfer Fcn`, `State-Space`, `Zero-Pole` | TransferFcn, StateSpace, ZeroPole | Simulink coefficient and matrix parameters | `ob_transfer_function`, `ob_state_space`, `ob_zero_pole` |
| `Discrete/Discrete Transfer Fcn`, `Discrete State-Space` | DiscreteTransferFcn, DiscreteStateSpace | as above plus `SampleTime` (−1) | `ob_discrete_transfer_function`, `ob_discrete_state_space` |
| `Continuous/PID Controller`, `Discrete/Discrete PID Controller` | SubSystem, MaskType `PID 1dof` | `P`, `I`, `D`, `N`, `Form`, `TimeDomain`, `SampleTime`, `LimitOutput`, limits | `ob_pid_controller` |
| `Lookup Tables/1-D Lookup Table` | Lookup_n-D | `BreakpointsForDimension1`, `Table`, `InterpMethod` (`Linear point-slope` or `Linear Lagrange`), `ExtrapMethod` (`Linear` default, or `Clip`) | `ob_lookup_table_1d` |
| `Lookup Tables/Lookup Table` (legacy) | Lookup | `InputValues`, `Table`, `LookUpMeth` (`Interpolation-Extrapolation` or `Interpolation-Use End Values`) | `ob_lookup_table_1d` |
| `Discontinuities/Rate Limiter` | RateLimiter | `RisingSlewLimit`, `FallingSlewLimit`, `SampleTimeMode` (`inherited`/`continuous`), `InitialCondition`, and the Octave-only `OctaveSampleTime` (0.1) | Sampled `ob_rate_limiter` at `OctaveSampleTime` |
| `Discontinuities/Relay` | Relay | switch points, outputs, `SampleTime` (−1) | Sampled `ob_relay` |
| `Sinks/Scope`, `Commonly Used Blocks/Scope`; `Sinks/Display`; `Sinks/Terminator`, `Commonly Used Blocks/Terminator`; `Sinks/To Workspace` | Scope; Display; Terminator; ToWorkspace | `VariableName`, `SaveFormat` (To Workspace) | Scope; Scope and To Workspace are logged by `sim` |
| `Sources/In1`, `Ports & Subsystems/In1`, `Commonly Used Blocks/In1`; `Sinks/Out1`, `Ports & Subsystems/Out1`, `Commonly Used Blocks/Out1` | Inport; Outport | `Port` (automatic when omitted); Outport `OutputWhenDisabled` (`held`; also `reset`) and `InitialOutput` (`[]`, meaning 0) | Inport, Outport; inside a conditional subsystem the Outport parameters set its `execution.outputs` (per port) and `initial_outputs` |
| `Ports & Subsystems/Subsystem`, `Commonly Used Blocks/Subsystem`, `Enabled Subsystem`, `Triggered Subsystem`, `Enabled and Triggered Subsystem`, `Resettable Subsystem` | SubSystem | — | Editable subsystem with In1 → Out1 and its control block; `built-in/SubSystem` starts empty, like Simulink |
| `Ports & Subsystems/Enable`, `Ports & Subsystems/Trigger`, `Ports & Subsystems/Resettable Subsystem/Reset` | EnablePort, TriggerPort, ResetPort | `StatesWhenEnabling` (`held`; also `reset`), `TriggerType`, `InitialTriggerSignalState` (`compatibility (no trigger on first evaluation)`; also `zero`, `positive`, `negative`), `ResetTriggerType` | Set the parent subsystem's execution mode; `StatesWhenEnabling` sets its `states`, `InitialTriggerSignalState` its `initial_control` (`'compatibility'`, 0, 1, −1) |
| `Discontinuities/Backlash` | Backlash | `BacklashWidth` (1), `InitialOutput` (0), `SampleTime` (−1; also T or [T offset]) | `ob_backlash` |
| `Discontinuities/Quantizer` | Quantizer | `QuantizationInterval` (0.5), `SampleTime` (−1; also T or [T offset]) | `ob_quantizer` |
| `Math Operations/MinMax` | MinMax | `Function` (`min`; also `max`), `Inputs` (1), `SampleTime` (−1) | `ob_minmax` for 2 or more inputs; `Inputs` 1 (Simulink's default) reduces every element of one input with `vec` and `min`/`max` Function blocks, which run in Octave but are not exported to C |
| `Discontinuities/Saturation Dynamic`; `Discontinuities/Dead Zone Dynamic` | SubSystem, MaskType `Saturation Dynamic`; `Dead Zone Dynamic` | — (ports `up`, `u`, `lo`) | `ob_saturation_dynamic`; `ob_dead_zone_dynamic` |
| `Math Operations/Sign` | Signum | `ZeroCross` (`on`), `SampleTime` (−1) | `ob_sign` (Switches with zero-crossing guards); `ZeroCross` `off` gives a guard-free Function `sign` |
| `Discontinuities/Coulomb & Viscous Friction` | SubSystem, MaskType `Coulombic and Viscous Friction` | `offset` (`[1 3 2 0]`), `gain` (1) | `ob_coulomb_viscous_friction` |
| `Logic and Bit Operations/Relational Operator`, `Commonly Used Blocks/Relational Operator` | RelationalOperator | `Operator` (`<=`; also `==`, `~=`, `<`, `>=`, `>`), `SampleTime` (−1) | `ob_relational_operator` (double 0/1 output) |
| `Logic and Bit Operations/Logical Operator`, `Commonly Used Blocks/Logical Operator` | Logic | `Operator` (`AND`; also `OR`, `NAND`, `NOR`, `XOR`, `NXOR`, `NOT`), `Inputs` (2; ignored for `NOT`, which has one port as in Simulink), `SampleTime` (−1) | `ob_logical_operator` (double 0/1 output) |
| `Signal Routing/Multiport Switch` | MultiPortSwitch | `Inputs` (3), `DataPortOrder` (`One-based contiguous`; also `Zero-based contiguous`), `DataPortForDefault` (`Last data port`; also `Additional data port`), `DiagnosticForDefault` (`Error`; accepted, always behaves as `None`), `SampleTime` (−1) | `ob_multiport_switch` (control truncated toward zero, as Simulink does) |
| `Sources/Pulse Generator` | DiscretePulseGenerator | `PulseType` (`Time based`; also `Sample based`), `TimeSource` (`Use simulation time` only), `Amplitude` (1), `Period` (10), `PulseWidth` (5, percent; samples when sample based), `PhaseDelay` (0), `SampleTime` (1, used when sample based) | `ob_pulse_generator`; a sample-based pulse is the time-based pulse with edges at `Period*SampleTime`, `PulseWidth*SampleTime` and `PhaseDelay*SampleTime`, sampled and held at `[SampleTime 0]` by a native Rate Transition, so it has Simulink's discrete rate for `FixedStep` `auto` and for inherited blocks downstream; `PulseWidth` is 1 to `Period` samples (`Period` holds `Amplitude`), as in Simulink |
| `Sources/Chirp Signal` | SubSystem, MaskType `chirp` | `f1` (0.1), `T` (100), `f2` (1) | `ob_chirp` |
| `Signal Routing/Mux`, `Commonly Used Blocks/Mux`; `Signal Routing/Demux`, `Commonly Used Blocks/Demux` | Mux; Demux | `Inputs` (2) / `Outputs` (2): a count of scalar signals or a vector of widths; `DisplayOption` (`bar`, cosmetic) | `ob_mux`, `ob_demux` (column vectors; widths must be declared because signal widths are not propagated). A count takes scalars. When a signal does not have the declared shape, `sim` stops with an `ob_simulink:MuxWidth` or `ob_simulink:DemuxWidth` error naming the block (Simulink would infer the width). It also adds the same hint to dimension errors raised in models with Mux or Demux blocks |
| `Continuous/Integrator, Second-Order` | SecondOrderIntegrator | `ICX` (0.0), `ICDXDT` (0.0); `ICSourceX`/`ICSourceDXDT` (`internal`), `LimitX`/`LimitDXDT` (`off`), `WrapX` (`off`), `ExternalReset` (`none`) and `ShowOutput` (`both`) only at these values | `ob_second_order_integrator` (outputs x and dx/dt) |

All library paths start with `simulink/`. Simulink has no
`simulink/Ports & Subsystems/Reset` block: the Reset block comes from inside
the Resettable Subsystem or as `built-in/ResetPort`. `built-in/<BlockType>`
blocks use Simulink's BlockType defaults, which can differ from the library
block's (for example `built-in/UnitDelay` has `SampleTime` 1, `built-in/Step`
has −1, `built-in/TransferFcn` has Denominator `[1 2 1]`, `built-in/ToWorkspace`
writes `simulink_output` as an Array, `built-in/RelationalOperator` uses
`>=`, `built-in/Mux` and `built-in/Demux` have 4 ports, and
`built-in/DiscretePulseGenerator` is a sample-based pulse with `Period` 2
and `PulseWidth` 1). All are recorded by
`reference_ob_simulink_api.m` and checked by `test_ob_simulink_api_reference`.
The exception is `built-in/Lookup_n-D`: Simulink's BlockType default is a
multi-dimensional table with three inputs, and only the 1-D configuration is
supported, so it uses the 1-D Lookup Table defaults. Ramp and the
PID Controllers are masked subsystems in Simulink, so `built-in/Ramp` does
not exist.

Library-built linear, controller and structural subsystems behave like
masked blocks: their contents are generated from the parameters and cannot
be edited by path.

The Trigger block's `InitialTriggerSignalState` behaves as in Simulink. Its
default is `compatibility (no trigger on first evaluation)`, so a library
Triggered Subsystem never executes at its first evaluation. Values are
case-insensitive, and plain `compatibility` is accepted. These rules were
recorded by `reference_ob_conditional_probes.m` and are checked by
`test_ob_simulink_api_reference`. The value sets the subsystem's
`initial_control`: `'compatibility'`, 0, 1 or −1 (see
[CONDITIONAL.md](CONDITIONAL.md#initial-trigger-control)). Simulink 26.2
traces confirm all four values for sampled triggers and for continuous
triggers under ode45. Deleting the Trigger block clears a `'compatibility'`
setting.

Inside a conditional subsystem, each Outport's `OutputWhenDisabled` and
`InitialOutput` and the Enable block's `StatesWhenEnabling` behave as in
Simulink (see [CONDITIONAL.md](CONDITIONAL.md#states-and-outputs)). The
policies are per Outport; `held`/`reset` are case-insensitive and stored in
lower case; any other value is an "Invalid setting" error. `InitialOutput`
is evaluated when the model is simulated or saved, as Simulink evaluates it
when compiling, so it may name a variable defined later; `[]` (the default)
means 0, and a scalar widens to a vector or matrix port: `sim` expands it
by static shape propagation before the run (`ob_expand_initial_outputs`),
so the port has its full width from the start, even when its subsystem
first runs later. A Triggered or
Resettable Subsystem accepts `OutputWhenDisabled` but keeps its outputs held,
as Simulink does. Native Outports (not added with `add_block`) report the
values their subsystem's execution holds. These rules are recorded by
`reference_ob_conditional_outputs.m` (`simulink-conditional-outputs-reference.json`)
and checked by `test_ob_simulink_api_reference`.

Models saved by earlier versions keep loading with unchanged behaviour:
their Step `Before`/`After`, Ramp `Slope`/`Start` and Rate Limiter
`SampleTime` parameters are renamed, and their Gains keep `Matrix(K*u)`.

## Differences from Simulink

A live comparison against Simulink 26.2 (MATLAB R2026b) found the following
remaining differences; each is either an intended limitation or recorded
as an explicit exception in `test_ob_simulink_api_reference`.

**Files, handles and objects**

- Systems are Octave Blocks models, not `.slx`/`.mdl` files: `load_system`
  rejects `.slx`/`.mdl` even when the file exists, and `save_system` writes
  `.mat` files (which Simulink rejects). `save_system` keeps the run
  settings but not `SaveFormat` or `ReturnWorkspaceOutputs`, and
  `SimulationMode` `rapid-accelerator` comes back as `accelerator` (both
  run the same accelerator). Commands
  return paths rather than numeric handles. The files keep each
  conditional subsystem's execution settings but not its Enable, Trigger
  and Reset blocks. `load_system` rebuilds those blocks from the settings,
  under Simulink's default names (`Enable`, `Trigger`, `Reset`), so their
  parameters, including `StatesWhenEnabling` and
  `InitialTriggerSignalState`, survive the round trip but renamed blocks
  get their default names back. Outport parameters are kept with the
  Outports.
- `SimulationMode` accepts `normal`, `accelerator` and `rapid-accelerator`;
  Simulink's `software-in-the-loop (sil)`, `processor-in-the-loop (pil)`
  and `external` are rejected. The "Invalid setting" message for
  `StatesWhenEnabling` names the Enable block, where Simulink gives its
  full path.
- `sim` returns a struct, not a `Simulink.SimulationOutput`; with
  `SaveFormat` `Dataset`, `yout` and `logsout` are Dataset-like structs
  (fields and function handles, see [Dataset output](#dataset-output)), not
  `Simulink.SimulationData.Dataset` objects, and To Workspace never logs a
  `timeseries`. The model default stays `Array` (Simulink's is `Dataset`)
  and To Workspace defaults to `Structure With Time` (Simulink's is
  `Timeseries`, which errors). Every logged signal is sampled on `tout`;
  Simulink logs each Dataset signal at its own rate (one sample, at the
  start time, for a constant; a 0.2 s Unit Delay at 0.2 s). With `Array`,
  matrix-valued Out1 ports give a cell of per-port arrays, where Simulink
  stops with an error. `sim` rejects `OutputOption`/`OutputTimes`; pass an output-time
  vector instead.
- Scope blocks are logged into `logsout` (Simulink logs a Scope only when
  its `DataLogging` is on, into `ScopeData`), so `who` also lists `logsout`.
  Line names, signal logging (`DataLogging` on ports) and
  `SignalLoggingName` are not available.
- `SimulationMetadata` is a struct; its `Solver` field (absent in Simulink,
  which keeps the solver in `ModelInfo.SolverInfo.Solver`) names the Octave
  Blocks solver that ran.
- The legacy `[t, x, y] = sim(...)` form returns an empty `x` (Simulink
  returns the states), on the output grid rather than at solver steps.
- `get_param(..., 'DialogParameters')` and the model's `ObjectParameters`
  return structs of current values, not Simulink's descriptor structs
  (`Prompt`, `Type`, `Enum`, `Attributes`), and list only the supported
  parameters.
- `find_system` returns the same paths as Simulink but in creation order
  (Enable/Trigger/Reset blocks last); Simulink sorts each diagram.
- `set_param` accepts numeric values (for example `StopTime` 2) and stores
  them as text; Simulink requires character vectors for model parameters.

**Blocks and parameters**

- Only the blocks and parameters above are recognized; anything else is an
  error that names the supported parameters. There is no bus,
  Stateflow, model reference or variant support (Mux and Demux need
  declared widths), and no Signal Builder
  (which Simulink still adds, as a deprecated masked subsystem). Unsupported Simulink
  parameters include Gain/Sum/Product data types,
  function-call triggers, Constant/Sine `SampleTime` and a discrete Step
  `SampleTime` (only 0 and −1 are accepted), Sine `SineType`,
  Transport Delay buffer/Padé options, block `ZeroCross` settings, Rate
  Transition `Integrity` or `Deterministic` `off` with an inherited input
  rate (those modes need explicit `OctaveInputSampleTime` and
  `OutPortSampleTime`; sample times are not propagated), the PID anti-windup, filter and
  integrator options, Discrete-Time Integrator methods, limits and reset,
  Discrete Transfer Fcn initial states and reset, and the Integrator's
  `InitialConditionSource`, `WrapState`, `ShowStatePort`,
  `ShowSaturationPort`, `IgnoreLimit` and `AbsoluteTolerance`.
- The Fcn block defaults to `sin(u)`: Simulink's default
  `sin(u(1)*exp(2.3*(-u(2))))` indexes a second input element, which a
  Function block (`name` or `name(u)`) cannot express.
- The Discrete PID Controller defaults to `SampleTime` 1 and rejects −1
  (inherited), which Simulink accepts: the discrete PID builder needs an
  explicit period.
- Rate Limiter and Relay are sampled. The Rate Limiter has no Simulink
  sample-time parameter (Simulink's `SampleTimeMode` `inherited` follows the
  driving block), so it samples at the Octave-only `OctaveSampleTime`
  (default 0.1): on a 0.05 s fixed step it rises 0.1 per 0.1 s where Simulink
  rises 0.05 per step. `OctaveSampleTime` is not counted by `FixedStep`
  `auto`, so a model whose only "rate" is a Rate Limiter gets Simulink's
  (stop − start)/50 grid, but the limiter still updates at its own 0.1 s
  hits (after a unit step at t = 1 it reads 0.1, 0.3, 0.5, ... on a 0.2 s
  grid; Simulink's inherited limiter updates once per 0.2 s step). The
  Relay's `SampleTime` −1 samples on the output grid.
- Switch `u2 > Threshold` is realized as `!(−u2 >= −Threshold)`; Octave
  Blocks rejects non-finite signals, so the two forms always agree.
- A Gain with `Multiplication` `Matrix(K*u)` multiplies the signal as
  stored: Octave Blocks vectors are rows, so use `Matrix(K*u) (u vector)`
  for K*u(:). That mode uses a `vec` Function and cannot be exported to C.
- Enable, Trigger and Reset blocks belong inside a subsystem: an Enable at
  the model root (an enabled referenced model in Simulink) is rejected.
- When a port disappears (deleting a block or an Enable/Trigger/Reset
  block, or setting an Integrator's `ExternalReset` to `none`), its lines
  are deleted; Simulink keeps them as unconnected lines. Octave Blocks also
  requires every input to be connected, where Simulink feeds an unconnected
  input with 0 (with a warning).
- Inherited (−1) sample times run on the output grid (`FixedStep`); this
  matches Simulink with fixed-step solvers but was not compared under
  variable-step solvers.
- 0.3.0 blocks: Relational and Logical Operators output double 0/1 (Simulink
  outputs `boolean`; `OutDataTypeStr` and the other data-type parameters are
  not listed); Relational `isInf`, `isNaN` and `isFinite` are not available;
  MinMax `Inputs` 1 (Simulink's default) runs in Octave, also in the
  accelerator modes, but `ob_codegen` cannot export it (`unsupported
  Function 'vec'`); Logical Operator `Inputs` 1 is rejected for every
  operator except `NOT` (no single-input reduction); Backlash
  `BacklashWidth` is a scalar and a vector signal needs an `InitialOutput`
  of its shape; Backlash with an inherited rate updates on the output grid;
  MinMax, Sign, Relational and Logical Operator and Multiport Switch accept
  only an inherited (−1) or continuous (0) `SampleTime`; Multiport Switch
  `DiagnosticForDefault` `Error`/`Warning` behave as `None` (Simulink stops
  or warns when the control leaves the data port range), a NaN control is
  rejected, and `Specify indices` and `Inputs` 1 are not supported; Pulse
  Generator `TimeSource` must be simulation time and its edges are exact in
  downstream integrators only with `ZeroCrossControl` `EnableAll`; Mux and
  Demux need declared widths (`Inputs` −1 is rejected) and column-vector
  signals: a Mux with a count fed Constant `[1 2]` stops with
  `ob_simulink:MuxWidth` where Simulink outputs `[1 2 3]` (recorded,
  scenario `followup`); write `[1;2]` and declare `Inputs` `[2 1]`; `Integrator, Second-Order` covers only its default options, and
  `Integrator, Second-Order Limited` is not supported. Rate Transition uses
  the native hold by default. Set its `OctaveInputSampleTime` and
  `OutPortSampleTime` explicitly to use the Integrity/Deterministic modes
  described in [MULTIRATE.md](MULTIRATE.md#rate-transition).

**Solvers and numerics**

- `ode23`, `ode113`, `ode23s`, `ode23t` and `ode23tb` are mapped to the
  nearest available solver rather than implemented; other Simulink solvers
  (ode1, ode2, ode3, ode5, ode8, ode14x, ode1be, ...) are rejected. With
  `FixedStepAuto` Octave Blocks runs RK4 (reported as `ode4` when the model
  has continuous states), where Simulink would choose its own solver.
- Variable-step runs report outputs on the `FixedStep` grid rather than at
  every solver step (Simulink's default `Refine` output). Output times are
  built with different rounding and can differ from Simulink's by about
  1e-15, so a value sampled exactly at a delay or step time can differ by a
  rounding residue.
- `FixedStep` `auto` uses (stop − start)/50 for a model that has both
  continuous states and discrete rates; Simulink's choice for such models
  was not compared.
- With `ode4`, a Step block transition that falls inside an RK4 step splits
  the step at the transition, and a transition exactly on the grid is taken
  as its left limit at the step's final stage. Simulink's ode4 does neither:
  it samples the Step in each stage (a PID loop with a Step at t = 1 and
  h = 0.02 differs by up to 1.7e-3; an integrated Step at 0.55 with h = 0.1
  by h/6·(After − Before)). Octave Blocks' result is closer to the exact
  solution. Ramp, built on a Step, behaves the same way.
- An Integrator with `LimitOutput` on reaches a limit exactly at the RK4
  step that crosses it; Simulink's ode4 gates each stage and arrives one
  step later (0.7083 instead of 0.75 at t = 0.75 for a unit ramp limited to
  0.75 with h = 0.25). Adaptive solvers gate each stage like Simulink, but
  limit hits are not located as events.
- Integrator `ExternalReset` resets are sampled at accepted solver hits
  (output times, sample hits and events). Simulink's variable-step solvers
  locate the reset edge, so a reset between output samples happens later in
  Octave Blocks, and a level pulse that starts and ends between samples is
  missed. Fixed-step runs agree. `level` also resets when the signal
  returns to zero (sampled at the next hit); `level hold` resets to the
  initial condition at every hit while the signal is nonzero, with no reset
  when it returns to zero.
- `ZeroCrossControl` `EnableAll` turns on event localization, which the
  Limited Integrator does not support; such models must use
  `UseLocalSettings` (sampled resets, unlocated limits) or `DisableAll`.

## Comparison with Simulink

`test_ob_simulink_api()` checks each command against analytical results and
direct Octave Blocks models, including C export of API-built models with the
structural Switch and Gain realizations; `ob_simulink_codegen_case` builds
such a model for the compiled C comparison.
`test_ob_simulink_api_reference()` compares the API with
`simulink-api-reference.json`, recorded in Simulink 26.2 (R2026b) by
`reference_ob_simulink_api.m`: every supported library path, its BlockType,
MaskType, `Ports`, parameter names and default values, the
`built-in/<BlockType>` paths and their defaults, parameter and error probes, the legacy `sim` outputs,
`SolverInfo.Solver`, and the outputs of the scenarios above where the
products agree (to 1e-9 or better, solver tolerance for adaptive runs; the
PID loop, which differs by the documented Step sampling, to 2e-3). Each
difference listed above that the reference covers is checked to remain the
documented Octave Blocks behaviour. Since 0.3.0 the record also holds the
library and `built-in/<BlockType>` defaults of the nineteen new library
paths, ode4 traces of every new block driven through the API (scenarios
`newnonlinear` and `newrouting`, matched to 1e-12, the sample-based pulse at
Simulink's own 1 s logging times), and the `Dataset` layout, access
functions, warning and error text (scenario `dataset`). Scenario `followup`
records the sample-based pulse feeding an inherited Unit Delay (with default
solver settings `tout` is 0:1:10 and the delay is one 1 s sample; also ode4
at 0.2 s), the sample-based `PulseWidth` limits, a Mux with a count fed a row
vector, and how `set_param` stores enumerated values typed in another case.
