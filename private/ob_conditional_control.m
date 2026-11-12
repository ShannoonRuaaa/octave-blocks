function state = ob_conditional_control (model, state, inputs, time, events, initialize = true)
  % Accepted enable transition, separate from the child's discrete sample clock.
  descriptor = ob_event_execution (model,events);
  options = descriptor.options;
  [unused, control] = ob_conditional_signals (model, inputs, time, false);
  active = control > 0; previous = state.was_enabled;
  state.control_sign = sign (double(control));
  if (previous && ! active)
    if (! isempty(state.continuous_active_since))
      state.continuous_elapsed += max(0,time-state.continuous_active_since);
    endif
    state.continuous_active_since = [];
    if (state.initialized), state.child = ob_suspend_enabled (state.child,time); endif
  elseif (active && (! previous || isempty(state.continuous_active_since)))
    state.continuous_active_since = time;
  endif
  reset = active && !previous && strcmp(options.states,'reset');
  if (reset)
    state.initialized = false; state.child = [];
    state.continuous_elapsed = 0; state.advance_interval = 0;
  endif
  state.was_enabled = active;
  if (! active)
    if (strcmp(options.outputs,'reset')), state.outputs = options.initial_outputs; endif
    return;
  endif
  if (! initialize), return; endif
  [signals, unused] = ob_conditional_signals (model, inputs, time);
  if (! state.initialized)
    child = model; child.inputs = signals;
    state.child = ob_runtime_engine ('init-child',child,time,events.options,events.origin,true,false,events);
    state.child.major_current = state.child.current;
    state.initialized = true;
  else
    state = ob_conditional_gate_flow (model,state,inputs,time,events);
  endif
  state = ob_refresh_conditional_outputs (model,state,descriptor);
  if (! previous), state.executions(end+1) = time; endif
endfunction
