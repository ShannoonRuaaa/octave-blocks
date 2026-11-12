function [states, accepted, records, memory, reached, dispatch_flow] = ob_integrate_events (model, edges, order, ids, states, boundaries, options, memory = struct ())
  % Locate control guard crossings within smooth, frozen-regime trajectories.
  % No scheduler hit or lifecycle callback is dispatched at these boundaries.
  records = struct ('time', {}, 'path', {}, 'type', {}, 'channel', {}, ...
                    'side', {}, 'direction', {}, 'boundary', {});
  accepted = 0; event_instants = 0;
  reached = boundaries(end);
  dispatch_flow = struct ();
  dynamic_controls = isfield(model,'continuous_controls') && model.continuous_controls;
  for segment = 1:numel (boundaries)-1
    cursor = boundaries(segment); endpoint = boundaries(segment+1);
    while (cursor < endpoint)
      finish = min (endpoint, cursor + min (options.maxstep, endpoint-cursor));
      end_slack = min ((finish-cursor)/16, ...
          8*eps(1)*max([realmin() abs(cursor) abs(endpoint)]));
      if (endpoint-finish <= end_slack), finish = endpoint; endif
      if (finish <= cursor), error ('ob_run: zero-crossing search cannot advance time'); endif
      [start, flow] = settle_modes (model, edges, order, ids, states, cursor, finish, options);
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
        memory = remember_endpoint (model, edges, order, states, finish, flow, []);
        accepted += count; cursor = finish;
        continue;
      endif
      [candidate, count, bracket] = search_segment (model, edges, order, ids, ...
          states, cursor, finish, options, flow, start);
      if (isempty (bracket))
        memory = remember_endpoint (model, edges, order, candidate, finish, flow, []);
        states = candidate; accepted += count; cursor = finish;
        continue;
      endif
      [event_time, event_states, event_snapshot, event_count] = locate_event (model, edges, ...
          order, ids, bracket, options, flow, finish);
      if (isempty (event_time))
        states = event_states; accepted += event_count; cursor = finish;
        memory = remember_endpoint (model, edges, order, states, finish, flow, []);
        continue;
      endif
      if (event_time <= cursor)
        error ('ob_run: zero-crossing event cannot make representable time progress');
      endif
      crossing = crossed (bracket.left.values, event_snapshot.values, start.descriptors, flow);
      if (! any (crossing)), error ('ob_run: zero-crossing bracket lost its crossing'); endif
      for index = reshape (find (crossing), 1, [])
        guard = start.descriptors(index);
        records(end+1) = struct ('time', event_time, 'path', guard.path, ...
            'type', guard.type, 'channel', guard.channel, 'side', guard.side, ...
            'direction', sign(event_snapshot.values(index)-bracket.left.values(index)), ...
            'boundary', guard.boundary);
      endfor
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
    before = state.control_sign; after = sign(snapshot.values(index));
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
    for index = 1:numel(snapshot.descriptors)
      for old = 1:numel(previous.snapshot.descriptors)
        if (isequal(snapshot.descriptors(index),previous.snapshot.descriptors(old)))
          reported(index) |= previous.reported(old);
          break;
        endif
      endfor
    endfor
  endif
  memory = struct ('time',time,'snapshot',snapshot,'flow',flow,'reported',reported);
endfunction

function memory = remember_endpoint (model, edges, order, states, time, flow, reported)
  evaluated = ob_runtime_eval (model, edges, order, time, states, true, [], [], struct (), flow);
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
  for index = reshape (find (snapshot.values == 0), 1, [])
    guard = snapshot.descriptors(index);
    if (strcmp(guard.type,'Conditional Subsystem')), continue; endif
    for previous = 1:numel (memory.snapshot.descriptors)
      if (! isequal (guard, memory.snapshot.descriptors(previous))), continue; endif
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

function check_event_limit (count)
  if (count > 1000)
    error ('ob_run: zero-crossing event limit exceeded; possible chattering');
  endif
endfunction

function [snapshot, flow] = settle_modes (model, edges, order, ids, states, begin, finish, options)
  evaluated = ob_runtime_eval (model, edges, order, begin, states);
  snapshot = ob_zc_snapshot (model, edges, evaluated); flow = snapshot.flow;
  if (isempty (snapshot.values)), return; endif
  probe_width = min ((finish-begin)/1024, sqrt(eps)*max(1,abs(begin)));
  probe_time = min (finish, begin + max (probe_width, eps(begin)));
  if (probe_time <= begin), error ('ob_run: zero-crossing probe cannot advance time'); endif
  % A feedforward cascade can propagate one mode change per evaluation.
  % Scale the bounded settling budget with its active control graph depth.
  settling_limit = max (16, 2*control_count(flow)+2);
  for iteration = 1:settling_limit
    evaluated = ob_runtime_eval (model, edges, order, begin, states, false, [], [], struct (), flow);
    refreshed = ob_zc_snapshot (model, edges, evaluated);
    require_layout (snapshot, refreshed); snapshot = refreshed;
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
      evaluated = ob_runtime_eval (model, edges, order, probe_time, trial, false, [], [], struct (), proposed);
      outgoing = ob_zc_snapshot (model, edges, evaluated);
      require_layout (snapshot, outgoing);
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
    if (isequal (proposed, flow)), return; endif
    flow = proposed;
  endfor
  error ('ob_run: zero-crossing outgoing modes did not settle; possible chattering');
endfunction

function count = control_count (flow)
  count = sum (! cellfun (@isempty, flow.modes));
  for child = flow.children
    if (! isempty (child{1})), count += control_count (child{1}); endif
  endfor
endfunction

function [next, count, bracket] = search_segment (model, edges, order, ids, states, begin, finish, options, flow, initial)
  previous_time = begin; previous_states = states; previous_snapshot = initial;
  accepted_before = 0; bracket = [];
  [next, count] = ob_flow_segment (model, edges, order, ids, states, begin, finish, options, flow, @monitor);

  function stop = monitor (sample_time, sample_states)
    sample_time = min (sample_time, finish);
    evaluated = ob_runtime_eval (model, edges, order, sample_time, sample_states, ...
                                 sample_time >= finish, [], [], struct (), flow);
    sampled = ob_zc_snapshot (model, edges, evaluated);
    require_layout (initial, sampled);
    stop = any (crossed (previous_snapshot.values, sampled.values, initial.descriptors, flow));
    if (stop)
      bracket = struct ('begin',previous_time,'finish',sample_time, ...
          'states',{previous_states},'next',{sample_states},'left',previous_snapshot, ...
          'right',sampled,'accepted_before',accepted_before, ...
          'origin',begin,'origin_states',{states},'initial',initial);
    else
      previous_time = sample_time; previous_states = sample_states;
      previous_snapshot = sampled; accepted_before += 1;
    endif
  endfunction
endfunction

function [time, states, snapshot, count] = locate_event (model, edges, order, ids, bracket, options, flow, endpoint)
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
    evaluated = ob_runtime_eval (model, edges, order, candidate_time, canonical_states, ...
                                 candidate_time >= endpoint, [], [], struct (), flow);
    canonical_snapshot = ob_zc_snapshot (model, edges, evaluated);
    require_layout (bracket.initial, canonical_snapshot);
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
  if (strcmp (guard.side, 'control'))
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
  if (! isequal (before.descriptors, after.descriptors) || ! same_shapes (before.flow, after.flow))
    error ('ob_run: zero-crossing guard layout changed inside an integration interval');
  endif
endfunction

function yes = same_shapes (before, after)
  yes = numel (before.modes) == numel (after.modes);
  if (! yes), return; endif
  for id = 1:numel (before.modes)
    if (! isequal (size(before.modes{id}),size(after.modes{id})))
      yes = false; return;
    endif
    left = before.children{id}; right = after.children{id};
    if (isempty(left) && isempty(right)), continue; endif
    if (isempty(left) || isempty(right) || ! same_shapes(left,right))
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
