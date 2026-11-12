function info = ob_codegen_conditional (model, file, config)
  % Atomic bodies are typed recursive units, never flattened into double state.
  unit = ob_c_conditional_unit (model);
  [unit, clocks] = ob_c_clock_inventory (unit);
  unit.clock_inventory = clocks;
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
endfunction
