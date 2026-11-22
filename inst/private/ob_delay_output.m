function y = ob_delay_output (params, history, time, left_limit = false)
  % Transport Delay output at TIME from its input history (see
  % ob_transport_delay, which documents the history and also answers its
  % 'output' operation through this function).  Solver stages query outputs
  % most often; evaluators call this directly, without the operation switch.
  t = history.t;
  % start_time () and same_instant () are inlined in this hot query with
  % the identical expressions.
  if (isfield (history, 'start') && ! isempty (history.start))
    start = history.start;
  elseif (! isempty (t))
    start = t(1);
  else
    start = Inf;
  endif
  delay = params.delay;
  % Times are compared in the time domain, with the same sums that jumps ()
  % returns as solver boundaries: time - T can miss a sample time by an ulp,
  % e.g. (0.1 + 0.2) - 0.2 > 0.1.
  boundary = start + delay;
  at_start = abs (time - boundary) <= min (delay / 16, 8 * eps * max (max (abs (time), abs (boundary)), realmin ()));
  % The initial output holds before start + T.  At start + T the output is
  % right-continuous, y = u(start), but its left limit is still the initial
  % output: RK4 and adaptive end stages evaluate that limit.
  if (isempty (t) || (time < boundary && ! at_start) || (left_limit && at_start))
    % initial_output (params, history), inlined.
    y = params.initial;
    if (isscalar (y) && ! isempty (history.shape) && prod (history.shape) != 1)
      y = y * ones (history.shape);
    endif
    return;
  endif
  n = numel (t);
  tau = max (time - delay, start);
  if (at_start), tau = start; endif
  k = lookup (t, tau);  % last index with t(k) <= tau, 0 before t(1)
  % A query at a sample's shifted time t(j) + T reads exactly t(j), so the
  % left and right limits of a delayed jump are exact at its boundary.
  % (same_instant (shifted, time, delay), inlined; the first test that holds
  % applies, as in an if/elseif chain.)
  snapped = false;
  if (k < n)
    shifted = t(k+1) + delay;
    if (abs (shifted - time) <= min (delay / 16, 8 * eps * max (max (abs (shifted), abs (time)), realmin ())))
      tau = t(k+1); k += 1;
      while (k < n && t(k+1) == tau), k += 1; endwhile
      snapped = true;
    endif
  endif
  if (! snapped && k > 0 && t(k) != tau)
    shifted = t(k) + delay;
    if (abs (shifted - time) <= min (delay / 16, 8 * eps * max (max (abs (shifted), abs (time)), realmin ())))
      tau = t(k);
    endif
  endif
  if (tau >= t(end))
    k = n;
    % A left-limit query exactly at a stored jump uses the left sample.
    if (left_limit && tau == t(end) && k > 1 && t(k-1) == t(k)), k -= 1; endif
    y = reshape (history.u(k, :), history.shape);
    return;
  endif
  k = max (1, k);
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
  if (k > 1 && k + 2 <= n && t(k-1) < a && t(k+2) > b)
    % Interior interval, the usual case: both slope () calls take their
    % two-sided branch, which shares the middle difference quotient.  The
    % expressions are slope ()'s, so the values are identical.
    u = history.u;
    h0 = a - t(k-1); h2 = t(k+2) - b;
    s0 = (u(k, :) - u(k-1, :)) / h0;
    s1 = (u(k+1, :) - u(k, :)) / h;
    s2 = (u(k+2, :) - u(k+1, :)) / h2;
    da = (h * s0 + h0 * s1) / (h0 + h);
    db = (h2 * s1 + h * s2) / (h + h2);
  else
    da = slope (t, history.u, k); db = slope (t, history.u, k+1);
  endif
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
