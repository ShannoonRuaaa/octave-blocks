function state = ob_conditional_control (model, state, inputs, time, events, initialize = true)
  % Accepted enable transition, separate from the child's discrete sample clock.
  descriptor = ob_event_execution (model,events);
  options = descriptor.options;
  [unused, control] = ob_conditional_signals (model, inputs, time, false, descriptor.input_ports);
  combined = ob_is_combined_mode(options.mode);
  if (combined), control = inputs{end-1}; endif
  if ((! isnumeric(control) && ! islogical(control)) || ! isreal(control) ...
      || ! isscalar(control) || ! isfinite(control))
    error ('ob_run: conditional enable must be a finite real scalar');
  endif
  active = control > 0; previous = state.was_enabled;
  if (combined), state.enable_sign = sign(double(control));
  else state.control_sign = sign(double(control)); endif
  if (previous && ! active)
    if (! isempty(state.continuous_active_since))
      state.continuous_elapsed += max(0,time-state.continuous_active_since);
    endif
    state.continuous_active_since = [];
    if (state.initialized), state.child = ob_suspend_enabled (state.child,time); endif
    if (state.initialized && isfield (state, 'reset_due'))
      if (isfield (descriptor, 'reset_ports')), state.reset_due = descriptor.reset_ports;
      else state.reset_due = ob_conditional_reset_ports (options); endif
    endif
  elseif (active && (! previous || isempty(state.continuous_active_since)))
    state.continuous_active_since = time;
  endif
  if (active && isfield (state, 'reset_due')), state.reset_due(:) = false; endif
  reset = active && !previous && strcmp(options.states,'reset');
  if (reset)
    if (combined), state.reset_pending = true;
    else
      if (state.initialized), state.reset_seed = state.child; endif
      state.initialized = false; state.child = [];
    endif
    state.continuous_elapsed = 0; state.advance_interval = 0;
  endif
  state.was_enabled = active;
  if (! active)
    state = ob_conditional_disabled_reset (state, descriptor, time);
    return;
  endif
  if (! initialize || combined), return; endif
  if (! state.initialized)
    [signals, unused] = ob_conditional_signals (model, inputs, time, true, descriptor.input_ports);
    child = model; child.inputs = signals; child = ob_expand_initial_outputs (child);
    reset_source = [];
    if (isfield(state,'reset_seed')), reset_source = state.reset_seed; endif
    if (descriptor.clocked)
      state = ob_conditional_buffers ('init', state, child, descriptor, time, events, false, reset_source);
    else
      state.child = ob_runtime_engine ('init-child',child,time,events.options,events.origin,true,false,events,reset_source);
    endif
    if (isfield(state,'reset_seed')), state = rmfield(state,'reset_seed'); endif
    state.child.major_current = state.child.current;
    state.initialized = true;
    state = ob_refresh_conditional_outputs (model,state,descriptor);
  else
    state = ob_conditional_gate_flow (model,state,inputs,time,events);
  endif
  if (! previous), state.executions(end+1) = time; endif
endfunction
