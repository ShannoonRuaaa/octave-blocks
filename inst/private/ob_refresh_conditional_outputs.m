function state = ob_refresh_conditional_outputs (model, state, descriptor = [])
  if (isempty(descriptor)), descriptor = ob_event_execution(model); endif
  options = descriptor.options;
  child = state.child; signal_map = child.signal_map;
  for output = 1:numel(descriptor.output_ids)
    id = descriptor.output_ids(output); port = descriptor.output_ports(output);
    % Compilation may insert virtual descendants before a top-level map item.
    % Use a direct route only when both its exact path and port are present.
    if (id <= numel(signal_map) && isnumeric(signal_map(id).path) ...
        && isscalar(signal_map(id).path) && signal_map(id).path==id ...
        && isnumeric(signal_map(id).outputs) && isreal(signal_map(id).outputs) ...
        && !isempty(signal_map(id).outputs) ...
        && isfinite(signal_map(id).outputs(1)) ...
        && signal_map(id).outputs(1)==fix(signal_map(id).outputs(1)) ...
        && signal_map(id).outputs(1)>=1 ...
        && signal_map(id).outputs(1)<=numel(child.current))
      value = child.current{signal_map(id).outputs(1)};
    else
      value = ob_runtime_outputs (child, id);
    endif
    if (! isnumeric(value) || ! isreal(value) || any(! isfinite(value(:))) ...
        || !size_equal(value,options.initial_outputs{port}))
      error ('ob_run: conditional output %d must be finite, real, and match its initial output shape', port);
    endif
    state.outputs{port} = full (double(value));
  endfor
endfunction
