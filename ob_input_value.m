function value = ob_input_value (signal, time, left_limit = false)
  % Query a normalized ob_input_signal. Outside its range, hold the endpoint.
  if (! isnumeric (time) || ! isscalar (time) || ! isreal (time) || ! isfinite (time))
    error ('ob_input_value: query time must be a finite real scalar');
  endif
  times = signal.t;
  if (time <= times(1))
    row = signal.values(1, :);
  elseif (strcmp (signal.method, 'zoh'))
    if (left_limit), index = find (times < time, 1, 'last');
    else index = find (times <= time, 1, 'last'); endif
    row = signal.values(index, :);
  elseif (time >= times(end))
    row = signal.values(end, :);
  else
    index = find (times <= time, 1, 'last');
    alpha = (time - times(index)) / (times(index + 1) - times(index));
    row = (1 - alpha) * signal.values(index, :) + alpha * signal.values(index + 1, :);
  endif
  value = reshape (row, signal.shape);
endfunction
