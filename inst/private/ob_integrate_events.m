function [states, accepted, records, memory, reached, dispatch_flow] = ob_integrate_events (model, edges, order, ids, states, boundaries, options, memory = struct ())
  % Locate control guard crossings within smooth, frozen-regime trajectories.
  % No scheduler hit or lifecycle callback is dispatched at these boundaries.
  records = struct ('time', {}, 'path', {}, 'type', {}, 'channel', {}, ...
                    'side', {}, 'direction', {}, 'boundary', {});
  accepted = 0; event_instants = 0;
  reached = boundaries(end);
  dispatch_flow = struct ();
  dynamic_controls = isfield(model,'continuous_controls') && model.continuous_controls;
  % The trusted plan's evaluation program, looked up once for every
  % evaluation below (see evaluate).
  fast = [];
  if (isfield (model, 'runtime_info'))
    info = model.runtime_info;
    if (isfield (info, 'plan') && isscalar (info) && isfield (info, 'kind') ...
        && strcmp (info.kind, 'octave-blocks-runtime-info-v1') && isfield (info.plan, 'program'))
      fast = struct ('program', info.plan.program, 'parameters', {info.plan.parameters});
    endif
  endif
  for segment = 1:numel (boundaries)-1
    cursor = boundaries(segment); endpoint = boundaries(segment+1);
    while (cursor < endpoint)
      finish = min (endpoint, cursor + min (options.maxstep, endpoint-cursor));
      end_slack = min ((finish-cursor)/16, ...
          8*eps(1)*max([realmin() abs(cursor) abs(endpoint)]));
      if (endpoint-finish <= end_slack), finish = endpoint; endif
      if (finish <= cursor), error ('ob_run: zero-crossing search cannot advance time'); endif
      [start, flow, simple] = settle_modes (model, edges, order, ids, states, cursor, finish, options, fast);
      if (dynamic_controls)
        % At an exact primitive root, its public equality result can still be
        % the incoming branch. Settling determines the right-hand regime;
        % downstream continuous controls must accept that algebraic change
        % before any more physical time is integrated.
        [changes, changed] = control_reconciliation (start, states, cursor);
        if (! isempty (changes))
          departures = boundary_departures (memory, start, flow, cursor);
          records = [records departures changes];
          for index = 1:numel(start.descriptors)
            guard = start.descriptors(index);
            for departure = departures
              if (isequal(guard.path,departure.path) && strcmp(guard.type,departure.type) ...
                  && guard.channel == departure.channel && strcmp(guard.side,departure.side) ...
                  && guard.boundary == departure.boundary)
                changed(index) = true;
              endif
            endfor
          endfor
          memory = reconciliation_memory (memory,start,flow,cursor,changed);
          reached = cursor; dispatch_flow = flow;
          return;
        endif
      endif
      departures = boundary_departures (memory, start, flow, cursor);
      if (! isempty (departures))
        records = [records departures]; event_instants += 1;
      endif
      check_event_limit (event_instants);
      if (isempty (start.values))
        [states, count] = ob_flow_segment (model, edges, order, ids, states, cursor, finish, options, flow);
        memory = remember_endpoint (model, edges, order, states, finish, flow, [], fast);
        accepted += count; cursor = finish;
        continue;
      endif
      [candidate, count, bracket] = search_segment (model, edges, order, ids, fast, ...
          states, cursor, finish, options, flow, start, simple);
      if (isempty (bracket))
        memory = remember_endpoint (model, edges, order, candidate, finish, flow, [], fast);
        states = candidate; accepted += count; cursor = finish;
        continue;
      endif
      [event_time, event_states, event_snapshot, event_count, event_lower] = locate_event (model, edges, fast, ...
          order, ids, bracket, options, flow, finish);
      if (isempty (event_time))
        states = event_states; accepted += event_count; cursor = finish;
        memory = remember_endpoint (model, edges, order, states, finish, flow, [], fast);
        continue;
      endif
      if (event_time <= cursor)
        error ('ob_run: zero-crossing event cannot make representable time progress');
      endif
      crossing = crossed (bracket.left.values, event_snapshot.values, start.descriptors, flow);
      if (! any (crossing)), error ('ob_run: zero-crossing bracket lost its crossing'); endif
      cross_ids = reshape (find (crossing), 1, []);
      directions = sign (event_snapshot.values(cross_ids) - bracket.left.values(cross_ids));
      times = repmat (event_time, 1, numel (cross_ids));
      if (bracket.begin == cursor && event_lower == cursor)
        % Every bisection midpoint was already past the crossing, so it lies
        % within the time tolerance of this search's origin (the previous stop).
        [times, keep] = origin_departures (memory, start, cross_ids, directions, times, cursor);
        cross_ids = cross_ids(keep); directions = directions(keep); times = times(keep);
        % Those departures now carry the origin's time, earlier than the
        % batch's other records (event_time).  List them first so the
        % cumulative records stay in time order; sort is stable, so guards
        % keep their index order at each time.
        [times, chronological] = sort (times);
        cross_ids = cross_ids(chronological); directions = directions(chronological);
      endif
      if (!isempty (cross_ids))
        guards = start.descriptors(cross_ids);
        new_records = struct ( ...
          'time',      num2cell (times), ...
          'path',      {guards.path}, ...
          'type',      {guards.type}, ...
          'channel',   num2cell ([guards.channel]), ...
          'side',      {guards.side}, ...
          'direction', num2cell (reshape (directions, 1, [])), ...
          'boundary',  num2cell ([guards.boundary]));
        records = [records new_records];
      endif
      event_instants += 1;
      check_event_limit (event_instants);
      memory = struct ('time',event_time,'snapshot',event_snapshot, ...
                       'flow',flow,'reported',crossing);
      states = event_states; cursor = event_time;
      accepted += event_count;
      if (dynamic_controls || any (strcmp ({start.descriptors(crossing).type}, 'Conditional Subsystem')))
        reached = event_time; return;
      endif
    endwhile
    if (dynamic_controls && segment < numel(boundaries)-1)
      % Accepted source discontinuities can change a gate without a smooth
      % sign bracket. Return to the scheduler before integrating past them.
      reached = endpoint; return;
    endif
  endfor
endfunction

function [records, changed] = control_reconciliation (snapshot, states, time)
  records = struct ('time', {}, 'path', {}, 'type', {}, 'channel', {}, ...
                   'side', {}, 'direction', {}, 'boundary', {});
  changed = false (size(snapshot.values));
  for index = 1:numel (snapshot.descriptors)
    guard = snapshot.descriptors(index);
    if (! strcmp(guard.type,'Conditional Subsystem')), continue; endif
    state = control_state (states,guard.path);
    if (strcmp(guard.side,'enable'))
      if (isfield(state,'enable_sign')), before = state.enable_sign;
      else before = double(state.was_enabled); endif
    else
      before = state.control_sign;
    endif
    after = sign(snapshot.values(index));
    if (before == after), continue; endif
    changed(index) = true;
    records(end+1) = struct ('time',time,'path',guard.path,'type',guard.type, ...
        'channel',guard.channel,'side',guard.side,'direction',sign(after-before), ...
        'boundary',guard.boundary);
  endfor
endfunction

function state = control_state (states, path)
  state = states{path(1)};
  if (numel(path)>1), state = control_state(state.child.states,path(2:end)); endif
endfunction

function memory = reconciliation_memory (previous, snapshot, flow, time, reported)
  % Preserve records already emitted at this timestamp even when activation
  % changes the set of active descendants after the scheduler accepts it.
  if (all(isfield(previous,{'time','snapshot','reported'})) && previous.time == time)
    if (same_layout(snapshot,previous.snapshot))
      reported |= previous.reported;
    else
      for index = 1:numel(snapshot.descriptors)
        for old = 1:numel(previous.snapshot.descriptors)
          if (isequal(snapshot.descriptors(index),previous.snapshot.descriptors(old)))
            reported(index) |= previous.reported(old);
            break;
          endif
        endfor
      endfor
    endif
  endif
  memory = struct ('time',time,'snapshot',snapshot,'flow',flow,'reported',reported);
endfunction

function memory = remember_endpoint (model, edges, order, states, time, flow, reported, fast)
  evaluated = evaluate (model, edges, order, fast, time, states, true, flow);
  snapshot = ob_zc_snapshot (model, edges, evaluated);
  if (isempty (reported)), reported = false (size(snapshot.values)); endif
  memory = struct ('time',time,'snapshot',snapshot,'flow',flow,'reported',reported);
endfunction

function records = boundary_departures (memory, snapshot, flow, time)
  records = struct ('time', {}, 'path', {}, 'type', {}, 'channel', {}, ...
                   'side', {}, 'direction', {}, 'boundary', {});
  if (! all (isfield (memory, {'time','snapshot','flow','reported'})) || memory.time != time)
    return;
  endif
  % A plateau can end exactly at an output, source, or search boundary. Keep
  % the incoming regime until a subsequent advance establishes its departure.
  % Match individual descriptors because enabled bodies may appear/disappear
  % at a major hit; a newly active guard has no previous continuous history.
  matching = same_layout(snapshot,memory.snapshot);
  for index = reshape (find (snapshot.values == 0), 1, [])
    guard = snapshot.descriptors(index);
    if (strcmp(guard.type,'Conditional Subsystem')), continue; endif
    if (matching), candidates=index; else candidates=1:numel(memory.snapshot.descriptors); endif
    for previous = candidates
      if (!matching && !isequal(guard,memory.snapshot.descriptors(previous))), continue; endif
      if (memory.snapshot.values(previous) != 0 || memory.reported(previous)), break; endif
      incoming = regime_side (guard, mode_at(memory.flow,guard.path,guard.channel));
      outgoing = regime_side (guard, mode_at(flow,guard.path,guard.channel));
      if (incoming != outgoing)
        records(end+1) = struct ('time',time,'path',guard.path,'type',guard.type, ...
            'channel',guard.channel,'side',guard.side,'direction',outgoing,'boundary',guard.boundary);
      endif
      break;
    endfor
  endfor
endfunction

function current = evaluate (model, edges, order, fast, time, states, left_limit, flow)
  % ob_runtime_eval (model, edges, order, time, states, left_limit, [], [],
  % struct (), flow), through the plan's program when there is one.
  if (isempty (fast))
    current = ob_runtime_eval (model, edges, order, time, states, left_limit, [], [], struct (), flow);
  else
    current = ob_program_eval (fast.program, fast.parameters, model, time, states, left_limit, flow);
  endif
endfunction

function check_event_limit (count)
  if (count > 1000)
    error ('ob_run: zero-crossing event limit exceeded; possible chattering');
  endif
endfunction

function [snapshot, flow, simple] = settle_modes (model, edges, order, ids, states, begin, finish, options, fast)
  % SIMPLE: the returned snapshot is simple (see ob_zc_snapshot).  Layout
  % checks between two simple snapshots of this model are skipped below and
  % in search_segment and locate_event: their layouts are equal.
  evaluated = evaluate (model, edges, order, fast, begin, states, false, struct ());
  [snapshot, simple] = ob_zc_snapshot (model, edges, evaluated); flow = snapshot.flow;
  flow_simple = simple;
  if (isempty (snapshot.values)), return; endif
  probe_width = min ((finish-begin)/1024, sqrt(eps)*max(1,abs(begin)));
  probe_time = min (finish, begin + max (probe_width, eps(begin)));
  if (probe_time <= begin), error ('ob_run: zero-crossing probe cannot advance time'); endif
  % A feedforward cascade can propagate one mode change per evaluation.
  % Scale the bounded settling budget with its active control graph depth.
  settling_limit = max (16, 2*control_count(flow)+2);
  for iteration = 1:settling_limit
    evaluated = evaluate (model, edges, order, fast, begin, states, false, flow);
    [refreshed, refreshed_simple] = ob_zc_snapshot (model, edges, evaluated);
    if (! (simple && refreshed_simple)), require_layout (snapshot, refreshed); endif
    snapshot = refreshed; simple = refreshed_simple;
    proposed = snapshot.flow;
    primitive = ! strcmp ({snapshot.descriptors.type}, 'Conditional Subsystem');
    zeros_at_start = find (snapshot.values == 0 & primitive(:));
    for index = reshape (zeros_at_start, 1, [])
      guard = snapshot.descriptors(index);
      proposed = replace_mode (proposed, guard.path, guard.channel, ...
                               mode_at(flow,guard.path,guard.channel));
    endfor
    if (! isempty (zeros_at_start))
      trial = ob_flow_segment (model, edges, order, ids, states, begin, probe_time, options, proposed);
      evaluated = evaluate (model, edges, order, fast, probe_time, trial, false, proposed);
      [outgoing, outgoing_simple] = ob_zc_snapshot (model, edges, evaluated);
      if (! (simple && outgoing_simple)), require_layout (snapshot, outgoing); endif
      for index = reshape (zeros_at_start, 1, [])
        guard = snapshot.descriptors(index); sign_after = sign (outgoing.values(index));
        if (sign_after == 0), continue; endif
        mode = mode_at (proposed, guard.path, guard.channel);
        if (strcmp (guard.side, 'threshold'))
          mode = double (sign_after > 0);
        elseif (strcmp (guard.side, 'lower'))
          if (sign_after < 0), mode = -1; elseif (mode == -1), mode = 0; endif
        else
          if (sign_after > 0), mode = 1; elseif (mode == 1), mode = 0; endif
        endif
        proposed = replace_mode (proposed, guard.path, guard.channel, mode);
      endfor
    endif
    % Regimes of simple snapshots of one model hold scalars at the same
    % blocks and no children, so comparing the scalars is isequal here.
    if (simple && flow_simple)
      settled = all ([proposed.modes{:}] == [flow.modes{:}]);
    else
      settled = same_flow (proposed, flow);
    endif
    if (settled), return; endif
    flow = proposed; flow_simple = simple;
  endfor
  error ('ob_run: zero-crossing outgoing modes did not settle; possible chattering');
endfunction

function count = control_count (flow)
  count = sum (! cellfun ('isempty', flow.modes));
  for child = flow.children
    if (! isempty (child{1})), count += control_count (child{1}); endif
  endfor
endfunction

function [next, count, bracket] = search_segment (model, edges, order, ids, fast, states, begin, finish, options, flow, initial, initial_simple)
  previous_time = begin; previous_states = states; previous_snapshot = initial;
  accepted_before = 0; bracket = [];
  [next, count] = ob_flow_segment (model, edges, order, ids, states, begin, finish, options, flow, @monitor);

  function stop = monitor (sample_time, sample_states)
    sample_time = min (sample_time, finish);
    evaluated = evaluate (model, edges, order, fast, sample_time, sample_states, sample_time >= finish, flow);
    [sampled, sampled_simple] = ob_zc_snapshot (model, edges, evaluated);
    if (! (initial_simple && sampled_simple)), require_layout (initial, sampled); endif
    stop = any (crossed (previous_snapshot.values, sampled.values, initial.descriptors, flow));
    if (stop)
      bracket = struct ('begin',previous_time,'finish',sample_time, ...
          'states',{previous_states},'next',{sample_states},'left',previous_snapshot, ...
          'right',sampled,'accepted_before',accepted_before, ...
          'origin',begin,'origin_states',{states},'initial',initial,'simple',initial_simple);
    else
      previous_time = sample_time; previous_states = sample_states;
      previous_snapshot = sampled; accepted_before += 1;
    endif
  endfunction
endfunction

function [times, keep] = origin_departures (memory, start, cross_ids, directions, times, time)
  % A guard exactly zero at the search origin that is already past zero at
  % every bisection midpoint leaves that zero at the origin itself.  Report
  % the departure at the origin, the previous stop, as boundary_departures
  % does for primitive regimes, not at the bisection's rounding-dependent
  % upper bound.  When this stop already reported the guard's arrival at
  % zero and the guard continues through it (the arrival came from the
  % opposite side), that arrival record describes the same crossing and no
  % second record is added.  A return to the incoming side is a separate
  % transition and keeps its record, at the stop time.
  keep = true (size (cross_ids));
  known = all (isfield (memory, {'time','snapshot','flow','reported'})) && memory.time == time;
  matching = known && same_layout (start, memory.snapshot);
  for k = 1:numel (cross_ids)
    index = cross_ids(k);
    if (start.values(index) != 0), continue; endif
    times(k) = time;
    if (! known), continue; endif
    guard = start.descriptors(index);
    if (matching), candidates = index; else candidates = 1:numel (memory.snapshot.descriptors); endif
    for previous = candidates
      if (! matching && ! isequal (guard, memory.snapshot.descriptors(previous))), continue; endif
      if (memory.snapshot.values(previous) == 0 && memory.reported(previous))
        incoming = regime_side (guard, mode_at (memory.flow, guard.path, guard.channel));
        keep(k) = incoming != -directions(k);
      endif
      break;
    endfor
  endfor
endfunction

function [time, states, snapshot, count, lower] = locate_event (model, edges, fast, order, ids, bracket, options, flow, endpoint)
  % lower is the final lower bisection bound.
  lower = bracket.begin; upper = bracket.finish;
  % Accepted adaptive samples live on an elapsed-time grid. Their absolute
  % timestamps may round by part of an ulp, so reconstruct every retained
  % candidate from the immutable search origin at its actual physical time.
  [states, count, snapshot] = canonical (upper);
  extension = max (eps(upper), 1e-6*(bracket.finish-bracket.begin));
  [unused_states, unused_count, left_snapshot] = canonical (lower);
  backward = extension;
  for attempt = 1:32
    if (! any (crossed(bracket.left.values,left_snapshot.values,bracket.left.descriptors,flow)))
      break;
    endif
    if (lower <= bracket.origin)
      error ('ob_run: zero-crossing incoming bracket is below physical time resolution');
    endif
    lower = max (bracket.origin, lower-backward); backward *= 2;
    [unused_states, unused_count, left_snapshot] = canonical (lower);
  endfor
  if (any (crossed(bracket.left.values,left_snapshot.values,bracket.left.descriptors,flow)))
    error ('ob_run: zero-crossing incoming bracket could not be reconstructed');
  endif
  for attempt = 1:32
    if (any (crossed(bracket.left.values,snapshot.values,bracket.left.descriptors,flow)))
      break;
    endif
    if (upper >= endpoint), time = []; return; endif
    upper = min (endpoint, upper+extension); extension *= 2;
    [states, count, snapshot] = canonical (upper);
  endfor
  if (! any (crossed(bracket.left.values,snapshot.values,bracket.left.descriptors,flow)))
    error ('ob_run: zero-crossing accepted bracket could not be reconstructed');
  endif
  % Scale to the local bracket, including tiny intervals. At large origins,
  % the midpoint-progress check supplies the actual representability limit.
  tolerance = 1e-11*(upper-lower);
  for iteration = 1:64
    if (upper-lower <= tolerance), break; endif
    middle = lower + (upper-lower)/2;
    if (middle <= lower || middle >= upper), break; endif
    [trial, trial_count, sampled] = canonical (middle);
    if (any (crossed (bracket.left.values, sampled.values, bracket.left.descriptors, flow)))
      upper = middle; states = trial; snapshot = sampled; count = trial_count;
    else
      lower = middle;
    endif
  endfor
  time = upper;

  function [canonical_states, canonical_count, canonical_snapshot] = canonical (candidate_time)
    if (candidate_time == bracket.origin)
      canonical_states = bracket.origin_states; canonical_count = 0;
      canonical_snapshot = bracket.initial; return;
    endif
    [canonical_states, canonical_count] = ob_flow_segment (model, edges, order, ids, ...
        bracket.origin_states, bracket.origin, candidate_time, options, flow);
    evaluated = evaluate (model, edges, order, fast, candidate_time, canonical_states, candidate_time >= endpoint, flow);
    [canonical_snapshot, canonical_simple] = ob_zc_snapshot (model, edges, evaluated);
    if (! (bracket.simple && canonical_simple)), require_layout (bracket.initial, canonical_snapshot); endif
  endfunction
endfunction

function selected = crossed (before, after, descriptors, flow)
  selected = (before < 0 & after >= 0) | (before > 0 & after <= 0);
  % A zero plateau may end long after initialization. Detect a departure only
  % if its side contradicts the frozen regime; settled start-time departures
  % already use the outgoing regime and must not repeatedly fire at time zero.
  for index = reshape (find (before == 0 & after != 0), 1, [])
    guard = descriptors(index); mode = mode_at (flow, guard.path, guard.channel);
    if (strcmp (guard.type, 'Conditional Subsystem'))
      selected(index) = mode == 0 || sign(after(index)) != sign(mode);
      continue;
    endif
    expected = regime_side (guard, mode);
    selected(index) = sign(after(index)) != expected;
  endfor
endfunction

function side = regime_side (guard, mode)
  if (any(strcmp (guard.side, {'control','enable'})))
    side = sign(mode);
  elseif (strcmp (guard.side, 'threshold'))
    side = 2*double(mode != 0)-1;
  elseif (strcmp (guard.side, 'lower'))
    side = 1-2*double(mode == -1);
  else
    side = 2*double(mode == 1)-1;
  endif
endfunction

function require_layout (before, after)
  if (! same_layout(before,after))
    error ('ob_run: zero-crossing guard layout changed inside an integration interval');
  endif
endfunction

function yes = same_layout (before, after)
  yes = numel(before.descriptors)==numel(after.descriptors) ...
      && numel(before.values)==numel(after.values) ...
      && same_descriptors(before.descriptors,after.descriptors) ...
      && same_shapes(before.flow,after.flow);
endfunction

function yes = same_descriptors (before, after)
  % isequal (before, after) for guard descriptor arrays.  Octave's isequal
  % walks struct arrays recursively and dominated event-heavy runs, so a
  % direct comparison settles the usual equal case; any other outcome is
  % left to isequal itself.
  yes = equal_descriptors (before, after) || isequal (before, after);
endfunction

function yes = equal_descriptors (a, b)
  % True only when isequal (a, b) is certainly true: both have exactly the
  % fields ob_zc_snapshot builds, character type/side, double scalar
  % channel/boundary and double row paths, all with equal contents.
  names = {'path','type','channel','boundary','side'};
  yes = isstruct (a) && isstruct (b) && size_equal (a, b) && ! isempty (a) ...
        && numfields (a) == 5 && numfields (b) == 5 ...
        && all (isfield (a, names)) && all (isfield (b, names));
  if (! yes), return; endif
  types = {a.type}; other_types = {b.type}; sides = {a.side}; other_sides = {b.side};
  yes = iscellstr (types) && iscellstr (other_types) && iscellstr (sides) ...
        && iscellstr (other_sides) && all (strcmp (types, other_types)) ...
        && all (strcmp (sides, other_sides)) ...
        && equal_scalars ({a.channel}, {b.channel}) ...
        && equal_scalars ({a.boundary}, {b.boundary});
  if (! yes), return; endif
  paths = {a.path}; other_paths = {b.path};
  yes = all (cellfun ('isclass', paths, 'double')) && all (cellfun ('isclass', other_paths, 'double')) ...
        && all (cellfun ('ndims', paths) == 2) && all (cellfun ('ndims', other_paths) == 2) ...
        && all (cellfun ('size', paths, 1) == 1) && all (cellfun ('size', other_paths, 1) == 1) ...
        && all (cellfun ('size', paths, 2) == cellfun ('size', other_paths, 2)) ...
        && all ([paths{:}] == [other_paths{:}]);
endfunction

function yes = equal_scalars (values, others)
  yes = all (cellfun ('isclass', values, 'double')) && all (cellfun ('isclass', others, 'double')) ...
        && all (cellfun ('prodofsize', values) == 1) && all (cellfun ('prodofsize', others) == 1) ...
        && all ([values{:}] == [others{:}]);
endfunction

function yes = same_flow (before, after)
  % isequal (before, after) for regime records, settled directly in the
  % usual equal case as same_descriptors () does.
  yes = equal_flow (before, after) || isequal (before, after);
endfunction

function yes = equal_flow (a, b)
  % True only when isequal (a, b) is certainly true for {modes, children}
  % records: same-size double mode arrays with equal values, and children
  % that are all empty doubles or equal nested records.
  yes = isstruct (a) && isstruct (b) && isscalar (a) && isscalar (b) ...
        && numfields (a) == 2 && numfields (b) == 2 ...
        && isfield (a, 'modes') && isfield (a, 'children') ...
        && isfield (b, 'modes') && isfield (b, 'children');
  if (! yes), return; endif
  modes = a.modes; other_modes = b.modes; children = a.children; other_children = b.children;
  yes = iscell (modes) && iscell (other_modes) && iscell (children) && iscell (other_children) ...
        && size_equal (modes, other_modes) && size_equal (children, other_children) ...
        && all (cellfun ('isclass', modes, 'double')) && all (cellfun ('isclass', other_modes, 'double')) ...
        && all (cellfun ('ndims', modes) == 2) && all (cellfun ('ndims', other_modes) == 2) ...
        && all (cellfun ('size', modes, 1) == cellfun ('size', other_modes, 1)) ...
        && all (cellfun ('size', modes, 2) == cellfun ('size', other_modes, 2));
  if (! yes), return; endif
  for k = reshape (find (! cellfun ('isempty', modes)), 1, [])
    if (! all (modes{k}(:) == other_modes{k}(:))), yes = false; return; endif
  endfor
  empty = cellfun ('isempty', children) & cellfun ('isclass', children, 'double');
  other_empty = cellfun ('isempty', other_children) & cellfun ('isclass', other_children, 'double');
  yes = all (cellfun ('size', children, 1) == cellfun ('size', other_children, 1) | ! empty) ...
        && all (cellfun ('size', children, 2) == cellfun ('size', other_children, 2) | ! empty);
  if (! yes), return; endif
  for k = reshape (find (! (empty & other_empty)), 1, [])
    if (! equal_flow (children{k}, other_children{k})), yes = false; return; endif
  endfor
endfunction

function yes = same_shapes (before, after)
  yes = numel(before.modes)==numel(after.modes) ...
      && numel(before.children)==numel(after.children);
  if (! yes), return; endif
  left_modes=before.modes(:); right_modes=after.modes(:);
  if (any(cellfun('ndims',left_modes)>2) || any(cellfun('ndims',right_modes)>2))
    % Ordinary modes are matrices; retain exact layouts for legacy callers
    % containing arrays with additional dimensions as well.
    for id = 1:numel(left_modes)
      if (!size_equal(left_modes{id},right_modes{id})), yes=false; return; endif
    endfor
  elseif (any(cellfun('size',left_modes,1)!=cellfun('size',right_modes,1)) ...
          || any(cellfun('size',left_modes,2)!=cellfun('size',right_modes,2)))
    yes=false; return;
  endif
  left_empty=cellfun('isempty',before.children(:));
  right_empty=cellfun('isempty',after.children(:));
  if (any(left_empty!=right_empty)), yes=false; return; endif
  for id = reshape(find(!left_empty),1,[])
    if (!same_shapes(before.children{id},after.children{id}))
      yes = false; return;
    endif
  endfor
endfunction

function mode = mode_at (flow, path, channel)
  if (numel(path) == 1)
    mode = flow.modes{path(1)}(channel);
  else
    mode = mode_at (flow.children{path(1)}, path(2:end), channel);
  endif
endfunction

function flow = replace_mode (flow, path, channel, mode)
  if (numel(path) == 1)
    flow.modes{path(1)}(channel) = mode;
  else
    flow.children{path(1)} = replace_mode (flow.children{path(1)}, path(2:end), channel, mode);
  endif
endfunction
