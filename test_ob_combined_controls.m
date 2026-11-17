function test_ob_combined_controls ()
  for solver = {'rk4','ode45','ode15s'}
    options = struct('solver',solver{1},'reltol',1e-8,'abstol',1e-10,'maxstep',.08);
    model = ob_combined_control_example ();
    result = ob_run(model,0:6,options);
    assert(ob_scope_data(result,5)',[-1 0 0 0 0 1 1]);
    assert(snapshot(result,4).executions,[1 5]);
    model.blocks(4).value.execution.states = 'reset';
    assert(ob_scope_data(ob_run(model,0:6,options),5)',[-1 0 0 0 0 0 0]);
    model.blocks(4).value.execution.outputs = 'reset';
    assert(ob_scope_data(ob_run(model,0:6,options),5)',[-1 0 0 -1 -1 0 0]);
    model.blocks(4).value.execution.mode = 'enabled_either';
    model.blocks(4).value.execution.states = 'held';
    model.blocks(4).value.execution.outputs = 'held';
    assert(ob_scope_data(ob_run(model,0:6,options),5)',[-1 0 1 1 1 2 5]);
    model.blocks(4).value.execution.mode = 'enabled_falling';
    result = ob_run(model,0:6,options);
    assert(snapshot(result,4).executions,[2 6]);
    assert(ob_scope_data(result,5)',[-1 -1 0 0 0 0 2]);

    % Continuous enable and trigger guards must both be located between sparse outputs.
    model = continuous_model ();
    options.zero_crossings = true;
    result = ob_run(model,[0 1.8],options);
    assert(abs(ob_scope_data(result,7)(end)-1.44)<1e-7);
    assert(max(abs(snapshot(result,6).executions-[.2 1.2]))<2e-8);
    state = snapshot(result,6);
    assert(numel(state.executions)==2);
    assert(any(strcmp({result.events.side},'enable')));
    assert(any([result.events.channel]==2));
    dense = ob_run(model,[0 .3 .8 1.3 1.8],options);
    assert(max(abs(snapshot(dense,6).executions-state.executions))<2e-8);
    % Parent integration uses only held event outputs, never trial-stage values.
    model.blocks(7).type='Integrator'; model.blocks(7).value=0;
    model.blocks(8)=model.blocks(7); model.blocks(8).type='Scope'; model.blocks(8).value=[];
    model.edges(end+1,:)=[7 1 8 1];
    result=ob_run(model,[0 1.8],options);
    assert(abs(ob_scope_data(result,8)(end)-(.04*1+1.44*.6-9*.2))<2e-6);
  endfor

  % Enable reset is lazy: activation without a trigger cannot evaluate the body.
  model=ob_combined_control_example();
  model.blocks(4).value.blocks(2).type='Function';
  model.blocks(4).value.blocks(2).name='combined_body_error';
  model.blocks(4).value.execution.states='reset';
  model.inputs{2}=ob_input_signal(0:6,ones(7,1));
  model.blocks(4).value.execution.initial_control=1;
  runtime=ob_runtime_init(model);
  runtime=ob_runtime_step(runtime,2);
  core=find(strcmp(runtime.types,'Conditional Subsystem'));
  assert(!runtime.states{core}.initialized && runtime.states{core}.reset_pending);
  runtime.model.inputs{2}=ob_input_signal([0 2.75],[-1;1]);
  runtime=ob_runtime_step(runtime,2.5);
  before=runtime;
  failed=false; try ob_runtime_step(runtime,2.75); catch failed=true; end_try_catch
  assert(failed && isequaln(before.states,runtime.states));
  % Checkpoint persistence retains separate enable and trigger history.
  model=ob_combined_control_example(); runtime=ob_runtime_init(model);
  runtime=ob_runtime_step(runtime,1); runtime=ob_runtime_step(runtime,2);
  saved=runtime;
  for t=3:6, runtime=ob_runtime_step(runtime,t); endfor
  for t=3:6, saved=ob_runtime_step(saved,t); endfor
  assert(isequaln(runtime,saved));
  fprintf('combined controls: passed\n');
endfunction

function state=snapshot(result,id)
  core=find(strcmp({result.compiled_model.blocks.type},'Conditional Subsystem'));
  for k=core
    if(result.block_paths{k}(1)==id),state=result.flat_values{end,k};return;endif
  endfor
  error('combined test: missing conditional snapshot');
endfunction

function model=continuous_model()
  child=ob_subsystem_template(); child.blocks(2).type='Function'; child.blocks(2).name='times';
  child.blocks(2).value=[]; child.edges=[1 1 2 1;1 1 2 2;2 1 3 1];
  child.execution=struct('mode','enabled_rising','control','continuous','initial_outputs',{{-9}});
  model.blocks=struct('type',{'Time','Function','Function','Constant','Constant','Subsystem','Scope'}, ...
      'value',{[],[],[],0,0,child,[]}, ...
      'name',{'Time','ob_combined_enable_wave','ob_combined_trigger_wave','unused','unused','combined','Output'}, ...
      'x',{.1,.3,.3,.1,.1,.6,.9},'y',{.8,.6,.3,.1,.1,.5,.5});
  model.edges=[1 1 2 1;1 1 3 1;1 1 6 1;2 1 6 2;3 1 6 3;6 1 7 1];
endfunction
