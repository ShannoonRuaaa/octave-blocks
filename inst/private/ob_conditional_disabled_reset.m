function state = ob_conditional_disabled_reset (state, descriptor, time)
  % OutputWhenDisabled 'reset' while the body is disabled.  Simulink runs
  % each Outport at the rate it inherits from its source, so in an enabled
  % body with inner clocks a port fed only by clocked blocks returns to its
  % initial output at the first hit of one of those clocks after disabling
  % (simulink-conditional-outputs-reference.json, gating_*: a 0.25 s port
  % disabled at 0.875 resets at 1.0).  Every other port resets at once.
  % reset_due marks clocked ports still waiting since the body was disabled.
  % A clocked block that drives a reset port directly shares its buffer, so
  % it also shows the initial output until it next executes
  % (ob_conditional_buffers).
  if (isfield (descriptor, 'reset_ports')), mask = descriptor.reset_ports;
  else mask = ob_conditional_reset_ports (descriptor.options); endif
  if (! any (mask)), return; endif
  initial = descriptor.options.initial_outputs;
  if (isfield (state, 'initial_outputs')), initial = state.initial_outputs; endif
  now = mask;
  gated = descriptor.clocked && state.initialized && isfield (state, 'gating') ...
          && ! isempty (state.gating) && isfield (state.gating, 'shared');
  if (gated)
    gating = state.gating;
    origin = state.child.start_time; rates = state.child.rates;
    for port = find (mask & ! gating.port_every)
      now(port) = false;
      if (! state.reset_due(port)), continue; endif
      for g = gating.port_blocks{port}
        if (ob_conditional_buffers ('hit', rates(g, 1), rates(g, 2), origin, time))
          now(port) = true; break;
        endif
      endfor
    endfor
  endif
  state.outputs(now) = initial(now);
  if (isfield (state, 'reset_due')), state.reset_due(now) = false; endif
  if (gated && any (now & gating.shared > 0))
    ports = find (now & gating.shared > 0);
    state.child = ob_conditional_buffers ('substitute', state.child, gating, ports, initial(ports));
  endif
endfunction
