function test_ob_enabled_multirate ()
  model = ob_enabled_multirate_example ();
  for solver = {'rk4','ode45','ode15s'}
    options = struct ('solver',solver{1},'reltol',1e-9,'abstol',1e-11,'maxstep',.05);
    sparse = ob_run (model,[0 1],options);
    assert (isequal(ob_scope_data(sparse,4)',[0 .375]));
    assert (isequal(ob_scope_data(sparse,5)',[0 .25]));
    state = last_child (sparse);
    assert (isequal(state.child.sample_hits{2},.375:.125:.75));
    assert (isequal(state.child.sample_hits{3},[.5 .75]));
    assert (state.child.start_time == 0);
    matrix = model; data = [1 -2;3 .5]; matrix.blocks(1).value = data;
    matrix.blocks(3).value.blocks(2).value = matrix.blocks(3).value.blocks(3).value = zeros(2);
    matrix.blocks(3).value.execution.initial_outputs = {zeros(2),zeros(2)};
    result = ob_run (matrix,[0 1],options);
    assert (isequal(ob_signal_values(result,3,1){end},.375*data));
    assert (isequal(ob_signal_values(result,3,2){end},.25*data));
    dense = ob_run (model,0:.0625:1,options);
    assert (ob_scope_data(dense,4)(end) == .375 && ob_scope_data(dense,5)(end) == .25);

    % Inner hits between explicit enable-control samples still dispatch.
    separated = model; separated.sample_times(3,:) = [.25 .125];
    result = ob_run (separated,[0 1],options);
    assert (ob_scope_data(result,4)(end) == .375 && ob_scope_data(result,5)(end) == .25);
    state = last_child (result);
    assert (isequal(state.child.sample_hits{3},[.5 .75]));

    % An inherited enable control derives hits from the inner clock union.
    inherited = model; inherited.sample_times(3,:) = [0 0];
    result = ob_run (inherited,[0 1],options);
    assert (ob_scope_data(result,4)(end) == .375 && ob_scope_data(result,5)(end) == .25);

    % Offsets stay relative to simulation origin, never first activation.
    offset = model; offset.sample_times(3,:) = [.5 .125];
    offset.inputs = {ob_input_signal(0,1)};
    offset.blocks(3).value.sample_times(2:3,:) = [.25 .0625;.25 .125];
    result = ob_run (offset,[0 1],options); state = last_child (result);
    assert (isequal(state.child.sample_hits{2},[.3125 .5625 .8125]));
    assert (isequal(state.child.sample_hits{3},[.125 .375 .625 .875]));
    assert (ob_scope_data(result,4)(end) == .5 && ob_scope_data(result,5)(end) == .75);
    shifted = model; shifted.inputs = {ob_input_signal([10 10.375 10.875],[0;1;0])};
    result = ob_run (shifted,[10 11],options); state = last_child (result);
    assert (state.child.start_time == 10 && isequal(state.child.sample_hits{3},[10.5 10.75]));
    decimal = model; decimal.sample_times(3,:) = [.25 .125];
    decimal.inputs = {ob_input_signal(0,1)};
    decimal.blocks(3).value.sample_times(2:3,:) = [.1 .03;.1 .03];
    result = ob_run (decimal,[1000 1001],options); state = last_child(result);
    expected_hits = 1000 + .03 + (1:9)*.1;
    assert (numel(state.child.sample_hits{2}) == 9);
    assert (max(abs(state.child.sample_hits{2}-expected_hits)) < 1e-12);
    assert (abs(ob_scope_data(result,4)(end)-.8) < 1e-12);
    coincidence = model; coincidence.inputs = {ob_input_signal(0,1)};
    coincidence.sample_times(3,:) = [.1 .07];
    coincidence.blocks(3).value.sample_times(2:3,:) = [.1 .07;.1 .07];
    result = ob_run (coincidence,[1000 1000.17],options);
    assert (abs(ob_scope_data(result,4)(end)-.1) < 1e-14);
    enormous = model; enormous.inputs = {ob_input_signal(0,1)};
    enormous.sample_times(3,:) = [8 0];
    enormous.blocks(3).value.sample_times(2:3,:) = [8 2;8 2];
    result = ob_run (enormous,[1e16 1e16+24],options); state = last_child(result);
    assert (isequal(state.child.sample_hits{2},1e16+[2 10 18]));
    assert (ob_scope_data(result,4)(end) == 16);

    % A pause skips hits without replay or integrating its wall-time gap.
    paused = model; paused.blocks(1).type = 'Time'; paused.blocks(1).value = [];
    paused.blocks(3).value.blocks(2).type = 'Unit Delay';
    paused.blocks(3).value.sample_times(2:3,:) = [.25 0;.25 0];
    paused.blocks(3).value.blocks(3).name = 'Euler';
    paused.blocks(3).value.edges(2,1) = 1;
    % The Euler uses a constant slope while Delay samples absolute time.
    child = paused.blocks(3).value;
    child.blocks(6) = child.blocks(1); child.blocks(6).type = 'Constant'; child.blocks(6).value = 1;
    child.edges(2,1) = 6; child.sample_times(6,:) = [0 0]; paused.blocks(3).value = child;
    paused.inputs = {ob_input_signal([0 .375 .875 1.125 1.875],[0;1;0;1;0])};
    queries = [0 .5 .75 1 1.125 1.25 1.5 2];
    result = ob_run (paused,queries,options);
    assert (isequal(ob_scope_data(result,4)',[0 0 .5 .5 .5 .75 1.25 1.5]));
    assert (isequal(ob_scope_data(result,5)',[0 0 .25 .25 .25 .5 .75 1]));
    state = last_child (result);
    assert (isequal(state.child.sample_hits{2},[.5 .75 1.25 1.5 1.75]));
    paused.blocks(3).value.execution.states = 'reset';
    result = ob_run (paused,queries,options);
    assert (isequal(ob_scope_data(result,4)',[0 0 .5 .5 0 0 1.25 1.5]));
    assert (isequal(ob_scope_data(result,5)',[0 0 .25 .25 0 0 .25 .5]));
    paused.blocks(3).value.execution.states = 'held';
    paused.blocks(3).value.blocks(2).type = 'Rate Transition';
    result = ob_run (paused,queries,options);
    assert (isequal(ob_scope_data(result,4)',[0 .5 .75 .75 .75 1.25 1.5 1.75]));

    % Continuous states flow between independently scheduled discrete hits.
    mixed = model; child = mixed.blocks(3).value;
    child.blocks(6) = child.blocks(2); child.blocks(6).type = 'Integrator';
    child.blocks(7) = child.blocks(4); child.blocks(7).value = 3;
    child.edges = [child.edges;1 1 6 1;6 1 7 1]; child.sample_times(6:7,:) = zeros(2);
    child.execution.initial_outputs = {0,0,0}; mixed.blocks(3).value = child;
    mixed.blocks(6) = mixed.blocks(4); mixed.edges(end+1,:) = [3 3 6 1];
    mixed.sample_times(6,:) = [0 0];
    result = ob_run (mixed,[0 1],options);
    assert (abs(ob_scope_data(result,6)(end)-.5) < 2e-9);
    assert (ob_scope_data(result,4)(end) == .375 && ob_scope_data(result,5)(end) == .25);

    % Nested enabled and virtual compilation preserve the root clock phase.
    nested = model; inner = nested.blocks(3).value;
    wrapper.blocks = struct ('type',{'Inport','Constant','Subsystem','Outport','Outport'}, ...
        'value',{1,1,inner,1,2},'name',{'Data','Enable','Inner','Fast','Slow'}, ...
        'x',{.1,.1,.5,.9,.9},'y',{.7,.3,.5,.7,.3});
    wrapper.edges = [1 1 3 1;2 1 3 2;3 1 4 1;3 2 5 1];
    wrapper.sample_times = [0 0;0 0;.25 .125;0 0;0 0];
    wrapper.execution = struct ('mode','enabled','initial_outputs',{{0,0}});
    nested.blocks(3).value = wrapper;
    result = ob_run (nested,[0 1],options);
    assert (ob_scope_data(result,4)(end) == .375 && ob_scope_data(result,5)(end) == .25);
    assert (ob_signal_values(result,[3 3 3]){end} == .25);
    inherited_nested = nested;
    inherited_nested.inputs = {ob_input_signal(0,1)};
    inherited_nested.sample_times(3,:) = [.5 0];
    inherited_nested.blocks(3).value.sample_times(3,:) = [0 0];
    result = ob_run (inherited_nested,[0 1],options);
    assert (ob_scope_data(result,4)(end) == 1 && ob_scope_data(result,5)(end) == 1);

    % An independently clocked nested enabled wrapper supplies its own period
    % to inherited Euler, rather than the faster ancestor's sample interval.
    timed = ob_subsystem_template ();
    timed.blocks(2).type = 'Discrete Integrator'; timed.blocks(2).value = 0;
    timed.execution = struct ('mode','enabled','initial_outputs',{{0}});
    local = wrapper; local.blocks = local.blocks(1:4);
    local.blocks(3).value = timed; local.edges = [1 1 3 1;2 1 3 2;3 1 4 1];
    local.sample_times = [0 0;0 0;.5 0;0 0]; local.execution.initial_outputs = {0};
    clocked = model; clocked.blocks = clocked.blocks(1:4);
    clocked.blocks(3).value = local; clocked.edges = clocked.edges(1:3,:);
    clocked.sample_times = clocked.sample_times(1:4,:);
    clocked.inputs = {ob_input_signal(0,1)};
    result = ob_run (clocked,[0 1],options);
    assert (ob_scope_data(result,4)(end) == 1);
    wrapper.blocks(2).type = 'Inport'; wrapper.blocks(2).value = 2;
    wrapper.execution.mode = 'virtual'; nested.blocks(3).value = wrapper;
    nested.sample_times(3,:) = [0 0];
    result = ob_run (nested,[0 1],options);
    assert (ob_scope_data(result,4)(end) == .375 && ob_scope_data(result,5)(end) == .25);
  endfor

  % Global schedule metadata survives forks, active/paused MAT checkpoints,
  % and a failed hidden inner hit without partially advancing any counter.
  runtime = ob_runtime_step (ob_runtime_init(model),.4); saved = runtime;
  fork = ob_runtime_step (runtime,1);
  assert (isequaln(runtime,saved) && all([fork.nested_clocks.next] > fork.time));
  paused = ob_runtime_step (runtime,.9);
  file = [tempname() '.mat'];
  unwind_protect
    save ('-mat7-binary',file,'runtime','paused'); restored = load(file);
    assert (isequaln(ob_runtime_step(runtime,1.25),ob_runtime_step(restored.runtime,1.25)));
    assert (isequaln(ob_runtime_step(paused,1.25),ob_runtime_step(restored.paused,1.25)));
  unwind_protect_cleanup
    if (exist(file,'file')), unlink(file); endif
  end_unwind_protect
  failing = model; failing.blocks(1).type = 'Inport'; failing.blocks(1).value = 1;
  failing.blocks(2).value = 2; failing.sample_times(3,:) = [.5 0];
  child = failing.blocks(3).value;
  child.blocks(6) = child.blocks(1); child.blocks(6).type = 'Function';
  child.blocks(6).value = []; child.blocks(6).name = 'chol';
  child.edges = [1 1 6 1;6 1 2 1;6 1 3 1;2 1 4 1;3 1 5 1];
  child.sample_times(6,:) = [0 0]; failing.blocks(3).value = child;
  failing.inputs = {ob_input_signal([0 .3],[4;-1]),ob_input_signal(0,1)};
  runtime = ob_runtime_step (ob_runtime_init(failing),.25); saved = runtime;
  assert_error (@() ob_runtime_step(runtime,.75),'positive definite');
  assert (isequaln(runtime,saved));
  retry = ob_runtime_step (runtime,.28); assert (ob_runtime_outputs(retry,4) == .5);
  dormant = failing; dormant.inputs = {ob_input_signal(0,-1),ob_input_signal(0,0)};
  result = ob_run (dormant,[0 1]);
  assert (isequal(ob_scope_data(result,4)',[0 0]));
  assert_error (@() ob_signal_values(result,[3 6]),'has not executed');

  triggered = model; triggered.blocks(3).value.execution.mode = 'rising';
  assert_error (@() ob_validate_model(triggered),'inherit its execution clock');
  large = model; large.sample_times(3,:) = [8 0];
  assert_error (@() ob_runtime_init(large,1e16),'nested sample clock cannot advance');
  disp ('Octave Blocks enabled multirate subsystem tests passed');
endfunction

function state = last_child (result)
  core = find (strcmp({result.compiled_model.blocks.type},'Conditional Subsystem'));
  assert (numel(core)==1); state = result.flat_values{end,core};
endfunction

function assert_error (callback, fragment)
  caught = false;
  try callback(); catch err, caught = !isempty(strfind(err.message,fragment)); end_try_catch
  assert (caught);
endfunction
