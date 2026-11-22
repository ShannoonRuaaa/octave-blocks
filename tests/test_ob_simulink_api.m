function test_ob_simulink_api ()
  % Simulink-style command API: construction, parameters, hierarchy,
  % simulation outputs, persistence, and explicit unsupported cases.
  % test_ob_simulink_api_reference compares the same API with recorded
  % Simulink R2026b results.
  here = fileparts (mfilename ('fullpath'));
  addpath (fullfile (fileparts (here), 'simulink'));
  bdclose ('all');
  cleanup = onCleanup (@() bdclose ('all'));
  cases = 0;

  % Sources, an integrator and a root Outport.
  new_system ('api');
  assert (bdIsLoaded ('api'));
  assert (strcmp (get_param ('api', 'Dirty'), 'off'));
  add_block ('simulink/Sources/Sine Wave', 'api/Sine', 'Amplitude', '2', 'Frequency', '3', 'Bias', '0.5');
  add_block ('simulink/Continuous/Integrator', 'api/Int');
  add_block ('simulink/Sinks/Out1', 'api/Out1');
  add_line ('api', 'Sine/1', 'Int/1'); add_line ('api', 'Int/1', 'Out1/1');
  set_param ('api', 'StopTime', '2', 'Solver', 'ode45', 'RelTol', '1e-9', 'AbsTol', '1e-12', 'FixedStep', '0.05');
  out = sim ('api');
  t = out.tout;
  assert (out.yout, 2/3 * (1 - cos (3*t)) + 0.5*t, 1e-7);
  % SimulationMetadata keeps the Octave Blocks fields and adds Simulink's
  % ModelInfo/TimingInfo layout.
  assert (out.SimulationMetadata.Solver, 'ode45');
  assert (out.SimulationMetadata.ModelInfo.ModelName, 'api');
  assert (out.SimulationMetadata.ModelInfo.SolverInfo.Solver, 'ode45');
  assert (out.SimulationMetadata.ModelInfo.SolverInfo.Type, 'Variable-Step');
  assert (out.SimulationMetadata.ModelInfo.SolverInfo.MaxStepSize, 0.04, 1e-15);
  assert (out.SimulationMetadata.TimingInfo.TotalElapsedWallTime >= 0);
  assert (out.who, {'tout'; 'yout'});
  cases += 2;

  % Signed sums, element-wise products, gains and a To Workspace log.
  new_system ('ops');
  for k = 1:3
    add_block ('simulink/Sources/Constant', sprintf ('ops/C%d', k), 'Value', mat2str (k * [1 2]));
  endfor
  add_block ('simulink/Math Operations/Sum', 'ops/Sum', 'Inputs', '+-+');
  add_block ('simulink/Math Operations/Product', 'ops/Prod', 'Inputs', '**/');
  add_block ('simulink/Math Operations/Gain', 'ops/K', 'Gain', '-2');
  add_block ('simulink/Sinks/To Workspace', 'ops/Log', 'VariableName', 'sumlog');
  add_block ('simulink/Sinks/Out1', 'ops/Out1');
  for k = 1:3
    add_line ('ops', sprintf ('C%d/1', k), sprintf ('Sum/%d', k));
    add_line ('ops', sprintf ('C%d/1', k), sprintf ('Prod/%d', k));
  endfor
  add_line ('ops', 'Sum/1', 'K/1'); add_line ('ops', 'K/1', 'Log/1'); add_line ('ops', 'Prod/1', 'Out1/1');
  out = sim ('ops', [0 1]);
  % To Workspace defaults to Simulink's 'Structure With Time' layout.
  assert (out.sumlog.signals.values(end, :), -2 * ([1 2] - [2 4] + [3 6]));
  assert (out.sumlog.signals.dimensions, 2);
  assert (out.sumlog.blockName, 'ops/Log');
  assert (out.sumlog.time, out.tout);
  % SaveFormat 'Array': vector ports become columns of one matrix.
  assert (size (out.yout), [51 2]);
  assert (out.yout(end, :), ([1 2] .* [2 4]) ./ [3 6], 1e-15);
  assert (out.who, {'sumlog'; 'tout'; 'yout'});
  assert (get_param ('ops/Sum', 'BlockType'), 'Sum');
  assert (get_param ('ops/Sum', 'Inputs'), '+-+');
  assert (get_param ('ops/Sum', 'Ports'), [3 1 0 0 0 0 0 0 0 0]);
  assert (get_param ('ops', 'SaveFormat'), 'Array');
  out = sim ('ops', [0 1], 'SaveFormat', 'StructureWithTime');
  assert (out.yout.time, out.tout);
  assert (out.yout.signals.values(end, :), [2/3 4/3], 1e-15);
  assert (out.yout.signals.dimensions, 2);
  assert (out.yout.signals.blockName, 'ops/Out1');
  set_param ('ops', 'SaveFormat', 'Structure');
  out = sim ('ops', [0 1]);
  assert (isempty (out.yout.time) && isequal (size (out.yout.signals.values), [51 2]));
  assert_error (@() set_param ('ops', 'SaveFormat', 'Dataset'), 'Dataset');
  assert (strcmp (get_param ('ops', 'SaveFormat'), 'Structure'));
  set_param ('ops/Log', 'SaveFormat', 'Array');
  out = sim ('ops', [0 1]);
  assert (out.sumlog, repmat ([-4 -8], 51, 1));
  set_param ('ops/Log', 'SaveFormat', 'Structure');
  out = sim ('ops', [0 1]);
  assert (isempty (out.sumlog.time) && isfield (out.sumlog, 'blockName'));
  assert_error (@() set_param ('ops/Log', 'SaveFormat', 'Timeseries'), 'Timeseries');
  cases += 4;

  % Transfer Fcn step response against its analytical solution.
  new_system ('tf');
  add_block ('simulink/Sources/Step', 'tf/Step', 'Time', '0.5');
  add_block ('simulink/Continuous/Transfer Fcn', 'tf/Plant', 'Denominator', '[1 2]', 'Numerator', '[4]');
  add_block ('simulink/Sinks/Out1', 'tf/y');
  add_line ('tf', 'Step/1', 'Plant/1'); add_line ('tf', 'Plant/1', 'y/1');
  out = sim ('tf', 'StopTime', '3', 'Solver', 'ode45', 'RelTol', '1e-10', 'AbsTol', '1e-12', 'FixedStep', '0.1');
  t = out.tout;
  assert (out.yout, (t >= 0.5) .* 2 .* (1 - exp (-2 * (t - 0.5))), 1e-7);
  % Workspace variables are read at simulation time.
  assignin ('base', 'ob_api_gain', 6);
  set_param ('tf/Plant', 'Numerator', 'ob_api_gain');
  out = sim ('tf', 'StopTime', '3', 'Solver', 'ode45', 'RelTol', '1e-10', 'AbsTol', '1e-12', 'FixedStep', '0.1');
  assert (out.yout(end), 3 * (1 - exp (-5)), 1e-7);
  assignin ('base', 'ob_api_gain', 2);
  out = sim ('tf', 'StopTime', '3', 'Solver', 'ode45', 'RelTol', '1e-10', 'AbsTol', '1e-12', 'FixedStep', '0.1');
  assert (out.yout(end), 1 - exp (-5), 1e-7);
  % Like Simulink, [t, x, y] = sim (...) needs ReturnWorkspaceOutputs 'off'
  % and never accepts name/value pairs.
  assert_error (@() legacy_sim ('tf', 'StopTime', '3', 'FixedStep', '0.1'), 'Too many output arguments');
  assert_error (@() legacy_sim ('tf', [0 3]), 'Too many output arguments');
  set_param ('tf', 'ReturnWorkspaceOutputs', 'off', 'FixedStep', '0.1');
  [t_legacy, x_legacy, y_legacy] = sim ('tf', [0 3]);
  assert (numel (t_legacy) == 31 && isempty (x_legacy) && numel (y_legacy) == 31);
  assert (sim ('tf', [0 3]), t_legacy);          % one output is t, as in Simulink
  assert_error (@() legacy_sim ('tf', 'StopTime', '3'), 'Too many output arguments');
  out = sim ('tf', 'StopTime', '3');             % the name/value form returns the struct
  assert (isstruct (out) && isfield (out, 'yout'));
  set_param ('tf', 'ReturnWorkspaceOutputs', 'on', 'FixedStep', 'auto');
  cases += 5;

  % Integrator options map to the Limited Integrator.
  new_system ('lim');
  add_block ('simulink/Sources/Constant', 'lim/One');
  add_block ('simulink/Continuous/Integrator', 'lim/Int', 'LimitOutput', 'on', ...
             'UpperSaturationLimit', '0.75', 'LowerSaturationLimit', '0');
  add_block ('simulink/Sinks/Out1', 'lim/Out1');
  add_line ('lim', 'One/1', 'Int/1'); add_line ('lim', 'Int/1', 'Out1/1');
  out = sim ('lim', 'StopTime', '2', 'Solver', 'ode4', 'FixedStep', '0.25');
  assert_limited (out, min (out.tout, 0.75));
  assert (out.SimulationMetadata.ModelInfo.SolverInfo.Solver, 'ode4');
  set_param ('lim/Int', 'ExternalReset', 'rising');
  assert (isequal (get_param ('lim/Int', 'Ports'), [2 1 0 0 0 0 0 0 0 0]));
  add_block ('simulink/Sources/Step', 'lim/Reset', 'Time', '1', 'Before', '-1', 'After', '1');
  add_line ('lim', 'Reset/1', 'Int/2');
  out = sim ('lim', 'StopTime', '2', 'Solver', 'ode4', 'FixedStep', '0.25');
  expected = min (out.tout, 0.75); expected(out.tout >= 1) = min (out.tout(out.tout >= 1) - 1, 0.75);
  assert_limited (out, expected);
  % 'level hold' maps to the Limited Integrator's level hold reset: while
  % the reset signal is nonzero the state returns to the initial condition
  % (it is not frozen at its last value).
  set_param ('lim/Int', 'ExternalReset', 'level hold');
  model = ob_simulink ('get_model', 'lim');
  assert (model.blocks(2).value.reset, 'level hold');
  set_param ('lim/Reset', 'Before', '0');          % zero until t = 1, then 1
  out = sim ('lim', 'StopTime', '2', 'Solver', 'ode4', 'FixedStep', '0.25');
  expected = min (out.tout, 0.75); expected(out.tout >= 1) = 0;
  assert_limited (out, expected);
  assert (max (out.yout(out.tout < 1)) > 0.5);      % the state had grown before the reset
  set_param ('lim/Int', 'ExternalReset', 'none');
  assert (isempty (find_line (ob_simulink ('get_model', 'lim'), 2, 2)));
  assert_error (@() set_param ('lim/Int', 'ExternalReset', 'sometimes'), 'ExternalReset');
  assert (strcmp (get_param ('lim/Int', 'ExternalReset'), 'none'));
  cases += 5;

  % Transport Delay.
  new_system ('dly');
  add_block ('simulink/Sources/Clock', 'dly/Clock');
  add_block ('simulink/Continuous/Transport Delay', 'dly/Delay', 'DelayTime', '0.3', 'InitialOutput', '-1');
  add_block ('simulink/Sinks/Out1', 'dly/Out1');
  add_line ('dly', 'Clock/1', 'Delay/1'); add_line ('dly', 'Delay/1', 'Out1/1');
  out = sim ('dly', 'StopTime', '1', 'Solver', 'ode4', 'FixedStep', '0.1');
  assert (out.yout, (out.tout < 0.3) * -1 + (out.tout >= 0.3) .* (out.tout - 0.3), 1e-12);
  cases += 1;

  % Enabled subsystem with held output, built through hierarchical paths.
  new_system ('cond');
  add_block ('simulink/Sources/Clock', 'cond/Clock');
  add_block ('simulink/Sources/Step', 'cond/On', 'Time', '0.45');
  add_block ('simulink/Sources/Step', 'cond/Off', 'Time', '1.05', 'After', '-1');
  add_block ('simulink/Math Operations/Add', 'cond/Gate');
  add_block ('simulink/Ports & Subsystems/Enabled Subsystem', 'cond/Sub');
  add_block ('simulink/Math Operations/Gain', 'cond/Sub/Double', 'Gain', '2');
  delete_line ('cond/Sub', 'In1/1', 'Out1/1');
  add_line ('cond/Sub', 'In1/1', 'Double/1'); add_line ('cond/Sub', 'Double/1', 'Out1/1');
  add_block ('simulink/Sinks/Out1', 'cond/Out1');
  add_line ('cond', 'On/1', 'Gate/1'); add_line ('cond', 'Off/1', 'Gate/2');
  add_line ('cond', 'Clock/1', 'Sub/1'); add_line ('cond', 'Gate/1', 'Sub/Enable');
  add_line ('cond', 'Sub/1', 'Out1/1');
  out = sim ('cond', 'StopTime', '1.5', 'Solver', 'ode4', 'FixedStep', '0.1');
  t = out.tout;
  expected = zeros (size (t));
  active = t >= 0.45 & t < 1.05; expected(active) = 2 * t(active);
  expected(t >= 1.05) = 2;
  assert (out.yout, expected, 1e-12);
  paths = find_system ('cond', 'SearchDepth', 1);
  assert (any (strcmp (paths, 'cond/Sub')) && ! any (strcmp (paths, 'cond/Sub/Double')));
  assert (any (strcmp (find_system ('cond'), 'cond/Sub/Enable')));
  assert (strcmp (get_param ('cond/Sub/Enable', 'BlockType'), 'EnablePort'));
  % Ports splits control ports out of the data inputs, like Simulink.
  assert (get_param ('cond/Sub', 'Ports'), [1 1 1 0 0 0 0 0 0 0]);
  assert (get_param ('cond/Sub/Enable', 'Ports'), zeros (1, 10));
  cases += 4;

  % Adding a Trigger makes an enabled-and-triggered subsystem; deleting the
  % Enable block moves the trigger wire down to the first control port.
  add_block ('simulink/Ports & Subsystems/Trigger', 'cond/Sub/Trigger', 'TriggerType', 'falling');
  model = ob_simulink ('get_model', 'cond');
  sub = find (strcmp ({model.blocks.name}, 'Sub'));
  assert (strcmp (ob_execution_mode (model.blocks(sub).value), 'enabled_falling'));
  assert (get_param ('cond/Sub', 'Ports'), [1 1 1 1 0 0 0 0 0 0]);
  add_line ('cond', 'On/1', 'Sub/Trigger');
  delete_block ('cond/Sub/Enable');
  model = ob_simulink ('get_model', 'cond');
  assert (strcmp (ob_execution_mode (model.blocks(sub).value), 'falling'));
  on = find (strcmp ({model.blocks.name}, 'On'));
  assert (! isempty (find_line (model, sub, 2)) && find_line (model, sub, 2)(1) == on);
  assert (ob_block_ports (model.blocks(sub)) == 2);
  assert (get_param ('cond/Sub', 'Ports'), [1 1 0 1 0 0 0 0 0 0]);
  cases += 2;

  % InitialTriggerSignalState defaults to Simulink's 'compatibility (no
  % trigger on first evaluation)' and maps onto initial_control.  A trigger
  % that is high from the start never executes under compatibility, while
  % 'zero' executes once at t=0.
  compat = 'compatibility (no trigger on first evaluation)';
  new_system ('trig0');
  add_block ('simulink/Sources/Constant', 'trig0/Data', 'Value', '5');
  add_block ('simulink/Sources/Constant', 'trig0/High', 'Value', '1');
  add_block ('simulink/Ports & Subsystems/Triggered Subsystem', 'trig0/Sub');
  add_block ('simulink/Sinks/Out1', 'trig0/Out1');
  add_line ('trig0', 'Data/1', 'Sub/1'); add_line ('trig0', 'High/1', 'Sub/Trigger');
  add_line ('trig0', 'Sub/1', 'Out1/1');
  set_param ('trig0', 'Solver', 'ode4', 'StopTime', '2', 'FixedStep', '1');
  assert (get_param ('trig0/Sub/Trigger', 'InitialTriggerSignalState'), compat);
  assert (any (strcmp (find_system ('trig0', 'InitialTriggerSignalState', compat), 'trig0/Sub/Trigger')));
  initial = @() ob_simulink ('get_model', 'trig0').blocks(3).value.execution.initial_control;
  assert (initial (), 'compatibility');
  assert (sim ('trig0').yout, [0; 0; 0]);
  for state = {'Zero', 0; 'POSITIVE', 1; 'negative', -1; 'compatibility', 'compatibility'}'
    set_param ('trig0/Sub/Trigger', 'InitialTriggerSignalState', state{1});
    assert (initial (), state{2});
  endfor
  assert (get_param ('trig0/Sub/Trigger', 'InitialTriggerSignalState'), compat);
  set_param ('trig0/Sub/Trigger', 'InitialTriggerSignalState', 'zero');
  assert (sim ('trig0').yout, [5; 5; 5]);
  assert_error (@() set_param ('trig0/Sub/Trigger', 'InitialTriggerSignalState', 'unknown'), ...
                'Invalid setting in TriggerPort block ''Trigger'' for parameter ''InitialTriggerSignalState''');
  assert (get_param ('trig0/Sub/Trigger', 'InitialTriggerSignalState'), 'zero');
  add_block ('simulink/Ports & Subsystems/Enable', 'trig0/Sub/Enable');
  set_param ('trig0/Sub/Trigger', 'InitialTriggerSignalState', 'compatibility');
  delete_block ('trig0/Sub/Trigger');
  assert (! isfield (ob_simulink ('get_model', 'trig0').blocks(3).value.execution, 'initial_control'));
  add_block ('simulink/Ports & Subsystems/Trigger', 'trig0/Sub/Trigger', ...
             'TriggerType', 'falling', 'InitialTriggerSignalState', 'positive');
  assert (initial (), 1);
  % save_system keeps the execution, and load_system rebuilds the control
  % port blocks from it, so the Trigger parameters survive a round trip.
  folder = tempname (); mkdir (folder);
  file = fullfile (folder, 'saved_trigger.mat');
  save_system ('trig0', file);
  load_system (file);
  assert (get_param ('saved_trigger/Sub/Trigger', 'InitialTriggerSignalState'), 'positive');
  assert (get_param ('saved_trigger/Sub/Trigger', 'TriggerType'), 'falling');
  assert (strcmp (get_param ('saved_trigger/Sub/Enable', 'BlockType'), 'EnablePort'));
  assert (get_param ('saved_trigger/Sub', 'Ports'), [1 1 1 1 0 0 0 0 0 0]);
  set_param ('saved_trigger/Sub/Trigger', 'InitialTriggerSignalState', 'compatibility');
  assert (ob_simulink ('get_model', 'saved_trigger').blocks(3).value.execution.initial_control, ...
          'compatibility');
  bdclose ('saved_trigger'); bdclose ('trig0');
  confirm_recursive_rmdir (false, 'local'); rmdir (folder, 's');
  cases += 4;

  % Outport OutputWhenDisabled and InitialOutput, and Enable
  % StatesWhenEnabling, set the enabled subsystem's execution per port.
  % An enable pulse over [1, 3) samples a Unit Delay (Out1) and a pass-
  % through (Out2) of a Digital-Clock-like ramp.
  new_system ('pp');
  add_block ('simulink/Sources/Clock', 'pp/Clock');
  add_block ('simulink/Sources/Step', 'pp/On', 'Time', '1');
  add_block ('simulink/Sources/Step', 'pp/Off', 'Time', '3', 'After', '-1');
  add_block ('simulink/Math Operations/Add', 'pp/Gate');
  add_block ('simulink/Ports & Subsystems/Enabled Subsystem', 'pp/Sub');
  add_block ('simulink/Discrete/Unit Delay', 'pp/Sub/Delay', 'InitialCondition', '7', 'SampleTime', '-1');
  delete_line ('pp/Sub', 'In1/1', 'Out1/1');
  add_line ('pp/Sub', 'In1/1', 'Delay/1'); add_line ('pp/Sub', 'Delay/1', 'Out1/1');
  add_block ('simulink/Sinks/Out1', 'pp/Sub/Out2', 'InitialOutput', '-5', 'OutputWhenDisabled', 'Reset');
  add_line ('pp/Sub', 'In1/1', 'Out2/1');
  add_block ('simulink/Sinks/Out1', 'pp/Y1'); add_block ('simulink/Sinks/Out1', 'pp/Y2');
  add_line ('pp', 'On/1', 'Gate/1'); add_line ('pp', 'Off/1', 'Gate/2');
  add_line ('pp', 'Clock/1', 'Sub/1'); add_line ('pp', 'Gate/1', 'Sub/Enable');
  add_line ('pp', 'Sub/1', 'Y1/1'); add_line ('pp', 'Sub/2', 'Y2/1');
  set_param ('pp', 'Solver', 'ode4', 'StopTime', '5', 'FixedStep', '1');
  % Simulink's names and recorded defaults; 'Reset' is stored as 'reset'.
  assert (get_param ('pp/Sub/Out1', 'OutputWhenDisabled'), 'held');
  assert (get_param ('pp/Sub/Out1', 'InitialOutput'), '[]');
  assert (get_param ('pp/Sub/Out2', 'OutputWhenDisabled'), 'reset');
  assert (get_param ('pp/Sub/Enable', 'StatesWhenEnabling'), 'held');
  out = sim ('pp');
  assert (out.yout, [0 -5; 7 1; 1 2; 1 -5; 1 -5; 1 -5]);
  execution = ob_simulink ('get_model', 'pp').blocks(5).value.execution;
  assert (execution.outputs, {'held', 'reset'});
  assert (execution.initial_outputs, {0, -5});
  % InitialOutput is evaluated at sim time, like Simulink, so a variable
  % may be defined after set_param.
  evalin ('base', 'clear ob_api_initial_output');
  set_param ('pp/Sub/Out1', 'InitialOutput', 'ob_api_initial_output');
  assert_error (@() sim ('pp'), 'InitialOutput');
  folder = tempname (); mkdir (folder);
  save_system ('pp', fullfile (folder, 'pending_initial.mat'));   % saving does not evaluate it
  set_param ('pp', 'Dirty', 'on');
  confirm_recursive_rmdir (false, 'local'); rmdir (folder, 's');
  assignin ('base', 'ob_api_initial_output', -9);
  set_param ('pp/Sub/Enable', 'StatesWhenEnabling', 'RESET');
  assert (get_param ('pp/Sub/Enable', 'StatesWhenEnabling'), 'reset');
  out = sim ('pp');
  assert (out.yout(:, 1), [-9; 7; 1; 1; 1; 1]);
  assert_error (@() set_param ('pp/Sub/Out2', 'OutputWhenDisabled', 'bogus'), ...
                'Invalid setting in Outport block ''Out2'' for parameter ''OutputWhenDisabled''');
  assert_error (@() set_param ('pp/Sub/Enable', 'StatesWhenEnabling', 'bogus'), ...
                'Invalid setting in EnablePort block ''Enable'' for parameter ''StatesWhenEnabling''');
  assert (get_param ('pp/Sub/Out2', 'OutputWhenDisabled'), 'reset');
  % A scalar InitialOutput widens to a vector port (Simulink).
  set_param ('pp/Sub/Out2', 'InitialOutput', '-4');
  add_block ('simulink/Math Operations/Gain', 'pp/Spread', 'Gain', '[1 2]');
  delete_line ('pp', 'Clock/1', 'Sub/1');
  add_line ('pp', 'Clock/1', 'Spread/1'); add_line ('pp', 'Spread/1', 'Sub/1');
  set_param ('pp/Sub/Delay', 'InitialCondition', '[7 8]');
  out = sim ('pp');
  assert (out.yout, [-9 -9 -4 -4; 7 8 1 2; 1 2 2 4; 1 2 -4 -4; 1 2 -4 -4; 1 2 -4 -4]);
  % Ports reorder with their parameters; save/load keeps everything,
  % including the Enable block's StatesWhenEnabling.
  set_param ('pp/Sub/Out2', 'Port', '1');
  execution = ob_simulink ('get_model', 'pp').blocks(5).value.execution;
  assert (execution.outputs, {'reset', 'held'});
  folder = tempname (); mkdir (folder);
  file = fullfile (folder, 'saved_ports.mat');
  save_system ('pp', file);
  load_system (file);
  assert (get_param ('saved_ports/Sub/Out2', 'Port'), '1');
  assert (get_param ('saved_ports/Sub/Out2', 'OutputWhenDisabled'), 'reset');
  assert (get_param ('saved_ports/Sub/Out2', 'InitialOutput'), '-4');
  assert (get_param ('saved_ports/Sub/Out1', 'InitialOutput'), 'ob_api_initial_output');
  assert (get_param ('saved_ports/Sub/Enable', 'StatesWhenEnabling'), 'reset');
  saved = sim ('saved_ports'); current = sim ('pp');
  assert (saved.yout, current.yout);
  bdclose ('saved_ports');
  confirm_recursive_rmdir (false, 'local'); rmdir (folder, 's');
  % Native Outports (no add_block metadata) show their execution's values.
  model = ob_conditional_example ();
  model.blocks(3).value.execution.outputs = 'reset';
  folder = tempname (); mkdir (folder);
  file = fullfile (folder, 'native_ports.mat');
  ob_save_model (file, model, [0 6 1]);
  load_system (file);
  assert (get_param ('native_ports/Conditional delay/Out1', 'OutputWhenDisabled'), 'reset');
  assert (get_param ('native_ports/Conditional delay/Out1', 'InitialOutput'), '-1');
  assert (get_param ('native_ports/Conditional delay/Enable', 'StatesWhenEnabling'), 'held');
  bdclose ('native_ports');
  confirm_recursive_rmdir (false, 'local'); rmdir (folder, 's');
  % sim expands a scalar InitialOutput to its port's width before the run,
  % so a subsystem first evaluated after the start ([0.5 0.25]) still logs
  % [-4 -4] from t = 0.
  model = ob_scalar_initial_example ('offset');
  model.blocks(5).type = 'Outport'; model.blocks(5).value = 1;
  folder = tempname (); mkdir (folder);
  file = fullfile (folder, 'offset_shape.mat');
  ob_save_model (file, model, [0 2 .25]);
  load_system (file);
  out = sim ('offset_shape');
  assert (out.yout, [repmat([-4 -4], 3, 1); repmat([2.25 4.5], 6, 1)]);
  bdclose ('offset_shape');
  confirm_recursive_rmdir (false, 'local'); rmdir (folder, 's');
  % A Triggered Subsystem keeps its outputs held whatever OutputWhenDisabled
  % says (recorded: triggered_reset_port), so the setting is accepted and
  % ignored; Enable blocks own the states policy.
  new_system ('tp');
  add_block ('simulink/Ports & Subsystems/Triggered Subsystem', 'tp/Sub');
  set_param ('tp/Sub/Out1', 'OutputWhenDisabled', 'reset', 'InitialOutput', '-9');
  add_block ('simulink/Sources/Clock', 'tp/Clock'); add_block ('simulink/Sources/Step', 'tp/Edge');
  add_block ('simulink/Sinks/Out1', 'tp/Y');
  add_line ('tp', 'Clock/1', 'Sub/1'); add_line ('tp', 'Edge/1', 'Sub/Trigger'); add_line ('tp', 'Sub/1', 'Y/1');
  execution = ob_simulink ('get_model', 'tp').blocks(1).value.execution;
  assert (execution.outputs, 'held'); assert (execution.initial_outputs, {-9});
  assert (sim ('tp', 'Solver', 'ode4', 'StopTime', '3', 'FixedStep', '1').yout, [-9; 1; 1; 1]);
  bdclose ('tp');
  cases += 5;

  % SimulationMode: 'normal' (default) interprets; 'accelerator' and
  % 'rapid-accelerator' run the compiled C accelerator, falling back to
  % interpretation with a note when the model is outside its subset.
  assert (get_param ('pp', 'SimulationMode'), 'normal');
  set_param ('pp', 'SimulationMode', 'Accelerator');
  assert (get_param ('pp', 'SimulationMode'), 'accelerator');
  [unused, unused, options] = ob_simulink ('get_model', 'pp');
  assert (options.accelerate, 'auto');
  assert_error (@() set_param ('pp', 'SimulationMode', 'Rapid Accelerator'), ...
                'Invalid setting for block_diagram parameter ''SimulationMode''');
  assert_error (@() set_param ('pp', 'SimulationMode', 'external'), 'not supported');
  assert (get_param ('pp', 'SimulationMode'), 'accelerator');
  normal = sim ('pp', 'SimulationMode', 'normal');
  assert (normal.SimulationMetadata.ModelInfo.SimulationMode, 'normal');
  assert (! normal.SimulationMetadata.Accelerated);
  ode15s = sim ('pp', 'Solver', 'ode15s');      % outside the accelerator's subset
  assert (ode15s.SimulationMetadata.ModelInfo.SimulationMode, 'accelerator');
  assert (! ode15s.SimulationMetadata.Accelerated);
  note = ode15s.SimulationMetadata.ExecutionInfo.WarningDiagnostics(1).Diagnostic.message;
  assert (! isempty (strfind (note, 'ran in normal (interpreted) mode')));
  assert (ode15s.yout, normal.yout, 1e-12);
  if (! isempty (file_in_path (getenv ('PATH'), 'gcc.exe')) || ! isempty (file_in_path (getenv ('PATH'), 'gcc')))
    fast = sim ('pp', 'SimulationMode', 'rapid-accelerator');
    assert (fast.SimulationMetadata.Accelerated);
    assert (isempty (fast.SimulationMetadata.ExecutionInfo.WarningDiagnostics));
    assert (fast.yout, normal.yout, 1e-12);
  endif
  % save_system keeps the accelerator setting (rapid-accelerator comes back
  % as accelerator).
  folder = tempname (); mkdir (folder);
  save_system ('pp', fullfile (folder, 'saved_mode.mat'));
  load_system (fullfile (folder, 'saved_mode.mat'));
  assert (get_param ('saved_mode', 'SimulationMode'), 'accelerator');
  bdclose ('saved_mode'); bdclose ('pp');
  confirm_recursive_rmdir (false, 'local'); rmdir (folder, 's');
  evalin ('base', 'clear ob_api_initial_output');
  cases += 2;

  % Deleting an Inport renumbers ports and the parent's wires.
  new_system ('ports');
  add_block ('simulink/Ports & Subsystems/Subsystem', 'ports/Sub');
  add_block ('simulink/Sources/In1', 'ports/Sub/In2');
  add_block ('simulink/Math Operations/Add', 'ports/Sub/Add');
  delete_line ('ports/Sub', 'In1/1', 'Out1/1');
  add_line ('ports/Sub', 'In1/1', 'Add/1'); add_line ('ports/Sub', 'In2/1', 'Add/2');
  add_line ('ports/Sub', 'Add/1', 'Out1/1');
  assert (strcmp (get_param ('ports/Sub/In2', 'Port'), '2'));
  add_block ('simulink/Sources/Constant', 'ports/A', 'Value', '1');
  add_block ('simulink/Sources/Constant', 'ports/B', 'Value', '10');
  add_line ('ports', 'A/1', 'Sub/1'); add_line ('ports', 'B/1', 'Sub/2');
  add_block ('simulink/Sinks/Out1', 'ports/Out1'); add_line ('ports', 'Sub/1', 'Out1/1');
  out = sim ('ports', [0 1]);
  assert (out.yout(end), 11);
  delete_block ('ports/Sub/In1');
  assert (strcmp (get_param ('ports/Sub/In2', 'Port'), '1'));
  model = ob_simulink ('get_model', 'ports');
  assert (find_line (model, 1, 1)(1) == find (strcmp ({model.blocks.name}, 'B')));
  assert (isempty (find_line (model, 1, 2)));
  cases += 1;

  % Setting an In1/Out1 Port renumbers the others, as Simulink does; the
  % parent's lines stay on their port numbers.
  new_system ('swap');
  add_block ('simulink/Ports & Subsystems/Subsystem', 'swap/Sub');
  add_block ('simulink/Sources/In1', 'swap/Sub/In2');
  add_block ('simulink/Sources/In1', 'swap/Sub/In3');
  add_block ('simulink/Math Operations/Gain', 'swap/Sub/Ten', 'Gain', '10');
  add_block ('simulink/Math Operations/Gain', 'swap/Sub/Hundred', 'Gain', '100');
  add_block ('simulink/Math Operations/Sum', 'swap/Sub/S1');
  add_block ('simulink/Math Operations/Sum', 'swap/Sub/S2');
  delete_line ('swap/Sub', 'In1/1', 'Out1/1');
  add_line ('swap/Sub', 'In2/1', 'Ten/1'); add_line ('swap/Sub', 'In3/1', 'Hundred/1');
  add_line ('swap/Sub', 'In1/1', 'S1/1'); add_line ('swap/Sub', 'Ten/1', 'S1/2');
  add_line ('swap/Sub', 'S1/1', 'S2/1'); add_line ('swap/Sub', 'Hundred/1', 'S2/2');
  add_line ('swap/Sub', 'S2/1', 'Out1/1');
  for k = 1:3
    add_block ('simulink/Sources/Constant', sprintf ('swap/C%d', k), 'Value', num2str (k));
    add_line ('swap', sprintf ('C%d/1', k), sprintf ('Sub/%d', k));
  endfor
  add_block ('simulink/Sinks/Out1', 'swap/Out1'); add_line ('swap', 'Sub/1', 'Out1/1');
  out = sim ('swap', [0 1]);
  assert (out.yout(end), 1 + 20 + 300);
  set_param ('swap/Sub/In3', 'Port', '1');
  assert (cellfun (@(p) get_param (p, 'Port'), {'swap/Sub/In1', 'swap/Sub/In2', 'swap/Sub/In3'}, ...
                   'UniformOutput', false), {'2', '3', '1'});
  out = sim ('swap', [0 1]);
  assert (out.yout(end), 2 + 30 + 100);         % C1 now feeds In3, C2 In1, C3 In2
  set_param ('swap/Sub/In3', 'Port', '3');
  assert (cellfun (@(p) get_param (p, 'Port'), {'swap/Sub/In1', 'swap/Sub/In2', 'swap/Sub/In3'}, ...
                   'UniformOutput', false), {'1', '2', '3'});
  assert_error (@() set_param ('swap/Sub/In3', 'Port', '4'), 'from 1 to 3');
  assert (strcmp (get_param ('swap/Sub/In3', 'Port'), '3'));
  cases += 2;

  % Persistence roundtrip, dirty tracking and a duplicate-name policy.
  folder = tempname (); mkdir (folder);
  file = fullfile (folder, 'tf_model.mat');
  assert (strcmp (get_param ('tf', 'Dirty'), 'on'));
  assert_error (@() close_system ('tf'), 'has been changed');
  assert (bdIsLoaded ('tf'));
  save_system ('tf', file);
  assert (strcmp (get_param ('tf', 'Dirty'), 'off'));
  reference = sim ('tf');                       % simulating does not modify
  assert (strcmp (get_param ('tf', 'Dirty'), 'off'));
  close_system ('tf');
  assert (! bdIsLoaded ('tf'));
  load_system (file);
  assert (bdIsLoaded ('tf_model'));
  assert (strcmp (get_param ('tf_model', 'Dirty'), 'off'));
  loaded = sim ('tf_model');
  assert (loaded.yout, reference.yout, 1e-12);
  assert (strcmp (get_param ('tf_model/Plant', 'Numerator'), 'ob_api_gain'));
  assert_error (@() add_block ('simulink/Math Operations/Gain', 'tf_model/Plant'), 'already exists');
  assert (strcmp (get_param ('tf_model', 'Dirty'), 'off'));   % failed commands change nothing
  path = add_block ('simulink/Math Operations/Gain', 'tf_model/Plant', 'MakeNameUnique', 'on');
  assert (strcmp (path, 'tf_model/Plant1'));
  assert (strcmp (get_param ('tf_model', 'Dirty'), 'on'));
  close_system ('tf_model/Plant');              % a block path leaves the system loaded
  assert (bdIsLoaded ('tf_model'));
  set_param ('tf_model', 'Dirty', 'off');
  set_param ('tf_model', 'StopTime', '4');
  assert (strcmp (get_param ('tf_model', 'Dirty'), 'on'));
  close_system ('tf_model', 0);                 % discard
  assert (! bdIsLoaded ('tf_model'));
  load_system (file);
  assert (strcmp (get_param ('tf_model', 'StopTime'), '10'));
  delete_block ('tf_model/y');
  close_system ('tf_model', 1);                 % save, then close
  load_system (file);
  assert (! any (strcmp (find_system ('tf_model'), 'tf_model/y')));
  set_param ('tf_model', 'StopTime', '5');
  bdclose ('tf_model');                         % bdclose discards changes
  assert (! bdIsLoaded ('tf_model'));
  confirm_recursive_rmdir (false, 'local'); rmdir (folder, 's');
  cases += 3;

  % API-built models export to C with the existing generator, including the
  % structural Switch criteria and non-scalar Gain realizations.  The
  % ob_simulink_codegen_case model is compiled and compared with Octave by
  % the C export check (test_ob_codegen manifest, Test-Codegen.ps1).
  model = ob_simulink ('get_model', 'api');
  folder = tempname (); mkdir (folder);
  info = ob_codegen (model, fullfile (folder, 'api.c'), [0 1 0.1]);
  assert (exist (fullfile (folder, 'api.c'), 'file') == 2 && isstruct (info));
  entry = ob_simulink_codegen_case (folder);
  assert (entry.standalone && exist (fullfile (folder, entry.source), 'file') == 2);
  expected = dlmread (fullfile (folder, entry.expected));
  assert (rows (expected) == 41 && columns (expected) > 8);
  assert (bdIsLoaded ('api') && ! bdIsLoaded (entry.name));
  confirm_recursive_rmdir (false, 'local'); rmdir (folder, 's');
  build_switch_gain_model ('swg');
  cases += 2;

  % Switch criteria: the Simulink library defaults to 'u2 > Threshold',
  % built-in/Switch to 'u2 >= Threshold'.
  out = sim ('swg');
  % Out1..Out3: Signal Routing Switch, built-in Switch and 'u2 ~= 0', with
  % u2 = t - 1 (exactly 0 at t = 1) against Threshold 0.
  t = out.tout; u2 = t - 1;
  assert (out.yout(:, 1), ifelse_vector (u2 > 0, 1, 3));
  assert (out.yout(:, 2), ifelse_vector (u2 >= 0, 1, 3));
  assert (out.yout(:, 3), ifelse_vector (u2 != 0, 1, 3));
  assert (get_param ('swg/Sw', 'Criteria'), 'u2 > Threshold');
  assert (get_param ('swg/SwB', 'Criteria'), 'u2 >= Threshold');
  assert (get_param ('swg/Sw', 'Ports'), [3 1 0 0 0 0 0 0 0 0]);
  % Gain Multiplication modes (Out4 and Out5 are two columns each).
  assert (out.yout(end, 4:5), [2 6], 1e-15);              % [2 3] .* [1 2]
  assert (out.yout(end, 6:7), [1 2] * [1 2; 3 4], 1e-15);  % Matrix(u*K)
  assert_error (@() set_param ('swg/Sw', 'Criteria', 'u2 < Threshold'), 'Criteria');
  assert_error (@() set_param ('swg/Kv', 'Multiplication', 'Element-wise(u.*K)'), 'Multiplication');
  new_system ('gm');
  add_block ('simulink/Sources/Constant', 'gm/U', 'Value', '[1 2]');
  add_block ('simulink/Math Operations/Gain', 'gm/K', 'Gain', '[1 2; 3 4]', 'Multiplication', 'Matrix(K*u) (u vector)');
  add_block ('simulink/Sinks/Out1', 'gm/Out1');
  add_line ('gm', 'U/1', 'K/1'); add_line ('gm', 'K/1', 'Out1/1');
  out = sim ('gm', [0 1]);
  assert (out.yout(end, :), [5 11], 1e-15);                % K * u(:)
  set_param ('gm/K', 'Multiplication', 'Matrix(K*u)');
  assert_error (@() sim ('gm', [0 1]), 'nonconformant');   % a row u cannot be K*u
  cases += 3;

  % Linear and controller library blocks match their direct builders.
  new_system ('pid');
  add_block ('simulink/Sources/Step', 'pid/Ref');
  add_block ('simulink/Math Operations/Subtract', 'pid/Err');
  add_block ('simulink/Continuous/PID Controller', 'pid/PID', 'P', '2', 'I', '1', 'D', '0.1', 'N', '50');
  add_block ('simulink/Continuous/State-Space', 'pid/Plant', 'A', '[0 1; -2 -3]', 'B', '[0; 1]', ...
             'C', '[1 0]', 'D', '0', 'InitialCondition', '0');
  add_block ('simulink/Sinks/Out1', 'pid/y');
  add_line ('pid', 'Ref/1', 'Err/1'); add_line ('pid', 'Plant/1', 'Err/2');
  add_line ('pid', 'Err/1', 'PID/1'); add_line ('pid', 'PID/1', 'Plant/1'); add_line ('pid', 'Plant/1', 'y/1');
  out = sim ('pid', 'StopTime', '12', 'Solver', 'ode4', 'FixedStep', '0.02');
  direct = direct_pid_loop ();
  assert (out.yout, direct, 1e-12);
  assert (abs (out.yout(end) - 1) < 0.02);   % integral action removes the offset
  assert (get_param ('pid/PID', 'BlockType'), 'SubSystem');
  assert (get_param ('pid/PID', 'MaskType'), 'PID 1dof');
  assert (get_param ('pid/PID', 'Mask'), 'on');
  cases += 2;

  % Discrete and nonlinear library blocks.
  build_mix ();
  out = sim ('mix', 'StopTime', '1', 'Solver', 'ode4', 'FixedStep', '0.1');
  t = out.tout; ramp = 1 + 2 * max (0, t - 0.5);
  assert (out.yout(:, 1), min (max (ramp, 0), 2), 1e-12);
  assert (out.yout(:, 2), exp (min (max (ramp, 0), 2)), 1e-12);
  held = 5 * ones (size (t));
  for k = 1:numel (t)
    hit = floor (t(k) / 0.2 + 1e-9) * 0.2;
    if (hit >= 0.2), held(k) = 1 + 2 * max (0, hit - 0.2 - 0.5); endif
  endfor
  assert (out.yout(:, 3), held, 1e-12);
  assert (strcmp (get_param ('mix/Exp', 'Name'), 'Exp'));
  set_param ('mix/Exp', 'Name', 'Exponential');
  assert (strcmp (get_param ('mix/Exponential', 'Expr'), 'exp(u)'));
  % Ramp is a masked subsystem with Simulink's lowercase parameter names;
  % names stay case-insensitive.
  assert (get_param ('mix/Ramp', 'BlockType'), 'SubSystem');
  assert (get_param ('mix/Ramp', 'MaskType'), 'Ramp');
  assert (fieldnames (get_param ('mix/Ramp', 'DialogParameters')), {'slope'; 'start'; 'InitialOutput'});
  assert (get_param ('mix/Ramp', 'Slope'), '2');
  cases += 4;

  % FixedStep 'auto': the fundamental sample time without continuous
  % states, (stop - start) / 50 with them.
  set_param ('mix', 'Solver', 'ode4', 'StopTime', '1');
  out = sim ('mix');
  assert (out.tout', 0:0.2:1, 1e-15);
  [~, config] = ob_simulink ('get_model', 'mix');
  assert (config(3), 0.2);
  set_param ('mix/Z', 'SampleTime', '[0.3 0.1]');
  [~, config] = ob_simulink ('get_model', 'mix');
  assert (config(3), 0.1, 1e-15);               % GCD of 0.3 and its offset 0.1
  add_block ('simulink/Discrete/Discrete Transfer Fcn', 'mix/DTF', 'SampleTime', '0.25');
  [~, config] = ob_simulink ('get_model', 'mix');
  assert (config(3), 0.05, 1e-15);              % rates inside library subsystems count
  [~, config] = ob_simulink ('get_model', 'lim');
  assert (config(3), 10 / 50);                   % continuous: span / 50
  set_param ('lim', 'MaxStep', '0.1');
  [~, config] = ob_simulink ('get_model', 'lim');
  assert (config(3), 0.1);
  % The Rate Limiter's Octave-only OctaveSampleTime is not a model rate
  % (Simulink's Rate Limiter is inherited), so 'auto' falls back to
  % span / 50; the limiter still runs at its own 0.1 period.
  new_system ('rla');
  add_block ('simulink/Sources/Step', 'rla/Step');
  add_block ('simulink/Discontinuities/Rate Limiter', 'rla/RL');
  add_block ('simulink/Sinks/Out1', 'rla/Out1');
  add_line ('rla', 'Step/1', 'RL/1'); add_line ('rla', 'RL/1', 'Out1/1');
  set_param ('rla', 'Solver', 'ode4');
  out = sim ('rla');
  assert (out.tout', 0:0.2:10, 1e-12);
  assert (out.yout(out.tout > 0.9 & out.tout < 1.5)', [0.1 0.3 0.5], 1e-12);
  close_system ('rla', 0);
  cases += 3;

  % Library paths must exist in Simulink R2026b; built-in/<BlockType> works.
  new_system ('lib');
  add_block ('built-in/SubSystem', 'lib/Empty');
  assert (get_param ('lib/Empty', 'Ports'), zeros (1, 10));
  add_block ('simulink/Ports & Subsystems/Subsystem', 'lib/Sub');
  add_block ('built-in/EnablePort', 'lib/Sub/Enable');
  assert (get_param ('lib/Sub', 'Ports'), [1 1 1 0 0 0 0 0 0 0]);
  delete_block ('lib/Sub/Enable');
  add_block ('built-in/ResetPort', 'lib/Sub/Reset', 'ResetTriggerType', 'either');
  assert (get_param ('lib/Sub', 'Ports'), [1 1 0 0 0 0 0 0 1 0]);
  delete_block ('lib/Sub/Reset');
  add_block ('simulink/Ports & Subsystems/Resettable Subsystem/Reset', 'lib/Sub/Reset');
  assert (get_param ('lib/Sub/Reset', 'BlockType'), 'ResetPort');
  assert_error (@() add_block ('simulink/Ports & Subsystems/Reset', 'lib/R'), 'There is no block named');
  assert_error (@() add_block ('simulink/Math Operations/sin', 'lib/S'), 'There is no block named');
  assert_error (@() add_block ('built-in/Ramp', 'lib/R'), 'There is no block named');
  assert_error (@() add_block ('built-in/PIDController', 'lib/P'), 'There is no block named');
  % Newlines inside Simulink library names compare as spaces.
  add_block (sprintf ('simulink/Discrete/Discrete-Time\nIntegrator'), 'lib/DTI');
  assert (get_param ('lib/DTI', 'BlockType'), 'DiscreteIntegrator');
  types = {'Saturate', 'DeadZone', 'UnitDelay', 'DiscreteIntegrator', 'TransportDelay', 'TransferFcn', ...
           'StateSpace', 'ZeroPole', 'DiscreteTransferFcn', 'DiscreteStateSpace', 'Math', 'Trigonometry', ...
           'MATLABFcn', 'ToWorkspace', 'RateTransition', 'Lookup_n-D', 'RateLimiter', 'Display', ...
           'Terminator', 'Switch', 'Relay', 'Step', 'Integrator', 'Fcn', 'Abs', 'Sqrt', 'Product', ...
           'Constant', 'Clock', 'Scope', 'Sum', 'Gain', 'Sin', 'Ground', 'Inport', 'Outport'};
  for k = 1:numel (types)
    path = add_block (['built-in/' types{k}], sprintf ('lib/B%d', k));
    assert (get_param (path, 'BlockType'), types{k});
  endfor
  assert (get_param ('lib/B31', 'Inputs'), '++');             % built-in/Sum
  add_block ('simulink/Math Operations/Sum', 'lib/LibSum');
  assert (get_param ('lib/LibSum', 'Inputs'), '|++');
  assert (get_param ('lib/LibSum', 'Ports'), [2 1 0 0 0 0 0 0 0 0]);
  add_block ('simulink/Continuous/Integrator Limited', 'lib/IL');
  assert ({get_param('lib/IL', 'LimitOutput'), get_param('lib/IL', 'UpperSaturationLimit')}, {'on', '1'});
  cases += 4;

  % Parameter names and defaults follow Simulink R2026b.
  add_block ('simulink/Sources/Step', 'lib/Step', 'InitialValue', '2', 'After', '3');
  assert (fieldnames (get_param ('lib/Step', 'DialogParameters')), ...
          {'Time'; 'InitialValue'; 'FinalValue'; 'SampleTime'});
  assert ({get_param('lib/Step', 'Before'), get_param('lib/Step', 'InitialValue')}, {'2', '2'});
  assert ({get_param('lib/Step', 'After'), get_param('lib/Step', 'FinalValue')}, {'3', '3'});
  set_param ('lib/Step', 'Before', '4');
  assert (get_param ('lib/Step', 'InitialValue'), '4');
  % Step SampleTime: 0 (Simulink's default) or -1 both give the native
  % continuous-time Step; a discrete period is rejected.
  assert (get_param ('lib/Step', 'SampleTime'), '0');
  set_param ('lib/Step', 'SampleTime', '-1');
  assert (get_param ('lib/Step', 'SampleTime'), '-1');
  assert_error (@() set_param ('lib/Step', 'SampleTime', '0.1'), 'discrete Step is not supported');
  assert (get_param ('lib/Step', 'SampleTime'), '-1');
  assert_error (@() add_block ('simulink/Sources/Step', 'lib/Step2', 'SampleTime', '0.5'), 'SampleTime');
  assert (! any (strcmp (find_system ('lib'), 'lib/Step2')));
  add_block ('simulink/Discontinuities/Rate Limiter', 'lib/RL');
  assert (get_param ('lib/RL', 'SampleTimeMode'), 'inherited');
  assert (get_param ('lib/RL', 'OctaveSampleTime'), '0.1');
  assert_error (@() set_param ('lib/RL', 'SampleTime', '0.2'), 'does not have a parameter named ''SampleTime''');
  assert_error (@() set_param ('lib/RL', 'SampleTimeMode', 'sometimes'), 'SampleTimeMode');
  add_block ('simulink/Discontinuities/Relay', 'lib/Relay');
  assert (get_param ('lib/Relay', 'SampleTime'), '-1');
  add_block ('simulink/Discrete/Discrete State-Space', 'lib/DSS');
  add_block ('simulink/Discrete/Discrete Transfer Fcn', 'lib/DTF');
  assert ({get_param('lib/DSS', 'SampleTime'), get_param('lib/DTF', 'SampleTime')}, {'-1', '-1'});
  add_block ('simulink/Discrete/Discrete PID Controller', 'lib/DPID');
  assert (get_param ('lib/DPID', 'SampleTime'), '1');     % the builder needs an explicit period
  assert_error (@() set_param ('lib/DPID', 'SampleTime', '-1'), 'explicit SampleTime');
  add_block ('simulink/User-Defined Functions/Fcn', 'lib/Fcn');
  assert (get_param ('lib/Fcn', 'Expr'), 'sin(u)');
  add_block ('simulink/Math Operations/Gain', 'lib/Gain');
  assert (get_param ('lib/Gain', 'Multiplication'), 'Element-wise(K.*u)');
  cases += 2;

  % Inherited-rate defaults simulate: Relay and Discrete Transfer Fcn.
  new_system ('inh');
  add_block ('simulink/Sources/Step', 'inh/Step');
  add_block ('simulink/Discrete/Discrete Transfer Fcn', 'inh/T');
  add_block ('simulink/Discontinuities/Relay', 'inh/R');
  add_block ('simulink/Sinks/Out1', 'inh/Out1'); add_block ('simulink/Sinks/Out1', 'inh/Out2');
  add_line ('inh', 'Step/1', 'T/1'); add_line ('inh', 'T/1', 'Out1/1');
  add_line ('inh', 'Step/1', 'R/1'); add_line ('inh', 'R/1', 'Out2/1');
  out = sim ('inh', 'StopTime', '1.5', 'Solver', 'ode4', 'FixedStep', '0.1');
  t = out.tout;
  % 1/(z + 0.5) at the 0.1 s base rate: y[k] = u[k-1] - 0.5 y[k-1].
  y = zeros (size (t)); u = double (t >= 1);
  for k = 2:numel (t), y(k) = u(k-1) - 0.5 * y(k-1); endfor
  assert (out.yout(:, 1), y, 1e-12);
  assert (out.yout(:, 2), u, 1e-12);
  cases += 1;

  % 1-D Lookup Table extrapolates linearly by default; the legacy Lookup
  % Table block keeps its own BlockType and parameter names.
  new_system ('lut');
  add_block ('simulink/Sources/Clock', 'lut/Clock');
  add_block ('simulink/Math Operations/Gain', 'lut/K', 'Gain', '2');
  add_block ('simulink/Lookup Tables/1-D Lookup Table', 'lut/LUT');
  add_block ('simulink/Lookup Tables/Lookup Table', 'lut/Old', 'LookUpMeth', 'Interpolation-Use End Values');
  add_block ('simulink/Sinks/Out1', 'lut/Out1'); add_block ('simulink/Sinks/Out1', 'lut/Out2');
  add_line ('lut', 'Clock/1', 'K/1'); add_line ('lut', 'K/1', 'LUT/1'); add_line ('lut', 'LUT/1', 'Out1/1');
  add_line ('lut', 'K/1', 'Old/1'); add_line ('lut', 'Old/1', 'Out2/1');
  out = sim ('lut', 'StopTime', '5', 'Solver', 'ode4', 'FixedStep', '0.25');
  assert (out.yout(end, 1), tanh (5) + 5 * (tanh (5) - tanh (4)), 1e-12);
  assert (out.yout(end, 2), tanh (5), 1e-12);
  assert ({get_param('lut/LUT', 'ExtrapMethod'), get_param('lut/LUT', 'InterpMethod')}, ...
          {'Linear', 'Linear point-slope'});
  set_param ('lut/LUT', 'InterpMethod', 'Linear Lagrange');
  assert_error (@() set_param ('lut/LUT', 'InterpMethod', 'Flat'), 'InterpMethod');
  assert (get_param ('lut/Old', 'BlockType'), 'Lookup');
  assert (fieldnames (get_param ('lut/Old', 'DialogParameters')), {'InputValues'; 'Table'; 'LookUpMeth'});
  assert_error (@() set_param ('lut/Old', 'LookUpMeth', 'Use Input Below'), 'LookUpMeth');
  cases += 2;

  % Display and Terminator keep their BlockTypes and log nothing; Scope
  % logging into logsout is an Octave Blocks extension.
  new_system ('term');
  add_block ('simulink/Sources/Clock', 'term/Clock');
  add_block ('simulink/Sinks/Terminator', 'term/T');
  add_block ('simulink/Sinks/Display', 'term/D');
  add_block ('simulink/Sinks/Scope', 'term/Sc');
  add_line ('term', 'Clock/1', 'T/1'); add_line ('term', 'Clock/1', 'D/1'); add_line ('term', 'Clock/1', 'Sc/1');
  out = sim ('term', 'StopTime', '1', 'Solver', 'ode4', 'FixedStep', '0.5');
  assert ({get_param('term/T', 'BlockType'), get_param('term/D', 'BlockType')}, {'Terminator', 'Display'});
  assert (find_system ('term', 'BlockType', 'Terminator'), {'term/T'});
  assert (fieldnames (out.logsout), {'Sc'});
  assert (out.logsout.Sc.signals.values, [0; 0.5; 1]);
  assert (out.who, {'logsout'; 'tout'});
  assert (isempty (out.yout));
  cases += 2;

  % Solvers without an Octave Blocks implementation map to the nearest one.
  % Without continuous states, SolverInfo.Solver is Simulink's discrete
  % solver whatever was chosen (recorded R2026b).
  set_param ('term', 'Solver', 'ode113');
  out = sim ('term', 'StopTime', '1', 'FixedStep', '0.5');
  assert ({out.SimulationMetadata.Solver, out.SimulationMetadata.ModelInfo.SolverInfo.Solver}, ...
          {'ode45', 'VariableStepDiscrete'});
  set_param ('term', 'Solver', 'ode23s');
  [~, ~, options] = ob_simulink ('get_model', 'term');
  assert (options.solver, 'ode15s');
  for solver = {'VariableStepAuto', 'ode45'}
    set_param ('term', 'Solver', solver{1});
    out = sim ('term', 'StopTime', '1', 'FixedStep', '0.5');
    assert (out.SimulationMetadata.ModelInfo.SolverInfo.Solver, 'VariableStepDiscrete');
  endfor
  for solver = {'FixedStepAuto', 'ode4'}
    set_param ('term', 'Solver', solver{1});
    out = sim ('term', 'StopTime', '1', 'FixedStep', '0.5');
    assert (out.SimulationMetadata.ModelInfo.SolverInfo.Solver, 'FixedStepDiscrete');
  endfor
  % With a continuous state the chosen solver's Simulink name is kept.
  add_block ('simulink/Continuous/Integrator', 'term/Int');
  add_line ('term', 'Clock/1', 'Int/1');
  set_param ('term', 'Solver', 'ode113');
  out = sim ('term', 'StopTime', '1', 'FixedStep', '0.5');
  assert ({out.SimulationMetadata.Solver, out.SimulationMetadata.ModelInfo.SolverInfo.Solver}, {'ode45', 'ode113'});
  cases += 2;

  % Models saved before the Simulink R2026b names still load and behave
  % as before (Step Before/After, Ramp Slope/Start, Rate Limiter
  % SampleTime, matrix Gains, no Kind/MaskType metadata).
  new_system ('old');
  add_block ('simulink/Sources/Step', 'old/S', 'Time', '0.5', 'FinalValue', '2');
  add_block ('simulink/Sources/Ramp', 'old/R', 'Slope', '3');
  add_block ('simulink/Sources/Constant', 'old/C', 'Value', '[1; 2]');
  add_block ('simulink/Math Operations/Gain', 'old/K', 'Gain', '[1 2; 3 4]', 'Multiplication', 'Matrix(K*u)');
  add_block ('simulink/Discontinuities/Rate Limiter', 'old/L', 'OctaveSampleTime', '0.25');
  for k = 1:3, add_block ('simulink/Sinks/Out1', sprintf ('old/Out%d', k)); endfor
  add_line ('old', 'C/1', 'K/1'); add_line ('old', 'K/1', 'Out1/1');
  add_line ('old', 'S/1', 'L/1'); add_line ('old', 'L/1', 'Out2/1'); add_line ('old', 'R/1', 'Out3/1');
  set_param ('old', 'Solver', 'ode4', 'StopTime', '1', 'FixedStep', '0.25');
  [model, config, options] = ob_simulink ('get_model', 'old');
  legacy = {'S', 'Step', struct('Time', '0.5', 'Before', '0', 'After', '2'); ...
            'R', 'Ramp', struct('Slope', '3', 'Start', '0', 'InitialOutput', '0'); ...
            'K', 'Gain', struct('Gain', '[1 2; 3 4]'); ...
            'L', 'RateLimiter', struct('RisingSlewLimit', '1', 'FallingSlewLimit', '-1', ...
                                       'SampleTime', '0.25', 'InitialCondition', '0')};
  for k = 1:rows (legacy)
    id = find (strcmp ({model.blocks.name}, legacy{k, 1}));
    model.blocks(id).simulink = struct ('BlockType', legacy{k, 2}, 'Params', legacy{k, 3});
  endfor
  folder = tempname (); mkdir (folder);
  file = fullfile (folder, 'old_model.mat');
  ob_save_model (file, model, config, options);
  load_system (file);
  assert ({get_param('old_model/S', 'InitialValue'), get_param('old_model/S', 'After'), ...
           get_param('old_model/S', 'SampleTime')}, {'0', '2', '0'});
  assert ({get_param('old_model/R', 'BlockType'), get_param('old_model/R', 'MaskType'), ...
           get_param('old_model/R', 'slope')}, {'SubSystem', 'Ramp', '3'});
  assert ({get_param('old_model/K', 'Multiplication'), get_param('old_model/L', 'OctaveSampleTime'), ...
           get_param('old_model/L', 'SampleTimeMode')}, {'Matrix(K*u)', '0.25', 'inherited'});
  out = sim ('old_model');
  reference = sim ('old');
  assert (out.yout, reference.yout, 1e-12);
  assert (out.yout(end, 1:2), [5 11], 1e-12);       % K*u, not the new element-wise default
  bdclose ('old_model');
  confirm_recursive_rmdir (false, 'local'); rmdir (folder, 's');
  cases += 1;

  % Explicit failures leave systems unchanged.
  assert_error (@() add_block ('simulink/Sources/Signal Builder', 'mix/S'), 'not supported');
  assert_error (@() set_param ('mix/Sat', 'Gain', '3'), 'does not have a parameter named ''Gain''');
  assert_error (@() get_param ('mix/Sat', 'NoSuchParam'), 'does not have a parameter named');
  assert_error (@() set_param ('mix', 'Solver', 'ode1'), 'not supported');
  assert (strcmp (get_param ('mix', 'Solver'), 'ode4'));
  set_param ('mix/Z', 'SampleTime', '0.2');
  assert_error (@() set_param ('mix/Z', 'SampleTime', '[0.2 0.5]'), 'offset');
  assert (strcmp (get_param ('mix/Z', 'SampleTime'), '0.2'));
  assert_error (@() add_line ('mix', 'Ramp/1', 'Out1/1'), 'already connected');
  assert_error (@() sim ('missing'), 'not loaded');
  assert_error (@() load_system ('model.slx'), '.slx');
  assert_error (@() add_block ('simulink/Math Operations/Sum', 'mix/S', 'Inputs', '+*'), 'Inputs');
  assert_error (@() add_block ('simulink/Ports & Subsystems/Enable', 'mix/Enable'), 'inside a subsystem');
  assert (! any (strcmp (find_system ('mix'), 'mix/S')));
  cases += 1;

  bdclose ('all');
  assert (isempty (ob_simulink ('list')));
  printf ('Simulink-style command API: %d cases passed\n', cases);
endfunction

function build_mix ()
  new_system ('mix');
  add_block ('simulink/Sources/Ramp', 'mix/Ramp', 'Slope', '2', 'Start', '0.5', 'InitialOutput', '1');
  add_block ('simulink/Discontinuities/Saturation', 'mix/Sat', 'UpperLimit', '2', 'LowerLimit', '0');
  add_block ('simulink/User-Defined Functions/Fcn', 'mix/Exp', 'Expr', 'exp(u)');
  add_block ('simulink/Discrete/Unit Delay', 'mix/Z', 'SampleTime', '0.2', 'InitialCondition', '5');
  add_block ('simulink/Sinks/Out1', 'mix/Out1'); add_block ('simulink/Sinks/Out1', 'mix/Out2');
  add_block ('simulink/Sinks/Out1', 'mix/Out3');
  add_line ('mix', 'Ramp/1', 'Sat/1'); add_line ('mix', 'Sat/1', 'Out1/1');
  add_line ('mix', 'Sat/1', 'Exp/1'); add_line ('mix', 'Exp/1', 'Out2/1');
  add_line ('mix', 'Ramp/1', 'Z/1'); add_line ('mix', 'Z/1', 'Out3/1');
endfunction

function build_switch_gain_model (name)
  % Out1..Out3: Switch with library, built-in and 'u2 ~= 0' criteria on
  % u2 = t - 1; Out4: element-wise vector Gain; Out5: Matrix(u*K).
  new_system (name);
  add_block ('simulink/Sources/Constant', [name '/One'], 'Value', '1');
  add_block ('simulink/Sources/Constant', [name '/Three'], 'Value', '3');
  add_block ('simulink/Sources/Ramp', [name '/U2'], 'InitialOutput', '-1');
  add_block ('simulink/Signal Routing/Switch', [name '/Sw']);
  add_block ('built-in/Switch', [name '/SwB']);
  add_block ('simulink/Commonly Used Blocks/Switch', [name '/SwN'], 'Criteria', 'u2 ~= 0');
  add_block ('simulink/Sources/Constant', [name '/U'], 'Value', '[1 2]');
  add_block ('simulink/Math Operations/Gain', [name '/Kv'], 'Gain', '[2 3]');
  add_block ('simulink/Math Operations/Gain', [name '/Km'], 'Gain', '[1 2; 3 4]', 'Multiplication', 'Matrix(u*K)');
  for k = 1:5, add_block ('simulink/Sinks/Out1', sprintf ('%s/Out%d', name, k)); endfor
  switches = {'Sw', 'SwB', 'SwN'};
  for k = 1:3
    add_line (name, 'One/1', [switches{k} '/1']); add_line (name, 'U2/1', [switches{k} '/2']);
    add_line (name, 'Three/1', [switches{k} '/3']);
    add_line (name, [switches{k} '/1'], sprintf ('Out%d/1', k));
  endfor
  add_line (name, 'U/1', 'Kv/1'); add_line (name, 'Kv/1', 'Out4/1');
  add_line (name, 'U/1', 'Km/1'); add_line (name, 'Km/1', 'Out5/1');
  set_param (name, 'StopTime', '2', 'Solver', 'ode4', 'FixedStep', '0.25');
endfunction

function y = ifelse_vector (condition, a, b)
  y = b * ones (size (condition)); y(condition) = a;
endfunction

function legacy_sim (varargin)
  [t, x, y] = sim (varargin{:});
endfunction

function assert_limited (out, expected)
  % A step that reaches the bound lands on it in Octave's RK4; Simulink ode4
  % gates each stage and gets there one step later (SIMULINK_API.md).
  reached = abs (out.yout - expected) > 1e-12;
  assert (out.yout(! reached), expected(! reached), 1e-12);
  stage_gated = expected(reached) - 0.25 / 6;
  assert (all (abs (out.yout(reached) - stage_gated) < 1e-12));
endfunction

function y = direct_pid_loop ()
  B = @(type, value, name) struct ('type', type, 'value', value, 'name', name, 'x', 0, 'y', 0);
  model.blocks = [B('Step', [1 0 1], 'Ref') B('Gain', -1, 'Neg') B('Sum', [], 'Err') ...
                  B('Subsystem', ob_pid_controller (2, 1, 0.1, 50), 'PID') ...
                  B('Subsystem', ob_state_space ([0 1; -2 -3], [0; 1], [1 0], 0, [0; 0]), 'Plant') ...
                  B('Outport', 1, 'y')];
  model.edges = [1 1 3 1; 5 1 2 1; 2 1 3 2; 3 1 4 1; 4 1 5 1; 5 1 6 1];
  result = ob_run (model, 0:0.02:12);
  y = cell2mat (result.values(:, 6));
endfunction

function sources = find_line (model, target, port)
  edges = ob_edges (model);
  sources = edges(edges(:, 3) == target & edges(:, 4) == port, 1);
endfunction

function assert_error (callback, fragment)
  try
    callback ();
  catch err
    if (isempty (strfind (err.message, fragment)))
      error ('expected error containing "%s"; got "%s"', fragment, err.message);
    endif
    return;
  end_try_catch
  error ('expected an error containing "%s"', fragment);
endfunction
