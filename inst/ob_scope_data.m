function traces = ob_scope_data (result, id, port = 1)
  ## -*- texinfo -*-
  ## @deftypefn {} {@var{traces} =} ob_scope_data (@var{result}, @var{id}, @var{port})
  ## Flatten a logged signal into a numeric matrix with one row per time.
  ## @var{result} is returned by @code{ob_run}; @var{id} is a block index
  ## or a hierarchy path.  The optional output @var{port} defaults to 1.
  ## Signal elements become columns in column-major order.  Samples must
  ## be real numeric values of a fixed, nonempty shape.
  ##
  ## @example
  ## r = ob_run (ob_oscillator (), 0:0.1:1);
  ## traces = ob_scope_data (r, 4);
  ## @end example
  ## @seealso{ob_signal_values, ob_scope_paths}
  ## @end deftypefn

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
