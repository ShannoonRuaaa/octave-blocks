function state = ob_refresh_conditional_outputs (model, state, descriptor = [])
  if (isempty(descriptor)), descriptor = ob_event_execution(model); endif
  options = descriptor.options;
  child = state.child; signal_map = child.signal_map;
  % Contexts created before per-port shapes existed lack these fields.
  current = isfield (state, 'output_shaped');
  if (current), initial = state.initial_outputs; shaped = state.output_shaped;
  else initial = options.initial_outputs; shaped = ! cellfun (@isscalar, initial); endif
  count = numel (descriptor.output_ids);
  gated = descriptor.clocked && count > 0 && isfield (state, 'gating');
  if (gated), values = cell (1, count); endif
  changed = false;
  for output = 1:count
    id = descriptor.output_ids(output); port = descriptor.output_ports(output);
    % Compilation may insert virtual descendants before a top-level map item.
    % Use a direct route only when both its exact path and port are present.
    direct = id <= numel(signal_map);
    if (direct)
      % Index the map item once; the checks are unchanged.
      item = signal_map(id); path = item.path; route = item.outputs;
      direct = isnumeric(path) && isscalar(path) && path==id ...
               && isnumeric(route) && isreal(route) && !isempty(route) ...
               && isfinite(route(1)) && route(1)==fix(route(1)) ...
               && route(1)>=1 && route(1)<=numel(child.current);
    endif
    if (direct)
      value = child.current{route(1)};
    else
      value = ob_runtime_outputs (child, id);
    endif
    if (! isnumeric(value) || ! isreal(value) || any(! isfinite(value(:))))
      error ('ob_run: conditional output %d must be finite, real, and match its initial output shape', port);
    endif
    if (! size_equal (value, initial{port}))
      % Simulink expands a scalar InitialOutput to the port's width.  The
      % first non-scalar value fixes the shape; the held output, if it is
      % still the scalar initial output, is expanded with it.
      if (shaped(port) || ! isscalar (initial{port}))
        error ('ob_run: conditional output %d must be finite, real, and match its initial output shape', port);
      endif
      initial{port} = repmat (initial{port}, size (value));
      if (isscalar (state.outputs{port}))
        state.outputs{port} = repmat (state.outputs{port}, size (value));
      endif
      shaped(port) = true; changed = true;
    elseif (! shaped(port) && ob_conditional_settled (child, id))
      % A scalar fixes the shape only when it is no nested subsystem's
      % initial output still waiting for its own shape.
      shaped(port) = true; changed = true;
    endif
    if (gated), values{port} = full (double (value));
    else state.outputs{port} = full (double (value)); endif
  endfor
  if (changed && current)
    state.initial_outputs = initial; state.output_shaped = shaped;
  endif
  if (gated)
    [state, publish] = gate (state, descriptor, child, count);
    for port = find (publish)
      state.outputs{port} = values{port};
    endfor
  endif
endfunction

function [state, publish] = gate (state, descriptor, child, count)
  % An enabled body with inner clocks: a port takes a new value only when
  % its rate executes, that is when one of its gates hits now, or at every
  % evaluation when it follows the body's rate (ob_conditional_gating).
  % Gates that have not executed show their shared Outport's value, so the
  % value published then is Simulink's (ob_conditional_buffers).
  if (isempty (state.gating) || ! isfield (state.gating, 'shared'))
    state.gating = ob_conditional_buffers ('analyse', child, descriptor);
  endif
  gating = state.gating;
  hits = child.sample_hits;
  publish = true (1, count);
  for port = find (! gating.port_every)
    fires = false;
    for g = gating.port_blocks{port}
      if (! isempty (hits{g}) && hits{g}(end) == child.time), fires = true; break; endif
    endfor
    publish(port) = fires;
  endfor
endfunction
