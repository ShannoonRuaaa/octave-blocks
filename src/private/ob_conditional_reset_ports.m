function mask = ob_conditional_reset_ports (options)
  % Numbered Outports whose OutputWhenDisabled policy is 'reset': one
  % policy for every port, or a cell with one per port (ob_execution_options).
  mask = strcmp (options.outputs, 'reset');
  if (! iscell (options.outputs))
    mask = repmat (mask, 1, numel (options.initial_outputs));
  endif
endfunction
