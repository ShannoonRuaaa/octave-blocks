function runtime = ob_suspend_enabled (runtime, time)
  % Freeze each active descendant's first interval after its last execution.
  % No outputs, clocks, state captures, or trigger histories execute here.
  if (isfield(runtime.model,'runtime_info') && isstruct(runtime.model.runtime_info) ...
      && isscalar(runtime.model.runtime_info) ...
      && all(isfield(runtime.model.runtime_info,{'kind','conditional_ids'})) ...
      && ischar(runtime.model.runtime_info.kind) ...
      && strcmp(runtime.model.runtime_info.kind,'octave-blocks-runtime-info-v1') ...
      && valid_ids(runtime.model.runtime_info.conditional_ids,numel(runtime.types)))
    ids = runtime.model.runtime_info.conditional_ids;
  else
    ids = reshape(find(strcmp(runtime.types,'Conditional Subsystem')),1,[]);
  endif
  for id = ids
    state = runtime.states{id};
    if (!state.initialized), continue; endif
    descriptor = ob_runtime_execution (runtime.model,id);
    options = descriptor.options;
    if (!strcmp(options.mode,'enabled') && !ob_is_combined_mode(options.mode))
      state.child = ob_suspend_enabled(state.child,time);
      runtime.states{id} = runtime.current{id} = state;
      continue;
    endif
    if (!state.was_enabled), continue; endif
    if (state.last_executed)
      interval = time-state.last_sample;
      if (runtime.rates(id,1)>0), interval=runtime.rates(id,1); endif
      if (interval>0 && isfinite(interval)), state.advance_interval=interval; endif
      state.last_executed = false;
    endif
    if (strcmp(options.control,'continuous') && !isempty(state.continuous_active_since))
      state.continuous_elapsed += max(0,time-state.continuous_active_since);
      state.continuous_active_since = [];
    endif
    % Ancestor disable is an effective local disable. Leave trigger history
    % untouched; the next accepted activation applies this child's policy.
    state.was_enabled = false;
    state.child = ob_suspend_enabled(state.child,time);
    runtime.states{id} = state;
    runtime.current{id} = state;
  endfor
endfunction

function yes = valid_ids (ids,count)
  yes=isnumeric(ids) && isreal(ids) && ndims(ids)==2 && rows(ids)==1 ...
      && all(isfinite(ids)) && all(ids==fix(ids)) ...
      && all(ids>=1 & ids<=count) && all(diff(double(ids))>0);
endfunction
