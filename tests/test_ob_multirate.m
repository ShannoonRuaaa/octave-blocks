function test_ob_multirate ()
  % Explicit schedules are independent of logging/output timestamps.
  delay = chain_model ('Time', [], 'Unit Delay', -1);
  delay.sample_times = [0 0; 0.25 0; 0 0];
  times = [0 0.1 0.25 0.49 0.5 0.74 0.75 0.99 1 1.1];
  expected = [-1 -1 0 0 0.25 0.25 0.5 0.5 0.75 0.75];
  original = delay;
  result = ob_run (delay, times);
  assert_trace (result, 3, expected);
  sparse = ob_run (delay, [0 0.49 0.99 1.1]);
  assert_trace (sparse, 3, [-1 0 0.5 0.75]);
  assert (isequal (delay, original));
  % A long sparse run must use integer clock ticks rather than accumulated dt.
  long_clock = delay; long_clock.sample_times(2, :) = [0.1 0];
  result = ob_run (long_clock, [0 100]);
  assert_trace (result, 3, [-1 99.9], 1e-10);

  % Offset schedules are relative to start time and emit IC on the first hit.
  euler = chain_model ('Constant', 2, 'Discrete Integrator', 5);
  period = 0.3; offset = 0.1; start = 10;
  ticks = start + offset + (0:3)*period;
  euler.sample_times = [0 0; period offset; 0 0];
  times = [start ticks(1) ticks(1)+0.05 ticks(2) ticks(2)+0.2 ticks(3) ticks(4)];
  result = ob_run (euler, times);
  assert_trace (result, 3, [5 5 5 5.6 5.6 6.2 6.8]);
  shifted = chain_model ('Time', [], 'Unit Delay', -5);
  shifted.sample_times = euler.sample_times;
  result = ob_run (shifted, times);
  assert_trace (result, 3, [-5 -5 -5 ticks(1) ticks(1) ticks(2) ticks(3)]);

  % Different delay rates commit their previously captured inputs together.
  cross = ob_oscillator ();
  cross.blocks(1).type = cross.blocks(2).type = 'Unit Delay';
  cross.blocks(1).value = 1; cross.blocks(2).value = 2;
  cross.blocks(3).type = cross.blocks(4).type = 'Scope';
  cross.edges = [2 1; 1 2; 1 3; 2 4];
  cross.sample_times = [0.5 0; 1 0; 0 0; 0 0];
  result = ob_run (cross, [0 0.5 1 1.5 2]);
  assert_trace (result, 3, [1 2 2 1 1]);
  assert_trace (result, 4, [2 2 1 1 2]);
  sparse = ob_run (cross, [0 1.5 2]);
  assert_trace (sparse, 3, [1 1 1]);
  assert_trace (sparse, 4, [2 1 2]);
  collision = cross;
  collision.sample_times = [0 0; 0.5 0; 0 0; 0 0];
  collision.blocks(1).value = 10; collision.blocks(2).value = 20;
  result = ob_run (collision, [0 0.5 1]);
  assert_trace (result, 3, [10 20 10]);
  assert_trace (result, 4, [20 10 20]);

  rt = chain_model ('Time', [], 'Rate Transition', -1);
  rt.sample_times = [0 0; 0.25 0; 0 0];
  result = ob_run (rt, [0 0.1 0.25 0.49 0.5 0.99 1]);
  assert_trace (result, 3, [0 0 0.25 0.25 0.5 0.75 1]);
  % Unlike Unit Delay, an output-schedule Rate Transition samples immediately.
  inherited_rt = rmfield (rt, 'sample_times');
  result = ob_run (inherited_rt, [0 0.2 0.7]);
  assert_trace (result, 3, [0 0.2 0.7]);
  % Decimal clocks coincide despite binary rounding, including near zero
  % after cancellation against a negative simulation origin.
  decimal = rt; decimal.sample_times(2, :) = [0.1 0];
  result = ob_run (decimal, [-0.3 0 0.3]);
  assert_trace (result, 3, [-0.3 0 0.3]);
  tiny = rt; tiny.sample_times(2, :) = [1e-10 1e-16];
  result = ob_run (tiny, [0 5e-17 1e-16 2e-16]);
  assert_trace (result, 3, [-1 -1 1e-16 1e-16], 1e-25);
  tiny.sample_times(2, :) = [0.1 eps(1)];
  result = ob_run (tiny, [1 1+eps(1) 1.05]);
  assert_trace (result, 3, [-1 1+eps(1) 1+eps(1)]);
  offset_rt = rt; offset_rt.sample_times(2, :) = [0.5 0.1];
  result = ob_run (offset_rt, [2 2.05 2.1 2.4 2.6]);
  assert_trace (result, 3, [-1 -1 2.1 2.1 2.6]);

  % A destination RT samples a source RT's new value at a coincident hit.
  cascaded = ob_oscillator ();
  cascaded.blocks(1).type = 'Time'; cascaded.blocks(1).value = [];
  cascaded.blocks(2).type = cascaded.blocks(3).type = 'Rate Transition';
  cascaded.blocks(2).value = -1; cascaded.blocks(3).value = -2;
  cascaded.edges = [1 2; 2 3; 3 4];
  cascaded.sample_times = [0 0; 0.25 0; 0.5 0; 0 0];
  result = ob_run (cascaded, [0 0.3 0.5 0.8 1]);
  assert_trace (result, 4, [0 0 0.5 0.5 1]);
  cascaded.sample_times = [0 0; 0.1 0; 0.3 0; 0 0];
  result = ob_run (cascaded, [0 0.3 0.6]);
  assert_trace (result, 4, [0 0.3 0.6]);
  loop = rt; loop.edges = [2 2; 2 3];
  assert_error (@() ob_run (loop, [0 1]), 'algebraic loop');

  % Integration holds sampled states until the next hit, including stage end.
  held = ob_oscillator ();
  held.blocks(1).type = 'Time'; held.blocks(1).value = [];
  held.blocks(2).type = 'Rate Transition'; held.blocks(2).value = 0;
  held.blocks(3).type = 'Integrator'; held.blocks(3).value = 0;
  held.edges = [1 2; 2 3; 3 4];
  held.sample_times = [0 0; 0.25 0; 0 0; 0 0];
  for solver = {'rk4', 'ode45', 'ode15s'}
    options = struct ('solver', solver{1}, 'reltol', 1e-8, 'abstol', 1e-10);
    result = ob_run (held, [0 0.1 0.6 1], options);
    assert_trace (result, 4, [0 0 0.1125 0.375], 2e-6);
    dense = ob_run (held, 0:0.05:1, options);
    assert_close (result.values{end, 4}, dense.values{end, 4}, 2e-6);

    % A ZOH input knot at a rate hit is sampled from the right. Knots between
    % rate hits do not update the Rate Transition or add a transport delay.
    sampled = held;
    sampled.blocks(1).type = 'Inport'; sampled.blocks(1).value = 1;
    sampled.inputs = {ob_input_signal([0 0.25 0.35 0.75 1], [1; 3; 9; -2; 5])};
    result = ob_run (sampled, [0 0.2 0.6 1], options);
    assert_trace (result, 2, [1 1 9 5]);
    assert_trace (result, 4, [0 0.2 1.9 2.75], 2e-6);
  endfor

  % Matrix state and nested metadata retain both shape and timing.
  matrix = chain_model ('Constant', [1 2; 3 4], 'Discrete Integrator', zeros (2));
  matrix.sample_times = [0 0; 0.2 0.05; 0 0];
  result = ob_run (matrix, [0 0.1 0.05+3*0.2]);
  assert_close (result.values{end, 3}, 0.6*[1 2; 3 4], 1e-12);
  matrix.blocks(2).type = 'Rate Transition'; matrix.blocks(2).value = zeros (2);
  result = ob_run (matrix, [0 0.04 0.05 0.17]);
  assert_close (result.values{2, 3}, zeros (2), 1e-12);
  assert_close (result.values{3, 3}, [1 2; 3 4], 1e-12);
  assert_close (result.values{end, 3}, [1 2; 3 4], 1e-12);
  child = ob_subsystem_template ();
  child.blocks(2).type = 'Unit Delay'; child.blocks(2).value = -1;
  child.sample_times = [0 0; 0.25 0; 0 0];
  nested = ob_example (); nested.blocks(2).type = 'Subsystem'; nested.blocks(2).value = child;
  nested.sample_times = zeros (3, 2);
  result = ob_run (nested, times_from_zero ());
  assert_trace (result, 3, [-1 0 0.5 0.75]);
  assert_trace (result, [2 2], [-1 0 0.5 0.75]);
  flat = ob_compile_model (nested);
  internal = find (strcmp ({flat.blocks.type}, 'Unit Delay'));
  assert (isequal (flat.sample_times(internal, :), [0.25 0]));

  % Explicit zero metadata preserves inherited Unit Delay/Euler behavior.
  legacy = ob_example ();
  legacy.blocks(1).type = 'Constant'; legacy.blocks(1).value = 2;
  legacy.blocks(2).type = 'Discrete Integrator'; legacy.blocks(2).value = 0;
  result = ob_run (legacy, [0 0.2 0.7]);
  assert_trace (result, 3, [0 0.4 1.4]);
  legacy.sample_times = zeros (3, 2);
  zero = ob_run (legacy, [0 0.2 0.7]);
  assert (isequal (zero.values, result.values));

  invalid = rt; invalid.sample_times = zeros (2, 2);
  assert_fails (@() ob_validate_model (invalid));
  invalid = rt; invalid.sample_times(2, :) = [-1 0];
  assert_fails (@() ob_validate_model (invalid));
  invalid = rt; invalid.sample_times(2, :) = [0.5 -0.1];
  assert_fails (@() ob_validate_model (invalid));
  invalid = rt; invalid.sample_times(2, :) = [0.5 0.5];
  assert_fails (@() ob_validate_model (invalid));
  invalid = rt; invalid.sample_times(2, :) = [0 0.1];
  assert_fails (@() ob_validate_model (invalid));
  invalid = rt; invalid.sample_times(2, 1) = Inf;
  assert_fails (@() ob_validate_model (invalid));
  invalid = rt; invalid.sample_times(2, 1) = NaN;
  assert_fails (@() ob_validate_model (invalid));
  invalid = rt; invalid.sample_times(1, :) = [0.5 0];
  assert_fails (@() ob_validate_model (invalid));
  invalid = nested; invalid.sample_times(2, :) = [0.5 0];
  assert_fails (@() ob_validate_model (invalid));
  invalid = nested; invalid.blocks(2).value.sample_times(2, :) = [0.5 0.7];
  assert_fails (@() ob_validate_model (invalid));

  file = [tempname() '.mat'];
  unwind_protect
    ob_save_model (file, nested, [0 1.1 0.1]);
    [loaded, config] = ob_load_model (file);
    assert (isequal (loaded, nested));
    result = ob_run (loaded, times_from_zero ());
    assert_trace (result, 3, [-1 0 0.5 0.75]);
    assert (isequal (config, [0 1.1 0.1]));
  unwind_protect_cleanup
    if (exist (file, 'file')), unlink (file); endif
  end_unwind_protect
  disp ('Octave Blocks multirate tests passed');
endfunction

function times = times_from_zero ()
  times = [0 0.49 0.99 1.1];
endfunction

function model = chain_model (source_type, source_value, state_type, initial)
  model = ob_example ();
  model.blocks(1).type = source_type; model.blocks(1).value = source_value;
  model.blocks(2).type = state_type; model.blocks(2).value = initial;
endfunction

function assert_trace (result, path, expected, tolerance = 1e-11)
  assert_close (ob_scope_data(result, path)', expected, tolerance);
endfunction

function assert_close (actual, expected, tolerance)
  assert (isequal (size(actual), size(expected)));
  assert (all (isfinite(actual(:))));
  assert (max (abs(actual(:)-expected(:))) < tolerance);
endfunction

function assert_error (callback, fragment)
  caught = false;
  try
    callback ();
  catch err
    caught = ! isempty (strfind (err.message, fragment));
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
