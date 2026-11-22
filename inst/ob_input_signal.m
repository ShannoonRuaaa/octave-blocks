function signal = ob_input_signal (t, values = [], shape = [], method = 'zoh')
  % One row per sample; components reshape into the declared column-order shape.
  if (nargin == 1 && isstruct (t) && isscalar (t))
    input = t;
    if (! all (isfield (input, {'t', 'values'})) ...
        || ! all (ismember (fieldnames(input), {'t', 'values', 'shape', 'method'})))
      error ('ob_input_signal: signal fields are t, values, shape, and method');
    endif
    t = input.t; values = input.values;
    if (isfield (input, 'shape')), shape = input.shape; endif
    if (isfield (input, 'method')), method = input.method; endif
  endif
  if (! isnumeric (t) || ! isreal (t) || ! isvector (t) || isempty (t) ...
      || any (! isfinite (t(:))))
    error ('ob_input_signal: times must be a nonempty finite real vector');
  endif
  t = full (double (t(:)));
  if (any (diff(t) <= 0) || any (! isfinite (diff(t))))
    error ('ob_input_signal: times must be strictly increasing with finite intervals');
  endif
  if (! isa (values, 'double') || ! isreal (values) || issparse (values) ...
      || ndims (values) != 2 || isempty (values) || any (! isfinite (values(:))) ...
      || rows (values) != numel (t))
    error ('ob_input_signal: values must be a full finite real double matrix with one row per time');
  endif
  if (isempty (shape)), shape = [1 columns(values)]; endif
  if (! isnumeric (shape) || ! isreal (shape) || ! isvector (shape) ...
      || numel (shape) != 2 || any (! isfinite (shape)) ...
      || any (shape <= 0) || any (shape != fix (shape)) ...
      || prod (double(shape)) != columns (values))
    error ('ob_input_signal: shape must be [rows cols] matching the sample component count');
  endif
  if (! ischar (method) || rows (method) != 1 || ! any (strcmp (method, {'zoh', 'linear'})))
    error ('ob_input_signal: method must be zoh or linear');
  endif
  signal = struct ('t', t, 'values', values, 'shape', full(double(shape(:)')), 'method', method);
endfunction
