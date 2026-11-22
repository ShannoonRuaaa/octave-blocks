function hits = ob_accelerate_hits (runtime, t, ticks, rates)
  % ob_run's per-block sample hit times for an accelerated run.
  %
  %   hits = ob_accelerate_hits (runtime, t, ticks, rates)
  %
  % runtime holds the static fields of an initialized interpreted context
  % (model, inherited, explicit, rates, nested_clocks); t the output times;
  % ticks the compiled tick counters of the root blocks with a positive
  % period in rates (the export's sample times), one row per such block in
  % block order and one column per output time.
  %
  % Inherited blocks hit at every output time.  An inherited enabled
  % Conditional Subsystem with sampled control also hits whenever one of its
  % inner clocks is due (ob_runtime_engine process_hits: "Enabled bodies with
  % inherited control sample at the union of inner clocks").  Explicit
  % clocks hit at their ticks.  The hit times come from the root clock
  % schedule, which is the same in the compiled and interpreted runs (zero
  % crossings never make a clock due: a located crossing lies before the
  % next scheduled tick, outside the clock tolerance).  clock_schedule
  % replays ob_runtime_engine's loop: the next event is the earliest pending
  % tick, an event within the clock tolerance of the output time is
  % processed at the output time, and every clock whose tick is within the
  % tolerance of an event is due there.  So a tick that nearly coincides with
  % an earlier tick of another clock (0.1*3 and 0.3) is processed at the
  % earlier time.  The tick counts of explicit clocks are checked against the
  % compiled counters; if they ever differ, those hits are rebuilt from the
  % counters alone (snapping only to output times).
  n = numel (runtime.model.blocks);
  hits = cell (1, n);
  for id = reshape (find (runtime.inherited), 1, [])
    hits{id} = t;
  endfor
  explicit = reshape (find (runtime.explicit), 1, []);
  nested = struct ('path', {}, 'rate', {});
  if (isfield (runtime, 'nested_clocks') && ! isempty (runtime.nested_clocks))
    nested = runtime.nested_clocks;
  endif
  roots = arrayfun (@(c) c.path(1), nested);
  unions = [];
  for id = unique (roots)
    if (runtime.inherited(id) && strcmp (runtime.model.blocks(id).type, 'Conditional Subsystem'))
      execution = ob_runtime_execution (runtime.model, id).options;
      if (strcmp (execution.mode, 'enabled') && strcmp (execution.control, 'sampled'))
        unions(end+1) = id;
      endif
    endif
  endfor
  if (isempty (explicit) && isempty (unions)), return; endif
  nested_rates = reshape ([nested.rate], 2, [])';
  if (isempty (nested_rates)), nested_rates = zeros (0, 2); endif
  period = [runtime.rates(explicit, 1)' nested_rates(:, 1)'];
  offset = [runtime.rates(explicit, 2)' nested_rates(:, 2)'];
  is_nested = [false(1, numel (explicit)) true(1, numel (nested))];
  % ob_runtime_engine clock_spacing: explicit and nested periods.
  spacing = min ([period Inf]);
  [when, step] = clock_schedule (t, period, offset, is_nested, spacing);
  clocks = find (rates(:, 1)' > 0);
  for k = 1:numel (explicit)
    id = explicit(k);
    row = find (clocks == id);
    counts = cumsum (accumarray (step{k}(:), 1, [numel(t) 1]))';
    if (! isempty (row) && isequal (counts, ticks(row, :)))
      hits{id} = when{k};
    elseif (! isempty (row))
      hits{id} = from_counters (runtime, t, ticks(row, :), id, spacing);
    endif
  endfor
  for id = unions
    members = numel (explicit) + find (roots == id);
    hits{id} = unique ([t when{members}]);
  endfor
endfunction

function [when, step] = clock_schedule (t, period, offset, is_nested, spacing)
  % Processing time and output step (1 = initialization) of every tick of
  % every clock up to t(end).  Without near coincidences (distinct tick and
  % output times closer than any clock tolerance) a tick is processed at
  % its own time, or at the output time it equals, so the schedule is built
  % directly.  Otherwise the engine's event loop is replayed.
  origin = t(1); last = t(end); count = numel (period);
  times = cell (1, count);
  for c = 1:count
    total = max (-1, floor ((last - origin - offset(c)) / period(c))) + 2;
    tick_times = origin + offset(c) + (0:total-1) * period(c);
    times{c} = tick_times;
  endfor
  everything = [times{:} t];
  scale = max ([realmin() abs(everything(isfinite (everything)))]);
  bound = min (spacing / 16, 8 * eps (1) * scale);
  values = unique (everything);
  if (any (diff (values) <= bound))
    [when, step] = replay (t, period, offset, is_nested, spacing, cellfun ('numel', times));
    return;
  endif
  when = cell (1, count); step = cell (1, count);
  for c = 1:count
    tick_times = times{c};
    tick_times = tick_times(tick_times <= last);
    index = lookup (t, tick_times);           % last output time <= tick
    exact = index >= 1 & t(max (index, 1)) == tick_times;
    s = index + ! exact;                      % processed in step s
    tick_times(exact) = t(index(exact));
    when{c} = tick_times;
    step{c} = s;
  endfor
endfunction

function [when, step] = replay (t, period, offset, is_nested, spacing, capacity)
  % ob_runtime_engine initialize/advance/process_hits, clocks only.
  origin = t(1); count = numel (period);
  tick = zeros (1, count);
  next = origin + offset;
  when = arrayfun (@(m) zeros (1, m), capacity + 1, 'uniformoutput', false);
  step = when;
  used = zeros (1, count);
  for s = 1:numel (t)
    target = t(s);
    if (s == 1), time = target; else time = t(s-1); endif
    while (s == 1 || time < target)
      if (s == 1)
        event = origin;                       % initialization hit
      else
        event = min ([next Inf]);
        at_output = ! (event < target && ! time_equal (event, target, origin, spacing));
        if (at_output), event = target; endif
        if (event <= time)
          error ('ob_accelerate: clock schedule cannot advance time');
        endif
      endif
      at_start = event == origin & offset > 0;
      % Explicit clocks use time_equal; nested clocks the engine's
      % vectorized check, whose bound omits the tick's own magnitude.
      nested_bound = min (spacing / 16, 8 * eps (1) * max ([realmin() abs(origin) abs(event)]));
      due = false (1, count);
      for c = 1:count
        if (at_start(c)), continue; endif
        if (is_nested(c))
          due(c) = isfinite (next(c)) && abs (next(c) - event) <= nested_bound;
        else
          due(c) = time_equal (next(c), event, origin, spacing);
        endif
      endfor
      for c = find (due)
        used(c) += 1;
        if (used(c) > numel (when{c}))
          when{c}(2*used(c)) = 0; step{c}(2*used(c)) = 0;
        endif
        when{c}(used(c)) = event; step{c}(used(c)) = s;
      endfor
      tick(due) += 1;
      next(due) = origin + offset(due) + tick(due) .* period(due);
      time = event;
      if (s == 1), break; endif
    endwhile
  endfor
  for c = 1:count
    when{c} = when{c}(1:used(c)); step{c} = step{c}(1:used(c));
  endfor
endfunction

function yes = time_equal (a, b, origin, spacing)
  % ob_runtime_engine time_equal.
  yes = isfinite (a) && isfinite (b) ...
        && abs (a - b) <= min (spacing/16, 8 * eps(1) * max([realmin() abs(origin) abs(a) abs(b)]));
endfunction

function times = from_counters (runtime, t, counts, id, spacing)
  % Fallback: the k-th hit at the k-th tick time, except that a tick within
  % the clock tolerance of an output time is processed at that output time;
  % it is then the last tick of that step.
  total = counts(end);
  if (total == 0), times = zeros (1, 0); return; endif
  origin = t(1);
  times = origin + runtime.rates(id, 2) + (0:total-1) * runtime.rates(id, 1);
  advanced = find (diff ([0 counts]) > 0);
  last = counts(advanced);
  close = abs (times(last) - t(advanced)) ...
          <= min (spacing / 16, 8 * eps (1) * max ([realmin() * ones(size (last)); ...
                                                    abs(origin) * ones(size (last)); ...
                                                    abs(times(last)); abs(t(advanced))]));
  times(last(close)) = t(advanced(close));
endfunction
