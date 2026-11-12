function rates = ob_sample_times (model)
  % Per-level metadata: [period offset], relative to simulation start.
  n = numel (model.blocks);
  rates = zeros (n, 2);
  if (isfield (model, 'sample_times')), rates = model.sample_times; endif
  if (! isnumeric (rates) || ! isreal (rates) || issparse (rates) ...
      || ndims (rates) != 2 || ! isequal (size (rates), [n 2]) ...
      || any (! isfinite (rates(:))) || any (rates(:) < 0))
    error ('ob_sample_times: sample_times must be a finite nonnegative N-by-2 [period offset] matrix');
  endif
  rates = double (rates);
  if (any (rates(:, 1) == 0 & rates(:, 2) != 0) ...
      || any (rates(:, 1) > 0 & rates(:, 2) >= rates(:, 1)))
    error ('ob_sample_times: use [0 0] to inherit, or period > 0 with 0 <= offset < period');
  endif
  eligible = ismember ({model.blocks.type}, {'Unit Delay', 'Discrete Integrator', 'Rate Transition'});
  for id = reshape (find (strcmp ({model.blocks.type}, 'Subsystem')), 1, [])
    eligible(id) = ! strcmp (ob_execution_mode(model.blocks(id).value), 'virtual');
    options = ob_execution_options (model.blocks(id).value, false);
    if (strcmp (options.control, 'continuous') && rates(id,1) > 0)
      error ('ob_sample_times: continuous subsystem control cannot have an explicit sample time');
    endif
  endfor
  if (any (rates(! eligible, 1) != 0))
    error ('ob_sample_times: only Unit Delay, Discrete Integrator, Rate Transition, and conditional Subsystems may have explicit sample times');
  endif
endfunction
