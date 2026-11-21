function value = ob_transport_delay (action, varargin)
  % Input history for a Transport Delay block.
  %
  % The history holds accepted input samples in time order.  A discontinuity
  % is stored as two samples with the same time: the left limit followed by
  % the right limit.  Output interpolates linearly between samples.
  switch (action)
    case 'init'
      value = struct ('kind', 'octave-blocks-transport-delay-v1', ...
                      't', zeros (0, 1), 'u', zeros (0, 0), 'left', false (0, 1), ...
                      'shape', []);
    case 'output'
      value = output (varargin{:});
    case 'record'
      value = record (varargin{:});
    case 'jumps'
      value = jumps (varargin{:});
    otherwise
      error ('ob_transport_delay: unknown operation');
  endswitch
endfunction

function y = output (params, history, time, left_limit = false)
  tau = time - params.delay;
  t = history.t;
  if (isempty (t) || tau < t(1))
    y = initial_output (params, history);
    return;
  endif
  if (tau >= t(end))
    k = numel (t);
    % A left-limit query exactly at a stored jump uses the left sample.
    if (left_limit && tau == t(end) && k > 1 && t(k-1) == t(k)), k -= 1; endif
    y = reshape (history.u(k, :), history.shape);
    return;
  endif
  k = lookup (t, tau);          % last index with t(k) <= tau
  if (left_limit && t(k) == tau)
    % Step back to the left sample of a jump at tau, if any.
    while (k > 1 && t(k-1) == tau), k -= 1; endwhile
    y = reshape (history.u(k, :), history.shape);
    return;
  endif
  a = t(k); b = t(k+1);
  if (b == a)
    y = reshape (history.u(k+1, :), history.shape);
    return;
  endif
  % Cubic Hermite interpolation with slopes from neighbouring samples in the
  % same continuous piece.  It is C1 between samples, so adaptive solvers see
  % no artificial kinks, and third-order accurate on smooth inputs.
  h = b - a; w = (tau - a) / h;
  da = slope (t, history.u, k); db = slope (t, history.u, k+1);
  h00 = (1 + 2*w) * (1 - w)^2; h10 = w * (1 - w)^2;
  h01 = w^2 * (3 - 2*w);       h11 = w^2 * (w - 1);
  value = h00 * history.u(k, :) + h10 * h * da + h01 * history.u(k+1, :) + h11 * h * db;
  y = reshape (value, history.shape);
endfunction

function d = slope (t, u, i)
  % Derivative at sample i of the quadratic through it and its neighbours,
  % never reaching across a stored discontinuity (two equal times).
  n = numel (t);
  left = i > 1 && t(i-1) < t(i);
  right = i < n && t(i+1) > t(i);
  if (left && right)
    h0 = t(i) - t(i-1); h1 = t(i+1) - t(i);
    s0 = (u(i, :) - u(i-1, :)) / h0; s1 = (u(i+1, :) - u(i, :)) / h1;
    d = (h1 * s0 + h0 * s1) / (h0 + h1);
  elseif (right)
    h0 = t(i+1) - t(i); s0 = (u(i+1, :) - u(i, :)) / h0;
    if (i + 2 <= n && t(i+2) > t(i+1))
      h1 = t(i+2) - t(i+1); s1 = (u(i+2, :) - u(i+1, :)) / h1;
      d = s0 * (2*h0 + h1) / (h0 + h1) - s1 * h0 / (h0 + h1);
    else
      d = s0;
    endif
  elseif (left)
    h1 = t(i) - t(i-1); s1 = (u(i, :) - u(i-1, :)) / h1;
    if (i > 2 && t(i-2) < t(i-1))
      h0 = t(i-1) - t(i-2); s0 = (u(i-1, :) - u(i-2, :)) / h0;
      d = s1 * (2*h1 + h0) / (h0 + h1) - s0 * h1 / (h0 + h1);
    else
      d = s1;
    endif
  else
    d = zeros (1, columns (u));
  endif
endfunction

function y = initial_output (params, history)
  y = params.initial;
  if (isscalar (y) && ! isempty (history.shape) && prod (history.shape) != 1)
    y = y * ones (history.shape);
  endif
endfunction

function history = record (params, history, time, input, side, id)
  if (! isnumeric (input) || ! isreal (input) || isempty (input) || ndims (input) > 2 ...
      || any (! isfinite (input(:))))
    error ('ob_run: Transport Delay block %d input must be a finite real matrix', id);
  endif
  shape = size (input);
  if (isempty (history.shape))
    if (! isscalar (params.initial) && ! isequal (size (params.initial), shape))
      error ('ob_run: Transport Delay block %d input shape must match its initial output', id);
    endif
    history.shape = shape;
    history.u = zeros (0, prod (shape));
  elseif (! isequal (history.shape, shape))
    error ('ob_run: Transport Delay block %d input changed shape', id);
  endif
  row = double (input(:)');
  left = strcmp (side, 'left');
  n = numel (history.t);
  if (n > 0 && time < history.t(end))
    error ('ob_run: Transport Delay block %d history cannot move backward in time', id);
  endif
  if (n > 0 && time == history.t(end))
    if (! left && history.left(end) && ! isequal (history.u(end, :), row))
      % Keep the left sample and add the right limit: a stored discontinuity.
      history.t(end+1, 1) = time; history.u(end+1, :) = row; history.left(end+1, 1) = false;
    else
      % A repeated sample at one time keeps the latest value on its side.
      if (n > 1 && history.t(end-1) == time && left)
        history.t(end) = []; history.u(end, :) = []; history.left(end) = [];
      endif
      history.u(end, :) = row; history.left(end) = left;
    endif
  else
    history.t(end+1, 1) = time; history.u(end+1, :) = row; history.left(end+1, 1) = left;
  endif
  % Retain only the samples still reachable by time - delay, plus the two
  % samples at or before that point used by interpolation and its slopes.
  horizon = time - params.delay;
  keep = find (history.t <= horizon, 1, 'last');
  if (! isempty (keep))
    while (keep > 1 && history.t(keep-1) == history.t(keep)), keep -= 1; endwhile
    keep = max (1, keep - 1);
    if (keep > 1)
      history.t(1:keep-1) = []; history.u(1:keep-1, :) = []; history.left(1:keep-1) = [];
    endif
  endif
endfunction

function times = jumps (params, history, begin, finish)
  % Output discontinuities inside (begin, finish): stored input jumps shifted
  % by the delay, plus the end of the initial-output interval.
  t = history.t;
  times = [];
  if (numel (t) > 1)
    duplicate = t(1:end-1) == t(2:end);
    times = t([duplicate; false])' + params.delay;
  endif
  if (! isempty (t))
    times(end+1) = t(1) + params.delay;
  endif
  times = times(times > begin & times < finish);
endfunction

%!shared params, h
%! params = struct ('delay', 1, 'initial', 5);
%! h = ob_transport_delay ('init');
%! h = ob_transport_delay ('record', params, h, 0, 0, 'right', 1);
%! h = ob_transport_delay ('record', params, h, 1, 1, 'left', 1);
%! h = ob_transport_delay ('record', params, h, 1, 3, 'right', 1);
%! h = ob_transport_delay ('record', params, h, 1.5, 3.5, 'left', 1);
%!assert (ob_transport_delay ('output', params, h, 0.5), 5)
%!assert (ob_transport_delay ('output', params, h, 1.5), 0.5)
%!assert (ob_transport_delay ('output', params, h, 2, true), 1)
%!assert (ob_transport_delay ('output', params, h, 2), 3)
%!assert (ob_transport_delay ('output', params, h, 2.25), 3.25)
%!assert (ob_transport_delay ('output', params, h, 3), 3.5)
%!assert (ob_transport_delay ('jumps', params, h, 0, 10), [2 1])
%!test
%! g = ob_transport_delay ('record', params, h, 4, 9, 'right', 1);
%! assert (g.t', [1 1.5 4]);
%!test
%! % Cubic Hermite slopes reproduce a quadratic input exactly.
%! q = ob_transport_delay ('init');
%! for s = 0:3, q = ob_transport_delay ('record', params, q, s, s^2, 'right', 1); endfor
%! assert (ob_transport_delay ('output', params, q, 2.5), 2.25, 1e-14);
%! assert (ob_transport_delay ('output', params, q, 3.25), 5.0625, 1e-14);
%!test
%! g = ob_transport_delay ('record', params, h, 1.5, 6, 'right', 1);
%! assert (g.t', [0 1 1 1.5 1.5]); assert (g.u(end), 6);
%! g = ob_transport_delay ('record', params, g, 1.5, 7, 'right', 1);
%! assert (g.t', [0 1 1 1.5 1.5]); assert (g.u(end), 7);
%!error <backward> ob_transport_delay ('record', params, h, 1, 0, 'right', 1)
%!error <shape> ob_transport_delay ('record', struct ('delay', 1, 'initial', [1 2]), ob_transport_delay ('init'), 0, 1, 'right', 3)
