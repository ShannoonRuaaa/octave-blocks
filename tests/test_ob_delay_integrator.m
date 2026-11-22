function test_ob_delay_integrator ()
  test_path_cleanup = ob_test_setup ();
  % Transport Delay and Limited Integrator checked against analytical traces.
  cases = 0;
  B = @(type, value, name) struct ('type', type, 'value', value, 'name', name, 'x', 0, 'y', 0);
  solvers = {'rk4', 'ode45', 'ode15s'};

  % Ramp through a delay: exact for linear input, initial output before T.
  % At exactly start + T the output is already u(start) (right-continuous).
  model.blocks = [B('Time', [], 'Time') B('Transport Delay', [0.5 7], 'Delay') B('Scope', [], 'Scope')];
  model.edges = [1 2; 2 3];
  for solver = solvers
    result = ob_run (model, 0:0.1:2, struct ('solver', solver{1}));
    t = result.t; y = cell2mat (result.values(:, 3));
    assert (y, (t < 0.5) * 7 + (t >= 0.5) .* (t - 0.5), 1e-12);
    cases += 1;
  endfor

  % The initial output differs from u(start): integration across start + T
  % must use the initial output as the left limit there, on and off the
  % RK4 grid, and with default adaptive tolerances.
  chain.blocks = [B('Time', [], 'Time') B('Transport Delay', [0.5 7], 'Delay') ...
                  B('Integrator', 0, 'Integrator') B('Scope', [], 'Scope')];
  chain.edges = [1 2; 2 3; 3 4];
  ramp = @(t, T) (t <= T) .* 7 .* t + (t > T) .* (7 * T + (t - T).^2 / 2);
  for T = [0.5 0.35]
    chain.blocks(2).value = [T 7];
    for solver = solvers
      result = ob_run (chain, 0:0.1:2, struct ('solver', solver{1}));
      % ode15s (default tolerances) is accurate only to its tolerance here.
      tolerance = 1e-12; if (strcmp (solver{1}, 'ode15s')), tolerance = 1e-4; endif
      assert (cell2mat (result.values(:, 4)), ramp (result.t, T), tolerance);
      cases += 1;
    endfor
  endfor
  % The same from start time 0.1 with T = 0.2, where (0.1 + 0.2) - 0.2
  % misses 0.1 by an ulp: the end stage at start + T still sees 7.
  chain.blocks(2).value = [0.2 7];
  t = 0.1 + (0:20) * 0.1;
  exact = (t <= 0.3) .* 7 .* (t - 0.1) + (t > 0.3) .* (1.4 + ((t - 0.2).^2 - 0.01) / 2);
  for solver = {'rk4', 'ode45'}
    result = ob_run (chain, t, struct ('solver', solver{1}));
    assert (cell2mat (result.values(:, 4)), exact(:), 1e-12);
    cases += 1;
  endfor
  % A second delay reads the first one's jump at start + T as a stored
  % jump.  Its own delayed jump, 0.1 + 0.2 + 0.05, and the output time
  % 0.1 + 5 * 0.05 differ by an ulp but are the same instant.
  pair.blocks = [B('Time', [], 'Time') B('Transport Delay', [0.2 7], 'Delay') ...
                 B('Transport Delay', [0.05 7], 'Second') B('Scope', [], 'Scope')];
  pair.edges = [1 2; 2 3; 3 4];
  t = 0.1 + (0:10) * 0.05;
  result = ob_run (pair, t, struct ('solver', 'rk4'));
  reference = 7 * ones (11, 1); reference(6:end) = t(6:end) - 0.25;
  assert (cell2mat (result.values(:, 4)), reference, 1e-12);
  cases += 1;

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
  % Steps whose delayed jump meets the output grid only up to rounding
  % (0.1 + 0.2 vs. 3 * 0.1; a Step at 0.7 vs. the output time 7 * 0.1), and
  % a Step between output times, whose right limit is recorded at that
  % interior boundary.  Before, these were off by h/6, by 1e12 (a 1e-16
  % history interval), and by up to 22 (ode45), respectively.
  for p = [0.1 0.2; 0.7 0.1; 0.7 0.2; 0.75 0.1]'
    model.blocks(1).value = [p(1) 0 1]; model.blocks(2).value = [p(2) 0];
    for solver = {'rk4', 'ode45'}
      result = ob_run (model, 0:0.1:2, struct ('solver', solver{1}));
      assert (cell2mat (result.values(:, 4)), max (0, result.t - sum (p)), 1e-12);
      cases += 1;
    endfor
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
  % A second delay reading y must see y's jump at t = 1 (left limit 1,
  % right limit 0.5), so z(t) = y(t - 0.25) is exact between samples.
  model.blocks(6:7) = [B('Transport Delay', [0.25 1], 'Second') B('Scope', [], 'Scope')];
  model.edges(end+1:end+2, :) = [2 1 6 1; 6 1 7 1];
  result = ob_run (model, 0:0.1:3);
  z = cell2mat (result.values(:, 7));
  reference = ones (size (result.t));
  reference(result.t >= 1.25) = 0.5; reference(result.t >= 2.25) = 0.75;
  assert (z, reference, 1e-12);
  cases += 1;

  % Matrix signals: matrix initial output, and a scalar initial broadcast.
  model.blocks = [B('Time', [], 'Time') B('Gain', [1; -2], 'Gain') ...
                  B('Transport Delay', struct ('delay', 0.2, 'initial', [5; 6]), 'Delay') B('Scope', [], 'Scope')];
  model.edges = [1 2; 2 3; 3 4];
  result = ob_run (model, 0:0.1:0.5);
  values = cell2mat (result.values(:, 4)');
  assert (values, [5 5 0 0.1 0.2 0.3; 6 6 0 -0.2 -0.4 -0.6], 1e-12);
  % A scalar initial output is broadcast from the very first sample, so
  % every sample has the input's shape and the trace stacks.
  model.blocks(3).value = [0.2 3];
  result = ob_run (model, 0:0.1:0.5);
  assert (result.values{1, 4}, [3; 3]);
  assert (result.values{2, 4}, [3; 3]);
  assert (cell2mat (result.values(:, 4)'), [3 3 0 0.1 0.2 0.3; 3 3 0 -0.2 -0.4 -0.6], 1e-12);
  model.blocks(2).value = [1 2; 3 4]; model.blocks(3).value = [0.2 0];
  result = ob_run (model, 0:0.1:0.4);
  assert (result.values{1, 4}, zeros (2));
  assert (result.values{end, 4}, [0.2 0.4; 0.6 0.8], 1e-12);
  % The same holds for a step-by-step context.
  context = ob_runtime_init (model, 0);
  assert (ob_runtime_outputs (context, 3, 1), zeros (2));
  % A scalar input is expanded to a matrix initial output's shape.
  scalar.blocks = [B('Time', [], 'Time') ...
                   B('Transport Delay', struct ('delay', 0.2, 'initial', [5; 6]), 'Delay') B('Scope', [], 'Scope')];
  scalar.edges = [1 2; 2 3];
  result = ob_run (scalar, 0:0.1:0.5);
  assert (cell2mat (result.values(:, 3)'), [5 5 0 0.1 0.2 0.3; 6 6 0 0.1 0.2 0.3], 1e-12);
  model.blocks(2).value = [1; -2];
  model.blocks(3).value = struct ('delay', 0.2, 'initial', [1 2 3]);
  assert_error (@() ob_run (model, 0:0.1:0.5), 'shape must match');
  cases += 6;

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
  for mode = {'level', 'level hold'}
    model.blocks(2).value.reset = mode{1};
    for solver = {'rk4', 'ode45'}
      result = ob_run (model, t, struct ('solver', solver{1}));
      reference = 0.25 + t; reference(t >= 1 & t < 2) = 0.25;
      reference(t >= 2) = 0.25 + t(t >= 2) - 2;
      assert (cell2mat (result.values(:, 5)), reference, 1e-9);
      cases += 1;
    endfor
  endfor
  % With the gate on [1.05, 2.05), between samples: with RK4, 'level' also
  % resets when the signal returns to zero, sampled at the next hit (2.1),
  % as Simulink ode4 does.  'level hold' only holds, so integration resumes
  % at 2.05.  With ode45 the hold ends at 2.05 with the state at its initial
  % value, where Simulink's variable-step solvers reset, so 'level' needs no
  % sampled reset and also resumes at 2.05.
  model.blocks(3).value = [1.05 0 1]; model.blocks(4).value = [2.05 0 -1];
  for mode = {'level', 'level hold'}
    model.blocks(2).value.reset = mode{1};
    for solver = {'rk4', 'ode45'}
      result = ob_run (model, t, struct ('solver', solver{1}));
      reference = 0.25 + t; reference(t >= 1.1 & t <= 2) = 0.25;
      if (strcmp (mode{1}, 'level') && strcmp (solver{1}, 'rk4'))
        reference(t > 2) = 0.25 + t(t > 2) - 2.1;
      else
        reference(t > 2) = 0.25 + t(t > 2) - 2.05;
      endif
      assert (cell2mat (result.values(:, 5)), reference, 1e-9);
      cases += 1;
    endfor
  endfor
  % Sparse output times: the RK4 sampled reset discards the integration
  % from the release at 2.05 up to the next hit; ode45 does not.
  model.blocks(2).value.reset = 'level';
  result = ob_run (model, 0:3, struct ('solver', 'rk4'));
  assert (cell2mat (result.values(:, 5))', [0.25 1.25 0.25 0.25], 1e-12);
  result = ob_run (model, 0:3, struct ('solver', 'ode45'));
  assert (cell2mat (result.values(:, 5))', [0.25 1.25 0.25 1.2], 1e-9);
  cases += 2;
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
  % Flat RK4 C export supports Transport Delay (CODEGEN.md); zero crossings do not.
  assert_error (@() ob_codegen (delay, fullfile (folder, 'delay.c'), [0 1 0.1], struct ('zero_crossings', true)), ...
                'not supported with zero_crossings=true');
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
