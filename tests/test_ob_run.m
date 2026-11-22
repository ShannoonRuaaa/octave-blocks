function test_ob_run ()
  grid = ob_time_grid (0, 1, 0.3);
  assert (numel (grid) == 5 && max (abs (grid - [0 0.3 0.6 0.9 1])) < 1e-12);
  assert (grid(end) == 1);
  assert (isequal (ob_time_grid (2, 3, 2), [2 3]));
  assert (strcmp (ob_value_text (2), "2"));
  assert (strcmp (ob_value_text ("2"), "2"));
  model = ob_example ();
  endpoint_result = ob_run (model, grid);
  assert (endpoint_result.t(end) == 1);
  assert (abs (endpoint_result.values{end, 3} - 2) < 1e-12);
  result = ob_run (model, 0:2);
  assert (isequal (cell2mat (result.values(:, 3))', [0 2 4]));

  model.blocks(2).type = "Function";
  model.blocks(2).name = "sin";
  result = ob_run (model, [0 pi/2]);
  assert (abs (result.values{2, 3} - 1) < 1e-12);
  model.blocks(2).type = "Gain";
  model.blocks(2).name = "Gain";

  model.blocks(1).type = "Step";
  model.blocks(1).value = [1 0 1];
  result = ob_run (model, 0:2);
  assert (isequal (cell2mat (result.values(:, 3))', [0 2 2]));

  model.blocks(1).type = "Constant";
  model.blocks(1).value = 1;
  model.blocks(2).type = "Discrete Integrator";
  model.blocks(2).value = 0;
  result = ob_run (model, 0:2);
  assert (isequal (cell2mat (result.values(:, 3))', [0 1 2]));

  % Integrating a Step must not leak its endpoint value into the prior interval.
  model.blocks(1).type = "Step";
  model.blocks(1).value = [0.35 0 1];
  model.blocks(2).type = "Integrator";
  result = ob_run (model, [0 0.3 0.6 1]);
  assert (max (abs (cell2mat (result.values(:, 3))' - [0 0 0.25 0.65])) < 1e-12);
  model.blocks(1).value = [1 0 1];
  result = ob_run (model, 0:2);
  assert (max (abs (cell2mat (result.values(:, 3))' - [0 0 1])) < 1e-12);
  model.blocks(1).type = "Constant";
  model.blocks(1).value = 1;

  model.blocks(2).type = "Sum";
  model.blocks(2).value = [];
  model.blocks(3).type = "Unit Delay";
  model.blocks(3).value = 0;
  model.edges = [1 2; 3 2; 2 3];
  result = ob_run (model, 0:2);
  assert (isequal (cell2mat (result.values(:, 2))', [1 2 3]));

  model.blocks(3).type = "Scope";
  try
    ob_run (model, 0:2);
    error ("test_ob_run: expected algebraic-loop error");
  catch err
    assert (! isempty (strfind (err.message, "algebraic loop")));
  end_try_catch

  % x' = v, v' = -x; a basic continuous feedback model.
  oscillator = ob_oscillator ();
  result = ob_run (oscillator, 0:0.1:1);
  assert (abs (result.values{end, 4} - cos (1)) < 1e-6);
  result = ob_run (ob_function_example (), [0 pi/2]);
  assert (abs (result.values{end, 3} - exp (-pi/10)) < 1e-12);

  vector_model = ob_example ();
  vector_model.blocks(1).type = "Constant";
  vector_model.blocks(1).value = [1; 2];
  vector_model.blocks(2).type = "Integrator";
  vector_model.blocks(2).value = zeros (2, 1);
  result = ob_run (vector_model, [0 0.3 1]);
  assert (max (abs (result.values{end, 3} - [1; 2])) < 1e-12);

  % Matrix Product must preserve connection order (A*B differs from B*A).
  matrix_model = ob_oscillator ();
  matrix_model.blocks(1).type = "Constant";
  matrix_model.blocks(1).value = [1 2; 0 1];
  matrix_model.blocks(2).type = "Constant";
  matrix_model.blocks(2).value = [2 0; 3 1];
  matrix_model.blocks(3).type = "Product";
  matrix_model.edges = [1 3; 2 3; 3 4];
  result = ob_run (matrix_model, [0 1]);
  assert (isequal (result.values{end, 4}, [8 2; 3 1]));
  disp ("Octave Blocks engine tests passed");
endfunction
