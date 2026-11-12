function state = ob_conditional_eval (model, state, inputs, time, inherited_interval = [], major = true, events = struct (), fixed_interval = false)
  descriptor = ob_event_execution (model,events);
  options = descriptor.options;
  ports = descriptor.input_ports;
  if (numel (inputs) != ports + 1)
    error ('ob_run: conditional Subsystem needs its data ports followed by one control port');
  endif
  control = inputs{end};
  if ((! isnumeric (control) && ! islogical (control)) || ! isreal (control) ...
      || ! isscalar (control) || ! isfinite (control))
    error ('ob_run: conditional control must be a finite real scalar');
  endif
  clocked = descriptor.clocked;
  continuous_enabled = strcmp(options.mode,'enabled') && strcmp(options.control,'continuous');
  if (major && state.last_executed && ! continuous_enabled)
    if (strcmp (options.mode, 'enabled') && ! isempty (inherited_interval))
      state.advance_interval = inherited_interval;
      if (clocked && !fixed_interval && inherited_interval > 0)
        state.advance_interval = min(inherited_interval,time-state.last_sample);
      endif
    else
      state.advance_interval = time - state.last_sample;
    endif
  endif
  if (major), state.last_sample = time; state.last_executed = false; endif
  reset = false;
  if (!major)
    if (continuous_enabled && isfield(events,'accepted') && events.accepted)
      % A descendant clock is not an inherited sample, but its accepted frame
      % must reconcile this gate before deciding whether that clock can run.
      state = ob_conditional_control (model,state,inputs,time,events,false);
    endif
    active = strcmp(options.mode,'enabled') && state.was_enabled;
  elseif (continuous_enabled)
    state = ob_conditional_control (model,state,inputs,time,events,false);
    active = state.was_enabled;
    if (active)
      state.advance_interval = state.continuous_elapsed;
      if (! isempty(state.continuous_active_since))
        state.advance_interval += max(0,time-state.continuous_active_since);
      endif
      state.continuous_elapsed = 0; state.continuous_active_since = time;
    endif
  elseif (strcmp (options.mode, 'enabled'))
    active = control > 0;
    reset = active && ! state.was_enabled && strcmp (options.states, 'reset');
    if (!active && state.was_enabled && state.initialized)
      state.child = ob_suspend_enabled(state.child,time);
    endif
    state.was_enabled = active;
    if (! active && strcmp (options.outputs, 'reset')), state.outputs = options.initial_outputs; endif
  else
    current_sign = sign (double (control));
    rising = (state.previous_sign < 0 && current_sign >= 0) || (state.previous_sign == 0 && current_sign > 0);
    falling = (state.previous_sign > 0 && current_sign <= 0) || (state.previous_sign == 0 && current_sign < 0);
    active = (any (strcmp (options.mode, {'rising','either'})) && rising && ! state.last_rising) ...
             || (any (strcmp (options.mode, {'falling','either'})) && falling && ! state.last_falling);
    changed = current_sign != state.previous_sign;
    state.previous_sign = current_sign;
    if (strcmp(options.control,'continuous'))
      % Output requests and unrelated clock hits must not rearm a plateau.
      % Preserve its edge until a genuine opposite transition is observed.
      if (changed && (rising || falling))
        state.last_rising = rising; state.last_falling = falling;
      endif
    else
      state.last_rising = rising; state.last_falling = falling;
    endif
    state.control_sign = current_sign;
  endif
  if (! active), return; endif
  signals = cell (1, ports);
  for port = 1:ports
    value = inputs{port};
    if (! isnumeric (value) || ! isreal (value) || isempty (value) ...
        || ndims (value) > 2 || any (! isfinite (value(:))))
      error ('ob_run: conditional data input %d must be a finite real numeric matrix', port);
    endif
    value = full (double (value));
    signals{port} = ob_input_signal (time, value(:)', size(value));
  endfor
  if (! state.initialized || reset)
    child = model; child.inputs = signals;
    if (clocked || continuous_enabled || descriptor.continuous_controls)
      state.child = ob_runtime_engine ('init-child',child,time,events.options,events.origin,true,major,events);
    else
      state.child = ob_runtime_init (child, time, events.options);
    endif
    if (strcmp (options.mode, 'enabled') && descriptor.needs_flow)
      state.child.major_current = state.child.current;
    endif
    state.initialized = true;
  else
    if (strcmp (options.mode, 'enabled')), interval = state.advance_interval;
    else interval = time - state.child.time; endif
    if (clocked)
      state.child = ob_runtime_engine ('clock-hit',state.child,time,signals,interval,major,events);
    elseif (strcmp (options.mode, 'enabled') && descriptor.needs_flow)
      state.child = ob_runtime_engine ('flow-hit', state.child, time, signals, interval, events);
    else
      state.child = ob_runtime_engine ('execute', state.child, time, signals, interval, false, events);
    endif
  endif
  state = ob_refresh_conditional_outputs (model,state,descriptor);
  state.executions(end + 1) = time;
  if (major), state.last_executed = true; endif
endfunction
