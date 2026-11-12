function test_ob_conditional ()
  expected = [-1 0 1 1 1 2 5];
  tagged = ob_conditional_example (); tagged.blocks(3).notes = 'editor metadata';
  assert (isequal (ob_scope_data(ob_run(tagged,0:6),4)', expected));
  for solver = {'rk4','ode45','ode15s'}
    options = struct ('solver', solver{1}, 'reltol', 1e-8, 'abstol', 1e-10);
    model = ob_conditional_example ();
    result = ob_run (model, 0:6, options);
    assert (isequal (ob_scope_data(result,4)', expected));
    assert (isequaln (ob_scope_data(result,[3 2])', [NaN 0 1 1 1 2 5]));
    runtime = ob_runtime_step (ob_runtime_init(model), 2);
    assert (ob_runtime_outputs(runtime, [3 2]) == 0); % one active hit at t=2
    model.blocks(3).value.execution.states = 'reset';
    assert (isequal (ob_scope_data(ob_run(model,0:6,options),4)', [-1 0 1 1 1 0 5]));
    model.blocks(3).value.execution.states = 'held';
    model.blocks(3).value.execution.outputs = 'reset';
    assert (isequal (ob_scope_data(ob_run(model,0:6,options),4)', [-1 0 1 -1 -1 2 5]));
    model.blocks(3).value.execution.states = 'reset';
    assert (isequal (ob_scope_data(ob_run(model,0:6,options),4)', [-1 0 1 -1 -1 0 5]));

    % A continuous parent consumes the held output; RK stages never execute a child.
    model = ob_conditional_example ();
    model.blocks(4).type = 'Integrator'; model.blocks(4).value = 0;
    model.blocks(5) = model.blocks(4); model.blocks(5).type = 'Scope'; model.blocks(5).value = [];
    model.edges(end+1,:) = [4 1 5 1];
    model.sample_times = [0 0;0 0;1 0;0 0;0 0];
    result = ob_run (model, [0 0.5 1.5 3.5 6], options);
    assert (max(abs(ob_scope_data(result,5)' - [0 -0.5 -1 0.5 4])) < 1e-8);
    core = find (strcmp ({result.compiled_model.blocks.type}, 'Conditional Subsystem'));
    assert (isequal (result.flat_values{end,core}.executions, [1 2 5 6]));
  endfor

  model = ob_conditional_example ();
  model.sample_times = [0 0;0 0;1 0.5;0 0];
  result = ob_run (model, 0:7);
  assert (isequal (ob_scope_data(result,4)', [-1 -1 0 1.5 1.5 1.5 2.5 5.5]));
  core = find (strcmp ({result.compiled_model.blocks.type}, 'Conditional Subsystem'));
  assert (isequal (result.sample_hits{core}, 0.5:1:6.5));

  % The zero plateau rule avoids consecutive duplicate rises/falls.
  control = [-1 0 1 0 0 1 -1 0 0 1];
  models = {'rising','falling','either'};
  answers = {[-1 0 0 0 0 1 1 5 5 7], [0 0 0 0 0 0 3 3 3 3], [0 0 0 1 1 3 5 6 6 7]};
  hits = {[1 5 7 9], [0 3 6], [0 1 3 5 6 7 9]};
  for k = 1:numel (models)
    model = ob_conditional_example ();
    model.inputs = {ob_input_signal(0:9, control')};
    model.blocks(3).value.execution.mode = models{k};
    result = ob_run (model, 0:9);
    assert (isequal (ob_scope_data(result,4)', answers{k}));
    core = find (strcmp ({result.compiled_model.blocks.type}, 'Conditional Subsystem'));
    assert (isequal (result.flat_values{end,core}.executions, hits{k}));
  endfor
  model.blocks(3).value.execution.mode = 'falling';
  model.blocks(3).value.execution.initial_control = -1;
  assert (isequal (ob_scope_data(ob_run(model,0:9),4)', [-1 -1 -1 0 0 0 3 3 3 3]));

  % Matrix state/output contracts and independent multiple output proxies.
  model = ob_conditional_example ();
  data = [1 2;3 4];
  model.blocks(1).type = 'Constant'; model.blocks(1).value = data;
  model.blocks(3).value.blocks(2).value = zeros (2);
  model.blocks(3).value.execution.initial_outputs = {-ones(2)};
  result = ob_run (model, 0:6);
  assert (isequal (result.values{1,4}, -ones(2)));
  assert (isequal (result.values{2,4}, zeros(2)) && isequal (result.values{3,4}, data));
  model.blocks(3).value.blocks(4) = model.blocks(3).value.blocks(3);
  model.blocks(3).value.blocks(4).value = 2;
  model.blocks(3).value.edges = [1 1 2 1;2 1 3 1;1 1 4 1];
  model.blocks(3).value.execution.initial_outputs = {-ones(2), zeros(2)};
  model.blocks(5) = model.blocks(4);
  model.edges(end+1,:) = [3 2 5 1];
  result = ob_run (model, 0:6);
  assert (isequal (ob_signal_values(result,3,2){2}, data));
  assert (isequal (result.values{2,5}, data) && isequal (result.values{2,4}, zeros(2)));

  % Neither initialization nor minor integration stages evaluate an inactive child.
  model = ob_conditional_example (); model = rmfield (model, 'inputs');
  model.blocks(1).type = 'Step'; model.blocks(1).value = [2 -1 4];
  model.blocks(2).type = 'Step'; model.blocks(2).value = [2 0 1];
  model.blocks(3).value.blocks(2).type = 'Function';
  model.blocks(3).value.blocks(2).name = 'sqrt'; model.blocks(3).value.blocks(2).value = [];
  assert (isequal (ob_scope_data(ob_run(model,0:3),4)', [-1 -1 2 2]));
  model.blocks(1).type = 'Constant'; model.blocks(1).value = -1;
  runtime = ob_runtime_step (ob_runtime_init(model), 1);
  saved = runtime; caught = false;
  try
    runtime = ob_runtime_step (runtime, 2);
  catch err
    caught = ! isempty (strfind (err.message, 'conditional output'));
  end_try_catch
  assert (caught && isequal (runtime,saved));
  retry = ob_runtime_step (runtime, 1.5);
  assert (ob_runtime_outputs(retry,4) == -1);
  assert_error (@() ob_runtime_outputs(retry,[3 2]), 'has not executed');
  assert_error (@() ob_runtime_outputs(retry,[3 99]), 'path does not exist');
  assert_error (@() ob_runtime_outputs(retry,[3 2],2), 'port does not exist');

  % Virtual wrapping retains paths; nested conditional contexts retain history.
  model = ob_conditional_example ();
  wrapper = wrap_child (model.blocks(3).value);
  model.blocks(3).value = wrapper;
  result = ob_run (model,0:6);
  assert (isequal (ob_scope_data(result,4)', expected));
  assert (isequaln (ob_scope_data(result,[3 3 2])', [NaN 0 1 1 1 2 5]));
  wrapper.execution = struct ('mode','enabled','initial_outputs',{{-9}});
  wrapper.blocks(3).value.execution.mode = 'rising';
  model.blocks(3).value = wrapper;
  model.blocks(5) = model.blocks(1); model.blocks(5).type = 'Constant'; model.blocks(5).value = 1;
  model.edges(end+1,:) = [5 1 3 3];
  result = ob_run (model,0:6);
  assert (isequal (ob_scope_data(result,4)', [-1 0 0 0 0 1 1]));
  assert (isequaln (ob_scope_data(result,[3 3 2])', [NaN 0 0 0 0 1 1]));
  checkpoint = ob_runtime_step (ob_runtime_init(model), 2);
  file = [tempname() '.mat'];
  unwind_protect
    ob_save_model (file, model, [0 6 1]);
    [loaded,config] = ob_load_model (file);
    assert (isequal (loaded, model) && isequal (config,[0 6 1]));
    save ('-mat7-binary',file,'checkpoint'); restored = load (file);
    assert (isequal (ob_runtime_step(checkpoint,6), ob_runtime_step(restored.checkpoint,6)));
  unwind_protect_cleanup
    if (exist (file,'file')), unlink (file); endif
  end_unwind_protect

  % Feedback inside an atomic child still uses the ordinary state dependency sort.
  model = ob_conditional_example ();
  child = ob_subsystem_template ();
  child.blocks(2).type = 'Unit Delay'; child.blocks(2).value = 0;
  child.blocks(3).type = 'Sum'; child.blocks(3).value = [];
  child.blocks(4) = child.blocks(1); child.blocks(4).type = 'Outport'; child.blocks(4).value = 1;
  child.edges = [1 1 3 1;2 1 3 2;3 1 2 1;2 1 4 1];
  child.execution = struct ('mode','enabled','initial_outputs',{{-1}});
  model.blocks(3).value = child;
  assert (isequal (ob_scope_data(ob_run(model,0:6),4)', [-1 0 1 1 1 3 8]));

  % Enabled Euler freezes disabled intervals; triggered Euler uses elapsed time.
  model = ob_conditional_example ();
  model.blocks(1).type = 'Constant'; model.blocks(1).value = 1;
  model.blocks(3).value.blocks(2).type = 'Discrete Integrator';
  assert (isequal (ob_scope_data(ob_run(model,0:6),4)', [-1 0 1 1 1 2 3]));
  model.blocks(3).value.execution.mode = 'rising';
  assert (isequal (ob_scope_data(ob_run(model,0:6),4)', [-1 0 0 0 0 4 4]));
  % The first interval after a prior execution is retained across a variable pause.
  model.blocks(3).value.execution.mode = 'enabled';
  model.inputs = {ob_input_signal([0 0.25 4],[1;0;1])};
  assert (isequal (ob_scope_data(ob_run(model,[0 0.25 2 4 6]),4)', [0 0 0 0.25 2.25]));

  % Enabled descendants inherit the active interval, not the parent's pause.
  inner = ob_subsystem_template ();
  inner.blocks(2).type = 'Discrete Integrator'; inner.blocks(2).value = 0;
  inner.execution = struct ('mode','enabled','initial_outputs',{{0}});
  wrapper = wrap_child (inner);
  wrapper.blocks(2).type = 'Constant'; wrapper.blocks(2).value = 1;
  wrapper.execution = struct ('mode','enabled','initial_outputs',{{-1}});
  model = ob_conditional_example ();
  model.blocks(1).type = 'Constant'; model.blocks(1).value = 1;
  model.blocks(3).value = wrapper;
  assert (isequal (ob_scope_data(ob_run(model,0:6),4)', [-1 0 1 1 1 2 3]));
  model.inputs = {ob_input_signal([0 0.25 4],[1;0;1])};
  assert (isequal (ob_scope_data(ob_run(model,[0 0.25 2 4 6]),4)', [0 0 0 0.25 2.25]));

  % Scope discovery includes atomic children; initial unavailable values are gaps.
  model = ob_conditional_example ();
  child = model.blocks(3).value;
  child.blocks(4) = child.blocks(3); child.blocks(4).type = 'Scope'; child.blocks(4).value = [];
  child.edges = ob_edges (child);
  child.edges(end+1,:) = [2 1 4 1]; model.blocks(3).value = child;
  assert (isequal (ob_scope_paths(model), {[3 4],4}));
  result = ob_run(model,0:6);
  assert (isequaln (ob_scope_data(result,[3 4])', [NaN 0 1 1 1 2 5]));
  model.inputs = {ob_input_signal(0,0)};
  assert_error (@() ob_scope_data(ob_run(model,0:6),[3 4]), 'has not executed');

  for config = {struct('mode','bad'), struct('mode','enabled','states','bad'), ...
                struct('mode','rising','states','reset'), struct('mode','either','outputs','reset'), ...
                struct('mode','enabled','initial_outputs',{{}}), ...
                struct('mode','enabled','initial_outputs',{{NaN}}), ...
                struct('mode','enabled','initial_control',Inf), struct('mode','enabled','unknown',1)}
    invalid = ob_conditional_example (); invalid.blocks(3).value.execution = config{1};
    assert_fails (@() ob_validate_model(invalid));
  endfor
  invalid = ob_conditional_example ();
  invalid.blocks(3).value.blocks(2).type = 'Integrator';
  invalid.blocks(3).value.execution.mode = 'rising';
  assert_error (@() ob_validate_model(invalid), 'discrete blocks');
  invalid = ob_conditional_example ();
  invalid.blocks(3).value.sample_times = [0 0;1 0;0 0];
  invalid.blocks(3).value.execution.mode = 'rising';
  assert_error (@() ob_validate_model(invalid), 'inherit its execution clock');
  invalid = ob_conditional_example ();
  invalid.blocks(3).value.execution.initial_outputs = {zeros(2)};
  assert_error (@() ob_run(invalid,0:6), 'initial output shape');
  invalid = ob_conditional_example (); invalid.blocks(2).value = 2;
  invalid.blocks(2).type = 'Constant'; invalid.blocks(2).value = [1 1]; invalid = rmfield(invalid,'inputs');
  assert_error (@() ob_run(invalid,0:6), 'control must be a finite real scalar');
  invalid = ob_conditional_example (); invalid.edges(2,:) = [3 1 3 2];
  assert_error (@() ob_run(invalid,0:6), 'algebraic loop');

  blank.blocks = struct ('type',{},'value',{},'name',{},'x',{},'y',{});
  blank.edges = zeros (0,2); blank.execution = struct ('mode','enabled');
  model = ob_conditional_example (); model.blocks = model.blocks(1:3);
  model.blocks(3).value = blank; model.edges = [2 1 3 1];
  result = ob_run (model,0:2);
  core = find (strcmp ({result.compiled_model.blocks.type}, 'Conditional Subsystem'));
  assert (isequal (result.flat_values{end,core}.executions,[1 2]));

  % Unused virtual metadata must not prevent adding an ordinary interface port.
  child = ob_subsystem_template (); child.execution = ob_execution_options (child);
  child.blocks(4) = child.blocks(3); child.blocks(4).value = 2;
  child.edges = ob_edges (child); child.edges(end+1,:) = [1 1 4 1];
  ob_validate_model (child, false);
  assert (numel (ob_execution_options(child).initial_outputs) == 2);

  file = [tempname() '.c'];
  unwind_protect
    fid = fopen(file,'w'); fputs(fid,'existing source'); fclose(fid);
    invalid = ob_conditional_example ();
    invalid.blocks(3).value.blocks(2).type = 'Function';
    invalid.blocks(3).value.blocks(2).name = 'ob_demo_function';
    invalid.blocks(3).value.blocks(2).value = [];
    assert_error (@() ob_codegen(invalid,file), 'unsupported Function');
    assert (strcmp (fileread(file),'existing source'));
  unwind_protect_cleanup
    if (exist (file,'file')), unlink (file); endif
  end_unwind_protect
  disp ('Octave Blocks conditional subsystem tests passed');
endfunction

function model = wrap_child (child)
  model.blocks = struct ('type',{'Inport','Inport','Subsystem','Outport'}, ...
      'value',{1,2,child,1},'name',{'Data','Control','Child','Output'}, ...
      'x',{0.1,0.1,0.5,0.9},'y',{0.7,0.3,0.5,0.5});
  model.edges = [1 1 3 1;2 1 3 2;3 1 4 1];
endfunction

function assert_fails (callback)
  caught = false;
  try callback (); catch caught = true; end_try_catch
  assert (caught);
endfunction

function assert_error (callback, text)
  caught = false;
  try callback (); catch err; caught = ! isempty(strfind(err.message,text)); end_try_catch
  assert (caught);
endfunction
