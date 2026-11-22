function [model, shapes] = ob_expand_initial_outputs (model, input_shapes = [])
  % [MODEL, SHAPES] = ob_expand_initial_outputs (MODEL, INPUT_SHAPES)
  % Expand every scalar InitialOutput of the conditional subsystems in MODEL
  % (at any depth) to its Outport's shape, found by static shape
  % propagation, as Simulink does at compile time and the C exporters do
  % (ob_c_conditional_unit): a 2-element port with InitialOutput -4 holds
  % [-4 -4] before its subsystem first executes, even when that is after
  % the start (explicit sample offset) or inside another conditional body.
  % SHAPES{p} is the static shape of MODEL's numbered Outport p, or [] when
  % it is unknown.  INPUT_SHAPES{k} is the shape of numbered Inport k ([]
  % unknown); by default MODEL.inputs gives them.
  %
  % Blocks whose result shape is only known by evaluating them (Function
  % blocks, lookup tables, ...) make what they feed unknown.  Those ports
  % keep their scalar initial output here; the runtime expands it from the
  % first value (ob_conditional_output_shapes, ob_refresh_conditional_outputs).
  % The conditional runtime applies this to every body it initializes;
  % callers that start a run (the editor, sim) apply it to the root model.
  out_ids = reshape (find (strcmp ({model.blocks.type}, 'Outport')), 1, []);
  shapes = cell (1, numel (out_ids));
  if (nargout < 2 && ! scalar_conditional (model)), return; endif
  in_ids = reshape (find (strcmp ({model.blocks.type}, 'Inport')), 1, []);
  if (isempty (input_shapes) && ! iscell (input_shapes))
    input_shapes = cell (1, numel (in_ids));
    if (isfield (model, 'inputs') && iscell (model.inputs))
      for k = 1:min (numel (in_ids), numel (model.inputs))
        signal = model.inputs{k};
        if (isstruct (signal) && isfield (signal, 'shape') && numel (signal.shape) == 2)
          input_shapes{k} = double (signal.shape(:)');
        elseif (isstruct (signal) && isfield (signal, 'values') && ! isempty (signal.values))
          input_shapes{k} = [1 columns(signal.values)];
        endif
      endfor
    endif
  endif
  input_shapes(end+1:numel (in_ids)) = {[]};
  % Only a positive [rows cols] is a shape (an empty value is a model error
  % the run reports).
  valid = @(s) isnumeric (s) && numel (s) == 2 && all (s >= 1) && all (s == fix (s));
  input_shapes(! cellfun (valid, input_shapes)) = {[]};
  % Scalar data through scalar blocks leaves nothing to expand.
  if (nargout < 2 && ! ob_conditional_may_widen (model, input_shapes)), return; endif
  % Compile a copy with placeholder inputs; the shapes of unknown inputs are
  % tracked here, not taken from the placeholders.
  work = model;
  work.inputs = cell (1, numel (in_ids));
  for k = 1:numel (in_ids)
    shape = input_shapes{k};
    if (isempty (shape)), shape = [1 1]; endif
    work.inputs{k} = ob_input_signal (0, zeros (1, prod (shape)), shape);
  endfor
  try
    [flat, signal_map, paths] = ob_compile_model (work);
    [order, edges] = ob_execution_order (flat, true);
  catch
    return;  % an invalid model reports its error when it runs
  end_try_catch
  types = {flat.blocks.type};
  n = numel (types);
  sources = cell (1, n);
  for k = 1:rows (edges)
    sources{edges(k, 2)}(end+1) = edges(k, 1);
  endfor
  sizes = cell (1, n); ports = cell (1, n);
  for id = reshape (order, 1, [])
    block = flat.blocks(id);
    in = sizes(sources{id});
    switch (types{id})
      case {'Constant', 'Unit Delay', 'Discrete Integrator', 'Integrator', 'Rate Transition'}
        if (isnumeric (block.value) && ndims (block.value) == 2), sizes{id} = size (block.value); endif
      case {'Time', 'Step'}
        sizes{id} = [1 1];
      case 'External Input'
        if (block.value <= numel (input_shapes)), sizes{id} = input_shapes{block.value}; endif
      case {'Scope', 'Inport', 'Outport', 'Saturation', 'Dead Zone', 'Transport Delay'}
        if (! isempty (in)), sizes{id} = in{1}; endif
      case 'Gain'
        if (! isempty (in) && isnumeric (block.value)), sizes{id} = product (size (block.value), in{1}); endif
      case 'Product'
        if (numel (in) == 2), sizes{id} = product (in{1}, in{2}); endif
      case 'Sum'
        if (numel (in) == 2), sizes{id} = broadcast (in{1}, in{2}); endif
      case 'Switch'
        if (numel (in) == 3 && isequal (in{1}, in{3})), sizes{id} = in{1}; endif
      case 'Conditional Subsystem'
        % Expand the body (and its own nested bodies) with the input shapes
        % reaching it, then publish its port shapes to its outputs.
        options = ob_execution_options (block.value, false);
        controls = 1 + ob_is_combined_mode (options.mode);
        data = sources{id}(1:max (0, end - controls));
        location = paths{id}(1:end-1);
        diagram = ob_model_at (model, location(1:end-1));
        body = diagram.blocks(location(end)).value;
        [body, inner] = ob_expand_initial_outputs (body, sizes(data));
        initial = ob_execution_options (body, false).initial_outputs;
        for port = 1:numel (initial)
          if (port <= numel (inner) && ! isempty (inner{port}) && isscalar (initial{port}) ...
              && ! isequal (inner{port}, [1 1]))
            initial{port} = repmat (initial{port}, inner{port});
          endif
          if (! isscalar (initial{port})), inner{port} = size (initial{port}); endif
        endfor
        body.execution.initial_outputs = initial;
        diagram.blocks(location(end)).value = body;
        model = ob_set_model_at (model, location(1:end-1), diagram);
        ports{id} = inner;
      case 'Conditional Output'
        core = sources{id}(1);
        if (block.value <= numel (ports{core})), sizes{id} = ports{core}{block.value}; endif
      otherwise
        % Function, Multiple Function, Function Output, Limited Integrator:
        % the shape is only known by evaluating the block.
    endswitch
  endfor
  for k = 1:numel (out_ids)
    port = model.blocks(out_ids(k)).value;
    for item = signal_map
      if (isequal (item.path, out_ids(k)))
        if (isnumeric (port) && isscalar (port) && port >= 1 && port == fix (port))
          shapes{port} = sizes{item.outputs(1)};
        endif
        break;
      endif
    endfor
  endfor
endfunction

function shape = product (a, b)
  % Octave's matrix product (scalars scale); [] when unknown or invalid.
  shape = [];
  if (isempty (a) || isempty (b)), return; endif
  if (prod (a) == 1), shape = b;
  elseif (prod (b) == 1), shape = a;
  elseif (a(2) == b(1)), shape = [a(1) b(2)]; endif
endfunction

function shape = broadcast (a, b)
  % Octave's element-wise broadcasting; [] when unknown or invalid.
  shape = [];
  if (isempty (a) || isempty (b) || any (a != b & a != 1 & b != 1)), return; endif
  shape = max (a, b);
endfunction

function yes = scalar_conditional (model)
  % Whether some conditional subsystem inside MODEL has a scalar initial
  % output (otherwise there is nothing to expand).
  yes = false;
  for k = reshape (find (strcmp ({model.blocks.type}, 'Subsystem')), 1, [])
    body = model.blocks(k).value;
    if (! isstruct (body) || ! isfield (body, 'blocks')), continue; endif
    try
      options = ob_execution_options (body, false);
    catch
      continue;
    end_try_catch
    if (! strcmp (options.mode, 'virtual') && any (cellfun (@isscalar, options.initial_outputs)))
      yes = true; return;
    endif
    if (scalar_conditional (body)), yes = true; return; endif
  endfor
endfunction
