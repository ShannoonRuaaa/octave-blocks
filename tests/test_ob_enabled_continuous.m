function test_ob_enabled_continuous ()
  % Continuous child states use the same solver stages as their parent.
  times = [0 0.5 1 1.5 2 2.5 3];
  held = [0 0.5 1 1 1 1.5 2];
  for solver = {'rk4','ode45','ode15s'}
    options = struct ('solver',solver{1},'reltol',1e-10,'abstol',1e-12,'maxstep',0.05);
    model = ob_enabled_continuous_example ();
    result = ob_run (model,times,options);
    assert_close (ob_scope_data(result,4)', held, 2e-9);
    assert_close (ob_signal_values(result,[3 2]){end}, 2, 2e-9);

    % State reset and disabled output reset are independent policies.
    model.blocks(3).value.execution.states = 'reset';
    result = ob_run (model,times,options);
    assert_close (ob_scope_data(result,4)', [0 0.5 1 1 0 0.5 1], 2e-9);
    model.blocks(3).value.execution.outputs = 'reset';
    result = ob_run (model,times,options);
    assert_close (ob_scope_data(result,4)', [0 0.5 -1 -1 0 0.5 -1], 2e-9);
    model.blocks(3).value.execution.states = 'held';
    result = ob_run (model,times,options);
    assert_close (ob_scope_data(result,4)', [0 0.5 -1 -1 1 1.5 -1], 2e-9);

    % A raw enable transition at an intermediate stage cannot change the gate.
    % Explicit wrapper hits are 0,.5,1,...; raw changes are .75 and 1.75.
    model = ob_enabled_continuous_example ();
    model.sample_times(3,:) = [0.5 0];
    model.inputs = {ob_input_signal([0 0.75 1.75], [1;0;1])};
    queried = [0 0.75 1 1.5 2 2.25 2.5 3];
    result = ob_run (model,queried,options);
    assert_close (ob_scope_data(result,4)', [0 .75 1 1 1 1.25 1.5 2], 2e-9);
    sparse = ob_run (model,[0 3],options);
    assert_close (ob_scope_data(sparse,4)', [0 2], 2e-9);

    % Different matrix components retain their own continuous states.
    model = ob_enabled_continuous_example ();
    slope = [1 -2;3 0.5]; initial = [4 0;-1 2];
    model.blocks(1).value = slope;
    model.blocks(3).value.blocks(2).value = initial;
    model.blocks(3).value.execution.initial_outputs = {-ones(2)};
    result = ob_run (model,times,options);
    outputs = ob_signal_values (result,3);
    for k = 1:numel (times)
      assert_close (outputs{k}, initial + held(k)*slope, 2e-9);
    endfor

    % A parent/child oscillator detects stale-input or split integration.
    % x'=y, y'=-x, x(0)=1, y(0)=0 must give cos(t), -sin(t).
    model = coupled_oscillator ();
    grid = 0:0.05:2;
    result = ob_run (model,grid,options);
    assert_close (ob_scope_data(result,4)', cos(grid), 2e-7);
    assert_close (ob_scope_data(result,5)', -sin(grid), 2e-7);
    child_values = ob_signal_values (result,[3 3]);
    assert_close (child_values{end}, -sin(2), 2e-7);

    % Nested bodies must pause when an ancestor is disabled, even though the
    % inner control is still positive. First activation remains lazy.
    model = ob_enabled_continuous_example ();
    inner = model.blocks(3).value;
    outer.blocks = struct ('type',{'Inport','Inport','Subsystem','Outport'}, ...
        'value',{1,2,inner,1},'name',{'Slope','Inner enable','Inner','Output'}, ...
        'x',{0.1,0.1,0.5,0.9},'y',{0.7,0.3,0.5,0.5});
    outer.edges = [1 1 3 1;2 1 3 2;3 1 4 1];
    outer.execution = struct ('mode','enabled','initial_outputs',{{-9}});
    model.blocks(3).value = outer;
    model.blocks(5) = model.blocks(1); model.blocks(5).name = 'Inner enable';
    model.edges = [1 1 3 1;5 1 3 2;2 1 3 3;3 1 4 1];
    model.sample_times(5,:) = [0 0];
    model.inputs = {ob_input_signal([0 1 3 5 7],[0;1;0;1;0])};
    result = ob_run (model,0:7,options);
    assert_close (ob_scope_data(result,4)', [-9 0 1 2 2 2 3 4], 2e-9);
    assert_close (ob_signal_values(result,[3 3 2]){end}, 4, 2e-9);

    % Structural continuous descendants may all be inactive. Even with no
    % active solver states, outer feedthrough outputs must cache the endpoint
    % immediately before disabling rather than the last wrapper-hit value.
    outer.blocks(2).type = 'Constant'; outer.blocks(2).value = 0;
    outer.edges = [1 1 3 1;2 1 3 2;1 1 4 1];
    model = ob_enabled_continuous_example ();
    model.blocks(1).type = 'Time'; model.blocks(1).value = [];
    model.blocks(3).value = outer;
    model.inputs = {ob_input_signal([0 1],[1;0])};
    result = ob_run (model,[0 0.6 1 1.5],options);
    assert_close (ob_scope_data(result,4)', [0 0.6 1 1], 2e-9);
    caught = false;
    try ob_signal_values(result,[3 3 2]); catch err
      caught = ! isempty (strfind(err.message,'has not executed'));
    end_try_catch
    assert (caught);

    % Source discontinuities buried inside continuous children are integration
    % boundaries even when output requests and wrapper hits miss the event.
    model = ob_enabled_continuous_example ();
    model.blocks(3).value.blocks(1).type = 'Step';
    model.blocks(3).value.blocks(1).value = [0.375 2 5];
    model.edges = [2 1 3 1;3 1 4 1];
    model.inputs = {ob_input_signal(0,1)};
    model.sample_times(3,:) = [0.5 0];
    result = ob_run (model,[0 1],options);
    assert_close (ob_scope_data(result,4)', [0 3.875], 2e-9);

    % Minor-stage/output snapshots must not replace the previous major-hit
    % input used by inherited Unit Delay and forward Euler updates.
    model = ob_enabled_continuous_example ();
    child = model.blocks(3).value;
    child.blocks(4) = child.blocks(1); child.blocks(4).type = 'Time'; child.blocks(4).value = [];
    child.blocks(5) = child.blocks(2); child.blocks(5).type = 'Unit Delay';
    child.blocks(6) = child.blocks(3); child.blocks(6).value = 2;
    child.blocks(7) = child.blocks(2); child.blocks(7).type = 'Discrete Integrator';
    child.blocks(8) = child.blocks(3); child.blocks(8).value = 3;
    child.edges = [ob_edges(child);4 1 5 1;5 1 6 1;4 1 7 1;7 1 8 1];
    child.execution.initial_outputs = {-1,0,0};
    model.blocks(3).value = child;
    model.inputs = {ob_input_signal(0,1)};
    result = ob_run (model,[0 .1 .25 .4 .5 .75 1],options);
    delays = ob_signal_values (result,3,2);
    euler = ob_signal_values (result,3,3);
    assert_close (cell2mat(delays)',[0 0 0 0 .25 .5 .75],2e-9);
    assert_close (cell2mat(euler)',[0 0 0 0 .0625 .1875 .375],2e-9);
    core = find (strcmp({result.compiled_model.blocks.type},'Conditional Subsystem'));
    assert (isequal(result.flat_values{end,core}.executions,0:.25:1));
    assert (isequal(result.flat_values{end,core}.child.sample_hits{5},0:.25:1));
  endfor

  % An inactive continuous child must not evaluate invalid user code, either
  % at initialization or in parent solver stages.
  model = ob_enabled_continuous_example ();
  child = model.blocks(3).value;
  child.blocks(4) = child.blocks(2); child.blocks(4).type = 'Function';
  child.blocks(4).name = 'ob_no_such_enabled_function'; child.blocks(4).value = [];
  child.edges = [1 1 4 1;4 1 2 1;2 1 3 1];
  model.blocks(3).value = child;
  model.inputs = {ob_input_signal(0,0)};
  result = ob_run (model,[0 0.5 1]);
  assert_close (ob_scope_data(result,4)', [-1 -1 -1], 0);

  % Errors during derivative evaluation leave all nested state and histories
  % unchanged. Retrying a safe time must produce the same independent context.
  model.blocks(3).value.blocks(4).name = 'sqrt';
  model.blocks(1).type = 'Inport'; model.blocks(1).value = 1;
  model.blocks(2).value = 2;
  model.inputs = {ob_input_signal([0 0.5],[1;-1]),ob_input_signal(0,1)};
  model.sample_times(3,:) = [0.1 0];
  for solver = {'rk4','ode45','ode15s'}
    options = struct ('solver',solver{1},'reltol',1e-9,'abstol',1e-11);
    runtime = ob_runtime_step (ob_runtime_init(model,0,options),0.25);
    saved = runtime; caught = false;
    try
      runtime = ob_runtime_step (runtime,0.75);
    catch err
      caught = ! isempty (strfind(err.message,'derivative must be finite'));
    end_try_catch
    assert (caught && isequaln(runtime,saved));
    retry = ob_runtime_step (runtime,0.4);
    assert_close (ob_runtime_outputs(retry,4),0.4,2e-9);

    % A genuine user-function domain exception also rolls back, rather than
    % only failures discovered by the derivative shape/type validator.
    domain = model; domain.blocks(3).value.blocks(4).name = 'chol';
    runtime = ob_runtime_step (ob_runtime_init(domain,0,options),0.25);
    saved = runtime; caught = false;
    try
      runtime = ob_runtime_step (runtime,0.75);
    catch err
      caught = ! isempty (strfind(err.message,'positive definite'));
    end_try_catch
    assert (caught && isequaln(runtime,saved));
    retry = ob_runtime_step (runtime,0.4);
    assert_close (ob_runtime_outputs(retry,4),0.4,2e-9);
  endfor

  % Copies fork state; MAT checkpoints retain active and paused contexts.
  model = ob_enabled_continuous_example ();
  runtime = ob_runtime_step (ob_runtime_init(model),0.5);
  saved = runtime;
  short = ob_runtime_step (runtime,0.75);
  long = ob_runtime_step (runtime,2.5);
  assert (isequaln(runtime,saved));
  assert_close (ob_runtime_outputs(short,4),0.75,1e-12);
  assert_close (ob_runtime_outputs(long,4),1.5,1e-12);
  paused = ob_runtime_step (runtime,1.5);
  file = [tempname() '.mat'];
  unwind_protect
    save ('-mat7-binary',file,'runtime','paused'); restored = load(file);
    assert (isequaln(ob_runtime_step(runtime,2.5),ob_runtime_step(restored.runtime,2.5)));
    assert (isequaln(ob_runtime_step(paused,2.5),ob_runtime_step(restored.paused,2.5)));
  unwind_protect_cleanup
    if (exist(file,'file')), unlink(file); endif
  end_unwind_protect

  % Triggered continuous states remain invalid and must preserve the existing
  % source file when export validation fails.
  model.blocks(3).value.execution.mode = 'rising';
  file = [tempname() '.c'];
  unwind_protect
    fid = fopen(file,'w'); fputs(fid,'existing source'); fclose(fid);
    caught = false;
    try ob_codegen(model,file); catch err
      caught = ! isempty (strfind(lower(err.message),'continuous'));
    end_try_catch
    assert (caught && strcmp(fileread(file),'existing source'));
  unwind_protect_cleanup
    if (exist(file,'file')), unlink(file); endif
  end_unwind_protect
  disp ('Octave Blocks continuous enabled subsystem tests passed');
endfunction

function model = coupled_oscillator ()
  child.blocks = struct ('type',{'Inport','Gain','Integrator','Outport'}, ...
      'value',{1,-1,0,1},'name',{'Parent state','Negative','Child state','Child output'}, ...
      'x',{0.1,0.35,0.6,0.9},'y',{0.5,0.5,0.5,0.5});
  child.edges = [1 1 2 1;2 1 3 1;3 1 4 1];
  child.execution = struct ('mode','enabled','initial_outputs',{{0}});
  model.blocks = struct ('type',{'Integrator','Constant','Subsystem','Scope','Scope'}, ...
      'value',{1,1,child,[],[]},'name',{'Parent state','Enable','Child','x','y'}, ...
      'x',{0.15,0.15,0.5,0.85,0.85},'y',{0.7,0.3,0.5,0.7,0.3});
  model.edges = [1 1 3 1;2 1 3 2;3 1 1 1;1 1 4 1;3 1 5 1];
  model.sample_times = [0 0;0 0;0.05 0;0 0;0 0];
endfunction

function assert_close (actual, expected, tolerance)
  assert (isequal(size(actual),size(expected)));
  assert (all(isfinite(actual(:))) && all(abs(actual(:)-expected(:)) <= tolerance));
endfunction
