function state = ob_conditional_eval (model, state, inputs, time, inherited_interval = [], major = true, events = struct (), fixed_interval = false)
  descriptor = ob_event_execution (model,events);
  options = descriptor.options;
  ports = descriptor.input_ports;
  combined = ob_is_combined_mode (options.mode);
  resettable = ob_is_resettable_mode (options.mode);
  uses_interval = resettable || strcmp (options.mode, 'enabled');
  [unused, control] = ob_conditional_signals (model, inputs, time, false, ports);
  clocked = descriptor.clocked;
  continuous_enabled = strcmp(options.mode,'enabled') && strcmp(options.control,'continuous');
  if (major && state.last_executed && ! continuous_enabled)
    if (uses_interval && ! isempty (inherited_interval))
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
    if (! active && descriptor.clocked && isfield (state, 'reset_due') && any (state.reset_due))
      % An inner clock hit while disabled: a reset port fed by it may be due.
      state = ob_conditional_disabled_reset (state, descriptor, time);
    endif
  elseif (resettable)
    [state, reset] = trigger_edge (state,control,options.mode(7:end),options.control);
    active = true;
  elseif (combined)
    state = ob_conditional_control (model,state,inputs,time,events,false);
    if (isfield(state,'trigger_seen') && ! state.trigger_seen)
      % Simulink's Enabled and Triggered Subsystem never triggers on its first
      % evaluation, whatever InitialTriggerSignalState says: the first sample
      % becomes the prior value.  This holds while disabled and when an
      % ancestor delays the first evaluation; ancestor resets keep the flag.
      state.previous_sign = sign(double(control));
      state.last_rising = false; state.last_falling = false;
      state.trigger_seen = true;
    endif
    [state, edge] = trigger_edge (state,control,options.mode(9:end),options.control);
    active = state.was_enabled && edge;
    reset = active && isfield(state,'reset_pending') && state.reset_pending;
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
      if (isfield (state, 'reset_due')), state.reset_due = reset_ports (descriptor); endif
    endif
    if (active && isfield (state, 'reset_due') && any (state.reset_due)), state.reset_due(:) = false; endif
    state.was_enabled = active;
    if (! active && any (reset_ports (descriptor)))
      state = ob_conditional_disabled_reset (state, descriptor, time);
    endif
  else
    current_sign = sign (double (control));
    if (ischar (options.initial_control) && isfield (state, 'trigger_seen') && ! state.trigger_seen)
      % 'compatibility' (Simulink's default InitialTriggerSignalState): the
      % first evaluation, at the start or when an ancestor first runs this
      % context, only records the sample.  Ancestor resets keep this flag
      % with the rest of the trigger history (ob_restore_reset_children).
      state.previous_sign = current_sign;
      state.last_rising = false; state.last_falling = false;
      state.trigger_seen = true;
    endif
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
  if (! state.initialized && isfield (state, 'shapes_probed') && ! state.shapes_probed)
    % Port shapes before the first execution (also when it is now: the
    % shared Outport buffers of ob_conditional_buffers need them).
    state = ob_conditional_output_shapes (model, state, inputs, time, events, descriptor, active);
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
    % Nested conditional bodies hold their scalar initial outputs expanded
    % to their port shapes from the start (ob_expand_initial_outputs).
    child = model; child.inputs = signals; child = ob_expand_initial_outputs (child);
    reset_source = [];
    if (reset && state.initialized && !resettable), reset_source = state.child;
    elseif (isfield(state,'reset_seed')), reset_source = state.reset_seed; endif
    if (clocked)
      state = ob_conditional_buffers ('init', state, child, descriptor, time, events, major, reset_source);
    elseif (continuous_enabled || resettable || descriptor.continuous_controls || !isempty(reset_source))
      state.child = ob_runtime_engine ('init-child',child,time,events.options,events.origin,true,major,events,reset_source);
    else
      state.child = ob_runtime_init (child, time, events.options);
    endif
    if (strcmp (options.mode, 'enabled') && descriptor.needs_flow)
      state.child.major_current = state.child.current;
    endif
    state.initialized = true;
    if (isfield(state,'reset_seed')), state = rmfield(state,'reset_seed'); endif
    if (combined), state.reset_pending = false; endif
  else
    if (uses_interval), interval = state.advance_interval;
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

function mask = reset_ports (descriptor)
  if (isfield (descriptor, 'reset_ports')), mask = descriptor.reset_ports;
  else mask = ob_conditional_reset_ports (descriptor.options); endif
endfunction

function [state, active] = trigger_edge (state,control,mode,control_mode)
  current_sign = sign(double(control));
  rising = (state.previous_sign < 0 && current_sign >= 0) || (state.previous_sign == 0 && current_sign > 0);
  falling = (state.previous_sign > 0 && current_sign <= 0) || (state.previous_sign == 0 && current_sign < 0);
  active = (any(strcmp(mode,{'rising','either'})) && rising && !state.last_rising) ...
           || (any(strcmp(mode,{'falling','either'})) && falling && !state.last_falling);
  changed = current_sign != state.previous_sign;
  state.previous_sign = current_sign; state.control_sign = current_sign;
  if (!strcmp(control_mode,'continuous') || (changed && (rising || falling)))
    state.last_rising = rising; state.last_falling = falling;
  endif
endfunction
