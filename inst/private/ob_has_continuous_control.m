function yes = ob_has_continuous_control (model)
  % Structural classification of gates inside this diagram, including lazy bodies.
  yes = false;
  for block = model.blocks
    if (any (strcmp (block.type, {'Subsystem','Conditional Subsystem'})))
      options = ob_execution_options (block.value, false);
      if (strcmp (options.control, 'continuous') || ob_has_continuous_control (block.value))
        yes = true; return;
      endif
    endif
  endfor
endfunction
