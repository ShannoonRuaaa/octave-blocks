function state = ob_conditional_gate_flow (model, state, inputs, time, events)
  % Refresh an active ancestor and dispatch accepted descendant controls only.
  % Its inherited discrete state is not captured/committed by this operation.
  if (! state.initialized || ! state.was_enabled), return; endif
  [signals, unused] = ob_conditional_signals (model, inputs, time);
  state.child = ob_runtime_engine ('gate-hit',state.child,time,signals,events);
  state = ob_refresh_conditional_outputs (model,state,ob_event_execution(model,events));
endfunction
