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
