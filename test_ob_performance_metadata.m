function test_ob_performance_metadata ()
  % Category indexes are optional additions to the serializable v1 cache.
  fields = {'conditional_ids','integrator_ids','step_ids','zc_ids', ...
            'continuous_path_ids','boundary_ids'};
  models = {ob_control_example(),ob_enabled_continuous_example(),ob_oscillator()};
  step = ob_example(); step.blocks(1).type='Step'; step.blocks(1).value=[.3 0 1];
  models{end+1}=step;
  for model = models
    prepared = ob_prepare_runtime_model(ob_compile_model(model{1}));
    assert_categories(prepared);
    rebuilt = prepared;
    for field = fields, rebuilt.runtime_info.(field{1})=-99; endfor
    rebuilt = ob_prepare_runtime_model(rebuilt);
    assert(isequal(rebuilt.runtime_info,prepared.runtime_info));
  endfor
  empty.blocks=struct('type',{},'value',{},'name',{},'x',{},'y',{});
  empty.edges=zeros(0,2);
  empty=ob_prepare_runtime_model(ob_compile_model(empty));
  assert_categories(empty);

  % Category-less v1 checkpoints, cache-less checkpoints, unknown cache kinds,
  % and incomplete cache records all resume through the general lookup paths.
  model=ob_enabled_continuous_example();
  model.blocks(3).value.execution.control='continuous';
  model.sample_times=zeros(4,2);
  options=struct('zero_crossings',true,'maxstep',.2);
  reference=ob_runtime_step(ob_runtime_init(model,0,options),.4);
  variants={without_categories(reference),without_cache(reference), ...
            change_cache(reference,'unknown'),change_cache(reference,'incomplete'), ...
            change_cache(reference,'invalid_categories')};
  for time=[.8 1.4 2.4]
    reference=ob_runtime_step(reference,time);
    for index=1:numel(variants)
      variants{index}=ob_runtime_step(variants{index},time);
      assert(isequaln(ob_runtime_outputs(reference),ob_runtime_outputs(variants{index})));
      assert(isequaln(without_cache(reference),without_cache(variants{index})));
    endfor
  endfor

  % An incomplete cached descriptor must fall back to ordinary body validation.
  prepared=ob_prepare_runtime_model(ob_compile_model(model));
  id=prepared.runtime_info.conditional_ids;
  descriptor=prepared.runtime_info.conditional{id};
  broken=prepared; broken.runtime_info.conditional{id}=rmfield(descriptor,'input_ports');
  assert(isequal(ob_runtime_execution(broken,id),descriptor));
  broken.blocks(id).value.execution.mode='rising';
  assert_error(@()ob_runtime_execution(broken,id),'triggered bodies');
  [order,edges]=ob_execution_order(broken,true);
  assert_error(@()ob_runtime_eval(broken,edges,order,reference.time,reference.states),'triggered bodies');

  % Source routes remain immutable while host values and derivative shapes
  % are checked at every stage; failed assignments leave the caller untouched.
  matrix=ob_example(); matrix.blocks(1).type='Constant';matrix.blocks(1).value=[1 2;3 4];
  matrix.blocks(2).type='Integrator';matrix.blocks(2).value=zeros(2);
  context=ob_runtime_init(matrix); saved=context;
  context=ob_runtime_step(context,1);
  assert(isequal(ob_runtime_outputs(context,3),[1 2;3 4]));
  bad=saved;bad.model.blocks(1).value=[1 2];before=bad;
  caught=false;
  try bad=ob_runtime_step(bad,1); catch err,caught=!isempty(strfind(err.message,'state shape'));end_try_catch
  assert(caught && isequaln(bad,before));
  bad=saved;bad.model.blocks(1).value(1)=Inf;before=bad;caught=false;
  try bad=ob_runtime_step(bad,1); catch err,caught=!isempty(strfind(err.message,'finite'));end_try_catch
  assert(caught && isequaln(bad,before));

  % Output-map shortcuts retain public argument and complete-context checks.
  assert_error(@()ob_runtime_outputs(context,3,2),'output port does not exist');
  assert_error(@()ob_runtime_outputs(context,[3 1]),'block path does not exist');
  assert_error(@()ob_runtime_outputs(rmfield(context,'time'),3),'expected a context');
  disp('Octave Blocks optional performance metadata tests passed');
endfunction

function assert_categories(model)
  info=model.runtime_info;types={model.blocks.type};conditional=strcmp(types,'Conditional Subsystem');
  assert(isequal(info.kind,'octave-blocks-runtime-info-v1'));
  assert(isequal(info.conditional_ids,reshape(find(conditional),1,[])));
  assert(isequal(info.integrator_ids,reshape(find(strcmp(types,'Integrator')),1,[])));
  assert(isequal(info.step_ids,reshape(find(strcmp(types,'Step')),1,[])));
  primitive=ismember(types,{'Switch','Saturation','Dead Zone'});
  assert(isequal(info.zc_ids,reshape(find(conditional|primitive),1,[])));
  assert(isequal(info.continuous_path_ids,reshape(find(conditional|strcmp(types,'Integrator')),1,[])));
  assert(isequal(info.boundary_ids,reshape(find(conditional|strcmp(types,'Step')),1,[])));
endfunction

function value=without_categories(value)
  value=transform(value,'categories');
endfunction

function value=without_cache(value)
  value=transform(value,'cache');
endfunction

function value=change_cache(value,mode)
  value=transform(value,mode);
endfunction

function value=transform(value,mode)
  if(isstruct(value))
    if(isfield(value,'runtime_info'))
      if(strcmp(mode,'cache'))
        value=rmfield(value,'runtime_info');
      elseif(strcmp(mode,'categories'))
        names={'conditional_ids','integrator_ids','step_ids','zc_ids','continuous_path_ids','boundary_ids'};
        value.runtime_info=rmfield(value.runtime_info,names(isfield(value.runtime_info,names)));
      elseif(strcmp(mode,'unknown'))
        value.runtime_info.kind='unknown-cache';
      elseif(strcmp(mode,'incomplete'))
        value.runtime_info=struct('kind','octave-blocks-runtime-info-v1');
      elseif(strcmp(mode,'invalid_categories'))
        names={'conditional_ids','integrator_ids','step_ids','zc_ids','continuous_path_ids','boundary_ids'};
        for name=names,value.runtime_info.(name{1})=-1;endfor
      endif
    endif
    names=fieldnames(value);
    for index=1:numel(value)
      for name=names',value(index).(name{1})=transform(value(index).(name{1}),mode);endfor
    endfor
  elseif(iscell(value))
    for index=1:numel(value),value{index}=transform(value{index},mode);endfor
  endif
endfunction

function assert_error(callback,fragment)
  caught=false;
  try callback();catch err,caught=!isempty(strfind(err.message,fragment));end_try_catch
  assert(caught);
endfunction
