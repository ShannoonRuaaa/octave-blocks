function [shapes, expressions] = ob_c_shapes (model, order, edges, paths)
  shapes = cell (1, numel (model.blocks));
  expressions = cell (1, numel (model.blocks));
  for id = order
    block = model.blocks(id);
    sources = edges(edges(:, 2) == id, 1);
    inputs = shapes(sources);
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
  for id = find (ismember ({model.blocks.type}, {"Integrator", "Unit Delay", "Discrete Integrator", "Rate Transition"}))
    source = edges(edges(:, 2) == id, 1);
    if (! isequal (shapes{id}, shapes{source}))
      error ("ob_codegen: state input shape must match its initial condition at block %s", ...
             strtrim(sprintf("%d ", paths{id})));
    endif
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
