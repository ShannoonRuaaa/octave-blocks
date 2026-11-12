function state = ob_refresh_conditional_outputs (model, state, descriptor = [])
  if (isempty(descriptor)), descriptor = ob_event_execution(model); endif
  options = descriptor.options;
  for output = 1:numel(descriptor.output_ids)
    id = descriptor.output_ids(output); port = descriptor.output_ports(output);
    value = ob_runtime_outputs (state.child, id);
    if (! isnumeric(value) || ! isreal(value) || any(! isfinite(value(:))) ...
        || ! isequal(size(value),size(options.initial_outputs{port})))
      error ('ob_run: conditional output %d must be finite, real, and match its initial output shape', port);
    endif
    state.outputs{port} = full (double(value));
  endfor
endfunction
