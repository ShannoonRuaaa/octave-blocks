function runtime = ob_suspend_enabled (runtime, time)
  % Freeze each active descendant's first interval after its last execution.
  % No outputs, clocks, state captures, or trigger histories execute here.
  for id = reshape(find(strcmp(runtime.types,'Conditional Subsystem')),1,[])
    state = runtime.states{id};
    if (!strcmp(ob_execution_mode(runtime.model.blocks(id).value),'enabled') ...
        || !state.initialized || !state.was_enabled)
      continue;
    endif
    if (state.last_executed)
      interval = time-state.last_sample;
      if (runtime.rates(id,1)>0), interval=runtime.rates(id,1); endif
      if (interval>0 && isfinite(interval)), state.advance_interval=interval; endif
      state.last_executed = false;
    endif
    descriptor = ob_runtime_execution (runtime.model,id);
    options = descriptor.options;
    if (strcmp(options.control,'continuous') && !isempty(state.continuous_active_since))
      state.continuous_elapsed += max(0,time-state.continuous_active_since);
      state.continuous_active_since = [];
    endif
    state.child = ob_suspend_enabled(state.child,time);
    runtime.states{id} = state;
    runtime.current{id} = state;
  endfor
endfunction
