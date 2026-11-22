function options = ob_execution_options (model, check_body = true)
  % A child model declares how its enclosing Subsystem may execute.
  count = sum (strcmp ({model.blocks.type}, 'Outport'));
  options = struct ('mode', 'virtual', 'states', 'held', 'outputs', 'held', ...
                    'initial_outputs', {repmat({0}, 1, count)}, 'initial_control', 0, ...
                    'control', 'sampled');
  if (isfield (model, 'execution'))
    supplied = model.execution;
    if (! isstruct (supplied) || ! isscalar (supplied) ...
        || any (! ismember (fieldnames(supplied), fieldnames(options))))
      error ('ob_execution_options: execution must be a scalar struct with supported fields');
    endif
    for field = fieldnames (supplied)'
      options.(field{1}) = supplied.(field{1});
    endfor
  endif
  if (! ischar (options.mode) || ! any (strcmp (options.mode, {'virtual','enabled','rising','falling','either'})))
    error ('ob_execution_options: mode must be virtual, enabled, rising, falling, or either');
  endif
  if (! ischar (options.control) || ! any (strcmp (options.control, {'sampled','continuous'})))
    error ('ob_execution_options: control must be sampled or continuous');
  endif
  if (strcmp (options.mode, 'virtual'))
    % Conditional output contracts do not constrain a virtual interface.
    options.states = options.outputs = 'held';
    options.initial_outputs = repmat ({0}, 1, count);
    options.initial_control = 0;
    options.control = 'sampled';
    return;
  endif
  for field = {'states','outputs'}
    if (! ischar (options.(field{1})) || ! any (strcmp (options.(field{1}), {'held','reset'})))
      error ('ob_execution_options: states and outputs must be held or reset');
    endif
  endfor
  if (! any (strcmp (options.mode, {'virtual','enabled'})) ...
      && (! strcmp (options.states, 'held') || ! strcmp (options.outputs, 'held')))
    error ('ob_execution_options: triggered subsystems require held states and outputs');
  endif
  if (! iscell (options.initial_outputs) || numel (options.initial_outputs) != count)
    error ('ob_execution_options: initial_outputs needs one cell per numbered Outport');
  endif
  options.initial_outputs = options.initial_outputs(:)';
  for port = 1:count
    value = options.initial_outputs{port};
    if (! isnumeric (value) || ! isreal (value) || isempty (value) ...
        || ndims (value) > 2 || any (! isfinite (value(:))))
      error ('ob_execution_options: initial output %d must be a finite real numeric matrix', port);
    endif
    options.initial_outputs{port} = full (double (value));
  endfor
  if (! isnumeric (options.initial_control) || ! isreal (options.initial_control) ...
      || ! isscalar (options.initial_control) || ! isfinite (options.initial_control))
    error ('ob_execution_options: initial_control must be a finite real scalar');
  endif
  options.initial_control = double (options.initial_control);
  if (check_body && ! strcmp (options.mode, 'virtual'))
    require_body (model, strcmp (options.mode, 'enabled'));
  endif
endfunction

function require_body (model, continuous)
  if (! continuous && any (strcmp ({model.blocks.type}, 'Integrator')))
    error ('ob_execution_options: triggered bodies require discrete blocks; continuous Integrator is not supported');
  endif
  rates = ob_sample_times (model);
  if (! continuous && any (rates(:) != 0))
    error ('ob_execution_options: blocks inside a triggered body must inherit its execution clock');
  endif
  for id = reshape (find (strcmp ({model.blocks.type}, 'Subsystem')), 1, [])
    child = model.blocks(id).value;
    mode = ob_execution_mode (child);
    child_options = ob_execution_options (child, false);
    if (! continuous && strcmp (child_options.control, 'continuous'))
      error ('ob_execution_options: continuous controls cannot execute inside a triggered body');
    endif
    require_body (child, continuous && any (strcmp (mode, {'virtual','enabled'})));
  endfor
endfunction
