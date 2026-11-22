function state = ob_conditional_output_shapes (model, state, inputs, time, events, descriptor, active = false)
  % At a body's first evaluation, before it first executes, find the shapes
  % of the ports whose initial output is scalar, so that the held initial
  % output already has the port's width: Simulink expands a scalar
  % InitialOutput to the port dimensions at compile time
  % (simulink-multioutput-reference.json, enabled_vector).  Static shape
  % propagation with the current input shapes (ob_expand_initial_outputs,
  % the rule the C exporters use) settles every port whose path has no
  % block of unknown result shape.  For the others, while the body is
  % disabled, a trial initialization with the current inputs is evaluated
  % and discarded, once per context and only when some input or block
  % value is non-scalar or a Function block could change the shape; if it
  % fails (a body may only be valid once enabled), or the body is ACTIVE
  % now, the first execution fixes the remaining shapes instead.
  state.shapes_probed = true;
  ports = descriptor.input_ports;
  if (numel (inputs) < ports), return; endif
  shapes = cell (1, ports);
  for port = 1:ports
    if (isnumeric (inputs{port}) || islogical (inputs{port})), shapes{port} = size (inputs{port}); endif
  endfor
  if (! ob_conditional_may_widen (model, shapes))
    % Scalar data through blocks with scalar values: every port is scalar.
    state.output_shaped(:) = true;
    return;
  endif
  [unused, static] = ob_expand_initial_outputs (model, shapes);
  for output = 1:numel (descriptor.output_ids)
    port = descriptor.output_ports(output);
    if (! state.output_shaped(port) && port <= numel (static) && ! isempty (static{port}))
      state = expand (state, port, static{port});
    endif
  endfor
  if (active || all (state.output_shaped)), return; endif
  child = ob_expand_initial_outputs (model, shapes); child.inputs = cell (1, ports);
  options = struct ();
  if (isstruct (events) && isfield (events, 'options')), options = events.options; endif
  try
    for port = 1:ports
      value = full (double (inputs{port}));
      child.inputs{port} = ob_input_signal (time, value(:)', size (value));
    endfor
    trial = ob_runtime_init (child, time, options);
    for output = 1:numel (descriptor.output_ids)
      port = descriptor.output_ports(output);
      if (state.output_shaped(port)), continue; endif
      id = descriptor.output_ids(output);
      value = ob_runtime_outputs (trial, id);
      % A scalar fixes nothing while it may still be a nested subsystem's
      % initial output (ob_conditional_settled).
      if (isnumeric (value) && ! isempty (value) && ndims (value) == 2 ...
          && (! isscalar (value) || ob_conditional_settled (trial, id)))
        state = expand (state, port, size (value));
      endif
    endfor
  catch
    % Leave the remaining shapes to the first execution.
  end_try_catch
endfunction

function state = expand (state, port, shape)
  % Broadcast a scalar initial (and still initial held) output to SHAPE.
  if (isscalar (state.initial_outputs{port}) && ! isequal (shape, [1 1]))
    state.initial_outputs{port} = repmat (state.initial_outputs{port}, shape);
    if (isscalar (state.outputs{port}))
      state.outputs{port} = repmat (state.outputs{port}, shape);
    endif
  endif
  state.output_shaped(port) = true;
endfunction
