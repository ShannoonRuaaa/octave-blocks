function test_ob_continuous_controls ()
  % Continuous gates must observe crossings between caller output requests.
  grid = [0 .4 .8 1.4 1.8];
  for solver = {'rk4','ode45','ode15s'}
    options = gate_options (solver{1});
    child = integrator_body (3);
    model = pulse_model (child, 2);
    result = ob_run (model, grid, options);
    assert_close (ob_scope_data(result,8)', [-9 3.4 4 4.4 5]);
    assert (isequal (result.t, grid'));

    % State reset and disabled output reset remain independent policies.
    model.blocks(7).value.execution.states = 'reset';
    result = ob_run (model, grid, options);
    assert_close (ob_scope_data(result,8)', [-9 3.4 4 3.4 4]);
    model.blocks(7).value.execution.outputs = 'reset';
    result = ob_run (model, grid, options);
    assert_close (ob_scope_data(result,8)', [-9 3.4 -9 3.4 -9]);

    % A child without continuous state must still refresh its feedthrough
    % output at parent ODE stages. The references are independent integrals.
    feedthrough = feedthrough_integral_model ('reset');
    result = ob_run (feedthrough, [0 1], options);
    assert_close (ob_scope_data(result,10)', [0 .225]);
    feedthrough.blocks(7).value.execution.outputs = 'held';
    result = ob_run (feedthrough, [0 1], options);
    assert_close (ob_scope_data(result,10)', [0 .435]);

    % Every control direction must update trigger history, even when only
    % rising or falling events execute the body. Data is evaluated at the root.
    trigger_grid = [0 .3 .8 1.3 1.8];
    modes = {'rising','falling','either'};
    % The default prior control is zero, while sin(-.4*pi) is negative:
    % falling/either therefore execute once at startup, just as sampled gates.
    execution_times = {[.2 1.2],[0 .7 1.7],[0 .2 .7 1.2 1.7]};
    expected = {[-9 .04 .04 1.44 1.44],[0 0 .49 .49 2.89],[0 .04 .49 1.44 2.89]};
    for index = 1:numel (modes)
      triggered = pulse_model (squared_body(modes{index}), []);
      triggered.blocks(1).type = 'Time';
      result = ob_run (triggered, trigger_grid, options);
      assert_close (ob_scope_data(result,8)', expected{index});
      state = conditional_snapshot (result, 7);
      assert_close (state.executions, execution_times{index}, 2e-8);
      sparse = ob_run (triggered, [0 1.8], options);
      assert_close (ob_scope_data(sparse,8)', [expected{index}(1) expected{index}(end)]);
      assert_close (conditional_snapshot(sparse,7).executions, execution_times{index}, 2e-8);
      % An explicitly matching negative initial control suppresses only that
      % startup edge; all hidden physical crossings must still execute.
      prearmed = triggered; prearmed.blocks(7).value.execution.initial_control = -1;
      sparse = ob_run (prearmed,[0 1.8],options);
      assert_close (ob_scope_data(sparse,8)', [-9 expected{index}(end)]);
      later_times = execution_times{index}(execution_times{index}>0);
      assert_close (conditional_snapshot(sparse,7).executions,later_times,2e-8);
      % A triggered Unit Delay commits the previous event's data exactly
      % once. Trial/root observations and output requests are not executions.
      delayed = prearmed;
      delayed.blocks(7).value.blocks(2).type = 'Unit Delay';
      delayed.blocks(7).value.blocks(2).value = -7;
      delayed.blocks(7).value.edges = [1 1 2 1;2 1 3 1];
      sparse = ob_run (delayed,[0 1.8],options);
      assert_close (ob_scope_data(sparse,8)',[-9 later_times(end-1)]);
      state = conditional_snapshot (sparse,7);
      assert_close (state.executions,later_times,2e-8);
      assert_close (state.child.sample_hits{2},later_times,2e-8);
    endfor

    % An exact zero at an output endpoint must not dispatch again when its
    % immediately following positive side is observed on the next advance.
    endpoint = linear_trigger ('rising', 1, -.5);
    result = ob_run (endpoint, [0 .5 1], options);
    assert_close (ob_scope_data(result,8)', [-9 .25 .25]);
    assert_close (conditional_snapshot(result,7).executions, .5, 2e-8);
    endpoint = linear_trigger ('falling', -1, .5);
    result = ob_run (endpoint, [0 .5 1], options);
    assert_close (ob_scope_data(result,8)', [-9 .25 .25]);
    assert_close (conditional_snapshot(result,7).executions, .5, 2e-8);

    % A zero plateau that departs toward positive values has one rising
    % execution, including when the requested stop initially ends at the zero.
    plateau = linear_trigger ('rising', 1, -.5);
    plateau.blocks(6).type = 'Function'; plateau.blocks(6).name = 'max';
    plateau = append_block (plateau, 'Constant', 0);
    plateau.edges(end+1,:) = [9 1 6 2];
    result = ob_run (plateau, [0 .5 .75 1], options);
    assert_close (ob_scope_data(result,8)', [-9 -9 .25 .25]);
    assert_close (conditional_snapshot(result,7).executions, .5, 2e-8);

    % A prolonged zero plateau must not be rearmed by an unrelated output
    % request with the same control sign. Both grids describe one rising edge.
    latch = ob_subsystem_template (); latch.blocks(2).value = 1;
    latch.execution = execution ('rising',{-9});
    held_zero = pulse_model (latch,[]); held_zero.blocks(1).type = 'Time';
    held_zero.blocks(6).type = 'Inport'; held_zero.blocks(6).value = 1;
    held_zero.edges(held_zero.edges(:,3)==6,:) = [];
    held_zero.inputs = {ob_input_signal([0 .5 1.5],[-1;0;1])};
    for requested = {[0 .5 1.5 2],[0 .5 1 1.5 2]}
      result = ob_run (held_zero,requested{1},options);
      assert_close (ob_scope_data(result,8)',[-9 .5*ones(1,numel(requested{1})-1)]);
      assert_close (conditional_snapshot(result,7).executions,.5,2e-8);
    endfor

    % Logical scalar controls are valid conditional signals even though the
    % nonlinear numeric primitives have a narrower numeric-input contract.
    logical_gate = pulse_model (latch,[]); logical_gate.blocks(1).type = 'Time';
    logical_gate.blocks(3).value = -.5; logical_gate.blocks(5).value = 1;
    logical_gate.blocks(6).name = 'gt';
    logical_gate = append_block (logical_gate,'Constant',0);
    logical_gate.edges(end+1,:) = [9 1 6 2];
    result = ob_run (logical_gate,[0 1],options);
    assert (islogical(result.values{1,6}) && islogical(result.values{end,6}));
    assert_close (ob_scope_data(result,8)',[-9 .5]);
    assert_close (conditional_snapshot(result,7).executions,.5,2e-8);
    logical_gate.blocks(5).value = [1;1];
    assert_error (@() ob_runtime_init(logical_gate,0,options),'scalar');

    % Gate-only activation/deactivation must not capture or commit the
    % inherited discrete states inside the enabled child or in its parent.
    clocks = pulse_model (mixed_body (), 2);
    clocks = append_root_clocks (clocks);
    result = ob_run (clocks, [0 1], options);
    assert_close (ob_scope_data(result,8)', [-9 1]);
    assert_close (ob_scope_data(result,10)', [-9 .75]);
    assert_close (ob_scope_data(result,12)', [-5 0]);
    assert_close (ob_scope_data(result,14)', [0 1]);
    assert_close (result.sample_hits{flat_id(result,9)}, 0:.25:1, 1e-12);
    assert_close (result.sample_hits{flat_id(result,11)}, [0 1], 1e-12);
    assert_close (result.sample_hits{flat_id(result,13)}, [0 1], 1e-12);
    state = conditional_snapshot (result, 7);
    assert (isempty(state.child.sample_hits{5}) && isempty(state.child.sample_hits{8}));
    assert_close (state.outputs{2}, -7);
    assert_close (state.outputs{3}, 0);

    % Inner explicit clocks stay on the global root phase through inactive
    % intervals. They must not acquire an activation-relative origin.
    inner = pulse_model (mixed_body (), 2);
    inner.blocks(7).value.sample_times = zeros (9,2);
    inner.blocks(7).value.sample_times(5,:) = [.125 0];
    result = ob_run (inner, [0 1.8], options);
    state = conditional_snapshot (result, 7);
    assert_close (state.child.sample_hits{5}, [.25 .375 .5 .625 1.25 1.375 1.5 1.625], 2e-8);
    assert (isempty(state.child.sample_hits{8}));
    assert_close (state.outputs{2}, 1.5);
    assert_close (state.outputs{3}, 0);

    % Known discontinuities dispatch continuous controls as well as smooth
    % roots, whereas the legacy sampled mode retains its output clock.
    source = pulse_model (integrator_body(0), 1);
    source.blocks(6).type = 'Step'; source.blocks(6).value = [.2 -1 1];
    source.edges(source.edges(:,3)==6,:) = [];
    result = ob_run (source, [0 1], options);
    assert_close (ob_scope_data(result,8)', [-9 .8]);
    source.blocks(6).type = 'Inport'; source.blocks(6).value = 1;
    source.inputs = {ob_input_signal([0 .2 .7],[-1;1;-1])};
    result = ob_run (source, [0 1], options);
    assert_close (ob_scope_data(result,8)', [-9 .5]);
    source.blocks(7).value.execution.control = 'sampled';
    result = ob_run (source, [0 1], options);
    assert_close (ob_scope_data(result,8)', [-9 -9]);

    % A localized numeric primitive may change the gate discontinuously at
    % the same physical time. The outgoing Switch value must reach the gate
    % before the remainder is integrated, in both enable directions.
    for increasing = [true false]
      bridge = switch_enabled_model (increasing);
      result = ob_run (bridge,[0 1],options);
      if (increasing), wanted = [-9 .65]; else wanted = [0 .35]; endif
      assert_close (ob_scope_data(result,8)',wanted);
    endfor
    bridge = append_root_clocks (switch_enabled_model(true));
    result = ob_run (bridge,[0 1],options);
    assert_close (ob_scope_data(result,8)',[-9 .65]);
    assert_close (ob_scope_data(result,10)',[-9 .75]);
    assert_close (ob_scope_data(result,12)',[-5 0]);
    assert_close (ob_scope_data(result,14)',[0 1]);
    assert_close (result.sample_hits{flat_id(result,9)},0:.25:1,1e-12);
    assert_close (result.sample_hits{flat_id(result,11)},[0 1],1e-12);
    assert_close (result.sample_hits{flat_id(result,13)},[0 1],1e-12);

    % Public Switch equality keeps the enable high at both exact roots. An
    % inner explicit clock coincident with activation must execute once after
    % initialization; the root peer clocks retain their own schedules.
    [coincident, peer_ids] = append_root_clocks (coincident_switch_model ());
    result = ob_run (coincident,[0 1],options);
    assert_close (ob_scope_data(result,8)',[-9 .5]);
    state = conditional_snapshot (result,7);
    assert_close (state.child.sample_hits{5},[.25 .5 .75],2e-8);
    assert_close (state.outputs{2},.5);
    assert (isempty(state.child.sample_hits{8}));
    assert_close (result.sample_hits{flat_id(result,peer_ids(1))},0:.25:1,1e-12);
    assert_close (result.sample_hits{flat_id(result,peer_ids(3))},[0 1],1e-12);
    assert_close (ob_scope_data(result,peer_ids(1)+1)',[-9 .75]);
    assert_close (ob_scope_data(result,peer_ids(3)+1)',[0 1]);

    % Inactive ancestors suppress all descendant integration, including an
    % inner continuous gate whose local control remains positive throughout.
    nested = pulse_model (nested_body (), 1);
    result = ob_run (nested, [0 1], options);
    assert_close (ob_scope_data(result,8)', [-9 .5]);
    values = ob_signal_values (result, [7 3 2]);
    assert_close (values{end}, .5);
    fprintf ('Continuous control tests passed for %s\n',solver{1});
  endfor

  options = gate_options ('rk4');
  model = pulse_model (integrator_body(3), 2);
  runtime = ob_runtime_step (ob_runtime_init(model,0,options), .4);
  saved = runtime;
  later = ob_runtime_step (runtime, 1.4);
  earlier = ob_runtime_step (runtime, .6);
  assert (isequaln(runtime,saved));
  assert_close (ob_runtime_outputs(later,8), 4.4);
  assert_close (ob_runtime_outputs(earlier,8), 3.8);
  file = [tempname() '.mat'];
  unwind_protect
    save ('-mat7-binary', file, 'runtime');
    restored = load (file);
    assert (isequaln(ob_runtime_step(restored.runtime,1.4),later));
  unwind_protect_cleanup
    if (exist(file,'file')), unlink(file); endif
  end_unwind_protect

  % Failure after earlier gate events and clock hits cannot commit partial
  % child state, captures, execution history, or accepted event history.
  failing = append_block (model, 'Gain', -1);
  failing = append_block (failing, 'Constant', .9);
  failing = append_block (failing, 'Sum', []);
  failing = append_block (failing, 'Function', []); failing.blocks(12).name = 'log';
  failing = append_block (failing, 'Saturation', [-100 100]);
  failing = append_block (failing, 'Unit Delay', -9);
  failing = append_block (failing, 'Scope', []);
  failing.edges = [failing.edges;2 1 9 1;10 1 11 1;9 1 11 2;11 1 12 1;12 1 13 1;2 1 14 1;14 1 15 1];
  failing.sample_times = zeros (15,2); failing.sample_times(14,:) = [.125 0];
  runtime = ob_runtime_init (failing,0,options); saved = runtime; caught = false;
  try runtime = ob_runtime_step (runtime,1); catch err
    caught = ! isempty(strfind(err.message,'finite')) || ! isempty(strfind(err.message,'real'));
  end_try_catch
  assert (caught && isequaln(runtime,saved));
  retry = ob_runtime_step (runtime,.6);
  assert_close (ob_runtime_outputs(retry,8),3.8);

  % Explicit model declarations survive persistence and must not silently
  % fall back to sampled gates or generated code with different behavior.
  file = [tempname() '.mat']; source = [tempname() '.c'];
  sentinel = sprintf ('existing C source\n');
  unwind_protect
    ob_save_model (file,model,[0 1 .1],options);
    [restored,config,loaded] = ob_load_model (file);
    assert (isequaln(restored,model) && isequal(config,[0 1 .1]) && loaded.zero_crossings);
    assert (strcmp(restored.blocks(7).value.execution.control,'continuous'));
    assert_close (ob_scope_data(ob_run(restored,[0 1],loaded),8)',[-9 4]);
    stream = fopen(source,'w'); assert(stream>=0); fputs(stream,sentinel); fclose(stream);
    assert_error (@() ob_codegen(model,source,[0 1 .1],options), 'continuous');
    assert (strcmp(fileread(source),sentinel));
    assert_error (@() ob_codegen(model,source,[0 1 .1]), 'continuous');
    assert (strcmp(fileread(source),sentinel));
  unwind_protect_cleanup
    if (exist(file,'file')), unlink(file); endif
    if (exist(source,'file')), unlink(source); endif
  end_unwind_protect
  assert_error (@() ob_run(model,[0 1]), 'zero_crossings');
  invalid = model; invalid.blocks(7).value.execution.control = 'invalid';
  assert_error (@() ob_validate_model(invalid,true), 'control');
  invalid = model; invalid.sample_times = zeros(8,2); invalid.sample_times(7,:) = [.1 0];
  assert_error (@() ob_validate_model(invalid,true), 'continuous');
  legacy = ob_subsystem_template ();
  legacy.execution = struct ('mode','enabled');
  assert (strcmp(ob_execution_options(legacy).control,'sampled'));
  disp ('Octave Blocks continuous control tests passed');
endfunction

function options = gate_options (solver)
  options = struct ('solver',solver,'zero_crossings',true,'maxstep',.1, ...
                    'reltol',1e-8,'abstol',1e-10);
endfunction

function child = integrator_body (initial)
  child = make_model ({'Inport','Integrator','Outport'},{1,initial,1});
  child.edges = [1 1 2 1;2 1 3 1];
  child.execution = execution ('enabled',{-9});
endfunction

function child = squared_body (mode)
  child = make_model ({'Inport','Product','Outport'},{1,[],1});
  child.edges = [1 1 2 1;1 1 2 2;2 1 3 1];
  child.execution = execution (mode,{-9});
endfunction

function child = mixed_body ()
  child = make_model ({'Inport','Integrator','Outport','Time','Unit Delay','Outport', ...
                       'Constant','Discrete Integrator','Outport'}, ...
                      {1,0,1,[],-7,2,1,0,3});
  child.edges = [1 1 2 1;2 1 3 1;4 1 5 1;5 1 6 1;7 1 8 1;8 1 9 1];
  child.execution = execution ('enabled',{-9,-7,0});
endfunction

function outer = nested_body ()
  outer = make_model ({'Inport','Constant','Subsystem','Outport'}, ...
                      {1,1,integrator_body(0),1});
  outer.edges = [1 1 3 1;2 1 3 2;3 1 4 1];
  outer.execution = execution ('enabled',{-9});
endfunction

function model = pulse_model (child, data)
  model = make_model ({'Constant','Time','Constant','Sum','Gain','Function','Subsystem','Scope'}, ...
                      {data,[],-.2,[],2*pi,[],child,[]});
  model.blocks(6).name = 'sin';
  model.edges = [2 1 4 1;3 1 4 2;4 1 5 1;5 1 6 1;1 1 7 1;6 1 7 2;7 1 8 1];
endfunction

function model = feedthrough_integral_model (output_policy)
  child = ob_subsystem_template ();
  child.blocks(2).value = 1;
  child.execution = execution ('enabled',{0}); child.execution.outputs = output_policy;
  model = pulse_model (child,[]); model.blocks(1).type = 'Time';
  model = append_block (model,'Integrator',0); model = append_block (model,'Scope',[]);
  model.edges = [model.edges;7 1 9 1;9 1 10 1];
endfunction

function model = linear_trigger (mode, slope, offset)
  model = pulse_model (squared_body(mode),[]); model.blocks(1).type = 'Time';
  model.blocks(3).value = offset; model.blocks(5).value = slope;
  % Phase = t + offset for rising, or -(t-.5) for falling.
  if (slope < 0), model.blocks(3).value = -offset; endif
  model.blocks(6).type = 'Gain'; model.blocks(6).value = 1;
endfunction

function model = switch_enabled_model (increasing)
  model = pulse_model (integrator_body(0),1);
  if (increasing), high = 1; low = -1; else high = -1; low = 1; endif
  model.blocks(3).value = high;
  model.blocks(4).type = 'Constant'; model.blocks(4).value = low;
  model.blocks(5).value = 1;
  model.blocks(6).type = 'Switch'; model.blocks(6).value = .35;
  model.edges(ismember(model.edges(:,3),[4 5 6]),:) = [];
  model.edges = [model.edges;2 1 5 1;3 1 6 1;2 1 6 2;4 1 6 3];
endfunction

function model = coincident_switch_model ()
  child = mixed_body ();
  child.sample_times = zeros(9,2); child.sample_times(5,:) = [.25 0];
  model = pulse_model (child,1);
  model.blocks(3).value = -.25;
  model.blocks(5).type = 'Product'; model.blocks(5).value = [];
  model.blocks(6).type = 'Switch'; model.blocks(6).value = 0;
  model = append_block (model,'Gain',-1);
  model = append_block (model,'Constant',.75);
  model = append_block (model,'Sum',[]);
  model = append_block (model,'Constant',1);
  model = append_block (model,'Constant',-1);
  model.edges(model.edges(:,3)==6,:) = [];
  model.edges = [model.edges;2 1 9 1;10 1 11 1;9 1 11 2;11 1 5 2; ...
                 12 1 6 1;5 1 6 2;13 1 6 3];
endfunction

function [model, ids] = append_root_clocks (model)
  count = numel(model.blocks); ids = count+[1 3 5];
  for entry = {{'Unit Delay',-9},{'Scope',[]},{'Unit Delay',-5},{'Scope',[]}, ...
               {'Discrete Integrator',0},{'Scope',[]},{'Constant',1}}
    model = append_block (model,entry{1}{1},entry{1}{2});
  endfor
  model.edges = [model.edges;2 1 ids(1) 1;ids(1) 1 ids(1)+1 1; ...
                 2 1 ids(2) 1;ids(2) 1 ids(2)+1 1; ...
                 count+7 1 ids(3) 1;ids(3) 1 ids(3)+1 1];
  model.sample_times = zeros(count+7,2); model.sample_times(ids(1),:) = [.25 0];
endfunction

function options = execution (mode, outputs)
  options = struct ('mode',mode,'control','continuous','initial_outputs',{outputs});
endfunction

function state = conditional_snapshot (result, block)
  state = result.flat_values{end,flat_id(result,[block 0])};
endfunction

function id = flat_id (result, path)
  selected = cellfun (@(candidate) isequal(candidate,path),result.block_paths);
  id = find(selected); assert(numel(id)==1);
endfunction

function model = append_block (model, type, value)
  block = model.blocks(1); block.type = type; block.value = value; block.name = type;
  model.blocks(end+1) = block;
endfunction

function model = make_model (types, values)
  count = numel(types);
  model.blocks = struct ('type',types,'value',values,'name',types, ...
      'x',num2cell(linspace(.1,.9,count)),'y',num2cell(.5*ones(1,count)));
  model.edges = zeros(0,4);
endfunction

function assert_close (actual, expected, tolerance = 2e-7)
  assert(isequal(size(actual),size(expected)) && all(isfinite(actual(:))));
  assert(all(abs(actual(:)-expected(:))<=tolerance));
endfunction

function assert_error (callback, fragment)
  caught = false;
  try callback(); catch err, caught = ! isempty(strfind(err.message,fragment)); end_try_catch
  assert(caught);
endfunction
