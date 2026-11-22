function cases = test_ob_event_codegen_hierarchy (directory = '', verify = false, experimental = false)
  % Independent nested lifecycle/source/clock acceptance tests. Analytical
  % expectations are checked before emitting C and comparing every channel.
  if (verify), verify_exports(directory); cases=[]; return; endif
  options=struct('solver','rk4','zero_crossings',true,'maxstep',Inf);
  cases=struct('name',{},'model',{},'config',{},'options',{},'counters',{});

  % The outer activates at .125. The nested body activates at .25; its raw
  % Switch changes at .5, and its private Step doubles the slope at .75.
  % Integral: -.25*2 + .25*3 + .25*6 = 1.75.
  add('event_hierarchy_continuous',nested_sources('continuous','continuous',.125,.25),[0 1 1],1.75);
  % Sampled ancestor first sees its .125 enable change at its .25 hit; its
  % continuously controlled descendant activates at .375 between those hits.
  add('event_hierarchy_sampled_ancestor',nested_sources('sampled','continuous',.125,.375),[0 1 1],2);
  % The reverse mix observes the inner .375 source change at the next .5 hit.
  add('event_hierarchy_sampled_descendant',nested_sources('continuous','sampled',.125,.375),[0 1 1],2.25);
  % Descendant source and guard boundaries passed while inactive must not
  % execute or replay when the ancestor first activates at .875.
  add('event_hierarchy_late_activation',nested_sources('continuous','continuous',.875,.25),[0 1 1],.75);
  dormant=nested_sources('continuous','continuous',.125,.25);
  dormant.blocks(2).type='Constant';dormant.blocks(2).value=-1;
  add('event_hierarchy_dormant',dormant,[0 1 1],-9);

  % Two nested enabled levels share an inherited Euler clock and a separate
  % .25 Delay clock. The first window is [.125,.625), the second [.875,1.5].
  % Held states accumulate 1.125 active seconds; reset states retain .625.
  held=policy_model('held','held');
  add('event_hierarchy_held_euler',held,[0 1.5 .25],[4.125 3.125 1.25],false, ...
      [-9 3.125 3.375 3.5 3.625 3.875 4.125; ...
       -7 2.125 2.375 2.375 2.625 2.875 3.125; ...
       -5 -5 .25 .25 .5 1 1.25]);
  reset=policy_model('reset','held');
  add('event_hierarchy_parent_reset_child_held',reset,[0 1.5 .25],[4.125 3.125 1.25],false, ...
      [-9 3.125 3.375 3.5 3.625 3.875 4.125; ...
       -7 2.125 2.375 2.375 2.625 2.875 3.125; ...
       -5 -5 .25 .25 .5 1 1.25]);
  reset.blocks(3).value.blocks(3).value.execution.states='reset';
  add('event_hierarchy_reset_euler',reset,[0 1.5 .25],[3.625 2.625 1.25],false, ...
      [-9 3.125 3.375 3.5 3.125 3.375 3.625; ...
       -7 2.125 2.375 2.375 2.125 2.375 2.625; ...
       -5 -5 .25 .25 -5 1 1.25]);
  reset_outputs=policy_model('held','reset');
  reset_outputs.inputs={ob_input_signal([0 .125 .625 .875 1.625],[-1;1;-1;1;-1])};
  add('event_hierarchy_output_reset',reset_outputs,[0 1.75 .25],[-9 -7 -5]);

  % At .5 the ancestor enable, its primitive Switch and the inner/root Delay
  % clocks coincide. Newly visible descendants must be reconciled once.
  add('event_hierarchy_coincident',coincident_model(),[0 1 .25],[1.5 .75 .75],true);
  add('event_hierarchy_simultaneous_channels',simultaneous_model(),[0 1 .25],{[.5;1.5]},true);
  add('event_hierarchy_plateau_memory',plateau_model(),[0 1 .25],.5,true);
  % One search from the stop .2 counts block 5's crossing (bisected to
  % .2000000000007276) before block 9's departure from zero at exactly .2,
  % in guard order; last_event_time is still the latest time, Octave's
  % events(end).time (checked exactly by the counter harness).
  bounded=options;bounded.maxstep=.1;
  add('event_hierarchy_staggered_departure',ob_staggered_enables_example(),[0 .5 .1],[.3 -9],true,[],bounded);
  if (isempty(directory)), return; endif
  if (!exist(directory,'dir')),mkdir(directory);endif
  manifest=struct('name',{},'source',{},'standalone',{},'expected',{});
  for item=cases
    source=[item.name '.c'];expected_file=[item.name '.expected.csv'];
    if(experimental)
      info=ob_codegen_conditional(item.model,fullfile(directory,source),item.config,item.options);
    else
      info=ob_codegen(item.model,fullfile(directory,source),item.config,item.options);
    endif
    result=ob_run(item.model,ob_time_grid(item.config(1),item.config(2),item.config(3)),item.options);
    expected=result.t;
    for block=1:numel(result.compiled_model.blocks)
      count=prod(info.shapes{block});if(count==0),continue;endif
      trace=zeros(numel(result.t),count);
      for sample=1:numel(result.t)
        value=result.flat_values{sample,block};
        assert(isnumeric(value)&&isreal(value)&&isequal(size(value),info.shapes{block}));
        trace(sample,:)=value(:)';
      endfor
      assert(all(isfinite(trace(:))));expected=[expected trace];
    endfor
    dlmwrite(fullfile(directory,expected_file),expected,'precision','%.17g');
    manifest(end+1)=struct('name',item.name,'source',source,'standalone',true,'expected',expected_file);
    if(item.counters)
      name=['api_' item.name];source=[name '.c'];
      write_text(fullfile(directory,source),counter_harness(item,result));
      manifest(end+1)=struct('name',name,'source',source,'standalone',false,'expected','');
    endif
  endfor
  write_text(fullfile(directory,'event-hierarchy-manifest.json'),jsonencode(manifest));
  fprintf('Prepared %d nested event C compilation/API cases (%d numeric models)\n',numel(manifest),numel(cases));

  function add(name,model,config,wanted,counters=false,trace=[],settings=options)
    result=ob_run(model,ob_time_grid(config(1),config(2),config(3)),settings);
    scopes=find(strcmp({model.blocks.type},'Scope'));
    if(!iscell(wanted)),wanted=num2cell(wanted);endif
    assert(numel(scopes)==numel(wanted),['hierarchy scope count: ' name]);
    for k=1:numel(scopes)
      values=ob_signal_values(result,scopes(k));actual=values{end};expected=wanted{k};
      assert(isequal(size(actual),size(expected))&&all(isfinite(actual(:))) ...
        && all(abs(actual(:)-expected(:))<2e-8*max(1,abs(expected(:)))), ...
        sprintf('hierarchy analytical mismatch %s scope %d actual %s expected %s',name,k,mat2str(actual),mat2str(expected)));
      if(!isempty(trace))
        actual_trace=cellfun(@(value)value(1),values);
        assert(numel(actual_trace)==columns(trace)&&max(abs(actual_trace(:)'-trace(k,:)))<2e-8, ...
          sprintf('hierarchy trace mismatch %s scope %d actual %s expected %s',name,k,mat2str(actual_trace(:)'),mat2str(trace(k,:))));
      endif
    endfor
    cases(end+1)=struct('name',name,'model',model,'config',config,'options',settings,'counters',counters);
  endfunction
endfunction

function model=nested_sources(outer_mode,inner_mode,outer_start,inner_start)
  leaf=make_model({'Inport','Constant','Constant','Switch','Step','Product','Integrator','Outport'}, ...
                  {1,3,-2,.5,[.75 1 2],[],0,1});
  leaf.edges=[2 1 4 1;1 1 4 2;3 1 4 3;4 1 6 1;5 1 6 2;6 1 7 1;7 1 8 1];
  leaf.execution=execution(inner_mode,{0});
  wrapper=make_model({'Inport','Step','Subsystem','Outport'}, ...
                     {1,[inner_start -1 1],leaf,1});
  wrapper.edges=[1 1 3 1;2 1 3 2;3 1 4 1];
  wrapper.execution=execution(outer_mode,{-9});
  wrapper.sample_times=zeros(4,2);
  if(strcmp(inner_mode,'sampled')),wrapper.sample_times(3,:)=[.25 0];endif
  model=make_model({'Time','Step','Subsystem','Scope'}, ...
                   {[],[outer_start -1 1],wrapper,[]});
  model.edges=[1 1 3 1;2 1 3 2;3 1 4 1];
  model.sample_times=zeros(4,2);
  if(strcmp(outer_mode,'sampled')),model.sample_times(3,:)=[.25 0];endif
endfunction

function model=policy_model(states,outputs)
  leaf=make_model({'Inport','Integrator','Outport','Discrete Integrator','Outport', ...
                    'Time','Unit Delay','Outport'}, {1,3,1,2,2,[],-5,3});
  leaf.edges=[1 1 2 1;2 1 3 1;1 1 4 1;4 1 5 1;6 1 7 1;7 1 8 1];
  leaf.sample_times=zeros(8,2);leaf.sample_times(7,:)=[.25 0];
  leaf.execution=execution('continuous',{-9,-7,-5});
  wrapper=make_model({'Inport','Constant','Subsystem','Outport','Outport','Outport'}, ...
                     {1,1,leaf,1,2,3});
  wrapper.edges=[1 1 3 1;2 1 3 2;3 1 4 1;3 2 5 1;3 3 6 1];
  wrapper.execution=execution('continuous',{-9,-7,-5});
  wrapper.execution.states=states;wrapper.execution.outputs=outputs;
  model=make_model({'Constant','Inport','Subsystem','Scope','Scope','Scope'}, ...
                   {1,1,wrapper,[],[],[]});
  model.edges=[1 1 3 1;2 1 3 2;3 1 4 1;3 2 5 1;3 3 6 1];
  model.inputs={ob_input_signal([0 .125 .625 .875],[-1;1;-1;1])};
endfunction

function model=coincident_model()
  leaf=make_model({'Inport','Constant','Constant','Switch','Integrator','Outport','Time','Unit Delay','Outport'}, ...
                  {1,3,-2,.5,0,1,[],-7,2});
  leaf.edges=[2 1 4 1;1 1 4 2;3 1 4 3;4 1 5 1;5 1 6 1;7 1 8 1;8 1 9 1];
  leaf.sample_times=zeros(9,2);leaf.sample_times(8,:)=[.25 0];
  leaf.execution=execution('continuous',{-9,-7});
  wrapper=make_model({'Inport','Constant','Subsystem','Outport','Outport'}, ...
                     {1,1,leaf,1,2});
  wrapper.edges=[1 1 3 1;2 1 3 2;3 1 4 1;3 2 5 1];
  wrapper.execution=execution('continuous',{-9,-7});
  model=make_model({'Time','Constant','Sum','Subsystem','Scope','Scope','Unit Delay','Scope'}, ...
                   {[],-.5,[],wrapper,[],[],-5,[]});
  model.edges=[1 1 3 1;2 1 3 2;1 1 4 1;3 1 4 2;4 1 5 1;4 2 6 1;1 1 7 1;7 1 8 1];
  model.sample_times=zeros(8,2);model.sample_times(7,:)=[.25 0];
endfunction

function model=simultaneous_model()
  model=make_model({'Time','Gain','Constant','Constant','Switch','Integrator','Scope'}, ...
                   {[],[1;1],[3;4],[-2;-1],.5,[0;0],[]});
  model.edges=[1 1 2 1;3 1 5 1;2 1 5 2;4 1 5 3;5 1 6 1;6 1 7 1];
endfunction

function model=plateau_model()
  model=make_model({'Time','Constant','Sum','Saturation','Gain','Constant','Constant','Switch','Integrator','Scope'}, ...
                   {[],-.5,[],[0 100],-1,1,0,0,0,[]});
  model.edges=[1 1 3 1;2 1 3 2;3 1 4 1;4 1 5 1;6 1 8 1;5 1 8 2;7 1 8 3;8 1 9 1;9 1 10 1];
endfunction

function text=counter_harness(item,result)
  name=item.name;
  lines={'#include <assert.h>','#include <stdio.h>', ['#include "' name '.c"'], ...
         'int main(void){ob_model model,saved;', ...
         sprintf('  assert(ob_model_init(&model,%.17g)==OB_OK);',result.t(1))};
  runtime=ob_runtime_init(item.model,result.t(1),item.options);
  for sample=1:numel(result.t)
    time=result.t(sample);
    if(sample>1)
      lines{end+1}=sprintf('  assert(ob_model_step(&model,%.17g)==OB_OK);',time);
      runtime=ob_runtime_step(runtime,time);
    endif
    % A plateau departure at the stop can be reported on the next advance
    % with the previous stop's timestamp. Compare the accepted checkpoint,
    % not a time-filtered final event log that includes future discoveries.
    % C and Octave locate events with the same bisection arithmetic, so the
    % last time must be identical: a tolerance would hide a record counted
    % out of time order (event_hierarchy_staggered_departure).
    events=runtime.events;
    lines{end+1}=sprintf('  assert(model.event_count==%d);',numel(events));
    if(!isempty(events)),lines{end+1}=sprintf('  assert(model.last_event_time==%.17g);',events(end).time);endif
    lines=[lines {'  saved=model;assert(ob_model_outputs(&model)==OB_OK);', ...
                  '  assert(model.event_count==saved.event_count&&model.last_event_time==saved.last_event_time);'}];
  endfor
  lines=[lines {['  puts("C event count/last-time/no-duplicate output checks passed: ' name '");return 0;}']}];
  text=[strjoin(lines,char(10)) char(10)];
endfunction

function verify_exports(directory)
  manifest=jsondecode(fileread(fullfile(directory,'event-hierarchy-manifest.json')));
  worst=0;compared=0;channels=0;
  for item=reshape(manifest,1,[])
    if(!item.standalone),continue;endif
    expected=dlmread(fullfile(directory,item.expected),',');
    actual=dlmread(fullfile(directory,[item.name '.csv']),',',1,0);
    assert(isequal(size(actual),size(expected)),['hierarchy CSV shape: ' item.name]);
    assert(all(isfinite(actual(:))),['nonfinite hierarchy C output: ' item.name]);
    scaled=abs(actual-expected)./max(1,abs(expected));[error,index]=max(scaled(:));
    [sample,column]=ind2sub(size(expected),index);
    assert(error<2e-8,sprintf('hierarchy C/Octave mismatch %s sample %d column %d: actual %.17g expected %.17g scaled %.17g', ...
      item.name,sample,column,actual(index),expected(index),error));
    worst=max(worst,error);compared+=1;channels+=columns(actual)-1;
  endfor
  fprintf('Compared %d nested event C models (%d numeric channels); worst scaled error %.3g\n',compared,channels,worst);
endfunction

function options=execution(control,outputs)
  options=struct('mode','enabled','control',control,'initial_outputs',{outputs});
endfunction

function model=make_model(types,values)
  count=numel(types);
  model.blocks=struct('type',types,'value',values,'name',types, ...
    'x',num2cell(linspace(.1,.9,count)),'y',num2cell(.5*ones(1,count)));
  model.edges=zeros(0,4);
endfunction

function write_text(file,value)
  fid=fopen(file,'wb');assert(fid>=0);
  unwind_protect
    assert(fwrite(fid,value,'char')==numel(value));
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
