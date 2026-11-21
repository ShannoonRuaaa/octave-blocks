function runtime = ob_restore_reset_children (runtime, previous)
  ids = reshape(find(strcmp(runtime.types,'Conditional Subsystem')),1,[]);
  for id = ids
    old = previous.states{id};
    options = ob_runtime_execution(runtime.model,id).options;
    enabled = strcmp(options.mode,'enabled') || ob_is_combined_mode(options.mode);
    if (enabled && (old.initialized || isfield(old,'reset_seed')))
      runtime.states{id} = old;
    elseif (old.initialized)
      runtime.states{id}.reset_seed = old.child;
    elseif (isfield(old,'reset_seed'))
      runtime.states{id}.reset_seed = old.reset_seed;
    endif
  endfor
endfunction
