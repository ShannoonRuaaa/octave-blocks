function [shapes, expressions] = ob_c_shapes (model, order, edges, paths, sources = [], external = [])
  % external (optional, ob_accelerate only): struct with ids (flat Function
  % blocks evaluated by the host through ob_external_call) and shapes (their
  % output shapes); such blocks get an empty expression.
  if (nargin < 5 || isempty (sources)), sources = ob_c_adjacency (numel(model.blocks), edges); endif
  if (isempty (external)), external = struct ('ids', zeros (1, 0), 'shapes', {{}}); endif
  types = {model.blocks.type};
  delays = find (strcmp (types, 'Transport Delay'));
  % A Transport Delay with a scalar initial output takes its input's shape.
  % ob_run learns that shape from a probe evaluation in which every such
  % delay still outputs its scalar initial value, then requires the input to
  % keep it (private/ob_transport_delay.m).  Mirror that: propagate once with
  % scalar outputs, fix the learned shapes, propagate again and check.
  learned = cell (1, numel (model.blocks));
  [shapes, expressions] = propagate (model, order, paths, sources, learned, external);
  if (! isempty (delays))
    for id = delays
      params = ob_block_parameters (model.blocks(id));
      if (isscalar (params.initial)), learned{id} = shapes{sources{id}(1)}; endif
    endfor
    [shapes, expressions] = propagate (model, order, paths, sources, learned, external);
    for id = delays
      params = ob_block_parameters (model.blocks(id));
      input = shapes{sources{id}(1)};
      location = sprintf ("%d/", paths{id}); location(end) = [];
      if (isscalar (params.initial))
        if (! isequal (input, learned{id}))
          error ("ob_codegen: Transport Delay block %s input changed shape", location);
        endif
      elseif (prod (input) != 1 && ! isequal (input, size (params.initial)))
        error ("ob_codegen: Transport Delay block %s input shape must match its initial output", location);
      endif
    endfor
  endif
  for id = find (ismember (types, {"Integrator", "Unit Delay", "Discrete Integrator", "Rate Transition"}))
    source = sources{id};
    if (! isequal (shapes{id}, shapes{source}))
      error ("ob_codegen: state input shape must match its initial condition at block %s", ...
             strtrim(sprintf("%d ", paths{id})));
    endif
  endfor
  for id = find (strcmp (types, 'Limited Integrator'))
    source = sources{id};
    if (! isequal (shapes{id}, shapes{source(1)}))
      error ("ob_codegen: state input shape must match its initial condition at block %s", ...
             strtrim(sprintf("%d ", paths{id})));
    endif
    % ob_run requires a finite real scalar reset signal at every accepted hit.
    if (numel (source) > 1 && prod (shapes{source(2)}) != 1)
      error ("ob_codegen: Limited Integrator block %s reset signal must be scalar", ...
             strtrim(sprintf("%d ", paths{id})));
    endif
  endfor
endfunction

function [shapes, expressions] = propagate (model, order, paths, sources, learned, external)
  shapes = cell (1, numel (model.blocks));
  expressions = cell (1, numel (model.blocks));
  for id = order
    block = model.blocks(id);
    inputs = shapes(sources{id});
    location = sprintf ("%d/", paths{id}); location(end) = [];
    if (any (strcmp (block.type, {"Constant", "Gain", "Step", "Integrator", ...
                                 "Unit Delay", "Discrete Integrator", "Rate Transition", ...
                                 "Saturation", "Dead Zone", "Switch"})))
      if (! isa (block.value, "double") || ndims (block.value) != 2 ...
          || issparse (block.value))
        error ("ob_codegen: block %s needs a full real double parameter with at most two dimensions", location);
      endif
    endif
    switch (block.type)
      case 'Conditional Subsystem'
        error ('ob_codegen: conditional core at block %s requires the typed recursive exporter', location);
      case {'Multiple Function', 'Function Output'}
        error ('ob_codegen: multiple-output function at block %s requires the typed recursive exporter', location);
      case {"Constant", "Integrator", "Unit Delay", "Discrete Integrator", "Rate Transition"}
        shapes{id} = size (block.value);
      case 'Limited Integrator'
        params = ob_block_parameters (block);
        shapes{id} = size (params.initial);
      case 'Transport Delay'
        params = ob_block_parameters (block);
        if (! isscalar (params.initial)), shapes{id} = size (params.initial);
        elseif (! isempty (learned{id})), shapes{id} = learned{id};
        else shapes{id} = [1 1]; endif
      case {"Time", "Step"}
        shapes{id} = [1 1];
      case "External Input"
        shapes{id} = model.inputs{block.value}.shape;
      case "Gain"
        shapes{id} = product_shape (size (block.value), inputs{1}, location);
      case "Product"
        shapes{id} = product_shape (inputs{1}, inputs{2}, location);
      case "Sum"
        shapes{id} = broadcast_shape (inputs{1}, inputs{2}, location);
      case {"Saturation", "Dead Zone"}
        shapes{id} = inputs{1};
      case "Switch"
        if (! isequal (inputs{1}, inputs{3}))
          error ("ob_codegen: Switch block %s data inputs must have identical shapes", location);
        endif
        if (prod (inputs{2}) != 1 && ! isequal (inputs{2}, inputs{1}))
          error ("ob_codegen: Switch block %s control must be scalar or match the data shape", location);
        endif
        shapes{id} = inputs{1};
      case "Function"
        host = find (external.ids == id, 1);
        if (! isempty (host))
          shapes{id} = external.shapes{host};
          continue;
        endif
        [expressions{id}, arity] = ob_c_function (block.name);
        if (numel (inputs) != arity)
          error ("ob_codegen: block %s Function %s needs %d inputs for C export", location, block.name, arity);
        endif
        if (arity == 1), shapes{id} = inputs{1};
        else shapes{id} = broadcast_shape (inputs{1}, inputs{2}, location); endif
      case {"Scope", "Inport", "Outport"}
        shapes{id} = inputs{1};
      otherwise
        error ("ob_codegen: block %s type %s is not supported", location, block.type);
    endswitch
  endfor
endfunction

function shape = product_shape (a, b, location)
  if (prod (a) == 1), shape = b;
  elseif (prod (b) == 1), shape = a;
  elseif (a(2) == b(1)), shape = [a(1) b(2)];
  else error ("ob_codegen: incompatible matrix multiplication at block %s", location); endif
endfunction

function shape = broadcast_shape (a, b, location)
  if (any (a != b & a != 1 & b != 1))
    error ("ob_codegen: incompatible broadcast dimensions at block %s", location);
  endif
  shape = max (a, b);
endfunction
