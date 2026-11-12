function [cases, api] = test_ob_inner_clock_c_cases ()
  % C-export fixtures with independent enabled clocks and analytical checks.
  % Parent test_ob_codegen performs strict compilation and full-channel parity.
  cases = struct ('name',{},'model',{},'config',{});
  base = ob_enabled_multirate_example ();
  add ('inner_clock_sparse',base,[0 1 1],[.375 .25]);
  add ('inner_clock_dense',base,[0 1 .0625],[.375 .25]);
  model = base; model.sample_times(3,:) = [.25 .125];
  add ('inner_clock_hidden',model,[0 1 1],[.375 .25]);
  model = base; model.sample_times(3,:) = [0 0];
  add ('inner_clock_inherited_control',model,[0 1 1],[.375 .25]);

  model = base; model.sample_times(3,:) = [.5 .125];
  model.inputs = {ob_input_signal(0,1)};
  model.blocks(3).value.sample_times(2:3,:) = [.25 .0625;.25 .125];
  add ('inner_clock_offsets',model,[0 1 .1],[.5 .75]);
  model = base;
  model.inputs = {ob_input_signal([10 10.375 10.875],[0;1;0])};
  add ('inner_clock_nonzero_origin',model,[10 11 .25],[.375 .25]);
  model = base; model.inputs = {ob_input_signal(0,1)};
  model.sample_times(3,:) = [.25 .125];
  model.blocks(3).value.sample_times(2:3,:) = [.1 .03;.1 .03];
  add ('inner_clock_decimal_origin',model,[1000 1001 .2],[.8 .8]);
  model.sample_times(3,:) = [.1 .07];
  model.blocks(3).value.sample_times(2:3,:) = [.1 .07;.1 .07];
  add ('inner_clock_decimal_coincidence',model,[1000 1000.17 .17],[.1 .1]);
  model.sample_times(3,:) = [8 0];
  model.blocks(3).value.sample_times(2:3,:) = [8 2;8 2];
  add ('inner_clock_large_origin',model,[1e16 1e16+24 24],[16 16]);

  model = base; data = [1 -2;3 .5]; model.blocks(1).value = data;
  model.blocks(3).value.blocks(2).value = zeros(2);
  model.blocks(3).value.blocks(3).value = zeros(2);
  model.blocks(3).value.execution.initial_outputs = {zeros(2),zeros(2)};
  add ('inner_clock_matrix',model,[0 1 .1],{.375*data,.25*data});

  for states = {'held','reset'}
    for outputs = {'held','reset'}
      model = paused_model ();
      model.blocks(3).value.execution.states = states{1};
      model.blocks(3).value.execution.outputs = outputs{1};
      if (strcmp(outputs{1},'reset')), expected = [0 0];
      elseif (strcmp(states{1},'reset')), expected = [1.5 .5];
      else expected = [1.5 1]; endif
      add (['inner_clock_pause_' states{1} '_' outputs{1}],model,[0 2 .125],expected);
    endfor
  endfor
  model = paused_model (); model.blocks(3).value.blocks(2).type = 'Rate Transition';
  add ('inner_clock_pause_transition',model,[0 2 .125],[1.75 1]);

  model = base; model.blocks(3).value = nested_body (model.blocks(3).value);
  add ('inner_clock_nested_enabled',model,[0 1 .1],[.375 .25]);
  inherited = model; inherited.inputs = {ob_input_signal(0,1)};
  inherited.sample_times(3,:) = [.5 0];
  inherited.blocks(3).value.sample_times(3,:) = [0 0];
  add ('inner_clock_nested_union',inherited,[0 1 .1],[1 1]);
  stronger = inherited;
  inner = stronger.blocks(3).value.blocks(3).value;
  inner.blocks(6) = inner.blocks(2); inner.blocks(6).name = 'Inherited Euler';
  inner.blocks(7) = inner.blocks(4); inner.blocks(7).value = 3;
  inner.edges = [inner.edges;1 1 6 1;6 1 7 1]; inner.sample_times(6:7,:) = zeros(2);
  inner.execution.initial_outputs = {0,0,0};
  outer = stronger.blocks(3).value; outer.blocks(3).value = inner;
  outer.blocks(6) = outer.blocks(4); outer.blocks(6).value = 3;
  outer.edges(end+1,:) = [3 3 6 1]; outer.sample_times(6,:) = [0 0];
  outer.execution.initial_outputs = {0,0,0}; stronger.blocks(3).value = outer;
  stronger.blocks(6) = stronger.blocks(4); stronger.edges(end+1,:) = [3 3 6 1];
  stronger.sample_times(6,:) = [0 0];
  add ('inner_clock_nested_union_inherited_euler',stronger,[0 1 .1],[1 1 1]);
  stronger.inputs = {ob_input_signal([0 .5 1],[1;0;1])};
  add ('inner_clock_nested_union_inherited_pause',stronger,[0 1.5 .1],[1 1 1]);
  model.blocks(3).value.blocks(2).type = 'Inport';
  model.blocks(3).value.blocks(2).value = 2;
  model.blocks(3).value.execution.mode = 'virtual';
  model.sample_times(3,:) = [0 0];
  add ('inner_clock_nested_virtual',model,[0 1 .1],[.375 .25]);
  model = timed_wrapper_model ();
  add ('inner_clock_nested_wrapper_euler',model,[0 2 .1],2);

  model = mixed_continuous_model ();
  add ('inner_clock_continuous_child',model,[0 1 .1],[.375 .25 .5]);
  model = coupled_model ();
  add ('inner_clock_coupled_continuous',model,[0 2 .05], ...
       [cos(2),-sin(2),1.8125],2e-7);
  model = step_to_parent_model ();
  add ('inner_clock_flow_step_parent',model,[0 1 1],[3.875 1]);

  model = domain_model (false);
  add ('inner_clock_inactive_domain',model,[0 2 .1],[2 2]);
  model = domain_model (true);
  add ('inner_clock_host',model,[0 1 .1],[2 2]);

  % Inherited Delay/Euler inputs must retain their prior major-hit snapshot
  % while independently clocked sample-and-hold exposes current hit values.
  model = mixed_discrete_model ();
  add ('inner_clock_inherited_discrete',model,[0 1 .1],[.5 .25 1]);
  model.blocks(2).value.sample_times(2,:) = [.25 0];
  add ('inner_clock_mixed_delay_clocks',model,[0 1 .1],[.75 .25 1]);

  lines = {'#include <assert.h>','#include <stdio.h>','#include "inner_clock_host.c"', ...
    'typedef struct {int mode;} provider_data;', ...
    'static int provider(double time,int left,double *out,size_t count,void *user){', ...
    '  provider_data *data=(provider_data*)user;if(count!=2)return 1;', ...
    '  if(data->mode==2&&time>0.6)return 17;', ...
    '  out[0]=4.0;out[1]=1.0;', ...
    '  if(data->mode==1&&time>0.6)out[0]=-1.0;', ...
    '  if(data->mode==3&&time>0.6)out[0]=NAN;', ...
    '  if(data->mode==4){', ...
    '    const int paused=(time>0.5||(time==0.5&&!left))&&(time<1.5||(time==1.5&&left));', ...
    '    if(paused){out[0]=-1.0;out[1]=0.0;}', ...
    '  }return OB_OK;}', ...
    'static size_t signal(const char *path){', ...
    '  for(size_t b=0;b<OB_BLOCK_COUNT;++b)if(strcmp(ob_block_path[b],path)==0)return ob_block_offset[b];', ...
    '  assert(!"Missing output signal");return 0;}', ...
    'int main(void){ob_model model,other,saved,independent;provider_data data={0};', ...
    '  const size_t fast=signal("4"),slow=signal("5");', ...
    '  assert(ob_model_init_inputs(&model,0.0,provider,NULL,&data)==OB_OK);', ...
    '  assert(ob_model_init(&other,0.0)==OB_OK);independent=other;', ...
    '  assert(ob_model_step(&model,0.25)==OB_OK);', ...
    '  assert(fabs(model.value[fast]-0.5)<1e-12&&fabs(model.value[slow]-0.5)<1e-12);saved=model;', ...
    '  for(int mode=1;mode<=3;++mode){data.mode=mode;', ...
    '    assert(ob_model_step(&model,0.75)==(mode==2?OB_INPUT_ERROR:OB_NONFINITE));', ...
    '    /* Includes the entire root clock_tick inventory and nested pending buffers. */', ...
    '    assert(memcmp(&model,&saved,sizeof(model))==0);', ...
    '    assert(memcmp(&other,&independent,sizeof(other))==0);}', ...
    '  data.mode=0;assert(ob_model_outputs(&model)==OB_OK);', ...
    '  assert(memcmp(&model,&saved,sizeof(model))==0);', ...
    '  assert(ob_model_step(&model,0.28)==OB_OK);', ...
    '  assert(fabs(model.value[fast]-0.5)<1e-12&&fabs(model.value[slow]-0.5)<1e-12);', ...
    '  data.mode=4;assert(ob_model_init_inputs(&model,0.0,provider,NULL,&data)==OB_OK);', ...
    '  assert(ob_model_step(&model,1.25)==OB_OK);', ...
    '  assert(fabs(model.value[fast]-0.75)<1e-12&&fabs(model.value[slow]-0.5)<1e-12);saved=model;', ...
    '  assert(ob_model_outputs(&model)==OB_OK);assert(memcmp(&model,&saved,sizeof(model))==0);', ...
    '  assert(ob_model_step(&model,1.5)==OB_OK);', ...
    '  assert(fabs(model.value[fast]-1.0)<1e-12&&fabs(model.value[slow]-1.0)<1e-12);', ...
    '  assert(ob_model_step(&model,1.75)==OB_OK);', ...
    '  assert(fabs(model.value[fast]-1.5)<1e-12&&fabs(model.value[slow]-1.5)<1e-12);', ...
    '  assert(ob_model_step(&other,1.75)==OB_OK);', ...
    '  assert(fabs(other.value[fast]-3.5)<1e-12&&fabs(other.value[slow]-3.5)<1e-12);', ...
    '  puts("C enabled inner-clock rollback, inactive pause, and instance tests passed");return 0;}'};
  api = struct ('name','api_inner_clocks','source','api_inner_clocks.c', ...
                'text',strjoin(lines,char(10)));

  fprintf ('Prepared %d enabled inner-clock C fixtures with analytical checks\n',numel(cases));

  function add (name, model, config, expected, tolerance = 1e-11)
    result = ob_run (model,ob_time_grid(config(1),config(2),config(3)));
    scopes = find (strcmp({model.blocks.type},'Scope'));
    if (!iscell(expected)), expected = num2cell(expected); endif
    assert (numel(scopes)==numel(expected),['fixture scope count: ' name]);
    for k = 1:numel(scopes)
      values = ob_signal_values(result,scopes(k)); value = values{end};
      assert (isequal(size(value),size(expected{k})),['fixture output shape: ' name]);
      assert (all(isfinite(value(:))) ...
              && all(abs(value(:)-expected{k}(:))<=tolerance*max(1,abs(expected{k}(:)))), ...
              sprintf('fixture analytical mismatch: %s scope %d actual %s expected %s', ...
                      name,scopes(k),mat2str(value),mat2str(expected{k})));
    endfor
    cases(end+1) = struct ('name',name,'model',model,'config',config);
  endfunction
endfunction

function model = paused_model ()
  model = ob_enabled_multirate_example ();
  model.blocks(1).type = 'Time'; model.blocks(1).value = [];
  child = model.blocks(3).value;
  child.blocks(2).type = 'Unit Delay'; child.sample_times(2:3,:) = [.25 0;.25 0];
  child.blocks(6) = child.blocks(1); child.blocks(6).type = 'Constant'; child.blocks(6).value = 1;
  child.edges(2,1) = 6; child.sample_times(6,:) = [0 0];
  model.blocks(3).value = child;
  model.inputs = {ob_input_signal([0 .375 .875 1.125 1.875],[0;1;0;1;0])};
endfunction

function model = nested_body (inner)
  model.blocks = struct ('type',{'Inport','Constant','Subsystem','Outport','Outport'}, ...
    'value',{1,1,inner,1,2},'name',{'Data','Enable','Inner','Fast','Slow'}, ...
    'x',{.1,.1,.5,.9,.9},'y',{.7,.3,.5,.7,.3});
  model.edges = [1 1 3 1;2 1 3 2;3 1 4 1;3 2 5 1];
  model.sample_times = [0 0;0 0;.25 .125;0 0;0 0];
  model.execution = struct ('mode','enabled','initial_outputs',{{0,0}});
endfunction

function model = timed_wrapper_model ()
  inner = ob_subsystem_template ();
  inner.blocks(2).type = 'Discrete Integrator'; inner.blocks(2).value = 0;
  inner.execution = struct ('mode','enabled','initial_outputs',{{0}});
  outer = nested_body (inner); outer.blocks = outer.blocks(1:4);
  outer.edges = [1 1 3 1;2 1 3 2;3 1 4 1];
  outer.sample_times = [0 0;0 0;.5 0;0 0]; outer.execution.initial_outputs = {0};
  model = ob_enabled_multirate_example (); model.blocks = model.blocks(1:4);
  model.blocks(3).value = outer; model.edges = model.edges(1:3,:);
  model.sample_times = model.sample_times(1:4,:); model.inputs = {ob_input_signal(0,1)};
endfunction

function model = mixed_continuous_model ()
  model = ob_enabled_multirate_example (); child = model.blocks(3).value;
  child.blocks(6) = child.blocks(2); child.blocks(6).type = 'Integrator';
  child.blocks(7) = child.blocks(4); child.blocks(7).value = 3;
  child.edges = [child.edges;1 1 6 1;6 1 7 1]; child.sample_times(6:7,:) = zeros(2);
  child.execution.initial_outputs = {0,0,0}; model.blocks(3).value = child;
  model.blocks(6) = model.blocks(4); model.edges(end+1,:) = [3 3 6 1];
  model.sample_times(6,:) = [0 0];
endfunction

function model = coupled_model ()
  child.blocks = struct ('type',{'Inport','Gain','Integrator','Outport','Time','Unit Delay','Outport'}, ...
    'value',{1,-1,0,1,[],0,2},'name',{'Parent','Negative','Child state','y','Time','Delay','Held time'}, ...
    'x',{.1,.3,.55,.9,.1,.55,.9},'y',{.7,.7,.7,.7,.3,.3,.3});
  child.edges = [1 1 2 1;2 1 3 1;3 1 4 1;5 1 6 1;6 1 7 1];
  child.sample_times = zeros(7,2); child.sample_times(6,:) = [.125 .0625];
  child.execution = struct ('mode','enabled','initial_outputs',{{0,0}});
  model.blocks = struct ('type',{'Integrator','Constant','Subsystem','Scope','Scope','Scope'}, ...
    'value',{1,1,child,[],[],[]},'name',{'Parent','Enable','Child','x','y','Held time'}, ...
    'x',{.1,.1,.5,.9,.9,.9},'y',{.7,.3,.5,.8,.5,.2});
  model.edges = [1 1 3 1;2 1 3 2;3 1 1 1;1 1 4 1;3 1 5 1;3 2 6 1];
  model.sample_times = zeros(6,2); model.sample_times(3,:) = [.25 0];
endfunction

function model = step_to_parent_model ()
  child.blocks = struct ('type',{'Inport','Step','Outport','Unit Delay','Outport'}, ...
    'value',{1,[.375 2 5],1,0,2},'name',{'Data','Step','Flow','Delay','Held'}, ...
    'x',{.1,.1,.9,.5,.9},'y',{.3,.7,.7,.3,.3});
  child.edges = [2 1 3 1;1 1 4 1;4 1 5 1];
  child.sample_times = zeros(5,2); child.sample_times(4,:) = [.25 0];
  child.execution = struct ('mode','enabled','initial_outputs',{{0,0}});
  model.blocks = struct ('type',{'Constant','Constant','Subsystem','Integrator','Scope','Scope'}, ...
    'value',{1,1,child,0,[],[]},'name',{'Data','Enable','Child','Integral','Integral scope','Held scope'}, ...
    'x',{.1,.1,.4,.6,.9,.9},'y',{.7,.3,.5,.7,.7,.3});
  model.edges = [1 1 3 1;2 1 3 2;3 1 4 1;4 1 5 1;3 2 6 1];
  model.sample_times = zeros(6,2); model.sample_times(3,:) = [.5 0];
endfunction

function model = domain_model (host)
  model = ob_enabled_multirate_example (); child = model.blocks(3).value;
  child.blocks(6) = child.blocks(1); child.blocks(6).type = 'Function';
  child.blocks(6).name = 'sqrt'; child.blocks(6).value = [];
  child.edges = [1 1 6 1;6 1 2 1;6 1 3 1;2 1 4 1;3 1 5 1];
  child.sample_times(6,:) = [0 0]; model.blocks(3).value = child;
  if (host)
    model.blocks(1).type = 'Inport'; model.blocks(1).value = 1;
    model.blocks(2).value = 2; model.sample_times(3,:) = [.5 0];
    model.inputs = {ob_input_signal(0,4),ob_input_signal(0,1)};
  else
    model.blocks(1).type = 'Step'; model.blocks(1).value = [1 -1 4];
    model.inputs = {ob_input_signal([0 1],[0;1])};
  endif
endfunction

function model = mixed_discrete_model ()
  child.blocks = struct ('type',{'Time','Unit Delay','Discrete Integrator','Rate Transition','Outport','Outport','Outport'}, ...
    'value',{[],0,0,0,1,2,3},'name',{'Time','Inherited Delay','Inherited Euler','Explicit hold','Delay','Euler','Held'}, ...
    'x',{.1,.5,.5,.5,.9,.9,.9},'y',{.5,.8,.5,.2,.8,.5,.2});
  child.edges = [1 1 2 1;1 1 3 1;1 1 4 1;2 1 5 1;3 1 6 1;4 1 7 1];
  child.sample_times = zeros(7,2); child.sample_times(4,:) = [.125 0];
  child.execution = struct ('mode','enabled','initial_outputs',{{0,0,0}});
  model.blocks = struct ('type',{'Constant','Subsystem','Scope','Scope','Scope'}, ...
    'value',{1,child,[],[],[]},'name',{'Enable','Mixed rates','Delay','Euler','Hold'}, ...
    'x',{.1,.5,.9,.9,.9},'y',{.5,.5,.8,.5,.2});
  model.edges = [1 1 2 1;2 1 3 1;2 2 4 1;2 3 5 1];
  model.sample_times = zeros(5,2); model.sample_times(2,:) = [.5 0];
endfunction
