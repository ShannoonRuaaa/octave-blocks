function samples = ob_signal_values (result, path, port = 1)
  if (! isnumeric (path) || ! isvector (path) || isempty (path) ...
      || ! isreal (path) || any (! isfinite (path)) || any (path < 1) ...
      || any (path != fix (path)) || ! isnumeric (port) || ! isscalar (port) ...
      || ! isreal (port) || ! isfinite (port) || port < 1 || port != fix (port))
    error ("ob_signal_values: use a block path and a positive output port");
  endif
  for k = 1:numel (result.signal_map)
    if (isequal (result.signal_map(k).path, path(:)'))
      ids = result.signal_map(k).outputs;
      if (port > numel (ids)), error ("ob_signal_values: output port does not exist"); endif
      samples = result.flat_values(:, ids(port));
      return;
    endif
  endfor
  for core = reshape (find (strcmp ({result.compiled_model.blocks.type}, 'Conditional Subsystem')), 1, [])
    prefix = result.block_paths{core}(1:end-1);
    path = path(:)';
    if (numel (path) > numel (prefix) && isequal (path(1:numel(prefix)), prefix))
      relative = path(numel(prefix)+1:end);
      model = result.compiled_model.blocks(core).value;
      diagram = ob_model_at (model, relative(1:end-1));
      if (relative(end) > numel (diagram.blocks)), error ('ob_signal_values: block path does not exist'); endif
      [unused, count] = ob_block_ports (diagram.blocks(relative(end)));
      if (port > count), error ('ob_signal_values: output port does not exist'); endif
      samples = cell (rows(result.flat_values), 1);
      available = false (size(samples));
      for step = 1:numel (samples)
        snapshot = result.flat_values{step, core};
        if (! snapshot.initialized), continue; endif
        try
          samples{step} = ob_runtime_outputs (snapshot.child, relative, port);
          available(step) = true;
        catch err
          if (isempty (strfind (err.message, 'conditional child has not executed'))), rethrow (err); endif
        end_try_catch
      endfor
      first = find (available, 1);
      if (isempty (first)), error ('ob_signal_values: conditional child has not executed'); endif
      for step = find (! available)'
        samples{step} = NaN (size (samples{first}));
      endfor
      return;
    endif
  endfor
  error ("ob_signal_values: block path does not exist");
endfunction
