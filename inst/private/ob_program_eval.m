function current = ob_program_eval (program, parameters, model, time, states, left_limit, flow)
  % ob_runtime_eval for a model with a prepared evaluation program
  % (ob_prepare_runtime_model): the same block expressions in the same
  % order, without the per-call cache checks and string-free dispatch setup.
  % PARAMETERS is the plan's parameter cache; FLOW holds frozen control
  % modes, or is an empty struct or [].  These models have no lifecycle
  % blocks, so ob_runtime_eval returns their states unchanged and this
  % function does not return them.  Callers check once that the plan is
  % trusted (runtime_info kind v1); the program was built for the context's
  % execution order, which every caller evaluates with.
  current = cell (1, program.count);
  current(program.held) = states(program.held);
  blocks = model.blocks;
  if (program.preset)
    current(program.constants) = {blocks(program.constants).value};
    current(program.times) = {time};
  endif
  slots = program.slots; ops = program.ops;
  first = program.first; second = program.second;
  has_modes = program.controls && isfield (flow, 'modes');
  for k = 1:numel (slots)
    id = slots(k);
    op = ops(k);
    % Ordered by how often solver stages meet them, as in ob_runtime_eval.
    if (op == 5)
      % Gain
      current{id} = blocks(id).value * current{first(k)};
    elseif (op == 6)
      % Sum
      current{id} = current{first(k)} + current{second(k)};
    elseif (op == 12)
      % Scope, Inport, Outport read by another block
      current{id} = current{first(k)};
    elseif (op == 8 || op == 9 || op == 10)
      % Saturation, Dead Zone, Switch: ob_control_output, whose case bodies
      % are inlined for finite real full double scalar inputs (its checks
      % pass and its conversions leave such inputs unchanged).  Anything
      % else goes to ob_control_output itself.
      mode = [];
      if (has_modes), mode = flow.modes{id}; endif
      inputs = current(program.inputs{k});
      scalar = all (cellfun ('isclass', inputs, 'double')) && all (cellfun ('prodofsize', inputs) == 1);
      if (scalar)
        packed = [inputs{:}];
        scalar = isreal (packed) && ! issparse (packed) && all (isfinite (packed));
      endif
      if (! scalar)
        current{id} = ob_control_output (blocks(id), inputs, id, mode);
        continue;
      endif
      value = double (blocks(id).value);
      if (op == 8)
        % Saturation
        if (isempty (mode))
          output = min (max (inputs{1}, value(1)), value(2));
        else
          output = inputs{1};
          output(mode < 0) = value(1); output(mode > 0) = value(2);
        endif
      elseif (op == 9)
        % Dead Zone
        input = inputs{1};
        output = zeros (size (input));
        below = input < value(1); above = input > value(2);
        if (! isempty (mode)), below = mode < 0; above = mode > 0; endif
        output(below) = input(below) - value(1);
        output(above) = input(above) - value(2);
      else
        % Switch: scalar data inputs have identical shapes and a scalar control.
        selected = inputs{2} >= value;
        if (! isempty (mode)), selected = logical (mode); endif
        if (isscalar (selected))
          if (selected), output = inputs{1}; else output = inputs{3}; endif
        else
          output = ifelse (selected, inputs{1}, inputs{3});
        endif
      endif
      if (any (! isfinite (output(:))))
        error ("ob_run: %s block %d produced nonfinite output", blocks(id).type, id);
      endif
      current{id} = output;
    elseif (op == 20)
      current{id} = ob_delay_output (parameters{id}, states{id}, time, left_limit);
    elseif (op == 11)
      % Function
      current{id} = feval (blocks(id).name, current{program.inputs{k}});
    elseif (op == 7)
      % Product
      current{id} = current{first(k)} * current{second(k)};
    elseif (op == 4)
      % Step
      value = blocks(id).value;
      if (! isnumeric (value) || numel (value) != 3)
        error ("ob_run: Step value must be [time initial final]");
      endif
      if (time < value(1) || (left_limit && time == value(1)))
        current{id} = value(2);
      else
        current{id} = value(3);
      endif
    elseif (op == 1)
      % External Input
      current{id} = ob_input_value (model.inputs{blocks(id).value}, time, left_limit);
    elseif (op == 19)
      % Limited Integrator (ob_runtime_parameters' plan lookup).
      params = parameters{id};
      if (! isstruct (params)), params = ob_block_parameters (blocks(id)); endif
      current{id} = min (max (states{id}, params.lower), params.upper);
    elseif (op == 13)
      % Multiple Function
      returned = cell (1, blocks(id).value);
      [returned{:}] = feval (blocks(id).name, current{program.inputs{k}});
      current{id} = returned;
    else
      % Function Output (op 14)
      current{id} = current{first(k)}{blocks(id).value};
    endif
  endfor
  if (program.copies), current(program.sinks) = current(program.sink_sources); endif
endfunction
