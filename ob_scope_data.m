function traces = ob_scope_data (result, id, port = 1)
  % Flatten a scalar, vector, or matrix signal into one trace per element.
  if (isfield (result, "signal_map"))
    samples = ob_signal_values (result, id, port);
  else
    samples = result.values(:, id);
  endif
  label = sprintf ("%d/", id); label(end) = [];
  if (isempty (samples))
    error ("ob_scope_data: the scope has no samples");
  endif
  shape = size (samples{1});
  count = numel (samples{1});
  if (count == 0)
    error ("ob_scope_data: Scope %s has empty samples", label);
  endif
  traces = zeros (numel (samples), count);
  for step = 1:numel (samples)
    value = samples{step};
    if (! isnumeric (value) || ! isreal (value) || ! isequal (size (value), shape))
      error ("ob_scope_data: Scope %s needs real numeric samples of a fixed size", label);
    endif
    traces(step, :) = value(:)';
  endfor
endfunction
