function descriptor = ob_runtime_execution (model, id)
  % Compiled block lookup, with validation/classification for old contexts.
  % This cache belongs to a fixed runtime graph. Reinitialize after model or
  % execution-parameter edits; changing runtime input tables is independent.
  if (! isnumeric (id) || ! isreal (id) || ! isscalar (id) || ! isfinite (id) ...
      || id != fix (id) || id < 1 || id > numel (model.blocks))
    error ('ob_runtime_execution: supply a valid conditional block index');
  endif
  if (isfield (model, 'runtime_info'))
    cache = model.runtime_info;
    if (isstruct (cache) && isscalar (cache) && all (isfield (cache, {'kind','conditional'})) ...
        && ischar(cache.kind) && strcmp (cache.kind, 'octave-blocks-runtime-info-v1') ...
        && iscell (cache.conditional) && numel (cache.conditional) >= id)
      candidate = cache.conditional{id};
      if (isstruct (candidate) && isscalar (candidate) ...
          && all (isfield (candidate, {'kind','options','needs_flow','clocked','continuous_controls', ...
                                      'input_ports','output_ids','output_ports'})) ...
          && ischar(candidate.kind) && strcmp (candidate.kind, 'octave-blocks-execution-descriptor-v1') ...
          && isstruct(candidate.options) && isscalar(candidate.options) ...
          && all(isfield(candidate.options,{'mode','states','outputs','initial_outputs','initial_control','control'})))
        descriptor = candidate;
        return;
      endif
    endif
  endif
  block = model.blocks(id);
  if (! any (strcmp (block.type, {'Conditional Subsystem','Subsystem'})))
    error ('ob_runtime_execution: block %d is not a conditional Subsystem', id);
  endif
  descriptor = ob_event_execution (block.value, struct ());
endfunction
