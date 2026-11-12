function test_ob_solvers ()
  tight = struct ("solver", "ode45", "reltol", 1e-9, "abstol", 1e-11, "maxstep", 0.2);
  times = [0 0.5 4 10];
  result = ob_run (ob_oscillator (), times, tight);
  actual = cell2mat (result.values(:, 4));
  assert (max (abs (actual - cos (times(:)))) < 1e-7);
  assert (isequal (result.t, times(:)));
  assert (result.integration_steps > numel (times) - 1);
  assert (strcmp (result.solver, "ode45"));

  stiff = ob_example ();
  stiff.blocks(1).type = "Integrator"; stiff.blocks(1).value = 1;
  stiff.blocks(2).value = -1000;
  stiff.edges = [1 2; 2 1; 1 3];
  result = ob_run (stiff, [0 0.01 0.1], struct ("solver", "ode15s"));
  assert (abs (result.values{2, 3} - exp (-10)) < 1e-8);
  assert (abs (result.values{end, 3}) < 1e-8);

  for solver = {"ode45", "ode15s"}
    options = struct ("solver", solver{1});
    matrix = ob_example ();
    matrix.blocks(1).type = "Constant"; matrix.blocks(1).value = [1 2; 3 4];
    matrix.blocks(2).type = "Integrator"; matrix.blocks(2).value = zeros (2);
    result = ob_run (matrix, [0 1], options);
    assert (isequal (size (result.values{end, 3}), [2 2]));
    assert (max (abs (result.values{end, 3}(:) - [1; 3; 2; 4])) < 1e-6);

    step = ob_example ();
    step.blocks(1).type = "Step"; step.blocks(1).value = [0.35 0 1];
    step.blocks(2).type = "Integrator"; step.blocks(2).value = 0;
    result = ob_run (step, [0 0.3 0.6 1], options);
    assert (max (abs (cell2mat (result.values(:, 3))' - [0 0 0.25 0.65])) < 1e-6);
    step.blocks(1).value = [1 0 1];
    result = ob_run (step, 0:2, options);
    assert (max (abs (cell2mat (result.values(:, 3))' - [0 0 1])) < 1e-6);

    % Unit Delay updates at output ticks, never at adaptive internal stages.
    mixed = ob_oscillator ();
    mixed.blocks(1).type = "Constant"; mixed.blocks(1).value = 1;
    mixed.blocks(2).type = "Unit Delay"; mixed.blocks(2).value = 0;
    mixed.blocks(3).type = "Integrator"; mixed.blocks(3).value = 0;
    mixed.edges = [1 2; 2 3; 3 4];
    result = ob_run (mixed, 0:3, options);
    assert (max (abs (cell2mat (result.values(:, 4))' - [0 0 1 2])) < 1e-6);
  endfor

  invalid = ob_example ();
  invalid.blocks(1).type = "Constant"; invalid.blocks(1).value = [1; 2];
  invalid.blocks(2).type = "Integrator"; invalid.blocks(2).value = 0;
  assert_error (@() ob_run (invalid, 0:1, tight), "match its state shape");
  assert_error (@() ob_solver_options (struct ("solver", "unknown")), "solver must be");
  assert_error (@() ob_solver_options (struct ("reltol", 0)), "reltol must be");
  assert_error (@() ob_solver_options (struct ("maxstep", NaN)), "maxstep must be");
  assert_error (@() ob_solver_options (struct ("abstol", [1 2])), "abstol must be");
  assert_error (@() ob_solver_options (struct ("typo", 1)), "unknown option");
  disp ("Octave Blocks adaptive solver tests passed");
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
