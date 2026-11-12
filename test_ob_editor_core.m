function test_ob_editor_core ()
  model = ob_example ();
  model.edges = zeros (0, 2);
  model = ob_connect (model, 1, 2);
  model = ob_connect (model, 2, 3);
  assert (isequal (model.edges, [1 2; 2 3]));
  assert_error (@() ob_connect (model, 1, 2), "already connected");
  assert_error (@() ob_connect (model, 1, 3), "no free input port");
  assert_error (@() ob_connect (model, 2, 1), "no free input port");
  model = ob_disconnect (model, 2, 3);
  assert (isequal (ob_edges (model), [1 1 2 1]));
  assert_error (@() ob_disconnect (model, 2, 3), "not connected");

  model = ob_example ();
  model.blocks(1).type = "Constant";
  model.blocks(1).value = [1 2; 3 4];
  result = ob_run (model, 0:2);
  traces = ob_scope_data (result, 3);
  assert (isequal (traces, repmat ([2 6 4 8], 3, 1)));

  config = [1 3 0.5];
  file = [tempname() ".mat"];
  unwind_protect
    ob_save_model (file, model, config);
    [loaded_model, loaded_config] = ob_load_model (file);
    assert (isequal (loaded_model, model));
    assert (isequal (loaded_config, config));
    options = struct ("solver", "ode45", "reltol", 1e-8, "abstol", 1e-10, "maxstep", 0.25);
    ob_save_model (file, model, config, options);
    [loaded_model, loaded_config, loaded_options] = ob_load_model (file);
    assert (isequal (loaded_options, ob_solver_options (options)));
    invalid = model; invalid.edges = [NaN 2];
    assert_error (@() ob_save_model (file, invalid, config), "valid block indices");
    [loaded_model, loaded_config] = ob_load_model (file);
    assert (isequal (loaded_model, model)); % invalid save preserves existing file
    % Older files have no solver options; they must retain the RK4 default.
    save ("-mat7-binary", file, "model", "config");
    [loaded_model, loaded_config, loaded_options] = ob_load_model (file);
    assert (strcmp (loaded_options.solver, "rk4"));
    options.solver = "invalid";
    save ("-mat7-binary", file, "model", "config", "options");
    assert_error (@() ob_load_model (file), "solver must be");
    config = [0 1 0];
    save ("-mat7-binary", file, "model", "config");
    assert_error (@() ob_load_model (file), "settings must be finite");
  unwind_protect_cleanup
    if (exist (file, "file")), unlink (file); endif
  end_unwind_protect
  invalid = model; invalid.edges(end + 1, :) = invalid.edges(1, :);
  assert_error (@() ob_run (invalid, 0:2), "duplicate connections");
  invalid = model; invalid.blocks(2).type = "Unknown";
  assert_error (@() ob_validate_model (invalid), "unknown type");
  invalid = model; invalid.edges = zeros (0, 2);
  ob_validate_model (invalid); % disconnected diagrams can be saved
  assert_error (@() ob_run (invalid, 0:2), "expected 1 to 1");
  disp ("Octave Blocks editor core tests passed");
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
