function value = ob_direct_output (block, inputs, id, mode = [])
  % Pure direct-feedthrough evaluation shared by the graph and loop residual.
  switch (block.type)
    case 'Gain'
      require_inputs (inputs, 1, block.type);
      value = block.value * inputs{1};
    case 'Sum'
      require_inputs (inputs, 2, block.type);
      value = inputs{1} + inputs{2};
    case 'Product'
      require_inputs (inputs, 2, block.type);
      value = inputs{1} * inputs{2};
    case {'Saturation', 'Dead Zone', 'Switch'}
      value = ob_control_output (block, inputs, id, mode);
    case 'Function'
      if (isempty (inputs)), error ('ob_run: Function needs an input'); endif
      value = feval (block.name, inputs{:});
    case {'Scope', 'Inport', 'Outport'}
      require_inputs (inputs, 1, block.type);
      value = inputs{1};
    otherwise
      error ('ob_run: unsupported direct-feedthrough block %d (%s)', id, block.type);
  endswitch
endfunction

function require_inputs (inputs, count, type)
  if (numel (inputs) != count)
    error ('ob_run: %s needs %d input(s); got %d', type, count, numel (inputs));
  endif
endfunction
