function test_ob_conditional ()
  test_path_cleanup = ob_test_setup ();
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

  % initial_control 'compatibility' (Simulink's default trigger state): the
  % first evaluation only records its sample.  At the root this equals the
  % sign of that sample for positive, negative and zero starts (Simulink
  % 26.2 traces), while the zero default executes at t=0 on an edge from 0.
  starts = {[1 1 -1 0 0 1], [-1 -1 1 1 0 -1], [0 1 0 -1 0 1], [1 0 -1 -1 0 1]};
  for k = 1:numel (starts)
    for mode = {'rising','falling','either'}
      model = ob_conditional_example ();
      model.inputs = {ob_input_signal(0:5, starts{k}')};
      model.blocks(3).value.execution.mode = mode{1};
      model.blocks(3).value.execution.initial_control = 'compatibility';
      compat = ob_scope_data (ob_run (model, 0:5), 4)';
      model.blocks(3).value.execution.initial_control = sign (starts{k}(1));
      assert (isequal (compat, ob_scope_data (ob_run (model, 0:5), 4)'));
    endfor
  endfor
  model = ob_conditional_example ();
  model.inputs = {ob_input_signal(0:5, starts{1}')};
  model.blocks(3).value.execution.mode = 'rising';
  assert (isequal (ob_scope_data(ob_run(model,0:5),4)', [0 0 0 0 0 3]));
  model.blocks(3).value.execution.initial_control = 'compatibility';
  compat = [-1 -1 -1 0 0 3];
  assert (isequal (ob_scope_data(ob_run(model,0:5),4)', compat));
  % The setting round-trips through validation, model files and contexts.
  assert (strcmp (ob_execution_options (model.blocks(3).value).initial_control, 'compatibility'));
  file = [tempname() '.mat'];
  unwind_protect
    ob_save_model (file, model, [0 5 1]);
    loaded = ob_load_model (file);
    assert (strcmp (loaded.blocks(3).value.execution.initial_control, 'compatibility'));
    assert (isequal (ob_scope_data(ob_run(loaded,0:5),4)', compat));
  unwind_protect_cleanup
    if (exist (file, 'file')), unlink (file); endif
  end_unwind_protect
  runtime = ob_runtime_init (model, 0);
  for time = 1:5, runtime = ob_runtime_step (runtime, time); endfor
  assert (isequal (ob_runtime_outputs (runtime, 4), 3));
  % A first evaluation delayed by a disabled Enabled ancestor (enable on at
  % t=2, trigger high there) does not execute either; the next rise does.
  inner = model.blocks(3).value;
  outer = ob_subsystem_template ();
  outer.blocks = [outer.blocks(1), struct('type','Inport','value',2,'name','Trigger','x',.1,'y',.3), ...
                  struct('type','Subsystem','value',inner,'name','Triggered','x',.5,'y',.5), outer.blocks(3)];
  outer.edges = [1 1 3 1;2 1 3 2;3 1 4 1];
  outer.execution = struct ('mode','enabled','initial_outputs',{{-9}});
  nested.blocks = struct ('type',{'Time','Inport','Inport','Subsystem','Scope'}, ...
      'value',{[],1,2,outer,[]},'name',{'Time','Trigger','Enable','Outer','Output'}, ...
      'x',{.1,.1,.1,.5,.9},'y',{.7,.5,.3,.5,.5});
  nested.edges = [1 1 4 1;2 1 4 2;3 1 4 3;4 1 5 1];
  nested.inputs = {ob_input_signal(0:7,[-1;-1;1;1;-1;1;1;1]), ob_input_signal(0:7,[0;0;1;1;1;1;1;1])};
  assert (isequal (ob_scope_data(ob_run(nested,0:7),5)', [-9 -9 -1 -1 -1 0 0 0]));
  nested.blocks(4).value.blocks(3).value.execution.initial_control = 0;
  assert (isequal (ob_scope_data(ob_run(nested,0:7),5)', [-9 -9 0 0 0 2 2 2]));
  child = ob_subsystem_template ();
  for mode = {'rising','falling','either','enabled','enabled_falling'}
    child.execution = struct ('mode',mode{1},'initial_control','compatibility');
    assert (strcmp (ob_execution_options(child,false).initial_control, 'compatibility'));
  endfor
  child.execution = struct ('mode','virtual','initial_control','compatibility');
  assert (ob_execution_options(child).initial_control == 0);
  child.execution = struct ('mode','reset_rising','initial_control','compatibility');
  assert_error (@() ob_execution_options(child,false), 'not resettable');
  for invalid_control = {'Compatibility','zero','1',[1 2]}
    child.execution = struct ('mode','rising','initial_control',invalid_control);
    assert_error (@() ob_execution_options(child,false), 'finite real scalar or ''compatibility''');
  endfor

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

  % OutputWhenDisabled per Outport: execution.outputs may list one policy per
  % numbered Outport (Simulink's per-Outport parameter); one string still
  % applies to every port.
  model = two_port_example ({'held', 'reset'});
  result = ob_run (model, 0:6);
  assert (isequal (ob_scope_data(result,4)', [-1 0 1 1 1 2 5]));
  assert (isequal (ob_scope_data(result,5)', [-3 2 4 -3 -3 10 12]));
  for policy = {'held', 'reset'}
    uniform = ob_run (two_port_example (policy{1}), 0:6);
    listed = ob_run (two_port_example ({policy{1}, policy{1}}), 0:6);
    assert (isequal ([ob_scope_data(uniform,4) ob_scope_data(uniform,5)], ...
                     [ob_scope_data(listed,4) ob_scope_data(listed,5)]));
  endfor
  model.blocks(3).value.execution.states = 'reset';
  assert (isequal (ob_scope_data(ob_run(model,0:6),4)', [-1 0 1 1 1 0 5]));
  for outputs = {{'held'}, {'held','reset','held'}, {'held','bad'}, {1, 'held'}, 3}
    invalid = two_port_example (outputs{1});
    assert_error (@() ob_validate_model(invalid), 'outputs must be held or reset');
  endfor
  invalid = two_port_example ({'held','reset'}); invalid.blocks(3).value.execution.mode = 'rising';
  assert_error (@() ob_validate_model(invalid), 'triggered subsystems require held states and outputs');
  assert (isequal (ob_execution_options(two_port_example({'held';'reset'}).blocks(3).value).outputs, ...
                   {'held','reset'}));

  % A scalar initial output is expanded to its port's shape (Simulink), also
  % before the first execution and when a reset port returns to it; once
  % the shape is known it is enforced.
  model = two_port_example ('reset');
  model.blocks(1).type = 'Constant'; model.blocks(1).value = [1 2];
  model.blocks(3).value.blocks(2).value = [0 0];
  result = ob_run (model, 0:6);
  assert (isequal (cell2mat (ob_signal_values (result, 4)), [-1 -1;0 0;1 2;-1 -1;-1 -1;1 2;1 2]));
  assert (isequal (cell2mat (ob_signal_values (result, 5)), [-3 -3;2 4;2 4;-3 -3;-3 -3;2 4;2 4]));
  wrong = model; wrong.blocks(3).value.execution.initial_outputs = {[0 0 0], -3};
  assert_error (@() ob_run(wrong,0:6), 'initial output shape');
  % ones(t) passed through: scalar at the first execution (t = 1), 2-by-2 at t = 2.
  growing = ob_conditional_example ();
  growing.blocks(3).value.blocks(2).type = 'Gain'; growing.blocks(3).value.blocks(2).value = 1;
  growing.blocks(1).type = 'Function'; growing.blocks(1).name = 'ones';
  growing.blocks(1).value = [];
  growing.blocks(end+1) = struct ('type','Time','value',[],'name','Time','x',.1,'y',.9);
  growing.edges(end+1,:) = [5 1 1 1];
  assert_error (@() ob_run(growing,0:6), 'initial output shape');
  % The shape is known statically: an inner body's [-5 -5] reaches the
  % outer port before the inner body first runs (the runtime expands nested
  % bodies), and a subsystem first evaluated after the start holds [-4 -4]
  % from t = 0: the root runtime initialization applies
  % ob_expand_initial_outputs, so the raw model, the expanded one and a
  % stepwise context all log one sample shape.
  result = ob_run (ob_scalar_initial_example ('nested'), 0:.25:2);
  assert (isequal (ob_scope_data (result, 6), [-4 -4;-4 -4;-5 -5;-5 -5;-5 -5;3.75 7.5;3.75 7.5;5.25 10.5;5.25 10.5]));
  offset = ob_scalar_initial_example ('offset');
  [expanded, shapes] = ob_expand_initial_outputs (offset);
  assert (isequal (expanded.blocks(4).value.execution.initial_outputs, {[-4 -4]}) && isempty (shapes));
  expected = [repmat([-4 -4],3,1); repmat([2.25 4.5],6,1)];
  result = ob_run (offset, 0:.25:2);
  assert (isequal (ob_scope_data (result, 5), expected));
  result = ob_run (expanded, 0:.25:2);
  assert (isequal (ob_scope_data (result, 5), expected));
  context = ob_runtime_init (offset, 0, struct ());
  assert (isequal (ob_runtime_outputs (context, 4, 1), [-4 -4]));
  context = ob_runtime_step (context, 0.25);
  assert (isequal (ob_runtime_outputs (context, 4, 1), [-4 -4]));
  % The root expansion leaves malformed models to the validator's messages.
  assert_error (@() ob_runtime_init (struct ()), 'expected a model with blocks and edges');
  assert_error (@() ob_run (struct ('blocks', struct ('x', 1), 'edges', []), 0:1), 'blocks need type');
  [unused, shapes] = ob_expand_initial_outputs (offset.blocks(4).value, {[1 2]});
  assert (isequal (shapes, {[1 2]}));
  [unused, shapes] = ob_expand_initial_outputs (offset.blocks(4).value, {[]});
  assert (isequal (shapes, {[]}));

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

function model = two_port_example (outputs)
  % ob_conditional_example plus a second Outport, 2u, with initial output -3.
  model = ob_conditional_example ();
  child = model.blocks(3).value;
  child.blocks(4) = struct ('type','Gain','value',2,'name','Double','x',.5,'y',.2);
  child.blocks(5) = struct ('type','Outport','value',2,'name','Twice','x',.9,'y',.2);
  child.edges = [ob_edges(child); 1 1 4 1; 4 1 5 1];
  child.execution = struct ('mode','enabled','outputs',{outputs},'initial_outputs',{{-1,-3}});
  model.blocks(3).value = child;
  model.blocks(5) = model.blocks(4); model.blocks(5).name = 'Twice';
  model.edges(end+1,:) = [3 2 5 1];
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
