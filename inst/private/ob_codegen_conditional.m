function info = ob_codegen_conditional (model, file, config, options = struct ())
  % Atomic bodies are typed recursive units, never flattened into double state.
  options = ob_solver_options (options);
  if (!strcmp(options.solver,'rk4'))
    error ('ob_codegen: C export requires rk4; adaptive solver code is not yet generated');
  endif
  if (ob_has_continuous_control(model) && !options.zero_crossings)
    error ('ob_codegen: continuous subsystem control requires zero_crossings');
  endif
  unit = ob_c_conditional_unit (model);
  [unit, clocks] = ob_c_clock_inventory (unit);
  unit.clock_inventory = clocks;
  if (options.zero_crossings)
    [unit, guards] = ob_c_event_inventory (unit);
    unit = event_flow_units (unit);
    unit.event_inventory = guards;
    unit.event_options = options;
  endif
  lines = ob_emit_c_conditional (unit, ob_time_grid(config(1),config(2),config(3)));
  text = [strjoin(lines, char(10)) char(10)];
  folder = fileparts(file); if (isempty(folder)), folder = pwd(); endif
  temporary = [tempname(folder) '.c']; fid = -1;
  unwind_protect
    fid = fopen(temporary,'wb');
    if (fid < 0), error('ob_codegen: cannot write output directory'); endif
    written = fwrite(fid,text,'char'); status = fclose(fid); fid = -1;
    if (written != numel(text) || status != 0), error('ob_codegen: source write failed'); endif
    [ok,message] = movefile(temporary,file,'f');
    if (! ok), error('ob_codegen: %s',message); endif
  unwind_protect_cleanup
    if (fid >= 0), fclose(fid); endif
    if (exist(temporary,'file')), unlink(temporary); endif
  end_unwind_protect
  inputs = unit.flat.inputs;
  info = struct('source',file,'paths',{unit.paths},'shapes',{unit.shapes}, ...
    'offsets',unit.offsets,'value_count',unit.value_count,'state_count',unit.state_count, ...
    'continuous_state_count',unit.continuous_count, ...
    'clock_count',numel(clocks),'clocks',{clocks}, ...
    'signal_map',{unit.signal_map},'solver','rk4', ...
    'input_shapes',{cellfun(@(s) s.shape,inputs,'uniformoutput',false)}, ...
    'input_offsets',unit.input_offsets,'input_value_count',unit.input_count, ...
    'sample_times',unit.flat.sample_times, ...
    'typed_conditional',any(strcmp(unit.types,'Conditional Subsystem')));
  info.zero_crossings = options.zero_crossings;
  info.event_guard_count = 0;
  if (options.zero_crossings), info.event_guard_count = numel(unit.event_inventory); endif
endfunction

function unit = event_flow_units (unit)
  % Keep flow classification aligned with ob_needs_continuous_flow.
  controls = ! unit.root && strcmp(unit.options.control,'continuous');
  for id = 1:unit.n
    if (isempty(unit.children{id})), continue; endif
    unit.children{id} = event_flow_units (unit.children{id});
    controls |= unit.children{id}.continuous_controls;
  endfor
  unit.continuous_controls = controls;
  unit.needs_flow = unit.has_continuous || unit.clocked || controls;
endfunction
