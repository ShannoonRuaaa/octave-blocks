function result = ob_run (model, t, options = struct ())
  % Collect a run using the same resumable scheduler exposed to host code.
  if (nargin < 2), t = 0:0.1:10; endif
  options = ob_solver_options (options);
  if (! isvector (t) || ! isnumeric (t) || ! isreal (t) || isempty (t) ...
      || any (! isfinite (t(:))) || any (diff (t(:)) <= 0))
    error ('ob_run: t must be a nonempty, strictly increasing numeric vector');
  endif
  t = double (t(:)');
  runtime = ob_runtime_init (model, t(1), options);
  values = cell (numel (t), numel (runtime.model.blocks));
  values(1, :) = runtime.current;
  for sample = 2:numel (t)
    runtime = ob_runtime_step (runtime, t(sample));
    values(sample, :) = runtime.current;
  endfor
  result = struct ('t', t(:), 'values', {values}, 'order', runtime.order, ...
                  'solver', options.solver, 'solver_options', options, ...
                  'integration_steps', runtime.integration_steps);
  result.flat_values = values;
  result.signal_map = runtime.signal_map;
  result.block_paths = runtime.block_paths;
  result.compiled_model = runtime.model;
  result.inputs = runtime.model.inputs;
  result.sample_hits = runtime.sample_hits;
  result.sample_times = runtime.rates;
  result.events = runtime.events;
  result.values = cell (numel (t), numel (model.blocks));
  for item = runtime.signal_map
    if (numel (item.path) == 1 && ! isempty (item.outputs))
      result.values(:, item.path) = values(:, item.outputs(1));
    endif
  endfor
endfunction
