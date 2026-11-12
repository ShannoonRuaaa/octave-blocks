function test_ob_controls ()
  % Exact elementwise boundaries, including equality at each ordered limit.
  input = [-3 -1 0; 1 2 4];
  saturation = unary_model ('Saturation', [-1 2], input);
  result = ob_run (saturation, [0 1]);
  assert_close (result.values{end, 3}, [-1 -1 0; 1 2 2]);
  signed_zero = unary_model ('Saturation', [0 1], -0.0);
  result = ob_run (signed_zero, [0 1]);
  assert (atan2(result.values{end, 3}, -1) == -pi);
  saturation.blocks(2).value = [2; 2];
  assert_close (ob_run(saturation, [0 1]).values{end, 3}, 2*ones(2,3));
  dead = unary_model ('Dead Zone', [-1; 2], input);
  assert_close (ob_run(dead, [0 1]).values{end, 3}, [-2 0 0; 0 0 2]);
  dead.blocks(2).value = [0 0];
  assert_close (ob_run(dead, [0 1]).values{end, 3}, input);
  saturation = unary_model ('Saturation', int16([-1 2]), int16(input));
  result = ob_run (saturation, [0 1]);
  assert (isa (result.values{end, 3}, 'double'));
  assert_close (result.values{end, 3}, [-1 -1 0; 1 2 2]);

  % Switch ports are explicit, and equality selects port 1 (criterion >=).
  switched = switch_model (42, -7, 0, 0);
  assert_close (ob_run(switched, [0 1]).values{end, 5}, 42);
  switched.blocks(2).value = -1;
  assert_close (ob_run(switched, [0 1]).values{end, 5}, -7);
  switched.blocks(2).type = 'Time'; switched.blocks(2).value = [];
  switched.blocks(4).value = 0.5;
  result = ob_run (switched, [0 0.5 1]);
  assert_close (ob_scope_data(result, 5)', [-7 42 42]);
  a = [11 12; 13 14]; b = -a;
  switched = switch_model (a, b, [-1 0; 1 -1], 0);
  assert_close (ob_run(switched, [0 1]).values{end, 5}, [-11 12; 13 -14]);
  switched.blocks(2).value = 0;
  assert_close (ob_run(switched, [0 1]).values{end, 5}, a);
  switched.blocks(2).value = -1;
  assert_close (ob_run(switched, [0 1]).values{end, 5}, b);
  switched.blocks(1).value = int16(a); switched.blocks(3).value = int16(b);
  result = ob_run (switched, [0 1]);
  assert (isa (result.values{end, 5}, 'double'));

  % Use smooth/constant feedback segments: this increment does not locate
  % unknown nonlinear zero crossings inside a solver interval.
  initial = [2 0.5; -0.25 -2];
  times = 0:0.05:0.5;
  for solver = {'rk4', 'ode45', 'ode15s'}
    options = struct ('solver', solver{1}, 'reltol', 1e-8, 'abstol', 1e-10);
    feedback = feedback_model ('Saturation', initial);
    result = ob_run (feedback, times, options);
    t = times(end);
    assert_close (result.values{end, 4}, [2-t 0.5*exp(-t); -0.25*exp(-t) -2+t], 2e-6);
    feedback = feedback_model ('Dead Zone', initial);
    result = ob_run (feedback, times, options);
    assert_close (result.values{end, 4}, [1+exp(-t) 0.5; -0.25 -1-exp(-t)], 2e-6);
    feedback = switch_feedback (initial);
    result = ob_run (feedback, times, options);
    assert_close (result.values{end, 6}, initial*exp(-t), 2e-6);

    nested = ob_oscillator ();
    nested.blocks(1).type = 'Inport'; nested.blocks(1).value = 1;
    nested.blocks(2).type = 'Subsystem'; nested.blocks(2).value = ob_subsystem_template ();
    nested.blocks(2).value.blocks(2).type = 'Saturation';
    nested.blocks(2).value.blocks(2).value = [-1 1];
    nested.blocks(3).type = 'Rate Transition'; nested.blocks(3).value = 0;
    nested.blocks(4).type = 'Integrator'; nested.blocks(4).value = 0;
    nested.blocks(5) = nested.blocks(4); nested.blocks(5).type = 'Scope'; nested.blocks(5).value = [];
    nested.edges = [1 2; 2 3; 3 4; 4 5];
    nested.inputs = {ob_input_signal([0 0.25 0.5 0.75 1], [-2; -1; 0; 1; 2])};
    nested.sample_times = [0 0; 0 0; 0.25 0; 0 0; 0 0];
    result = ob_run (nested, [0 0.1 0.6 0.85 1], options);
    assert_close (ob_scope_data(result, 5)', [0 -0.1 -0.5 -0.4 -0.25], 2e-6);
  endfor
  demo = ob_control_example ();
  result = ob_run (demo, 0:4);
  assert_close (ob_scope_data(result, 5)', [-1 -1 2 3 3]);
  assert_close (ob_scope_data(result, 7)', [-1 0 0 1 2]);

  for type = {'Saturation', 'Dead Zone'}
    for value = {[], 1, [1 2 3], [2 1], [NaN 1], [0 Inf], [0 1i], 'limits'}
      invalid = unary_model (type{1}, value{1}, 0);
      assert_fails (@() ob_validate_model (invalid));
    endfor
  endfor
  for value = {[], [0 1], NaN, Inf, 1i, 'threshold'}
    invalid = switch_model (1, -1, 0, value{1});
    assert_fails (@() ob_validate_model (invalid));
  endfor
  invalid = switch_model (ones(2), 0, 1, 0);
  assert_error (@() ob_run (invalid, [0 1]), 'identical shapes');
  invalid = switch_model (ones(2), zeros(2), ones(1,2), 0);
  assert_error (@() ob_run (invalid, [0 1]), 'scalar or match the data shape');

  % Check runtime source outputs, not only constant-parameter validation.
  invalid = generated_input_model ('zeros');
  assert_error (@() ob_run (invalid, [0 1]), 'nonempty finite real numeric matrix');
  invalid = generated_input_model ('sqrt');
  invalid.blocks(1).type = 'Constant'; invalid.blocks(1).value = -1;
  assert_error (@() ob_run (invalid, [0 1]), 'nonempty finite real numeric matrix');
  invalid = generated_input_model ('log');
  invalid.blocks(1).type = 'Constant'; invalid.blocks(1).value = 0;
  assert_error (@() ob_run (invalid, [0 1]), 'nonempty finite real numeric matrix');
  invalid = unary_model ('Saturation', [-1 1], ones(2,2,2));
  assert_error (@() ob_run (invalid, [0 1]), 'nonempty finite real numeric matrix');
  invalid = unary_model ('Dead Zone', [-realmax -realmax], realmax);
  assert_error (@() ob_run (invalid, [0 1]), 'produced nonfinite output');

  % Even an unselected Switch data branch must retain the common data shape.
  dynamic = switch_model (7, 0, 1, 0);
  dynamic.blocks(3).type = 'Function'; dynamic.blocks(3).name = 'zeros';
  dynamic.blocks(6) = dynamic.blocks(1); dynamic.blocks(6).type = 'Time'; dynamic.blocks(6).value = [];
  dynamic.edges(end + 1, :) = [6 1 3 1];
  assert (ob_run(dynamic, 1).values{1, 5} == 7);
  assert_error (@() ob_run (dynamic, [1 2]), 'identical shapes');
  dynamic.blocks(3).name = 'log'; dynamic.blocks(6).type = 'Constant'; dynamic.blocks(6).value = 0;
  assert_error (@() ob_run (dynamic, [0 1]), 'nonempty finite real numeric matrix');

  % Controls remain direct-feedthrough and cannot independently break a loop.
  loop = unary_model ('Saturation', [-1 1], 0); loop.edges = [2 2; 2 3];
  assert_error (@() ob_run (loop, [0 1]), 'algebraic loop');
  loop = switch_model (7, -7, 1, 0); loop.edges(1, 1) = 4;
  assert_error (@() ob_run (loop, [0 1]), 'algebraic loop');
  file = [tempname() '.mat'];
  unwind_protect
    saved = ob_control_example ();
    saved.blocks(2).value = int16 ([0 3]);
    saved.blocks(3).value = int16 ([1 2]);
    saved.blocks(4).value = int16 (2);
    config = [0 4 0.5]; options = struct ('solver', 'ode45');
    ob_save_model (file, saved, config, options);
    [loaded, loaded_config, loaded_options] = ob_load_model (file);
    assert (isequal (loaded, saved));
    assert (isequal (loaded_config, config));
    assert (isequal (loaded_options, ob_solver_options(options)));
    assert (isa (loaded.blocks(2).value, 'int16'));
    assert (isa (loaded.blocks(3).value, 'int16'));
    assert (isa (loaded.blocks(4).value, 'int16'));
    result = ob_run (loaded, 0:4, loaded_options);
    assert_close (ob_scope_data(result, 5)', [-1 -1 2 3 3]);
    assert_close (ob_scope_data(result, 7)', [-1 0 0 1 2]);
  unwind_protect_cleanup
    if (exist (file, 'file')), unlink (file); endif
  end_unwind_protect
  disp ('Octave Blocks nonlinear control tests passed');
endfunction

function model = unary_model (type, parameter, input)
  model = ob_example ();
  model.blocks(1).type = 'Constant'; model.blocks(1).value = input;
  model.blocks(2).type = type; model.blocks(2).value = parameter;
endfunction

function model = switch_model (yes, no, control, threshold)
  model.blocks = struct ('type', {'Constant','Constant','Constant','Switch','Scope'}, ...
    'value', {yes, control, no, threshold, []}, 'name', {'True','Control','False','Switch','Scope'}, ...
    'x', {0.15,0.15,0.15,0.5,0.85}, 'y', {0.75,0.5,0.25,0.5,0.5});
  model.edges = [3 1 4 3; 1 1 4 1; 2 1 4 2; 4 1 5 1];
endfunction

function model = feedback_model (type, initial)
  model = ob_oscillator ();
  model.blocks(1).value = initial;
  model.blocks(2).type = 'Gain'; model.blocks(2).value = -1;
  model.blocks(3).type = type; model.blocks(3).value = [-1 1];
  model.edges = [1 2; 2 3; 3 1; 1 4];
endfunction

function model = switch_feedback (initial)
  model = switch_model (0, zeros(size(initial)), 1, 0);
  model.blocks(1).type = 'Integrator'; model.blocks(1).value = initial;
  model.blocks(5).type = 'Gain'; model.blocks(5).value = -1;
  model.blocks(6) = model.blocks(5); model.blocks(6).type = 'Scope'; model.blocks(6).value = [];
  model.edges = [1 1 5 1; 5 1 4 1; 2 1 4 2; 3 1 4 3; 4 1 1 1; 1 1 6 1];
endfunction

function model = generated_input_model (name)
  model = ob_oscillator ();
  model.blocks(1).type = 'Time'; model.blocks(1).value = [];
  model.blocks(2).type = 'Function'; model.blocks(2).name = name;
  model.blocks(3).type = 'Saturation'; model.blocks(3).value = [-1 1];
  model.edges = [1 2; 2 3; 3 4];
endfunction

function assert_close (actual, expected, tolerance = 1e-12)
  assert (isequal(size(actual), size(expected)));
  assert (all(isfinite(actual(:))));
  assert (max(abs(actual(:)-expected(:))) < tolerance);
endfunction

function assert_error (callback, fragment)
  caught = false;
  try
    callback ();
  catch err
    caught = ! isempty(strfind(err.message, fragment));
  end_try_catch
  assert (caught);
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
