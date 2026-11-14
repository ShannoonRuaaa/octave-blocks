function test_ob_performance_events ()
  % Category caches cannot alter guards, port routes, or lazy clock discovery.
  model = ob_example ();
  model.blocks(1).type = 'Constant';
  model.blocks(1).value = [-2 0;1 3];
  model.blocks(2).type = 'Saturation'; model.blocks(2).value = [-1 2];
  runtime = ob_runtime_init (model);
  prepared = runtime.model;
  reference = ob_zc_snapshot(prepared,runtime.edges,runtime.current);
  assert (reference.values,[-1;2;1;4;-4;-1;-2;1]);
  assert ([reference.descriptors.channel],[1:4 1:4]);
  legacy = rmfield(prepared,'runtime_info');
  assert (isequal(reference,ob_zc_snapshot(legacy,runtime.edges,runtime.current)));
  optional = strip_categories(prepared);
  assert (isequal(reference,ob_zc_snapshot(optional,runtime.edges,runtime.current)));
  unknown = prepared; unknown.runtime_info.kind = 'future-runtime-info';
  assert (isequal(reference,ob_zc_snapshot(unknown,runtime.edges,runtime.current)));
  for ids={-1,[2 2],NaN,[1;2],complex(2,1)}
    malformed=prepared; malformed.runtime_info.zc_ids=ids{1};
    assert (isequal(reference,ob_zc_snapshot(malformed,runtime.edges,runtime.current)));
  endfor

  % Clockless cached bodies are skipped only after recursive validation;
  % legacy graphs retain their original compilation path and identical clocks.
  for model = {ob_enabled_continuous_example(),ob_enabled_multirate_example()}
    runtime = ob_runtime_init(model{1});
    flat = runtime.model; legacy = rmfield(flat,'runtime_info');
    expected = ob_nested_clocks(legacy,0);
    assert (isequal(ob_nested_clocks(flat,0),expected));
    assert (isequal(ob_nested_clocks(strip_categories(flat),0),expected));
    unknown = flat; unknown.runtime_info.kind = 'future-runtime-info';
    assert (isequal(ob_nested_clocks(unknown,0),expected));
    malformed=flat; malformed.runtime_info.conditional_ids=-1;
    assert (isequal(ob_nested_clocks(malformed,0),expected));
  endfor

  % A nested virtual subsystem shifts signal_map indices before the Outport.
  % The direct route must reject that index and read the exact mapped path.
  child = ob_subsystem_template ();
  child.blocks(2).type='Subsystem'; child.blocks(2).value=ob_subsystem_template();
  child.execution=struct('mode','enabled','initial_outputs',{{0}});
  parent = ob_enabled_continuous_example(); parent.blocks(3).value=child;
  context = ob_runtime_init(parent);
  core=find(strcmp(context.types,'Conditional Subsystem'));
  state=context.states{core}; descriptor=ob_runtime_execution(context.model,core);
  out=descriptor.output_ids;
  assert (!isequal(state.child.signal_map(out).path,out));
  refreshed=ob_refresh_conditional_outputs(child,state,descriptor);
  assert (refreshed.outputs{1},ob_runtime_outputs(state.child,out));
  map=find(arrayfun(@(item)isequal(item.path,out),state.child.signal_map));
  target=state.child.signal_map(map).outputs(1);
  state.child.current{target}=NaN;
  assert_error(@()ob_refresh_conditional_outputs(child,state,descriptor),'finite');
  state.child.current{target}=[1 2];
  assert_error(@()ob_refresh_conditional_outputs(child,state,descriptor),'shape');

  % Existing complete v1 contexts can omit every optional category field.
  model=ob_enabled_continuous_example();
  cached=ob_runtime_init(model); old=strip_categories(cached);
  for time=[.5 1.5 2.5 3]
    cached=ob_runtime_step(cached,time); old=ob_runtime_step(old,time);
    assert (isequaln(strip_categories(cached),strip_categories(old)));
  endfor
  disp('Octave Blocks event performance regression tests passed');
endfunction

function value = strip_categories (value)
  names={'zc_ids','conditional_ids','integrator_ids','step_ids', ...
         'continuous_path_ids','boundary_ids'};
  if (isstruct(value))
    for name=names
      if (isfield(value,name{1})), value=rmfield(value,name{1}); endif
    endfor
    fields=fieldnames(value);
    for index=1:numel(value)
      for name=fields'
        value(index).(name{1})=strip_categories(value(index).(name{1}));
      endfor
    endfor
  elseif (iscell(value))
    for index=1:numel(value), value{index}=strip_categories(value{index}); endfor
  endif
endfunction

function assert_error (callback,fragment)
  caught=false;
  try callback(); catch err, caught=!isempty(strfind(err.message,fragment)); end_try_catch
  assert(caught);
endfunction
