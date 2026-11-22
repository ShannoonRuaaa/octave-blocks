function [inputs, outputs, minimum] = ob_block_ports (block)
  outputs = 1;
  switch (block.type)
    case {"Constant", "Time", "Step", "Inport"}
      inputs = 0;
    case {"Gain", "Scope", "Unit Delay", "Integrator", "Discrete Integrator", "Rate Transition", "Outport", "Saturation", "Dead Zone"}
      inputs = 1;
    case {"Sum", "Product"}
      inputs = 2;
    case "Switch"
      inputs = 3;
    case "Function"
      inputs = Inf;
      outputs = ob_function_output_count (block);
    case "Subsystem"
      types = {block.value.blocks.type};
      inputs = sum (strcmp (types, "Inport"));
      outputs = sum (strcmp (types, "Outport"));
      if (! strcmp (ob_execution_mode(block.value), 'virtual')), inputs += 1; endif
    otherwise
      error ("ob_block_ports: unknown type '%s'", block.type);
  endswitch
  minimum = inputs;
  if (isinf (inputs)), minimum = 1; endif
endfunction
