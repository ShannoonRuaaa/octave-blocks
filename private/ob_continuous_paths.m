function paths = ob_continuous_paths (model, states)
  % One shared solver vector includes every active enabled child's states.
  paths = {};
  indexed = false; ids = []; integrator_ids = []; conditional_ids = [];
  if (isfield (model, 'runtime_info'))
    info = model.runtime_info;
    if (isstruct (info) && isscalar (info) ...
        && all (isfield (info, {'kind', 'continuous_path_ids', 'integrator_ids', 'conditional_ids'})) ...
        && ischar (info.kind) && strcmp (info.kind, 'octave-blocks-runtime-info-v1'))
      candidate = info.continuous_path_ids;
      if (valid_ids_check (candidate, numel (model.blocks)))
        integrator_ids = info.integrator_ids;
        conditional_ids = info.conditional_ids;
        indexed = true;
      endif
    endif
  endif
  if (indexed)
    % Fast path: add all flat integrators directly as scalar-path cells.
    paths = num2cell (integrator_ids);
    % Only recurse into enabled conditional children.
    for id = conditional_ids
      state = states{id};
      descriptor = ob_runtime_execution (model, id);
      options = descriptor.options;
      if (strcmp (options.mode, 'enabled') && state.initialized && state.was_enabled)
        child_paths = ob_continuous_paths (state.child.model, state.child.states);
        for path = child_paths
          paths{end + 1} = [id path{1}];
        endfor
      endif
    endfor
  else
    % Original fallback: iterate all blocks.
    if (isempty (ids)), ids = 1:numel (model.blocks); endif
    for id = ids
      type = model.blocks(id).type;
      if (strcmp (type, 'Integrator') || strcmp (type, 'Limited Integrator'))
        paths{end + 1} = id;
      elseif (strcmp (type, 'Conditional Subsystem'))
        state = states{id};
        descriptor = ob_runtime_execution (model, id);
        options = descriptor.options;
        if (strcmp (options.mode, 'enabled') && state.initialized && state.was_enabled)
          child_paths = ob_continuous_paths (state.child.model, state.child.states);
          for path = child_paths
            paths{end + 1} = [id path{1}];
          endfor
        endif
      endif
    endfor
  endif
endfunction

function ok = valid_ids_check (ids, n)
  ok = isnumeric (ids) && isreal (ids) && ndims (ids) == 2 && rows (ids) == 1 ...
       && all (isfinite (ids)) && all (ids == fix (ids)) ...
       && all (ids >= 1 & ids <= n) && (isempty (ids) || all (diff (ids) > 0));
endfunction
