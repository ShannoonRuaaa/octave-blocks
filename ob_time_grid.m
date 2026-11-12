function t = ob_time_grid (start_time, stop_time, step)
  % Build fixed-size steps and include the exact requested stop time.
  if (! isscalar (start_time) || ! isscalar (stop_time) || ! isscalar (step) ...
      || ! isnumeric (start_time) || ! isnumeric (stop_time) ...
      || ! isnumeric (step) || ! isreal (start_time) ...
      || ! isreal (stop_time) || ! isreal (step) ...
      || ! isfinite (start_time) || ! isfinite (stop_time) ...
      || ! isfinite (step) || stop_time <= start_time || step <= 0)
    error ("ob_time_grid: use finite scalar times, stop > start, and step > 0");
  endif
  t = start_time:step:stop_time;
  if (t(end) < stop_time)
    t(end + 1) = stop_time;
  else
    t(end) = stop_time;
  endif
endfunction
