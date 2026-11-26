function test_ob_editor_core ()
  test_path_cleanup = ob_test_setup ();
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
  check_wire_routes ();
  disp ("Octave Blocks editor core tests passed");
endfunction

function check_wire_routes ()
  % Editor wire routing is display geometry: orthogonal, port to port, and
  % no two signals share a segment or pass through a block in the demos.
  demos = {@ob_oscillator, @ob_subsystem_example, @ob_multirate_example, ...
           @ob_control_example, @ob_input_example, @ob_multioutput_example};
  for d = 1:numel (demos)
    model = demos{d} ();
    [routes, edges, centers, inputs, outputs] = editor_routes (model);
    [overlaps, through] = ob_wire_overlaps (routes, edges, centers);
    assert (isempty (overlaps), "%s: wires %s share a segment", ...
            func2str (demos{d}), mat2str (overlaps));
    assert (isempty (through), "%s: wire/block %s", func2str (demos{d}), mat2str (through));
    for k = 1:rows (edges)
      source = centers(edges(k,1),:); target = centers(edges(k,3),:);
      first = [source(1)+.105 source(2)+port_offset(edges(k,2),outputs(edges(k,1)))];
      last = [target(1)-.105 target(2)+port_offset(edges(k,4),inputs(edges(k,3)))];
      assert (norm (routes{k}(1,:) - first) < 1e-12 && norm (routes{k}(end,:) - last) < 1e-12);
      % The arrowhead needs a final horizontal run into the port.
      assert (routes{k}(end-1,2) == last(2) && routes{k}(end-1,1) < last(1));
    endfor
    % Deterministic: the same diagram always gets the same routes, and the
    % model itself carries no routing data.
    assert (isequal (editor_routes (model), routes));
    assert (isequal (model, demos{d} ()));
  endfor

  % Oscillator: the two feedback wires used to share their top segment.
  % Each now runs in its own channel, and Position -> Scope goes around the
  % Velocity block in a separate lane instead of under it.
  [routes, edges] = editor_routes (ob_oscillator ());
  feedback = find (edges(:,1) == 2 & edges(:,3) == 1);
  gain = find (edges(:,1) == 3 & edges(:,3) == 2);
  scope = find (edges(:,1) == 1 & edges(:,3) == 4);
  assert (rows (routes{feedback}) == 6 && rows (routes{gain}) == 6);
  assert (routes{feedback}(3,2) != routes{gain}(3,2));
  assert (all (routes{feedback}(3:4,2) > .652) && all (routes{scope}(3:4,2) > .652));
  assert (abs (routes{feedback}(3,2) - routes{scope}(3,2)) >= .024 - 1e-12);

  % Moving a block reroutes its wires around the others (as during a drag);
  % routing everything again (as on the drop) keeps the separation.
  [routes, edges, centers, inputs, outputs] = editor_routes (ob_oscillator ());
  centers(3,:) += [.08 .1];
  moved = find (any (edges(:,[1 3]) == 3, 2))';
  partial = ob_route_wires (centers, edges, inputs, outputs, routes, moved);
  unchanged = setdiff (1:rows (edges), moved);
  assert (isequal (partial(unchanged), routes(unchanged)));
  assert (isempty (ob_wire_overlaps (partial, edges)));
  [overlaps, through] = ob_wire_overlaps (ob_route_wires (centers, edges, inputs, outputs), edges, centers);
  assert (isempty (overlaps) && isempty (through));

  % A fan-out branch may share its trunk; a different signal may not.
  routes = {[0 0; .5 0]; [0 0; .25 0; .25 .5; .5 .5]; [.1 0; .4 0]};
  edges = [1 1 2 1; 1 1 3 1; 4 1 5 1];
  assert (isequal (ob_wire_overlaps (routes, edges), [1 3; 2 3]));
  assert (isempty (ob_route_wires (zeros (0, 2), zeros (0, 4), [], [])));
endfunction

function [routes, edges, centers, inputs, outputs] = editor_routes (model)
  % The editor's routing inputs (ob_draw): canonical edges, block centers,
  % and drawn port counts, where Function blocks show their used inputs.
  edges = ob_edges (model);
  count = numel (model.blocks);
  inputs = zeros (1, count); outputs = zeros (1, count);
  for id = 1:count
    [inputs(id), outputs(id)] = ob_block_ports (model.blocks(id));
    if (isinf (inputs(id))), inputs(id) = max (1, max ([0; edges(edges(:,3)==id,4)])); endif
  endfor
  centers = [[model.blocks.x]' [model.blocks.y]'];
  routes = ob_route_wires (centers, edges, inputs, outputs);
endfunction

function offset = port_offset (port, count)
  % The editor's port placement.
  if (count <= 1), offset = 0; else offset = 0.036 - 0.072 * (port - 1) / (count - 1); endif
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
