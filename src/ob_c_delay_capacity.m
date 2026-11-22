function capacity = ob_c_delay_capacity (delays, times, periods, step_count, inputs)
  % Ring-buffer capacity (samples) of each Transport Delay history in C.
  %
  % A history keeps the samples recorded in (time - T, time] plus at most
  % three at or before time - T (private/ob_transport_delay.m), and one more
  % while a sample is appended.  Every recording instant can hold a left and
  % a right sample.  The generated step also never reuses, before it
  % commits, a slot that was live when it began (in-place rollback, see
  % ob_c_delay_lines), so the buffer must hold one window's samples plus
  % everything a single host step records.  Recording instants inside a
  % window of length W (W = T, and W = the longest host step) are:
  %   - host step times (the output grid 'times'),
  %   - explicit clock hits, Step times and root input knots,
  %   - refinement points (segments never exceed the shortest delay, so
  %     refinement points are at least half the shortest delay apart),
  %   - delayed discontinuities t(j) + T, estimated as one per instant of
  %     the window plus each start + T, for every delay.
  % The last term is a heuristic, not a bound: when delayed jumps feed back
  % through delays (for example y = u + a y(t - T1) + b y(t - T2) with
  % incommensurate T1, T2), every jump spawns new ones and their number per
  % window keeps growing.  The generated code then returns OB_DELAY_OVERFLOW
  % instead of writing; ob_accelerate regenerates with doubled capacities.
  % The total is rounded up to a power of two so that nearby output grids
  % share one compiled accelerator.
  delays = double (delays(:)');
  capacity = zeros (size (delays));
  if (isempty (delays)), return; endif
  shortest = min (delays);
  times = sort (double (times(:)'));
  longest_step = 0;
  if (numel (times) > 1), longest_step = max (diff (times)); endif
  knot_times = cell (1, numel (inputs));
  for port = 1:numel (inputs)
    knot_times{port} = sort (double (inputs{port}.t(:)'));
  endfor
  instants = @(W, limit) window_instants (W, times, periods, step_count, knot_times, ...
                                          shortest, numel (delays), limit);
  % ob_run rejects a gap that needs more than 1e6 segments, so the host-step
  % term counts at most that many refinement points (a C run then reports
  % OB_DELAY_SEGMENTS, like ob_run, instead of the export being too large).
  step_instants = instants (longest_step, 1e6 + 1);
  for k = 1:numel (delays)
    total = instants (delays(k), Inf) + step_instants;
    capacity(k) = 2^nextpow2 (max (64, 2 * total + 8));
  endfor
endfunction

function count = window_instants (W, times, periods, step_count, knot_times, shortest, delay_count, limit)
  % Recording instants inside any closed window of length W.
  out = window_count (times, W);
  ticks = 0;
  for p = double (periods(:)')
    ticks += floor (W / p) + 2;
  endfor
  knots = 0;
  for port = 1:numel (knot_times)
    knots += window_count (knot_times{port}, W);
  endfor
  refine = min (ceil (2 * W / shortest) + 1, limit);
  base = out + ticks + step_count + knots;
  jumps = delay_count * (base + 1);
  count = base + refine + jumps;
endfunction

function count = window_count (times, T)
  % Largest number of times inside any closed window of length T.
  count = 0;
  if (isempty (times)), return; endif
  % lookup returns the last index with times(index) <= times + T.
  last = lookup (times, times + T);
  count = max (last(:)' - (1:numel (times)) + 1);
endfunction
