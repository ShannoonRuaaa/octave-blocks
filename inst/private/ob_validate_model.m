function ob_validate_model (model, complete = false, depth = 0)
  if (depth > 32), error ("ob_validate_model: subsystem nesting exceeds 32 levels"); endif
  if (! isstruct (model) || ! isscalar (model) ...
      || ! isfield (model, "blocks") || ! isfield (model, "edges") ...
      || ! isstruct (model.blocks))
    error ("ob_validate_model: expected a model with blocks and edges");
  endif
  if (! all (isfield (model.blocks, {"type", "value", "name", "x", "y"})))
    error ("ob_validate_model: blocks need type, value, name, x, and y fields");
  endif
  n = numel (model.blocks);
  edges = ob_edges (model);
  if (any (edges(:, [1 3])(:) > n))
    error ("ob_validate_model: connections must use valid block indices");
  endif
  if (rows (unique (model.edges, "rows")) != rows (model.edges))
    error ("ob_validate_model: duplicate connections are not allowed");
  endif
  if (rows (unique (edges(:, [3 4]), "rows")) != rows (edges))
    error ("ob_validate_model: each input port can have only one connection");
  endif
  input_counts = output_counts = minimums = zeros (1, n);
  for id = 1:n
    block = model.blocks(id);
    if (isfield (block, 'algebraic_initial') && ! isempty (block.algebraic_initial))
      guess = block.algebraic_initial;
      if (! isa (guess, 'double') || ! isreal (guess) || issparse (guess) ...
          || ndims (guess) > 2 || any (! isfinite (guess(:))))
        error ('ob_validate_model: block %d algebraic_initial must be a finite real full double matrix', id);
      endif
    endif
    if (! ischar (block.type) || rows (block.type) != 1 ...
        || ! ischar (block.name) || rows (block.name) > 1 ...
        || ! isnumeric (block.x) || ! isscalar (block.x) ...
        || ! isreal (block.x) || ! isfinite (block.x) ...
        || ! isnumeric (block.y) || ! isscalar (block.y) ...
        || ! isreal (block.y) || ! isfinite (block.y))
      error ("ob_validate_model: block %d has invalid text or coordinates", id);
    endif
    if (strcmp (block.type, "Subsystem"))
      try
        ob_validate_model (block.value, complete, depth + 1);
      catch err
        error ("ob_validate_model: subsystem %d (%s): %s", id, block.name, err.message);
      end_try_catch
    endif
    if (strcmp (block.type, 'Function')), ob_function_output_count (block); endif
    try
      [input_counts(id), output_counts(id), minimums(id)] = ob_block_ports (block);
    catch err
      error ("ob_validate_model: block %d has unknown type '%s'", id, block.type);
    end_try_catch
    if (strcmp (block.type, "Function") && ! isvarname (block.name))
      error ("ob_validate_model: block %d needs a valid Octave function name", id);
    endif
    if (any (strcmp (block.type, {"Constant", "Gain", "Step", "Unit Delay", ...
                                 "Integrator", "Discrete Integrator", "Rate Transition", "Inport", "Outport", ...
                                 "Saturation", "Dead Zone", "Switch"})))
      value = block.value;
      if (! isnumeric (value) || isempty (value) || ! isreal (value) ...
          || any (! isfinite (value(:))))
        error ("ob_validate_model: block %d (%s) needs a nonempty finite real numeric value", id, block.type);
      endif
      if (strcmp (block.type, "Step") && (! isvector (value) || numel (value) != 3))
        error ("ob_validate_model: block %d Step value must be [time initial final]", id);
      endif
      if (any (strcmp (block.type, {"Saturation", "Dead Zone"})) ...
          && (! isvector (value) || numel (value) != 2 || value(1) > value(2)))
        error ("ob_validate_model: block %d %s value must be ordered [lower upper] limits", id, block.type);
      endif
      if (strcmp (block.type, "Switch") && ! isscalar (value))
        error ("ob_validate_model: block %d Switch threshold must be a finite real scalar", id);
      endif
      if (any (strcmp (block.type, {"Inport", "Outport"})) ...
          && (! isscalar (value) || value < 1 || value != fix (value)))
        error ("ob_validate_model: block %d port number must be a positive integer", id);
      endif
    endif
  endfor
  for type = {"Inport", "Outport"}
    ids = find (strcmp ({model.blocks.type}, type{1}));
    numbers = sort ([model.blocks(ids).value]);
    if (! isequal (numbers(:)', 1:numel (ids)))
      error ("ob_validate_model: %s numbers must be unique and contiguous from 1", type{1});
    endif
  endfor
  for k = 1:rows (edges)
    if (edges(k, 2) > output_counts(edges(k, 1)))
      error ("ob_validate_model: block %d output port %d does not exist", edges(k, 1), edges(k, 2));
    endif
    if (edges(k, 4) > input_counts(edges(k, 3)))
      error ("ob_validate_model: block %d input port %d does not exist", edges(k, 3), edges(k, 4));
    endif
  endfor
  for id = 1:n
    ports = sort (edges(edges(:, 3) == id, 4))';
    count = numel (ports);
    if (complete && (count < minimums(id) || ! isequal (ports, 1:count)))
      error ("ob_validate_model: block %d (%s) has %d inputs; expected %g to %g with contiguous ports", ...
             id, model.blocks(id).type, count, minimums(id), input_counts(id));
    endif
  endfor
  ob_sample_times (model);
  ob_execution_options (model);
  if (depth == 0)
    ob_model_inputs (model, complete);
  elseif (isfield (model, 'inputs') && ! isempty (model.inputs))
    error ('ob_validate_model: input datasets belong to the root model, not a subsystem');
  endif
endfunction
