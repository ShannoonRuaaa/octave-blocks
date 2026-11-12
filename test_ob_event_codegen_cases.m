function [cases, api] = test_ob_event_codegen_cases ()
  % Event-export fixtures: analytical checks precede compiled full-channel parity.
  % This factory does not export or compile; test_ob_codegen owns those steps.
  cases = struct ('name',{},'model',{},'config',{},'options',{});
  options = struct ('solver','rk4','zero_crossings',true,'maxstep',Inf);

  rising = switched_integrator (1,.35,3,-2);
  add ('event_switch_rising',rising,[0 1 1],1.25);
  add ('event_switch_output_root',rising,[0 1 .35],1.25);
  add ('event_switch_falling',switched_integrator(-1,-.35,3,-2),[0 1 1],-.25);
  add ('event_initial_zero_departure',switched_integrator(-1,0,1,0),[0 1 1],0);
  add ('event_constant_zero_guard',switched_integrator(0,0,1,0),[0 1 1],1);

  state_guard = make_model ({'Constant','Integrator','Constant','Switch','Scope'}, ...
                            {2,0,1,.3,[]});
  state_guard.edges = [1 1 4 1;2 1 4 2;3 1 4 3;4 1 2 1;2 1 5 1];
  add ('event_state_guard',state_guard,[0 1 1],1.7);
  add ('event_saturation',limited_integrator('Saturation',[.2 .7]),[0 1 1],.475);
  add ('event_dead_zone',limited_integrator('Dead Zone',[.2 .7]),[0 1 1],.025);
  equal = limited_integrator ('Dead Zone',[0 0]);
  equal.blocks(1).type = 'Sum';
  equal = append_block (equal,'Time',[]); equal = append_block(equal,'Constant',-.3);
  equal.edges = [equal.edges;5 1 1 1;6 1 1 2];
  add ('event_equal_boundaries',equal,[0 1 1],.2);

  add ('event_matrix_switch',matrix_switch(),[0 1 1],{[2 1;2 -.5]});
  add ('event_root_discrete_clocks',root_clocks(rising),[0 1 1],[1.25 .75 0 1]);
  stateless = rising; stateless.blocks(6).type = 'Scope'; stateless.blocks(6).value = [];
  add ('event_no_continuous_states',stateless,[0 1 1],[3 3]);
  add ('event_virtual_primitive',nested_primitive('virtual'),[0 1 1],1.25);
  add ('event_sampled_enabled_primitive',nested_primitive('sampled'),[0 1 1],1.25);
  add ('event_continuous_enabled_primitive',nested_primitive('continuous'),[0 1 1],1.25);

  source_step = rising; source_step.blocks(1).type = 'Step';
  source_step.blocks(1).value = [.6 3 5];
  add ('event_step_data_left_limit',source_step,[0 1 1],2.05);
  zoh = rising; zoh.blocks(3).type = 'Inport'; zoh.blocks(3).value = 1;
  zoh.edges(zoh.edges(:,3)==3,:) = [];
  zoh.inputs = {ob_input_signal([0 .35 .8],[-1;1;-1])}; zoh.blocks(5).value = 0;
  add ('event_zoh_control_boundaries',zoh,[0 1 1],.25);
  linear = zoh; linear.inputs = {ob_input_signal([0 1],[-.35;.65],[1 1],'linear')};
  add ('event_linear_input_control',linear,[0 1 1],1.25);
  source_input = rising; source_input.blocks(1).type = 'Inport'; source_input.blocks(1).value = 1;
  source_input.inputs = {ob_input_signal([0 .6],[3;5])};
  add ('event_zoh_data_left_limit',source_input,[0 1 1],2.05);

  oscillating = rising; oscillating.blocks(1).value = 1; oscillating.blocks(4).value = 0;
  oscillating.blocks(3).type = 'Function'; oscillating.blocks(3).name = 'sin';
  oscillating.blocks(5).value = .5;
  oscillating = append_block (oscillating,'Gain',2*pi);
  oscillating.edges(oscillating.edges(:,3)==3,:) = [];
  oscillating.edges = [oscillating.edges;2 1 8 1;8 1 3 1];
  bounded = options; bounded.maxstep = .05;
  add ('event_bounded_oscillation',oscillating,[0 1 1],1/3,2e-8,bounded);

  plateau = plateau_switch ();
  add ('event_zero_plateau_departure',plateau,[0 1 1],.5);
  bounded = options; bounded.maxstep = .1;
  add ('event_plateau_decimal_steps',plateau,[0 1 1],.5,2e-8,bounded);
  add ('event_plateau_output_boundary',plateau,[0 1 .5],.5);

  enabled = window_gate (integrator_body(3),2,.2,.7);
  % Both ends of a complete window have the same sign. Bound the search
  % interval independently of the intentionally coarse output schedule.
  add ('event_enable_product_window',enabled,[0 1 1],4,2e-8,bounded);
  add ('event_enable_root_clocks',root_clocks(enabled),[0 1 1],[4 .75 0 1],2e-8,bounded);
  source_gate = enabled; source_gate.blocks(5).type = 'Inport'; source_gate.blocks(5).value = 1;
  source_gate.edges(source_gate.edges(:,3)==5,:) = [];
  source_gate.inputs = {ob_input_signal([0 .2 .7],[-1;1;-1])};
  add ('event_enable_zoh_window',source_gate,[0 1 1],4);
  source_gate.blocks(5).type = 'Step'; source_gate.blocks(5).value = [.2 -1 1];
  source_gate = rmfield (source_gate,'inputs');
  add ('event_enable_step',source_gate,[0 1 1],4.6);

  for policy = {'held','reset'}
    child = integrator_body (3); child.execution.states = policy{1};
    pulse = sine_gate (child,2);
    if (strcmp(policy{1},'held')), expected = 5; else expected = 4; endif
    add (['event_enable_pause_' policy{1}],pulse,[0 1.8 1.8],expected,2e-8,bounded);
    pulse.blocks(7).value.execution.outputs = 'reset';
    add (['event_enable_output_reset_' policy{1}],pulse,[0 1.8 1.8],-9,2e-8,bounded);
  endfor
  add ('event_enable_feedthrough_reset',feedthrough_parent('reset'),[0 1 1],.225,2e-8,bounded);
  add ('event_enable_feedthrough_held',feedthrough_parent('held'),[0 1 1],.435,2e-8,bounded);

  for mode = {'rising','falling','either'}
    child = squared_body (mode{1}); child.execution.initial_control = -1;
    triggered = sine_gate (child,[]); triggered.blocks(1).type = 'Time';
    if (strcmp(mode{1},'rising')), expected = 1.44; else expected = 2.89; endif
    add (['event_trigger_' mode{1}],triggered,[0 1.8 1.8],expected,2e-8,bounded);
    child.blocks(2).type = 'Unit Delay'; child.blocks(2).value = -7;
    child.edges = [1 1 2 1;2 1 3 1];
    delayed = sine_gate(child,[]); delayed.blocks(1).type = 'Time';
    if (strcmp(mode{1},'rising')), expected = .2;
    elseif (strcmp(mode{1},'falling')), expected = .7; else expected = 1.2; endif
    add (['event_trigger_delay_' mode{1}],delayed,[0 1.8 1.8],expected,2e-8,bounded);
  endfor

  clock_child = mixed_body ();
  clock_child.sample_times = zeros(9,2); clock_child.sample_times(5,:) = [.25 0];
  coincident = window_gate (clock_child,1,.25,.75);
  % Switch equality intentionally enables the body at both exact roots.
  coincident = gate_through_switch (coincident);
  coincident = expose_child_outputs (coincident,3);
  add ('event_coincident_inner_clocks',coincident,[0 1 1],[.5 .5 0],2e-8,bounded);
  add ('event_coincident_root_and_inner_clocks',root_clocks(coincident),[0 1 1],[.5 .5 0 .75 0 1],2e-8,bounded);

  host = host_model ();
  add ('event_host_inputs',host,[0 1 1],1.25);
  chatter = chatter_model ();
  add ('event_host_chatter',chatter,[0 1 1],1);
  % Harness descriptors deliberately use only the stable public APIs. A root
  % event return code can be asserted once the emitter's status enum is fixed.
  api = struct ('name',{},'model_name',{},'checks',{});
  api(end+1) = struct ('name','api_event_inputs','model_name','event_host_inputs', ...
      'checks',{{'NULL model/time arguments return OB_BAD_ARGUMENT without mutation', ...
        'Interleaved independent contexts retain separate state and input providers', ...
        'Provider high=4, control=t-.35 gives x(1)=1.9', ...
        'Failure code after t>.6 returns OB_INPUT_ERROR and preserves complete context via memcmp', ...
        'NAN callback after t>.6 returns OB_NONFINITE and preserves complete context via memcmp', ...
        'Same-time provider reconcile at t=.5 preserves x and changes only current outputs/provider data', ...
        'Provider high=6 at t=.5 after high=4 gives x(1)=2.9', ...
        'Failed initial/provider callbacks preserve previous complete initialized context', ...
        'Restoring compiled tables at the current time does not replay earlier crossings'}});
  api(end+1) = struct ('name','api_event_chatter','model_name','event_host_chatter', ...
      'checks',{{'Compiled input high=1 gives x(1)=1', ...
        'After x(.25)=.25, provider high=-1 creates inward fields and must fail stepping through x=0', ...
        'Chattering/event failure preserves complete context via memcmp', ...
        'Another interleaved context remains byte-identical', ...
        'Restoring high=1 permits a retry from the original accepted state'}});
  fprintf ('Prepared %d event C fixtures with analytical checks\n',numel(cases));

  function add (name, model, config, expected, tolerance = 2e-8, settings = options)
    result = ob_run (model,ob_time_grid(config(1),config(2),config(3)),settings);
    scopes = find (strcmp({model.blocks.type},'Scope'));
    if (! iscell(expected)), expected = num2cell(expected); endif
    assert(numel(scopes)==numel(expected),['event fixture scope count: ' name]);
    for scope_index = 1:numel(scopes)
      values = ob_signal_values (result,scopes(scope_index)); actual = values{end};
      wanted = expected{scope_index};
      assert(isequal(size(actual),size(wanted)),['event fixture output shape: ' name]);
      assert(all(isfinite(actual(:))) && all(abs(actual(:)-wanted(:))<=tolerance*max(1,abs(wanted(:)))), ...
          sprintf('event fixture analytical mismatch: %s scope %d actual %s expected %s', ...
                  name,scopes(scope_index),mat2str(actual),mat2str(wanted)));
    endfor
    cases(end+1) = struct('name',name,'model',model,'config',config,'options',settings);
  endfunction
endfunction

function model = switched_integrator (slope, threshold, high, low)
  model = make_model ({'Constant','Time','Gain','Constant','Switch','Integrator','Scope'}, ...
                      {high,[],slope,low,threshold,0,[]});
  model.edges = [1 1 5 1;2 1 3 1;3 1 5 2;4 1 5 3;5 1 6 1;6 1 7 1];
endfunction

function model = limited_integrator (type, limits)
  model = make_model ({'Time',type,'Integrator','Scope'},{[],limits,0,[]});
  model.edges = [1 1 2 1;2 1 3 1;3 1 4 1];
endfunction

function model = matrix_switch ()
  model = make_model ({'Time','Gain','Constant','Sum','Constant','Switch','Integrator','Scope','Constant'}, ...
      {[],ones(2),[-.2 -.4;-.2 -.7],[],3*ones(2),0,zeros(2),[],-2*ones(2)});
  model.edges = [1 1 2 1;2 1 4 1;3 1 4 2;5 1 6 1;4 1 6 2;9 1 6 3;6 1 7 1;7 1 8 1];
endfunction

function model = root_clocks (model)
  count = numel(model.blocks); time = find(strcmp({model.blocks.type},'Time'),1);
  if (isempty(time)), model = append_block(model,'Time',[]); time = numel(model.blocks); count += 1; endif
  for entry = {{'Unit Delay',-9},{'Scope',[]},{'Unit Delay',-5},{'Scope',[]}, ...
               {'Discrete Integrator',0},{'Scope',[]},{'Constant',1}}
    model = append_block (model,entry{1}{1},entry{1}{2});
  endfor
  model.edges = [model.edges;time 1 count+1 1;count+1 1 count+2 1; ...
      time 1 count+3 1;count+3 1 count+4 1;count+7 1 count+5 1;count+5 1 count+6 1];
  model.sample_times = zeros(count+7,2); model.sample_times(count+1,:) = [.25 0];
endfunction

function model = nested_primitive (mode)
  child = make_model ({'Inport','Constant','Constant','Switch','Integrator','Outport'}, ...
                      {1,3,-2,.35,0,1});
  child.edges = [2 1 4 1;1 1 4 2;3 1 4 3;4 1 5 1;5 1 6 1];
  child.execution = execution ('enabled',{0});
  if (strcmp(mode,'virtual')), child.execution.mode = 'virtual';
  elseif (strcmp(mode,'sampled')), child.execution.control = 'sampled'; endif
  model = make_model ({'Time','Subsystem','Scope'},{[],child,[]});
  model.edges = [1 1 2 1;2 1 3 1];
  if (! strcmp(mode,'virtual'))
    model = append_block (model,'Constant',1); model.edges(end+1,:) = [4 1 2 2];
    if (strcmp(mode,'sampled')), model.sample_times = [0 0;.25 0;0 0;0 0]; endif
  endif
endfunction

function model = plateau_switch ()
  model = switched_integrator (1,0,1,0);
  model.blocks(3).type = 'Gain'; model.blocks(3).value = -1;
  model = append_block (model,'Constant',-.5);
  model = append_block (model,'Sum',[]);
  model = append_block (model,'Saturation',[0 100]);
  model.edges(model.edges(:,3)==3,:) = [];
  model.edges = [model.edges;2 1 9 1;8 1 9 2;9 1 10 1;10 1 3 1];
endfunction

function child = integrator_body (initial)
  child = make_model ({'Inport','Integrator','Outport'},{1,initial,1});
  child.edges = [1 1 2 1;2 1 3 1]; child.execution = execution ('enabled',{-9});
endfunction

function child = squared_body (mode)
  child = make_model ({'Inport','Product','Outport'},{1,[],1});
  child.edges = [1 1 2 1;1 1 2 2;2 1 3 1]; child.execution = execution(mode,{-9});
endfunction

function child = mixed_body ()
  child = make_model ({'Inport','Integrator','Outport','Time','Unit Delay','Outport', ...
      'Constant','Discrete Integrator','Outport'},{1,0,1,[],-7,2,1,0,3});
  child.edges = [1 1 2 1;2 1 3 1;4 1 5 1;5 1 6 1;7 1 8 1;8 1 9 1];
  child.execution = execution('enabled',{-9,-7,0});
endfunction

function model = window_gate (child, data, first, last)
  model = make_model ({'Constant','Time','Constant','Sum','Product','Gain','Constant','Sum','Subsystem','Scope'}, ...
                      {data,[],-first,[],[],-1,last,[],child,[]});
  model.edges = [2 1 4 1;3 1 4 2;2 1 6 1;7 1 8 1;6 1 8 2; ...
                 4 1 5 1;8 1 5 2;1 1 9 1;5 1 9 2;9 1 10 1];
endfunction

function model = sine_gate (child, data)
  model = make_model ({'Constant','Time','Constant','Sum','Gain','Function','Subsystem','Scope'}, ...
                      {data,[],-.2,[],2*pi,[],child,[]});
  model.blocks(6).name = 'sin';
  model.edges = [2 1 4 1;3 1 4 2;4 1 5 1;5 1 6 1;1 1 7 1;6 1 7 2;7 1 8 1];
endfunction

function model = feedthrough_parent (policy)
  child = ob_subsystem_template (); child.blocks(2).value = 1;
  child.execution = execution('enabled',{0}); child.execution.outputs = policy;
  model = window_gate(child,[],.2,.7); model.blocks(1).type = 'Time';
  model.blocks(10).type = 'Integrator'; model.blocks(10).value = 0;
  model = append_block(model,'Scope',[]); model.edges(end+1,:) = [10 1 11 1];
endfunction

function model = gate_through_switch (model)
  model = append_block(model,'Constant',1); high = numel(model.blocks);
  model = append_block(model,'Constant',-1); low = numel(model.blocks);
  model = append_block(model,'Switch',0); gate = numel(model.blocks);
  model.edges(model.edges(:,3)==9 & model.edges(:,4)==2,:) = [];
  model.edges = [model.edges;high 1 gate 1;5 1 gate 2;low 1 gate 3;gate 1 9 2];
endfunction

function model = expose_child_outputs (model, count)
  for port = 2:count
    model = append_block(model,'Scope',[]);
    model.edges(end+1,:) = [9 port numel(model.blocks) 1];
  endfor
endfunction

function model = host_model ()
  model = switched_integrator(1,0,3,-2);
  model.blocks(1).type = 'Inport'; model.blocks(1).value = 1;
  model.blocks(3).type = 'Inport'; model.blocks(3).value = 2;
  model.edges(model.edges(:,3)==3,:) = [];
  model.inputs = {ob_input_signal(0,3),ob_input_signal([0 1],[-.35;.65],[1 1],'linear')};
endfunction

function model = chatter_model ()
  model = make_model ({'Inport','Constant','Integrator','Switch','Scope'}, {1,1,0,0,[]});
  model.edges = [1 1 4 1;3 1 4 2;2 1 4 3;4 1 3 1;3 1 5 1];
  model.inputs = {ob_input_signal(0,1)};
endfunction

function options = execution (mode, outputs)
  options = struct('mode',mode,'control','continuous','initial_outputs',{outputs});
endfunction

function model = append_block (model, type, value)
  block = model.blocks(1); block.type = type; block.value = value; block.name = type;
  model.blocks(end+1) = block;
endfunction

function model = make_model (types, values)
  count = numel(types);
  model.blocks = struct('type',types,'value',values,'name',types, ...
      'x',num2cell(linspace(.1,.9,count)),'y',num2cell(.5*ones(1,count)));
  model.edges = zeros(0,4);
endfunction
