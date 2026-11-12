function test_ob_runtime ()
  % Streaming uses the same requested schedule, including hidden rate hits.
  grids = {[0 0.1 0.37 0.5 1], [-0.3 -0.1 0 0.3], [0 0.3 0.6 1]};
  delay = ob_example ();
  delay.blocks(2).type = 'Unit Delay'; delay.blocks(2).value = -1;
  explicit = delay; explicit.sample_times = [0 0; 0.1 0; 0 0];
  euler = explicit; euler.blocks(2).type = 'Discrete Integrator';
  euler.sample_times(2,:) = [0.2 0.05];
  models = {ob_example(), delay, explicit, euler, ob_multirate_example(), ...
            ob_subsystem_example(), ob_input_example(), ob_control_example()};
  for solver = {'rk4', 'ode45', 'ode15s'}
    options = struct ('solver', solver{1}, 'reltol', 1e-8, 'abstol', 1e-10);
    for model = models
      for grid = grids
        times = grid{1};
        reference = ob_run (model{1}, times, options);
        runtime = ob_runtime_init (model{1}, times(1), options);
        assert (isequal (runtime.current, reference.flat_values(1,:)));
        for sample = 2:numel (times)
          runtime = ob_runtime_step (runtime, times(sample));
          assert (isequal (runtime.current, reference.flat_values(sample,:)));
          assert (isequal (ob_runtime_outputs(runtime), reference.values(sample,:)));
        endfor
        assert (isequal (runtime.sample_hits, reference.sample_hits));
        assert (runtime.integration_steps == reference.integration_steps);
      endfor
    endfor
  endfor

  % Context copies fork execution rather than sharing clocks or pending state.
  runtime = ob_runtime_init (ob_multirate_example ());
  runtime = ob_runtime_step (runtime, 0.1);
  saved = runtime;
  first = ob_runtime_step (runtime, 1);
  second = ob_runtime_step (runtime, 0.5);
  assert (isequal (runtime, saved));
  assert (abs (ob_runtime_outputs(first, 4) - 0.375) < 1e-12);
  assert (abs (ob_runtime_outputs(second, 4) - 0.0625) < 1e-12);
  assert (first.time == 1 && second.time == 0.5);
  assert (numel (first.sample_hits{2}) == 5 && numel (second.sample_hits{2}) == 3);

  % Checkpoints retain partial clocks, pending captures, and matrix state.
  euler.blocks(1).type = 'Constant'; euler.blocks(1).value = [1 2;3 4];
  euler.blocks(2).value = zeros (2);
  runtime = ob_runtime_init (euler, -0.3);
  runtime = ob_runtime_step (runtime, 0.07);
  expected = ob_runtime_step (runtime, 0.9);
  file = [tempname() '.mat'];
  unwind_protect
    save ('-mat7-binary', file, 'runtime');
    restored = load (file);
    resumed = ob_runtime_step (restored.runtime, 0.9);
    assert (isequal (resumed, expected));
  unwind_protect_cleanup
    if (exist (file, 'file')), unlink (file); endif
  end_unwind_protect

  % Read numbered subsystem outputs and nested signals without executing again.
  child = ob_subsystem_template ();
  child.blocks(2).type = 'Inport'; child.blocks(2).value = 2;
  child.blocks(3).type = 'Sum'; child.blocks(3).value = [];
  child.blocks(4) = child.blocks(1); child.blocks(4).type = 'Outport'; child.blocks(4).value = 1;
  child.blocks(5) = child.blocks(4); child.blocks(5).value = 2;
  child.edges = [1 1 3 1; 2 1 3 2; 3 1 4 1; 2 1 5 1];
  multi = ob_oscillator ();
  multi.blocks(1).type = multi.blocks(2).type = 'Constant';
  multi.blocks(1).value = 2; multi.blocks(2).value = 3;
  multi.blocks(3).type = 'Subsystem'; multi.blocks(3).value = child;
  multi.edges = [1 1 3 1; 2 1 3 2; 3 2 4 1];
  runtime = ob_runtime_init (multi);
  assert (ob_runtime_outputs(runtime, 3, 1) == 5);
  assert (ob_runtime_outputs(runtime, 3, 2) == 3);
  assert (ob_runtime_outputs(runtime, [3;3]) == 5);
  before = runtime; ob_runtime_outputs (runtime); ob_runtime_outputs (runtime, 4);
  assert (isequal (before, runtime));
  assert_error (@() ob_runtime_outputs(runtime, 3, 3), 'port does not exist');
  assert_error (@() ob_runtime_outputs(runtime, [3 99]), 'path does not exist');
  assert_error (@() ob_runtime_outputs(runtime, [-1 2]), 'positive integer');
  assert_error (@() ob_runtime_outputs(runtime, 3, NaN), 'positive integer');
  assert_error (@() ob_runtime_outputs(runtime, ''), 'positive integer');
  assert_error (@() ob_runtime_outputs(runtime, {}), 'positive integer');
  assert_error (@() ob_runtime_outputs(runtime, [], 2), 'select a block path');

  % Failure after several hidden hits must not commit any partial progress.
  failing = ob_oscillator ();
  failing.blocks(1).type = 'Inport'; failing.blocks(1).value = 1;
  failing.blocks(2).type = 'Function'; failing.blocks(2).name = 'sqrt'; failing.blocks(2).value = [];
  failing.blocks(3).type = 'Unit Delay'; failing.blocks(3).value = 0;
  failing.edges = [1 2;2 3;3 4];
  failing.inputs = {ob_input_signal([0 0.2 0.4], [0;1;-1])};
  failing.sample_times = [0 0;0 0;0.1 0;0 0];
  runtime = ob_runtime_step (ob_runtime_init(failing), 0.25);
  saved = runtime;
  caught = false;
  try
    runtime = ob_runtime_step (runtime, 0.5);
  catch err
    caught = ! isempty (strfind (err.message, 'finite, real'));
  end_try_catch
  assert (caught && isequal (runtime, saved));
  retry = ob_runtime_step (runtime, 0.3);
  assert (retry.time == 0.3 && ob_runtime_outputs(retry, 4) == 1);

  failing.blocks(3).type = 'Integrator'; failing.sample_times(3,:) = [0 0];
  runtime = ob_runtime_step (ob_runtime_init(failing), 0.25);
  saved = runtime; caught = false;
  try
    runtime = ob_runtime_step (runtime, 0.5);
  catch err
    caught = ! isempty (strfind (err.message, 'derivative must be finite'));
  end_try_catch
  assert (caught && isequal (runtime, saved));

  for value = {NaN, Inf, 1i, [], [0 1], 'time'}
    assert_error (@() ob_runtime_init(ob_example(), value{1}), 'finite real numeric scalar');
  endfor
  runtime = ob_runtime_init (ob_example ()); saved = runtime;
  for value = {0, -1, NaN, Inf, 1i, [], [0 1], 'time'}
    assert_error (@() ob_runtime_step(runtime, value{1}), 'greater than the current time');
    assert (isequal (runtime, saved));
  endfor
  assert_error (@() ob_runtime_step(struct(), 1), 'context returned');
  assert_error (@() ob_runtime_outputs(struct()), 'context returned');
  corrupt = rmfield (runtime, 'states');
  assert_error (@() ob_runtime_step(corrupt, 1), 'context returned');
  blank.blocks = struct ('type',{},'value',{},'name',{},'x',{},'y',{});
  blank.edges = zeros (0,2);
  runtime = ob_runtime_step (ob_runtime_init(blank), 1);
  assert (runtime.time == 1 && isempty (ob_runtime_outputs(runtime)));
  result = ob_run (blank, [0 1]);
  assert (isequal (size(result.values), [2 0]) && isequal (result.t, [0;1]));
  runtime = ob_runtime_init (blank, -realmax);
  assert_error (@() ob_runtime_step(runtime, realmax), 'greater than the current time');
  runtime = ob_runtime_init (blank, 2^53);
  assert_error (@() ob_runtime_step(runtime, uint64(2^53)+uint64(1)), 'greater than the current time');
  advanced = ob_runtime_step (runtime, uint64(2^53)+uint64(2));
  assert (advanced.time == 2^53+2 && runtime.time == 2^53);

  % Regression: ode45 can return one ulp beyond the requested endpoint for
  % this held derivative and initial state. Never sample the right-hand jump.
  endpoint = ob_input_example ();
  endpoint.blocks(2).value = -0.087499999999999967;
  endpoint.inputs = {ob_input_signal([0.2 0.3], [0.2;1e8])};
  for solver = {'rk4', 'ode45', 'ode15s'}
    result = ob_run (endpoint, [0.2 0.3], struct('solver',solver{1},'reltol',1e-8,'abstol',1e-10));
    assert (result.values{end,1} == 1e8);
    assert (abs (result.values{end,3} + 0.0675) < 1e-9);
  endfor
  disp ('Octave Blocks resumable runtime tests passed');
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
