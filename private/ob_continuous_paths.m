function paths = ob_continuous_paths (model, states)
  % One shared solver vector includes every active enabled child's states.
  paths = {};
  for id = 1:numel (model.blocks)
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
