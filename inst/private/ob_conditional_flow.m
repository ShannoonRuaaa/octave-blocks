function state = ob_conditional_flow (model, state, inputs, time, left_limit, flow = struct (), descriptor = [])
  % A minor-stage flow evaluation never changes enable/trigger or sample history.
  if (! state.initialized || ! state.was_enabled), return; endif
  if (isempty(descriptor)), descriptor = ob_event_execution(model); endif
  count = descriptor.input_ports;
  if (numel (inputs) != count + 1)
    error ('ob_run: conditional Subsystem needs its data ports followed by one control port');
  endif
  signals = cell (1, count);
  for port = 1:count
    value = inputs{port};
    if (! isnumeric (value) || ! isreal (value) || isempty (value) ...
        || ndims (value) > 2 || any (! isfinite (value(:))))
      error ('ob_run: conditional data input %d must be a finite real numeric matrix', port);
    endif
    signals{port} = ob_input_signal (time, full(double(value(:)')), size(value));
  endfor
  state.child.model.inputs = signals;
  [state.child.current, state.child.states] = ob_runtime_eval (state.child.model, ...
      state.child.edges, state.child.order, time, state.child.states, left_limit, [], [], struct (), flow);
  state.child.time = time;
  state = ob_refresh_conditional_outputs (model,state,descriptor);
endfunction
