function test_ob_simulink_api ()
  % Simulink-style command API: construction, parameters, hierarchy,
  % simulation outputs, persistence, and explicit unsupported cases.
  here = fileparts (mfilename ('fullpath'));
  addpath (fullfile (here, 'simulink'));
  bdclose ('all');
  cleanup = onCleanup (@() bdclose ('all'));
  cases = 0;

  % Sources, an integrator and a root Outport.
  new_system ('api');
  assert (bdIsLoaded ('api'));
  add_block ('simulink/Sources/Sine Wave', 'api/Sine', 'Amplitude', '2', 'Frequency', '3', 'Bias', '0.5');
  add_block ('simulink/Continuous/Integrator', 'api/Int');
  add_block ('simulink/Sinks/Out1', 'api/Out1');
  add_line ('api', 'Sine/1', 'Int/1'); add_line ('api', 'Int/1', 'Out1/1');
  set_param ('api', 'StopTime', '2', 'Solver', 'ode45', 'RelTol', '1e-9', 'AbsTol', '1e-12', 'FixedStep', '0.05');
  out = sim ('api');
  t = out.tout;
  assert (out.yout, 2/3 * (1 - cos (3*t)) + 0.5*t, 1e-7);
  assert (out.SimulationMetadata.Solver, 'ode45');
  cases += 1;

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
  assert (out.sumlog.signals.values(end, :), -2 * ([1 2] - [2 4] + [3 6]));
  assert (out.yout{1}(end, :), ([1 2] .* [2 4]) ./ [3 6], 1e-15);
  assert (get_param ('ops/Sum', 'BlockType'), 'Sum');
  assert (get_param ('ops/Sum', 'Inputs'), '+-+');
  cases += 2;

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
  [t_legacy, x_legacy, y_legacy] = sim ('tf', 'StopTime', '3', 'FixedStep', '0.1');
  assert (numel (t_legacy) == 31 && isempty (x_legacy) && numel (y_legacy) == 31);
  cases += 4;

  % Integrator options map to the Limited Integrator.
  new_system ('lim');
  add_block ('simulink/Sources/Constant', 'lim/One');
  add_block ('simulink/Continuous/Integrator', 'lim/Int', 'LimitOutput', 'on', ...
             'UpperSaturationLimit', '0.75', 'LowerSaturationLimit', '0');
  add_block ('simulink/Sinks/Out1', 'lim/Out1');
  add_line ('lim', 'One/1', 'Int/1'); add_line ('lim', 'Int/1', 'Out1/1');
  out = sim ('lim', 'StopTime', '2', 'Solver', 'ode4', 'FixedStep', '0.25');
  assert (out.yout, min (out.tout, 0.75), 1e-12);
  set_param ('lim/Int', 'ExternalReset', 'rising');
  assert (isequal (get_param ('lim/Int', 'Ports'), [2 1]));
  add_block ('simulink/Sources/Step', 'lim/Reset', 'Time', '1', 'Before', '-1', 'After', '1');
  add_line ('lim', 'Reset/1', 'Int/2');
  out = sim ('lim', 'StopTime', '2', 'Solver', 'ode4', 'FixedStep', '0.25');
  expected = min (out.tout, 0.75); expected(out.tout >= 1) = min (out.tout(out.tout >= 1) - 1, 0.75);
  assert (out.yout, expected, 1e-12);
  set_param ('lim/Int', 'ExternalReset', 'none');
  assert (isempty (find_line (ob_simulink ('get_model', 'lim'), 2, 2)));
  assert_error (@() set_param ('lim/Int', 'ExternalReset', 'level hold'), 'level hold');
  assert (strcmp (get_param ('lim/Int', 'ExternalReset'), 'none'));
  cases += 4;

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
  cases += 3;

  % Adding a Trigger makes an enabled-and-triggered subsystem; deleting the
  % Enable block moves the trigger wire down to the first control port.
  add_block ('simulink/Ports & Subsystems/Trigger', 'cond/Sub/Trigger', 'TriggerType', 'falling');
  model = ob_simulink ('get_model', 'cond');
  sub = find (strcmp ({model.blocks.name}, 'Sub'));
  assert (strcmp (ob_execution_mode (model.blocks(sub).value), 'enabled_falling'));
  add_line ('cond', 'On/1', 'Sub/Trigger');
  delete_block ('cond/Sub/Enable');
  model = ob_simulink ('get_model', 'cond');
  assert (strcmp (ob_execution_mode (model.blocks(sub).value), 'falling'));
  on = find (strcmp ({model.blocks.name}, 'On'));
  assert (! isempty (find_line (model, sub, 2)) && find_line (model, sub, 2)(1) == on);
  assert (ob_block_ports (model.blocks(sub)) == 2);
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

  % Persistence roundtrip and a duplicate-name policy.
  folder = tempname (); mkdir (folder);
  file = fullfile (folder, 'tf_model.mat');
  save_system ('tf', file);
  reference = sim ('tf');
  close_system ('tf');
  assert (! bdIsLoaded ('tf'));
  load_system (file);
  assert (bdIsLoaded ('tf_model'));
  loaded = sim ('tf_model');
  assert (loaded.yout, reference.yout, 1e-12);
  assert (strcmp (get_param ('tf_model/Plant', 'Numerator'), 'ob_api_gain'));
  assert_error (@() add_block ('simulink/Math Operations/Gain', 'tf_model/Plant'), 'already exists');
  path = add_block ('simulink/Math Operations/Gain', 'tf_model/Plant', 'MakeNameUnique', 'on');
  assert (strcmp (path, 'tf_model/Plant1'));
  confirm_recursive_rmdir (false, 'local'); rmdir (folder, 's');
  cases += 2;

  % API-built models export to C with the existing generator.
  model = ob_simulink ('get_model', 'api');
  folder = tempname (); mkdir (folder);
  info = ob_codegen (model, fullfile (folder, 'api.c'), [0 1 0.1]);
  assert (exist (fullfile (folder, 'api.c'), 'file') == 2 && isstruct (info));
  confirm_recursive_rmdir (false, 'local'); rmdir (folder, 's');
  cases += 1;

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
  cases += 1;

  % Discrete and nonlinear library blocks.
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
  cases += 3;

  % Explicit failures leave systems unchanged.
  assert_error (@() add_block ('simulink/Sources/Signal Builder', 'mix/S'), 'not supported');
  assert_error (@() set_param ('mix/Sat', 'Gain', '3'), 'no parameter ''Gain''');
  assert_error (@() set_param ('mix', 'Solver', 'ode113'), 'not supported');
  assert (strcmp (get_param ('mix', 'Solver'), 'VariableStepAuto'));
  assert_error (@() set_param ('mix/Z', 'SampleTime', '[0.2 0.5]'), 'offset');
  assert (strcmp (get_param ('mix/Z', 'SampleTime'), '0.2'));
  assert_error (@() add_line ('mix', 'Ramp/1', 'Out1/1'), 'already connected');
  assert_error (@() sim ('missing'), 'not loaded');
  assert_error (@() load_system ('model.slx'), '.slx');
  assert_error (@() add_block ('simulink/Math Operations/Sum', 'mix/S', 'Inputs', '+*'), 'Inputs');
  cases += 1;

  bdclose ('all');
  assert (isempty (ob_simulink ('list')));
  printf ('Simulink-style command API: %d cases passed\n', cases);
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
