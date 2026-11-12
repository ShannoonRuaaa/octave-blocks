function output = ob_control_output (block, inputs, id, mode = [])
  % Shared finite real-matrix semantics for nonlinear control primitives.
  count = 1;
  if (strcmp (block.type, "Switch")), count = 3; endif
  if (numel (inputs) != count)
    error ("ob_run: %s block %d needs %d inputs", block.type, id, count);
  endif
  for port = 1:count
    input = inputs{port};
    if (! isnumeric (input) || ! isreal (input) || isempty (input) ...
        || ndims (input) > 2 || any (! isfinite (input(:))))
      error ("ob_run: %s block %d input %d must be a nonempty finite real numeric matrix", ...
             block.type, id, port);
    endif
    inputs{port} = full (double (input));
  endfor
  value = double (block.value);
  switch (block.type)
    case "Saturation"
      if (isempty (mode))
        output = min (max (inputs{1}, value(1)), value(2));
      else
        output = inputs{1};
        output(mode < 0) = value(1); output(mode > 0) = value(2);
      endif
    case "Dead Zone"
      input = inputs{1};
      output = zeros (size (input));
      below = input < value(1); above = input > value(2);
      if (! isempty (mode)), below = mode < 0; above = mode > 0; endif
      output(below) = input(below) - value(1);
      output(above) = input(above) - value(2);
    case "Switch"
      if (! isequal (size (inputs{1}), size (inputs{3})))
        error ("ob_run: Switch block %d data inputs 1 and 3 must have identical shapes", id);
      endif
      if (! isscalar (inputs{2}) && ! isequal (size (inputs{1}), size (inputs{2})))
        error ("ob_run: Switch block %d control input 2 must be scalar or match the data shape", id);
      endif
      selected = inputs{2} >= value;
      if (! isempty (mode)), selected = logical (mode); endif
      if (isscalar (selected))
        if (selected), output = inputs{1}; else output = inputs{3}; endif
      else
        output = inputs{3};
        output(selected) = inputs{1}(selected);
      endif
    otherwise
      error ("ob_run: unsupported control block '%s'", block.type);
  endswitch
  if (any (! isfinite (output(:))))
    error ("ob_run: %s block %d produced nonfinite output", block.type, id);
  endif
endfunction
