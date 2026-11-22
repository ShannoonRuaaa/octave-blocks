function test_ob_subsystems ()
  model = ob_subsystem_example ();
  for solver = {"rk4", "ode45", "ode15s"}
    result = ob_run (model, 0:0.1:1, struct ("solver", solver{1}));
    assert (abs (result.values{end, 4} - cos (1)) < 1e-5);
    nested = ob_scope_data (result, [1 2]);
    assert (abs (nested(end) - cos (1)) < 1e-5);
  endfor
  % Nest a second subsystem around the first state. State must stay global.
  child = ob_subsystem_template ();
  child.blocks(2) = model.blocks(1);
  model.blocks(1).value = child;
  result = ob_run (model, 0:0.1:1);
  assert (abs (result.values{end, 4} - cos (1)) < 1e-6);
  assert (abs (ob_scope_data(result, [1 2 2])(end) - cos (1)) < 1e-6);
  discrete = ob_subsystem_example ();
  for id = 1:2
    discrete.blocks(id).value.blocks(2).type = "Unit Delay";
  endfor
  result = ob_run (discrete, 0:3);
  assert (isequal (cell2mat(result.values(:, 4))', [1 0 -1 0]));

  % One subsystem exposes two independent outputs in explicit port order.
  child = ob_subsystem_template ();
  child.blocks(2).value = 2;
  child.blocks(4) = child.blocks(3); child.blocks(4).value = 2;
  child.blocks(4).name = "Out2"; child.blocks(4).y = 0.3;
  child.edges = [1 2; 2 3; 1 4];
  multi = ob_example ();
  multi.blocks(2).type = "Subsystem"; multi.blocks(2).value = child;
  multi.blocks(4) = multi.blocks(3);
  multi.edges = [1 1 2 1; 2 2 4 1; 2 1 3 1];
  result = ob_run (multi, 0:2);
  assert (isequal (cell2mat(result.values(:, 3))', [0 2 4]));
  assert (isequal (cell2mat(result.values(:, 4))', [0 1 2]));
  assert (isequal (ob_scope_data(result, 2, 2)', [0 1 2]));

  % Both boundary directions preserve explicit port identities, even when
  % connection rows are deliberately shuffled and the body is noncommutative.
  child.blocks(2).type = "Inport"; child.blocks(2).value = 2;
  child.blocks(3).type = "Function"; child.blocks(3).value = []; child.blocks(3).name = "power";
  child.blocks(4).type = "Outport"; child.blocks(4).value = 1;
  child.blocks(5) = child.blocks(4); child.blocks(5).value = 2;
  child.edges = [2 1 3 2; 1 1 3 1; 3 1 4 1; 1 1 5 1];
  two = ob_oscillator ();
  two.blocks(1).type = "Constant"; two.blocks(1).value = 2;
  two.blocks(2).type = "Constant"; two.blocks(2).value = 3;
  two.blocks(3).type = "Subsystem"; two.blocks(3).value = child;
  two.blocks(5) = two.blocks(4);
  two.edges = [3 2 5 1; 2 1 3 2; 3 1 4 1; 1 1 3 1];
  result = ob_run (two, 0:1);
  assert (result.values{end, 4} == 8 && result.values{end, 5} == 2);

  % The same signal can branch to distinct ports on the same target.
  branch = ob_example ();
  branch.blocks(2).type = "Sum";
  branch.edges = zeros (0, 4);
  branch = ob_connect (branch, 1, 2, 1, 1);
  branch = ob_connect (branch, 1, 2, 1, 2);
  branch = ob_connect (branch, 2, 3, 1, 1);
  assert (ob_run(branch, 0:2).values{end, 3} == 4);
  assert_error (@() ob_disconnect (branch, 1, 2), "specify ports");
  branch = ob_disconnect (branch, 1, 2, 1, 1);
  assert (any (all (branch.edges == [1 1 2 2], 2)));

  edited = ob_model_at (model, [1 2]);
  edited.blocks(2).value = 3;
  changed = ob_set_model_at (model, [1; 2], edited);
  assert (ob_model_at(changed, [1; 2]).blocks(2).value == 3);
  assert (isequal (ob_model_at(model, [1 2]).blocks(2).value, 1));

  % Explicit input indices, not row order, determine Function argument order.
  ordered = ob_example ();
  ordered.blocks(1).type = "Constant"; ordered.blocks(1).value = 2;
  ordered.blocks(2).type = "Function"; ordered.blocks(2).name = "power";
  ordered.blocks(4) = ordered.blocks(1); ordered.blocks(4).value = 3;
  ordered.edges = [4 1 2 2; 2 1 3 1; 1 1 2 1];
  result = ob_run (ordered, 0:1);
  assert (result.values{end, 3} == 8);
  ordered = ob_disconnect (ordered, 1, 2, 1, 1);
  assert (any (all (ordered.edges == [4 1 2 2], 2)));
  ordered = ob_connect (ordered, 1, 2, 1, 1);
  assert (ob_run(ordered, 0:1).values{end, 3} == 8);

  % A virtual boundary does not hide an underdetermined identity constraint.
  loop = ob_example ();
  loop.blocks(2).type = "Subsystem"; loop.blocks(2).value = ob_subsystem_template ();
  loop.edges = [2 2; 2 3];
  assert_error (@() ob_run (loop, 0:1), "algebraic loop");

  invalid = multi; invalid.edges(end, 2) = 3;
  assert_error (@() ob_validate_model (invalid), "output port 3 does not exist");
  invalid = multi; invalid.blocks(2).value.blocks(4).value = 1;
  assert_error (@() ob_validate_model (invalid), "Outport numbers must be unique");
  invalid = multi; invalid.edges(end + 1, :) = [1 1 3 1];
  assert_error (@() ob_validate_model (invalid), "only one connection");
  file = [tempname() ".mat"];
  unwind_protect
    options = struct ("solver", "ode45");
    ob_save_model (file, model, [0 1 0.1], options);
    [loaded, config, loaded_options] = ob_load_model (file);
    assert (isequal (loaded, model));
    assert (strcmp (loaded_options.solver, "ode45"));
    result = ob_run (loaded, ob_time_grid(config(1), config(2), config(3)), loaded_options);
    assert (abs (result.values{end, 4} - cos (1)) < 1e-5);
  unwind_protect_cleanup
    if (exist (file, "file")), unlink (file); endif
  end_unwind_protect
  disp ("Octave Blocks subsystem tests passed");
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
