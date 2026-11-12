function mode = ob_execution_mode (model)
  % Read only the mode, so an editable draft can still expose its ports.
  mode = 'virtual';
  if (isfield (model, 'execution') && isstruct (model.execution) ...
      && isscalar (model.execution) && isfield (model.execution, 'mode'))
    mode = model.execution.mode;
  endif
  if (! ischar (mode) || ! any (strcmp (mode, {'virtual','enabled','rising','falling','either'})))
    error ('ob_execution_options: mode must be virtual, enabled, rising, falling, or either');
  endif
endfunction
