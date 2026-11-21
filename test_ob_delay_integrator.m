function test_ob_delay_integrator ()
  % Transport Delay and Limited Integrator checked against analytical traces.
  cases = 0;
  B = @(type, value, name) struct ('type', type, 'value', value, 'name', name, 'x', 0, 'y', 0);
  solvers = {'rk4', 'ode45', 'ode15s'};

  % Ramp through a delay: exact for linear input, initial output before T.
  model.blocks = [B('Time', [], 'Time') B('Transport Delay', [0.5 7], 'Delay') B('Scope', [], 'Scope')];
  model.edges = [1 2; 2 3];
  for solver = solvers
    result = ob_run (model, 0:0.1:2, struct ('solver', solver{1}));
    t = result.t; y = cell2mat (result.values(:, 3));
    assert (y, (t < 0.5) * 7 + (t >= 0.5) .* (t - 0.5), 1e-12);
    cases += 1;
  endfor

  % A delay shorter than the output interval subdivides integration.
  model.blocks(2).value = [0.03 0];
  result = ob_run (model, 0:0.1:1);
  assert (cell2mat (result.values(:, 3)), max (0, result.t - 0.03), 1e-12);
  cases += 1;

  % A delayed step keeps its discontinuity; its integral is exact.
  model.blocks = [B('Step', [1 0 1], 'Step') B('Transport Delay', [0.35 0], 'Delay') ...
                  B('Integrator', 0, 'Integrator') B('Scope', [], 'Scope')];
  model.edges = [1 2; 2 3; 3 4];
  for solver = solvers
    result = ob_run (model, 0:0.1:3, struct ('solver', solver{1}));
    assert (cell2mat (result.values(:, 4)), max (0, result.t - 1.35), 1e-9);
    cases += 1;
  endfor

  % Delay differential equation x' = -x(t-1), x = 1 for t <= 0.
  model.blocks = [B('Integrator', 1, 'x') B('Transport Delay', [1 1], 'Delay') ...
                  B('Gain', -1, 'Gain') B('Scope', [], 'Scope')];
  model.edges = [1 2; 2 3; 3 1; 1 4];
  reference = @(t) (t <= 1) .* (1 - t) + (t > 1) .* (1 - t + (t - 1).^2 / 2);
  result = ob_run (model, 0:0.01:2);
  assert (cell2mat (result.values(:, 4)), reference (result.t), 1e-4);
  result = ob_run (model, 0:0.1:2, struct ('solver', 'ode45', 'reltol', 1e-10, 'abstol', 1e-12));
  assert (cell2mat (result.values(:, 4)), reference (result.t), 1e-6);
  cases += 2;

  % A delay breaks direct feedback: y = 1 - y(t - 1)/2 has no algebraic loop.
  model.blocks = [B('Constant', 1, 'One') B('Sum', [], 'Sum') B('Transport Delay', [1 0], 'Delay') ...
                  B('Gain', -0.5, 'Gain') B('Scope', [], 'Scope')];
  model.edges = [1 1 2 1; 4 1 2 2; 2 1 3 1; 3 1 4 1; 2 1 5 1];
  result = ob_run (model, 0:0.5:3);
  assert (cell2mat (result.values(:, 5))', [1 1 0.5 0.5 0.75 0.75 0.625], 1e-12);
  cases += 1;

  % Matrix signals: matrix initial output, and a scalar initial broadcast.
  model.blocks = [B('Time', [], 'Time') B('Gain', [1; -2], 'Gain') ...
                  B('Transport Delay', struct ('delay', 0.2, 'initial', [5; 6]), 'Delay') B('Scope', [], 'Scope')];
  model.edges = [1 2; 2 3; 3 4];
  result = ob_run (model, 0:0.1:0.5);
  values = cell2mat (result.values(:, 4)');
  assert (values, [5 5 0 0.1 0.2 0.3; 6 6 0 -0.2 -0.4 -0.6], 1e-12);
  model.blocks(3).value = [0.2 3];
  result = ob_run (model, 0:0.1:0.5);
  assert (result.values{2, 4}, [3; 3]);
  model.blocks(3).value = struct ('delay', 0.2, 'initial', [1 2 3]);
  assert_error (@() ob_run (model, 0:0.1:0.5), 'shape must match');
  cases += 3;

  % Limited Integrator reaches a bound exactly with every solver.
  model.blocks = [B('Constant', 1, 'One') ...
                  B('Limited Integrator', struct ('initial', 0, 'lower', 0, 'upper', 1), 'Limited') ...
                  B('Scope', [], 'Scope')];
  model.edges = [1 2; 2 3];
  for solver = solvers
    result = ob_run (model, 0:0.25:2, struct ('solver', solver{1}));
    assert (cell2mat (result.values(:, 3)), min (result.t, 1), 1e-8);
    cases += 1;
  endfor

  % Inward release: integrating cos t within [-0.5, 0.5].
  ob_write_function ('ob_test_cos_input', 'y = cos (t);');
  model.blocks = [B('Time', [], 'Time') B('Function', [], 'ob_test_cos_input') ...
                  B('Limited Integrator', struct ('initial', 0, 'lower', -0.5, 'upper', 0.5), 'Limited') ...
                  B('Scope', [], 'Scope')];
  model.edges = [1 2; 2 3; 3 4];
  result = ob_run (model, 0:0.05:7, struct ('solver', 'ode45', 'reltol', 1e-10, 'abstol', 1e-12));
  assert (cell2mat (result.values(:, 4)), clipped_sine (result.t), 1e-6);
  result = ob_run (model, 0:0.01:7);
  assert (cell2mat (result.values(:, 4)), clipped_sine (result.t), 2e-2);
  cases += 2;

  % Elementwise limits on a matrix state.
  model.blocks = [B('Constant', [1 -1 2], 'Rates') ...
                  B('Limited Integrator', struct ('initial', [0 0 0], 'lower', [-0.5 -0.25 -1], 'upper', [0.5 1 1]), 'Limited') ...
                  B('Scope', [], 'Scope')];
  model.edges = [1 2; 2 3];
  result = ob_run (model, 0:0.25:1);
  assert (result.values{end, 3}, [0.5 -0.25 1], 1e-12);
  assert (result.values{2, 3}, [0.25 -0.25 0.5], 1e-12);
  cases += 1;

  % Sampled resets: each mode against a square wave of period 1.
  ob_write_function ('ob_test_square_input', 'y = 2 * (mod (t, 1) >= 0.5) - 1;');
  base.blocks = [B('Constant', 1, 'One') B('Limited Integrator', struct ('initial', 0.25, 'reset', 'rising'), 'Limited') ...
                 B('Time', [], 'Time') B('Function', [], 'ob_test_square_input') B('Scope', [], 'Scope')];
  base.edges = [1 1 2 1; 3 1 4 1; 4 1 2 2; 2 1 5 1];
  t = (0:0.1:3)';
  expected.rising = 0.25 + t;
  expected.rising(t >= 0.5) = 0.25 + mod (t(t >= 0.5) - 0.5, 1);
  expected.falling = 0.25 + t;
  expected.falling(t >= 1) = 0.25 + mod (t(t >= 1), 1);
  expected.either = 0.25 + mod (t, 0.5);
  expected.either(t < 0.5) = 0.25 + t(t < 0.5);
  for mode = {'rising', 'falling', 'either'}
    model = base; model.blocks(2).value.reset = mode{1};
    result = ob_run (model, t);
    assert (cell2mat (result.values(:, 5)), expected.(mode{1}), 1e-9);
    cases += 1;
  endfor
  % A level reset holds the initial state while its signal is nonzero.
  % Step blocks make the gate edges solver boundaries.
  ob_write_function ('ob_test_gate_input', 'y = double (t >= 1 && t < 2);');
  model = base; model.blocks(2).value.reset = 'level';
  model.blocks(3) = B('Step', [1 0 1], 'Open');
  model.blocks(4) = B('Step', [2 0 -1], 'Close');
  model.blocks(6) = B('Sum', [], 'Gate');
  model.edges = [1 1 2 1; 3 1 6 1; 4 1 6 2; 6 1 2 2; 2 1 5 1];
  for solver = {'rk4', 'ode45'}
    result = ob_run (model, t, struct ('solver', solver{1}));
    reference = 0.25 + t; reference(t >= 1 & t < 2) = 0.25;
    reference(t >= 2) = 0.25 + t(t >= 2) - 2;
    assert (cell2mat (result.values(:, 5)), reference, 1e-9);
    cases += 1;
  endfor
  % A falling reset ignores the gate's rising edge at t = 1.
  model = base; model.blocks(4).name = 'ob_test_gate_input';
  model.blocks(2).value.reset = 'falling';
  result = ob_run (model, 0:0.5:1.5);
  assert (cell2mat (result.values(:, 5))', [0.25 0.75 1.25 1.75], 1e-12);
  cases += 1;

  % Contexts with history and reset memory resume identically when copied.
  model = base;
  context = ob_runtime_init (model, 0);
  context = ob_runtime_step (context, 0.7);
  copy = context;
  for time = [0.9 1.3 1.6]
    context = ob_runtime_step (context, time); copy = ob_runtime_step (copy, time);
  endfor
  assert (isequaln (context.states, copy.states));
  % Resets are sampled at accepted hits: the edge near 1.5 is seen at 1.6.
  assert (ob_runtime_outputs (copy, 2, 1), 0.25, 1e-12);
  assert (ob_runtime_outputs (ob_runtime_step (copy, 1.8), 2, 1), 0.45, 1e-12);
  cases += 1;

  % Persistence keeps structured parameters.
  folder = tempname (); mkdir (folder);
  cleanup = onCleanup (@() remove_folder (folder));
  file = fullfile (folder, 'advanced.mat');
  model.blocks(end+1) = B('Transport Delay', [0.5 1], 'Delay');
  model.edges(end+1, :) = [2 1 6 1];
  ob_save_model (file, model, [0 2 0.1]);
  loaded = ob_load_model (file);
  assert (isequal (loaded.blocks(2).value, model.blocks(2).value));
  assert (isequal (loaded.blocks(6).value, [0.5 1]));
  cases += 1;

  % Invalid parameters and port counts.
  bad = base; bad.blocks(2).value = struct ('initial', 0, 'lower', 1, 'upper', 0);
  assert_error (@() ob_validate_model (bad), 'lower <= upper');
  bad = base; bad.edges(bad.edges(:, 3) == 2 & bad.edges(:, 4) == 2, :) = [];
  assert_error (@() ob_run (bad, 0:0.1:1), 'expected 2 to 2');
  bad = base; bad.blocks(2).value.reset = 'none';
  assert_error (@() ob_validate_model (bad), 'input port 2 does not exist');
  delay.blocks = [B('Time', [], 'Time') B('Transport Delay', [-1 0], 'Delay')];
  delay.edges = [1 2];
  assert_error (@() ob_validate_model (delay), 'positive finite');
  cases += 4;

  % Explicit unsupported contracts.
  delay.blocks(2).value = [0.5 0];
  assert_error (@() ob_run (delay, 0:0.1:1, struct ('zero_crossings', true)), 'zero_crossings');
  assert_error (@() ob_codegen (delay, fullfile (folder, 'delay.c')), 'not supported by C export');
  assert (! exist (fullfile (folder, 'delay.c'), 'file'));
  child.blocks = [B('Inport', 1, 'In') B('Limited Integrator', 0, 'Limited') B('Outport', 1, 'Out')];
  child.edges = [1 2; 2 3];
  child.execution = struct ('mode', 'enabled');
  parent.blocks = [B('Constant', 1, 'One') B('Subsystem', child, 'Enabled') B('Scope', [], 'Scope')];
  parent.edges = [1 1 2 1; 1 1 2 2; 2 1 3 1];
  assert_error (@() ob_run (parent, 0:0.1:1), 'inside a conditional subsystem');
  virtual = child; virtual = rmfield (virtual, 'execution');
  parent.blocks(2).value = virtual; parent.edges = [1 2; 2 3];
  result = ob_run (parent, 0:0.5:1);
  assert (cell2mat (result.values(:, 3))', [0 0.5 1], 1e-12);
  cases += 5;

  printf ('Transport Delay and Limited Integrator: %d cases passed\n', cases);
endfunction

function y = clipped_sine (t)
  % Integral of cos t clipped to [-0.5, 0.5] from x(0) = 0.
  y = zeros (size (t));
  for k = 1:numel (t)
    s = t(k);
    if (s <= pi/6), y(k) = sin (s);
    elseif (s <= pi/2), y(k) = 0.5;
    else
      phase = mod (s - pi/2, 2*pi);
      if (phase <= pi/2), y(k) = 0.5 + sin (s) - 1;
      elseif (phase <= pi), y(k) = -0.5;
      elseif (phase <= 3*pi/2), y(k) = -0.5 + sin (s) + 1;
      else y(k) = 0.5;
      endif
    endif
  endfor
endfunction

function remove_folder (folder)
  confirm_recursive_rmdir (false, 'local');
  if (exist (folder, 'dir')), rmdir (folder, 's'); endif
endfunction

function ob_write_function (name, body)
  folder = fullfile (tempdir (), 'octave-blocks-delay-tests');
  if (! exist (folder, 'dir')), mkdir (folder); endif
  fid = fopen (fullfile (folder, [name '.m']), 'w');
  fprintf (fid, 'function y = %s (t)\n  %s\nendfunction\n', name, body);
  fclose (fid);
  addpath (folder);
  rehash ();
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
