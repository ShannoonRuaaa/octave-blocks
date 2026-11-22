function paths = ob_continuous_paths (model, states)
  % One shared solver vector includes every active enabled child's states.
  paths = {};
  indexed = false; ids = [];
  if (isfield(model,'runtime_info'))
    info = model.runtime_info;
    if (isstruct(info) && isscalar(info) && all(isfield(info,{'kind','continuous_path_ids'})) ...
        && ischar(info.kind) && strcmp(info.kind,'octave-blocks-runtime-info-v1'))
      candidate = info.continuous_path_ids;
      if (isnumeric(candidate) && isreal(candidate) && ndims(candidate)==2 && rows(candidate)==1 ...
          && all(isfinite(candidate)) && all(candidate==fix(candidate)) ...
          && all(candidate>=1 & candidate<=numel(model.blocks)) && all(diff(candidate)>0))
        ids = candidate;
        indexed = true;
      endif
    endif
  endif
  if (!indexed), ids = 1:numel(model.blocks); endif
  for id = ids
    type = model.blocks(id).type;
    if (strcmp (type, 'Integrator'))
      paths{end + 1} = id;
    elseif (strcmp (type, 'Conditional Subsystem'))
      state = states{id};
      descriptor = ob_runtime_execution (model,id);
      options = descriptor.options;
      if (strcmp (options.mode, 'enabled') && state.initialized && state.was_enabled)
        child_paths = ob_continuous_paths (state.child.model, state.child.states);
        for path = child_paths
          paths{end + 1} = [id path{1}];
        endfor
      endif
    endif
  endfor
endfunction
