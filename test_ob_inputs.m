function test_ob_inputs ()
  % Root inputs have explicit sample times, component shapes, and interpolation.
  held = ob_input_signal ([0 0.4 1], [1; 3; 5]);
  assert (isequal (held.t, [0; 0.4; 1]));
  assert (isequal (held.shape, [1 1]) && strcmp (held.method, 'zoh'));
  assert (ob_input_value (held, -2) == 1);
  assert (ob_input_value (held, 0.4) == 3);
  assert (ob_input_value (held, 0.4, true) == 1);
  assert (ob_input_value (held, 1, true) == 3);
  assert (ob_input_value (held, 2) == 5);
  constant = ob_input_signal (0, [2 4], [1 2], 'linear');
  assert (isequal (ob_input_value (constant, -3), [2 4]));
  assert (isequal (ob_input_value (constant, 10, true), [2 4]));
  raw = struct ('t', [0 1], 'values', [1 2; 3 4]);
  normalized = ob_input_signal (raw);
  assert (isequal (normalized.shape, [1 2]) && strcmp (normalized.method, 'zoh'));
  assert (isequal (normalized.t, [0; 1]) && isequal (raw.t, [0 1]));
  extremes = ob_input_signal ([0 1], [-realmax; realmax], [1 1], 'linear');
  assert (ob_input_value (extremes, 0.5) == 0);
  assert_fails (@() ob_input_value (held, [0 1]));
  assert_fails (@() ob_input_value (held, NaN));

  matrix_signal = ob_input_signal ([0 1], [1 3 2 4; 2 6 4 8], [2 2], 'linear');
  assert (isequal (ob_input_value (matrix_signal, 0), [1 2; 3 4]));
  assert (isequal (ob_input_value (matrix_signal, 0.5), [1.5 3; 4.5 6]));
  assert (isequal (ob_input_value (matrix_signal, 0.5, true), [1.5 3; 4.5 6]));

  model = root_integrator ();
  model.inputs = {ob_input_signal([0 0.35 0.8 1], [1; 3; -2; 4])};
  original = model;
  times = [0 0.2 0.6 1 1.4];
  expected = [0 0.2 1.1 1.3 2.9];
  for solver = {'rk4', 'ode45', 'ode15s'}
    options = struct ('solver', solver{1}, 'reltol', 1e-8, 'abstol', 1e-10);
    result = ob_run (model, times, options);
    assert_close (ob_scope_data(result, 3)', expected, 2e-6);
    assert (isequal (result.t, times(:)));
    assert_close (ob_scope_data(result, 1)', [1 1 3 4 4], 1e-12);

    % Linear segments include their analytic area and hold their endpoint value
    % outside the supplied range; none of the interior knots is an output time.
    linear = model;
    linear.inputs = {ob_input_signal([0 0.35 1], [0; 2; 1], [1 1], 'linear')};
    result = ob_run (linear, [-0.2 0.1 0.6 1.4], options);
    exact = [0, 0.1^2/0.35, 0.35+2*0.25-0.25^2/(2*0.65), 1.725];
    assert_close (ob_scope_data(result, 3)', exact, 2e-6);

    matrix = model;
    matrix.inputs = {matrix_signal}; matrix.blocks(2).value = zeros (2);
    result = ob_run (matrix, [0 0.3 1], options);
    assert_close (result.values{end, 3}, 1.5*[1 2; 3 4], 2e-6);

    child = ob_subsystem_template ();
    child.blocks(2).type = 'Integrator'; child.blocks(2).value = 0;
    nested = model;
    nested.blocks(2).type = 'Subsystem'; nested.blocks(2).value = child;
    result = ob_run (nested, times, options);
    assert_close (ob_scope_data(result, 3)', expected, 2e-6);
    assert_close (ob_scope_data(result, [2 2])', expected, 2e-6);

    % Internal input knots cannot trigger extra Unit Delay/Euler sample hits.
    discrete_signal = ob_input_signal ([0 0.25 1 1.75 3], [10; 20; 30; 40; 50]);
    discrete = model; discrete.inputs = {discrete_signal};
    discrete.blocks(2).type = 'Unit Delay'; discrete.blocks(2).value = -1;
    result = ob_run (discrete, 0:3, options);
    assert_close (ob_scope_data(result, 3)', [-1 10 30 40], 1e-12);
    discrete.blocks(2).type = 'Discrete Integrator'; discrete.blocks(2).value = 0;
    result = ob_run (discrete, 0:3, options);
    assert_close (ob_scope_data(result, 3)', [0 10 40 80], 1e-12);
    mixed = ob_oscillator ();
    mixed.blocks(1).type = 'Inport'; mixed.blocks(1).value = 1;
    mixed.blocks(2).type = 'Unit Delay'; mixed.blocks(2).value = 0;
    mixed.blocks(3).type = 'Integrator'; mixed.blocks(3).value = 0;
    mixed.edges = [1 2; 2 3; 3 4]; mixed.inputs = {discrete_signal};
    result = ob_run (mixed, 0:3, options);
    assert_close (ob_scope_data(result, 4)', [0 0 10 40], 2e-6);
  endfor
  assert (isequal (model, original));

  % Port numbers identify datasets independently of block-array and wire order.
  ordered = ob_oscillator ();
  ordered.blocks(1).type = ordered.blocks(2).type = 'Inport';
  ordered.blocks(1).value = 2; ordered.blocks(2).value = 1;
  ordered.blocks(3).type = 'Function'; ordered.blocks(3).name = 'power';
  ordered.edges = [1 1 3 2; 2 1 3 1; 3 1 4 1];
  ordered.inputs = {ob_input_signal(0, 2), ob_input_signal(0, 3)};
  result = ob_run (ordered, [0 1]);
  assert (result.values{end, 1} == 3 && result.values{end, 2} == 2);
  assert (result.values{end, 4} == 8);

  assert_fails (@() ob_input_signal ([0 0], [1; 2]));
  assert_fails (@() ob_input_signal ([1 0], [1; 2]));
  assert_fails (@() ob_input_signal ([0 Inf], [1; 2]));
  assert_fails (@() ob_input_signal ([-realmax realmax], [1; 2]));
  assert_fails (@() ob_input_signal ([0 1i], [1; 2]));
  assert_fails (@() ob_input_signal ([], []));
  assert_fails (@() ob_input_signal ([0 1], [1 2]));
  assert_fails (@() ob_input_signal (0, 'x'));
  assert_fails (@() ob_input_signal (0, NaN));
  assert_fails (@() ob_input_signal (0, Inf));
  assert_fails (@() ob_input_signal (0, 1i));
  assert_fails (@() ob_input_signal (0, single(1)));
  assert_fails (@() ob_input_signal (0, sparse(1)));
  assert_fails (@() ob_input_signal (0, [1 2 3], [2 2]));
  assert_fails (@() ob_input_signal (0, 1, [0 1]));
  assert_fails (@() ob_input_signal (0, [1 2], [1.5 2]));
  assert_fails (@() ob_input_signal (0, 1, [1 1 1]));
  assert_fails (@() ob_input_signal (0, 1, [1 1], 'nearest'));
  invalid_signal = raw; invalid_signal.extra = 1;
  assert_fails (@() ob_input_signal (invalid_signal));

  partial = root_integrator ();
  ob_validate_model (partial); % Editing/saving before data configuration is allowed.
  assert_fails (@() ob_run (partial, [0 1]));
  partial.inputs = {[]}; ob_validate_model (partial);
  assert_fails (@() ob_run (partial, [0 1]));
  invalid = model; invalid.inputs = [1 2];
  assert_fails (@() ob_validate_model (invalid));
  invalid = model; invalid.inputs{2} = model.inputs{1};
  assert_fails (@() ob_validate_model (invalid));
  invalid = model; invalid.inputs{1} = rmfield (model.inputs{1}, 'values');
  assert_fails (@() ob_validate_model (invalid));
  invalid = nested; invalid.blocks(2).value.inputs = model.inputs;
  assert_fails (@() ob_validate_model (invalid));
  invalid = ob_example (); invalid.inputs = model.inputs;
  assert_fails (@() ob_validate_model (invalid));

  file = [tempname() '.mat'];
  unwind_protect
    config = [0 1.4 0.2]; options = struct ('solver','ode45');
    ob_save_model (file, model, config, options);
    [loaded, loaded_config, loaded_options] = ob_load_model (file);
    assert (isequal (loaded.inputs, model.inputs));
    assert (isequal (loaded_config, config));
    result = ob_run (loaded, times, loaded_options);
    assert_close (ob_scope_data(result, 3)', expected, 2e-6);
    ob_save_model (file, partial, config);
    loaded = ob_load_model (file);
    assert (isequal (loaded.inputs, {[]}));
    assert_fails (@() ob_run (loaded, times));
  unwind_protect_cleanup
    if (exist (file, 'file')), unlink (file); endif
  end_unwind_protect
  disp ('Octave Blocks external input tests passed');
endfunction

function model = root_integrator ()
  model = ob_example ();
  model.blocks(1).type = 'Inport'; model.blocks(1).value = 1; model.blocks(1).name = 'In1';
  model.blocks(2).type = 'Integrator'; model.blocks(2).value = 0;
endfunction

function assert_close (actual, expected, tolerance)
  assert (isequal (size(actual), size(expected)));
  assert (all (isfinite(actual(:))));
  assert (max (abs(actual(:)-expected(:))) < tolerance);
endfunction

function assert_fails (callback)
  caught = false;
  try
    callback ();
  catch
    caught = true;
  end_try_catch
  assert (caught);
endfunction
