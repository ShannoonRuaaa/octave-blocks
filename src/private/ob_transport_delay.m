function value = ob_transport_delay (action, varargin)
  % Input history for a Transport Delay block.
  %
  % The history holds accepted input samples in time order.  A discontinuity
  % is stored as two samples with the same time: the left limit followed by
  % the right limit.  Output uses cubic Hermite interpolation between
  % samples.  'start' is the first recorded time; pruning old samples never
  % changes it, so the end of the initial-output interval stays known.
  %
  % Times a few ulps apart are one instant (same_instant, which mirrors the
  % engine's time_equal): a Step at 0.7 and the output time 7 * 0.1, or a
  % delayed jump t(j) + T and a nearby output time.  Such samples merge in
  % the history, queries there snap onto the delayed sample, and jumps ()
  % does not return a boundary that duplicates an existing one.
  switch (action)
    case 'record'
      % Evaluators read outputs through ob_delay_output directly, so records
      % (two per accepted step and delay) are the most frequent operation.
      value = record (varargin{:});
    case 'output'
      value = ob_delay_output (varargin{:});
    case 'init'
      value = struct ('kind', 'octave-blocks-transport-delay-v1', ...
                      't', zeros (0, 1), 'u', zeros (0, 0), 'left', false (0, 1), ...
                      'shape', [], 'start', []);
    case 'shape'
      % Fix the signal shape from an input value without recording a sample,
      % so a scalar initial output is broadcast from the very first output.
      value = shape_input (varargin{:});
    case 'jumps'
      value = jumps (varargin{:});
    otherwise
      error ('ob_transport_delay: unknown operation');
  endswitch
endfunction

function yes = same_instant (a, b, delay)
  % The engine's time_equal tolerance, with the delay as the shortest
  % meaningful spacing.
  yes = abs (a - b) <= min (delay / 16, 8 * eps * max (max (abs (a), abs (b)), realmin ()));
endfunction

function start = start_time (history)
  % Histories saved before 'start' existed fall back to the oldest sample.
  if (isfield (history, 'start') && ! isempty (history.start))
    start = history.start;
  elseif (! isempty (history.t))
    start = history.t(1);
  else
    start = Inf;
  endif
endfunction

function [history, input] = shape_input (params, history, input, id)
  % Validate an input value and fix the history's signal shape.  A scalar
  % initial output takes the input's shape; a scalar input is expanded to a
  % matrix initial output's shape, as Simulink does.
  if (! isnumeric (input) || ! isreal (input) || isempty (input) || ndims (input) > 2 ...
      || any (! isfinite (input(:))))
    error ('ob_run: Transport Delay block %d input must be a finite real matrix', id);
  endif
  if (isscalar (input) && ! isscalar (params.initial))
    input = input * ones (size (params.initial));
  endif
  shape = size (input);
  if (isempty (history.shape))
    if (! isscalar (params.initial) && ! isequal (size (params.initial), shape))
      error ('ob_run: Transport Delay block %d input shape must match its initial output', id);
    endif
    history.shape = shape;
    history.u = zeros (0, prod (shape));
  elseif (! (size_equal (history.shape, shape) && all (history.shape == shape)))
    % Explicit isequal () of two size vectors.
    error ('ob_run: Transport Delay block %d input changed shape', id);
  endif
endfunction

function history = record (params, history, time, input, side, id)
  [history, input] = shape_input (params, history, input, id);
  row = double (input(:)');
  left = strcmp (side, 'left');
  n = numel (history.t);
  if (n > 0 && time < history.t(end))
    error ('ob_run: Transport Delay block %d history cannot move backward in time', id);
  endif
  if (n == 0 && (! isfield (history, 'start') || isempty (history.start)))
    history.start = time;
  endif
  if (n > 0 && time > history.t(end) && same_instant (time, history.t(end), params.delay))
    % One instant, e.g. a Step at 0.7 and the output time 7 * 0.1.  Separate
    % samples would leave an interval of about 1e-16 whose difference
    % quotients wreck the Hermite slopes.  The later sample is the right
    % limit at that instant: it forms a stored jump with a single earlier
    % sample, or replaces a jump's right limit.
    % same_row () is isequal () for these finite double rows.
    if (! same_row (history.u(end, :), row))
      if (n > 1 && history.t(end-1) == history.t(end))
        history.u(end, :) = row;
      else
        history.left(end) = true;
        history.t(end+1, 1) = history.t(end); history.u(end+1, :) = row; history.left(end+1, 1) = false;
      endif
    endif
  elseif (n > 0 && time == history.t(end))
    if (! left && history.left(end) && ! same_row (history.u(end, :), row))
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

function yes = same_row (a, b)
  yes = size_equal (a, b) && all (a == b);
endfunction

function times = jumps (params, history, begin, finish, existing = [begin finish])
  % Output discontinuities inside (begin, finish): stored input jumps shifted
  % by the delay, plus the end of the initial-output interval.  A jump at
  % the same instant as an existing solver boundary (an output time, a Step
  % time, another delayed jump) is left out: output () snaps queries at that
  % boundary onto the jump, so it already acts as the jump's boundary.
  t = history.t;
  times = [];
  if (numel (t) > 1)
    duplicate = t(1:end-1) == t(2:end);
    times = t([duplicate; false])' + params.delay;
  endif
  start = start_time (history);
  if (isfinite (start))
    times(end+1) = start + params.delay;
  endif
  times = times(times > begin & times < finish);
  keep = true (size (times));
  for k = 1:numel (times)
    keep(k) = ! any (same_instant (existing, times(k), params.delay));
    if (keep(k)), existing(end+1) = times(k); endif
  endfor
  times = times(keep);
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
%!assert (h.start, 0)
%!test
%! % At exactly start + T the output is u(start), right-continuous, while
%! % its left limit is still the initial output.
%! assert (ob_transport_delay ('output', params, h, 1), 0);
%! assert (ob_transport_delay ('output', params, h, 1, true), 5);
%! assert (ob_transport_delay ('output', params, h, 1 - eps, true), 5);
%!test
%! % A single recorded sample: the left limit at start + T is the initial value.
%! g = ob_transport_delay ('record', params, ob_transport_delay ('init'), 0, 2, 'right', 1);
%! assert (ob_transport_delay ('output', params, g, 1, true), 5);
%! assert (ob_transport_delay ('output', params, g, 1), 2);
%!test
%! % Pruning keeps the start time, so jumps () and the initial interval agree.
%! g = ob_transport_delay ('record', params, h, 4, 9, 'right', 1);
%! assert (g.t', [1 1.5 4]);
%! assert (g.start, 0);
%! assert (ob_transport_delay ('jumps', params, g, 0, 10), 1);
%! assert (ob_transport_delay ('output', params, g, 0.9, true), 5);
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
%!test
%! % 'shape' broadcasts a scalar initial output before any sample exists.
%! g = ob_transport_delay ('shape', params, ob_transport_delay ('init'), [1; 2], 1);
%! assert (isempty (g.t)); assert (isempty (g.start)); assert (g.shape, [2 1]);
%! assert (ob_transport_delay ('output', params, g, 0), [5; 5]);
%!test
%! % A scalar input is expanded to a matrix initial output's shape.
%! p = struct ('delay', 1, 'initial', [5; 6]);
%! g = ob_transport_delay ('record', p, ob_transport_delay ('init'), 0, 2, 'right', 1);
%! g = ob_transport_delay ('record', p, g, 0.5, 3, 'right', 1);
%! assert (g.shape, [2 1]);
%! assert (ob_transport_delay ('output', p, g, 0.5), [5; 6]);
%! assert (ob_transport_delay ('output', p, g, 1.5), [3; 3]);
%!test
%! % Histories saved without 'start' still use their oldest sample.
%! g = rmfield (h, 'start');
%! assert (ob_transport_delay ('output', params, g, 1, true), 5);
%! assert (ob_transport_delay ('jumps', params, g, 0, 10), [2 1]);
%!test
%! % (0.1 + 0.2) - 0.2 > 0.1: the start + T boundary and a stored jump shifted
%! % by T are still met exactly by queries at the sums jumps () returns.
%! p = struct ('delay', 0.2, 'initial', 7);
%! g = ob_transport_delay ('record', p, ob_transport_delay ('init'), 0.1, 0.1, 'right', 1);
%! g = ob_transport_delay ('record', p, g, 0.2, 0, 'left', 1);
%! g = ob_transport_delay ('record', p, g, 0.2, 1, 'right', 1);
%! g = ob_transport_delay ('record', p, g, 0.3, 1, 'left', 1);
%! assert ((0.1 + 0.2) - 0.2 > 0.1);
%! assert (ob_transport_delay ('output', p, g, 0.1 + 0.2, true), 7);
%! assert (ob_transport_delay ('output', p, g, 0.1 + 0.2), 0.1);
%! assert (ob_transport_delay ('output', p, g, 0.2 + 0.2, true), 0);
%! assert (ob_transport_delay ('output', p, g, 0.2 + 0.2), 1);
%! % A query a few ulps from start + T or t(j) + T is the same instant.
%! assert (ob_transport_delay ('output', p, g, 0.3, true), 7);
%! assert (ob_transport_delay ('output', p, g, 0.3), 0.1);
%! assert (ob_transport_delay ('output', p, g, 0.4 - eps (0.4), true), 0);
%! assert (ob_transport_delay ('output', p, g, 0.4 + eps (0.4)), 1);
%!test
%! % A Step at 0.7 and the output time 7 * 0.1 = 0.7 + ulp are one instant:
%! % the samples merge into a stored jump instead of a 1e-16 interval.
%! p = struct ('delay', 0.1, 'initial', 0);
%! g = ob_transport_delay ('record', p, ob_transport_delay ('init'), 0.6, 0, 'right', 1);
%! g = ob_transport_delay ('record', p, g, 0.7, 0, 'left', 1);
%! g = ob_transport_delay ('record', p, g, 7 * 0.1, 1, 'left', 1);
%! g = ob_transport_delay ('record', p, g, 7 * 0.1, 1, 'right', 1);
%! g = ob_transport_delay ('record', p, g, 0.8, 1, 'left', 1);
%! assert (g.t', [0.6 0.7 0.7 0.8]); assert (g.u', [0 0 1 1]);
%! assert (ob_transport_delay ('jumps', p, g, 0.7, 1), 0.7 + 0.1);
%! assert (ob_transport_delay ('output', p, g, 0.85), 1);
%! assert (ob_transport_delay ('output', p, g, 0.75), 0);
%! % A merged sample replaces the right limit of a stored jump.
%! g = ob_transport_delay ('record', p, g, 0.8 + eps (0.8), 2, 'left', 1);
%! assert (g.t', [0.6 0.7 0.7 0.8 0.8]); assert (g.u', [0 0 1 1 2]);
%! g = ob_transport_delay ('record', p, g, 0.8 + 2 * eps (0.8), 3, 'right', 1);
%! assert (g.u', [0 0 1 1 3]);
%!test
%! % jumps () leaves out a boundary at the same instant as an existing one.
%! p = struct ('delay', 0.1, 'initial', 0);
%! g = ob_transport_delay ('record', p, ob_transport_delay ('init'), 0.6, 0, 'right', 1);
%! g = ob_transport_delay ('record', p, g, 0.7, 0, 'left', 1);
%! g = ob_transport_delay ('record', p, g, 0.7, 1, 'right', 1);
%! assert (0.7 + 0.1 != 8 * 0.1);
%! assert (isempty (ob_transport_delay ('jumps', p, g, 0.7, 8 * 0.1)));
%! assert (isempty (ob_transport_delay ('jumps', p, g, 0.7, 1, [0.7 8 * 0.1 1])));
%! assert (ob_transport_delay ('jumps', p, g, 0.7, 1, [0.7 0.75 1]), 0.7 + 0.1);
%! assert (ob_transport_delay ('output', p, g, 8 * 0.1, true), 0);
%! assert (ob_transport_delay ('output', p, g, 8 * 0.1), 1);
%!error <backward> ob_transport_delay ('record', params, h, 1, 0, 'right', 1)
%!error <shape> ob_transport_delay ('record', struct ('delay', 1, 'initial', [1 2]), ob_transport_delay ('init'), 0, [1 2 3], 'right', 3)
