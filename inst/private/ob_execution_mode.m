function mode = ob_execution_mode (model)
  % Read only the mode, so an editable draft can still expose its ports.
  mode = 'virtual';
  if (isfield (model, 'execution') && isstruct (model.execution) ...
      && isscalar (model.execution) && isfield (model.execution, 'mode'))
    mode = model.execution.mode;
  endif
  if (! ischar (mode) || ! (ob_is_resettable_mode(mode) || any (strcmp (mode, {'virtual','enabled','rising','falling','either','enabled_rising','enabled_falling','enabled_either'}))))
    error ('ob_execution_options: unsupported subsystem execution mode');
  endif
endfunction
