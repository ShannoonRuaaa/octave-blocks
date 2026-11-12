function test_ob_runtime_metadata ()
  % Input routes are canonical port order, independent of wire row order.
  model = ob_oscillator ();
  model.blocks(1).type = model.blocks(2).type = 'Constant';
  model.blocks(1).value = 2; model.blocks(2).value = 3;
  model.blocks(3).type = 'Function'; model.blocks(3).name = 'power';
  model.edges = [2 1 3 2;3 1 4 1;1 1 3 1];
  flat = ob_compile_model (model);
  [unused, edges, unused_stateful, flat.algebraic_loops] = ob_execution_order (flat, true);
  before = flat; prepared = ob_prepare_runtime_model (flat);
  assert (isequal (rmfield(prepared,'runtime_info'), before));
  assert (isequal (prepared.runtime_info.sources{3}, [1 2]));
  assert (isequal (prepared.runtime_info.loop_at, zeros(1,numel(flat.blocks))));
  for id = 1:numel (flat.blocks)
    assert (isequal (prepared.runtime_info.sources{id}, edges(edges(:,2)==id,1)'));
  endfor
  duplicate = ob_example (); duplicate.blocks(2).type = 'Sum';
  duplicate.edges = [1 1 2 2;2 1 3 1;1 1 2 1];
  repeated = ob_prepare_runtime_model (ob_compile_model(duplicate));
  assert (isequal (repeated.runtime_info.sources{2}, [1 1]));

  % A missing loop inventory is computed; a supplied valid one is indexed.
  loop = ob_oscillator ();
  loop.blocks(1).type = 'Constant'; loop.blocks(1).value = 3;
  loop.blocks(2).type = 'Sum'; loop.blocks(2).value = [];
  loop.blocks(3).type = 'Gain'; loop.blocks(3).value = 2;
  loop.edges = [1 1 2 1;3 1 2 2;2 1 3 1;2 1 4 1];
  cyclic = ob_prepare_runtime_model (ob_compile_model(loop));
  assert (isequal (cyclic.algebraic_loops, {[2 3]}));
  assert (isequal (cyclic.runtime_info.loop_at, [0 1 1 0]));

  % Normalization, classifications, and interface IDs match the legacy paths.
  enabled = ob_enabled_continuous_example ();
  flat = ob_compile_model (enabled); core = conditional_id (flat);
  cached = ob_prepare_runtime_model (flat);
  descriptor = ob_runtime_execution (cached, core);
  assert (isequal (descriptor.options, ob_execution_options(enabled.blocks(3).value)));
  assert (descriptor.needs_flow && !descriptor.clocked && !descriptor.continuous_controls);
  assert (descriptor.input_ports == 1 && isequal(descriptor.output_ids,3) ...
          && isequal(descriptor.output_ports,1));
  assert (isequal (ob_runtime_execution(flat,core), descriptor));
  frame = struct ('execution_descriptor',descriptor);
  assert (isequal (ob_event_execution(enabled.blocks(3).value,frame), descriptor));
  assert (isequal (ob_event_execution(enabled.blocks(3).value), descriptor));

  clocks = ob_enabled_multirate_example ();
  flat = ob_prepare_runtime_model (ob_compile_model(clocks));
  descriptor = ob_runtime_execution (flat, conditional_id(flat));
  assert (descriptor.clocked && descriptor.needs_flow && !descriptor.continuous_controls);
  assert (isequal(descriptor.output_ids,[4 5]) && isequal(descriptor.output_ports,[1 2]));
  clocks.blocks(3).value.blocks(4).value = 2;
  clocks.blocks(3).value.blocks(5).value = 1;
  reordered = ob_prepare_runtime_model (ob_compile_model(clocks));
  reordered_descriptor = ob_runtime_execution (reordered, conditional_id(reordered));
  assert (isequal(reordered_descriptor.output_ids,[4 5]) ...
          && isequal(reordered_descriptor.output_ports,[2 1]));
  enabled.blocks(3).value.execution.control = 'continuous';
  enabled.sample_times = zeros (4,2);
  flat = ob_prepare_runtime_model (ob_compile_model(enabled));
  descriptor = ob_runtime_execution (flat, conditional_id(flat));
  assert (strcmp(descriptor.options.control,'continuous') && descriptor.needs_flow ...
          && !descriptor.clocked && !descriptor.continuous_controls);

  outer = ob_subsystem_template ();
  outer.blocks(2) = enabled.blocks(3);
  outer.blocks(4) = outer.blocks(1); outer.blocks(4).type = 'Constant'; outer.blocks(4).value = 1;
  outer.edges = [1 1 2 1;4 1 2 2;2 1 3 1];
  outer.execution = struct ('mode','enabled','initial_outputs',{{0}});
  nested = ob_event_execution (outer);
  assert (nested.continuous_controls && nested.needs_flow);

  % Cache rebuilding ignores old cache contents. Input tables are not cached.
  rebuilt = cached; rebuilt.runtime_info.sources{1} = 999;
  rebuilt = ob_prepare_runtime_model (rebuilt);
  assert (isequal (rebuilt.runtime_info, cached.runtime_info));
  changed = cached; changed.inputs = {ob_input_signal([0 1],[2;3])};
  assert (isequal (changed.runtime_info, cached.runtime_info));
  assert (isequal (ob_runtime_execution(changed,core), ob_runtime_execution(cached,core)));
  legacy = cached; legacy = rmfield (legacy, 'runtime_info');
  assert (isequal (ob_runtime_execution(legacy,core), ob_runtime_execution(cached,core)));
  malformed = cached; malformed.runtime_info.kind = 'old-cache';
  assert (isequal (ob_runtime_execution(malformed,core), ob_runtime_execution(cached,core)));
  frame.execution_descriptor.kind = 'old-descriptor';
  assert (isequal (ob_event_execution(enabled.blocks(3).value,frame), ...
                   ob_event_execution(enabled.blocks(3).value)));

  % Full normalization/body validation remains the fallback for old callers.
  invalid = enabled.blocks(3).value; invalid.execution.mode = 'rising';
  assert_error (@() ob_event_execution(invalid), 'triggered bodies');
  invalid_flat = cached; invalid_flat.blocks(core).value = invalid;
  assert_error (@() ob_prepare_runtime_model(invalid_flat), 'triggered bodies');
  assert_error (@() ob_runtime_execution(cached,0), 'block index');
  assert_error (@() ob_runtime_execution(cached,1), 'not a conditional');
  invalid_flat = cached; invalid_flat.algebraic_loops = {[1 2],[2 3]};
  assert_error (@() ob_prepare_runtime_model(invalid_flat), 'disjoint');

  empty.blocks = struct ('type',{},'value',{},'name',{},'x',{},'y',{});
  empty.edges = zeros (0,2);
  empty = ob_prepare_runtime_model (ob_compile_model(empty));
  assert (isempty(empty.runtime_info.sources) && isempty(empty.runtime_info.conditional) ...
          && isequal(size(empty.runtime_info.loop_at),[1 0]));

  % A pre-cache checkpoint lacks metadata in every nested child/snapshot.
  % Its future numerical states, pending updates, clocks and reads still match.
  cached_context = ob_runtime_step (ob_runtime_init(ob_enabled_continuous_example()), .5);
  legacy_context = without_runtime_info (cached_context);
  legacy_file = [tempname() '.mat'];
  unwind_protect
    save ('-mat7-binary',legacy_file,'legacy_context');
    restored_legacy = load (legacy_file); legacy_context = restored_legacy.legacy_context;
    for time = [.9 1.5 2.25 2.75 3]
      cached_context = ob_runtime_step (cached_context, time);
      legacy_context = ob_runtime_step (legacy_context, time);
      assert (isequaln (ob_runtime_outputs(cached_context), ob_runtime_outputs(legacy_context)));
      assert (isequaln (without_runtime_info(cached_context), without_runtime_info(legacy_context)));
    endfor
  unwind_protect_cleanup
    if (exist(legacy_file,'file')), unlink(legacy_file); endif
  end_unwind_protect

  % Live host input tables are independent of the fixed execution graph.
  driven = ob_enabled_continuous_example ();
  driven.blocks(1).type = 'Inport'; driven.blocks(1).value = 1;
  driven.blocks(2).value = 2;
  driven.inputs = {ob_input_signal(0,1), ob_input_signal(0,1)};
  cached_context = ob_runtime_step (ob_runtime_init(driven), .25);
  legacy_context = without_runtime_info (cached_context);
  retained_info = cached_context.model.runtime_info;
  cached_context.model.inputs{1} = ob_input_signal (.25,2);
  legacy_context.model.inputs{1} = cached_context.model.inputs{1};
  cached_context = ob_runtime_step (cached_context,.75);
  legacy_context = ob_runtime_step (legacy_context,.75);
  assert (abs(ob_runtime_outputs(cached_context,4)-1.25) < 1e-12);
  assert (isequaln (without_runtime_info(cached_context), without_runtime_info(legacy_context)));
  assert (isequal (cached_context.model.runtime_info, retained_info));

  % Caching does not bypass finite-value or derivative-shape checks, and a
  % failed assignment must leave the complete caller context untouched.
  bad_context = cached_context; bad_context.model.inputs{1}.values(1) = NaN;
  before_bad = bad_context; caught = false;
  try bad_context = ob_runtime_step(bad_context,1);
  catch err, caught = !isempty(strfind(err.message,'finite')); end_try_catch
  assert (caught && isequaln(bad_context,before_bad));
  bad_context = cached_context;
  bad_context.model.inputs{1} = ob_input_signal (.75,[1 2],[2 1]);
  before_bad = bad_context; caught = false;
  try bad_context = ob_runtime_step(bad_context,1);
  catch err, caught = !isempty(strfind(err.message,'shape')); end_try_catch
  assert (caught && isequaln(bad_context,before_bad));

  % Metadata consists only of serializable immutable values.
  file = [tempname() '.mat'];
  unwind_protect
    save ('-mat7-binary',file,'cached'); restored = load (file);
    assert (isequal (restored.cached, cached));
    assert (isequal (ob_runtime_execution(restored.cached,core), ...
                     ob_runtime_execution(cached,core)));
  unwind_protect_cleanup
    if (exist(file,'file')), unlink(file); endif
  end_unwind_protect
  disp ('Octave Blocks runtime metadata tests passed');
endfunction

function id = conditional_id (model)
  id = find (strcmp ({model.blocks.type}, 'Conditional Subsystem'));
  assert (isscalar (id));
endfunction

function assert_error (callback, fragment)
  caught = false;
  try callback(); catch err, caught = !isempty(strfind(err.message,fragment)); end_try_catch
  assert (caught);
endfunction

function value = without_runtime_info (value)
  if (isstruct (value))
    if (isfield(value,'runtime_info')), value = rmfield (value,'runtime_info'); endif
    names = fieldnames (value);
    for item = 1:numel (value)
      for name = names'
        value(item).(name{1}) = without_runtime_info (value(item).(name{1}));
      endfor
    endfor
  elseif (iscell (value))
    for item = 1:numel (value), value{item} = without_runtime_info (value{item}); endfor
  endif
endfunction
