function [states, accepted, events, memory, reached, dispatch_flow] = ob_runtime_integrate (model, edges, order, ids, states, start_time, end_time, options, memory = struct ())
  accepted = 0;
  dispatch_flow = struct ();
  reached = end_time;
  events = struct ('time', {}, 'path', {}, 'type', {}, 'channel', {}, ...
                  'side', {}, 'direction', {}, 'boundary', {});
  event_mode = isfield (options, 'zero_crossings') && options.zero_crossings;
  delays = ob_runtime_type_ids (model, 'delay_ids', 'Transport Delay');
  if (isempty (ids) && ! event_mode && isempty (delays))
    states = refresh_endpoint (model, edges, order, states, end_time);
    return;
  endif
  if (! iscell (ids)), ids = num2cell (reshape (ids, 1, [])); endif
  boundaries = [start_time end_time];
  boundaries = [boundaries enabled_boundaries(model, states, start_time, end_time)];
  if (!isempty(model.inputs))
    % Gather every input signal's knot vector in one vectorized pass rather
    % than a scalar-append loop over ports.
    all_knots = cellfun (@(sig) sig.t(sig.t > start_time & sig.t < end_time)', ...
                         model.inputs, 'UniformOutput', false);
    boundaries = [boundaries all_knots{:}];
  endif
  boundaries = unique (boundaries);
  if (event_mode)
    [states, accepted, events, memory, reached, dispatch_flow] = ob_integrate_events (model, edges, order, ids, states, boundaries, options, memory);
    states = refresh_endpoint (model, edges, order, states, reached);
    return;
  endif
  if (! isempty (delays))
    boundaries = delay_boundaries (model, states, delays, boundaries);
  endif
  % The active graph is fixed throughout these smooth segments. Resolve each
  % derivative's source once, before solver stages change only numeric states.
  [routes, limits] = derivative_routes (model, edges, ids, states);
  for segment = 1:numel (boundaries)-1
    begin = boundaries(segment); finish = boundaries(segment + 1);
    h = finish - begin;
    if (isempty (ids))
      % Only delay histories advance; no state is integrated.
    elseif (! strcmp (options.solver, "rk4"))
      [states, count, times, solution] = adaptive_segment (model, edges, order, ids, routes, limits, states, begin, finish, options);
      accepted += count;
      if (! isempty (delays))
        % Accepted interior solver points refine the delayed signal history.
        for point = 2:numel (times)-1
          sample = clamp_states (unpack_states (solution(point, :)', states, ids), ids, limits);
          evaluated = ob_runtime_eval (model, edges, order, times(point), sample);
          states = record_delays (model, delays, states, evaluated, times(point), 'right');
        endfor
      endif
    else
      accepted += 1;
      % Fixed steps decide saturation from the step's initial state, so a
      % step that reaches a bound lands on it rather than stopping short.
      step_limits = saturation_at (states, ids, limits);
      initial = ob_runtime_eval (model, edges, order, begin, states);
      k1 = derivatives (initial, ids, routes, step_limits);
      stage = set_integrator_states (states, ids, k1, h / 2);
      middle = ob_runtime_eval (model, edges, order, begin + h / 2, stage);
      k2 = derivatives (middle, ids, routes, step_limits);
      stage = set_integrator_states (states, ids, k2, h / 2);
      middle = ob_runtime_eval (model, edges, order, begin + h / 2, stage);
      k3 = derivatives (middle, ids, routes, step_limits);
      stage = set_integrator_states (states, ids, k3, h);
      endpoint = ob_runtime_eval (model, edges, order, finish, stage, true);
      k4 = derivatives (endpoint, ids, routes, step_limits);
      for j = 1:numel (ids)
        value = get_state (states, ids{j});
        value += h / 6 * (k1{j} + 2*k2{j} + 2*k3{j} + k4{j});
        states = put_state (states, ids{j}, value);
      endfor
      states = clamp_states (states, ids, limits);
    endif
    if (! isempty (delays))
      % Record the left limit at the segment end; an accepted hit at this
      % time records the right limit, which preserves input discontinuities.
      evaluated = ob_runtime_eval (model, edges, order, finish, states, true);
      states = record_delays (model, delays, states, evaluated, finish, 'left');
    endif
  endfor
  states = refresh_endpoint (model, edges, order, states, end_time);
endfunction

function boundaries = delay_boundaries (model, states, delays, boundaries)
  % Delayed discontinuities become segment boundaries, and no segment is
  % longer than the shortest delay.  Solver stages then read only recorded
  % history: time - delay never passes the segment's start.
  begin = boundaries(1); finish = boundaries(end);
  shortest = Inf;
  for id = delays
    params = ob_runtime_parameters (model, id);
    shortest = min (shortest, params.delay);
    boundaries = [boundaries ob_transport_delay('jumps', params, states{id}, begin, finish)];
  endfor
  boundaries = unique (boundaries);
  refined = boundaries(1);
  for k = 2:numel (boundaries)
    gap = boundaries(k) - boundaries(k-1);
    pieces = ceil (gap / shortest * (1 - 4*eps));
    if (pieces > 1)
      if (pieces > 1e6)
        error ('ob_run: Transport Delay of %.17g needs more than 1e6 segments per output interval', shortest);
      endif
      refined = [refined boundaries(k-1) + (1:pieces-1) * (gap / pieces)];
    endif
    refined(end+1) = boundaries(k);
  endfor
  boundaries = refined;
endfunction

function states = record_delays (model, delays, states, current, time, side)
  if (isfield (model, 'runtime_info') && isfield (model.runtime_info, 'sources'))
    sources = model.runtime_info.sources;
  else
    sources = [];
  endif
  for id = delays
    if (iscell (sources)), source = sources{id};
    else
      ordered = sortrows (ob_edges (model), [3 4]);
      source = ordered(ordered(:, 3) == id, 1);
    endif
    require_inputs (source, 1, 'Transport Delay');
    params = ob_runtime_parameters (model, id);
    states{id} = ob_transport_delay ('record', params, states{id}, time, current{source}, side, id);
  endfor
endfunction

function limits = saturation_at (states, ids, limits)
  for j = 1:numel (ids)
    if (isempty (limits{j})), continue; endif
    value = get_state (states, ids{j});
    limits{j}.at_upper = value >= limits{j}.upper;
    limits{j}.at_lower = value <= limits{j}.lower;
  endfor
endfunction

function states = clamp_states (states, ids, limits)
  for j = 1:numel (ids)
    if (isempty (limits{j})), continue; endif
    value = get_state (states, ids{j});
    states = put_state (states, ids{j}, min (max (value, limits{j}.lower), limits{j}.upper));
  endfor
endfunction

function states = refresh_endpoint (model, edges, order, states, end_time)
  % Preserve the left-limit child snapshot before a major hit can disable it.
  % Ordinary flat models need no additional evaluation after the solver stages.
  for id = category_ids(model,'conditional_ids',{'Conditional Subsystem'})
    descriptor = ob_runtime_execution (model,id);
    if (states{id}.initialized && states{id}.was_enabled ...
        && descriptor.needs_flow)
      [unused, states] = ob_runtime_eval (model, edges, order, end_time, states, true);
      break;
    endif
  endfor
endfunction

function [routes, limits] = derivative_routes (model, edges, ids, states)
  routes = zeros (1, numel(ids));
  limits = cell (1, numel(ids));
  for j = 1:numel(ids)
    path = ids{j}; local_model = model; local_edges = edges; local_states = states;
    for core = path(1:end-1)
      child = local_states{core}.child;
      local_model = child.model; local_edges = child.edges; local_states = child.states;
    endfor
    id = path(end);
    if (has_sources(local_model))
      sources = local_model.runtime_info.sources{id};
    else
      sources = local_edges(local_edges(:,2)==id,1);
    endif
    if (strcmp (local_model.blocks(id).type, 'Limited Integrator'))
      params = ob_runtime_parameters (local_model, id);
      has_reset = ! strcmp (params.reset, 'none');
      require_inputs (sources, 1 + has_reset, 'Limited Integrator');
      limits{j} = struct ('lower', params.lower, 'upper', params.upper, ...
                          'level', strcmp (params.reset, 'level'), 'reset', 0);
      if (has_reset), limits{j}.reset = sources(2); endif
    else
      require_inputs (sources, 1, 'Integrator');
    endif
    routes(j) = sources(1);
  endfor
endfunction

function k = derivatives (current, integrators, routes, limits)
  k = cell (1, numel (integrators));
  for j = 1:numel (integrators)
    path = integrators{j};
    local_current = current;
    for core = path(1:end-1)
      child = local_current{core}.child;
      local_current = child.current;
    endfor
    id = path(end);
    k{j} = local_current{routes(j)};
    if (! isnumeric (k{j}) || ! isreal (k{j}) ...
        || ! size_equal (k{j}, local_current{id}) ...
        || any (! isfinite (k{j}(:))))
      error ("ob_run: Integrator block %s derivative must be finite, real, and match its state shape", ...
             strtrim (sprintf ('%d ', path)));
    endif
    limit = limits{j};
    if (! isempty (limit))
      % A saturated state stops integrating outward; inward motion resumes
      % immediately.  A nonzero level reset holds the state.
      if (isfield (limit, 'at_upper'))
        at_upper = limit.at_upper; at_lower = limit.at_lower;
      else
        output = local_current{id};
        at_upper = output >= limit.upper; at_lower = output <= limit.lower;
      endif
      outward = (at_upper & k{j} > 0) | (at_lower & k{j} < 0);
      k{j}(outward) = 0;
      if (limit.level)
        signal = local_current{limit.reset};
        if (! isnumeric (signal) || ! isreal (signal) || ! isscalar (signal) || ! isfinite (signal))
          error ('ob_run: Limited Integrator block %s reset must be a finite real scalar', ...
                 strtrim (sprintf ('%d ', path)));
        endif
        if (signal != 0), k{j}(:) = 0; endif
      endif
    endif
  endfor
endfunction

function [states, accepted, times, solution] = adaptive_segment (model, edges, order, ids, routes, limits, states, start_time, end_time, options)
  initial = pack_states (states, ids);
  settings = odeset ("RelTol", options.reltol, "AbsTol", options.abstol, ...
                     "MaxStep", min (options.maxstep, end_time - start_time), "Refine", 1);
  packed_ids = num2cell (1:numel(ids));
  rhs = @(time, y) adaptive_rhs (time, y, model, edges, order, ids, routes, limits, packed_ids, states, end_time);
  if (strcmp (options.solver, "ode15s"))
    settings = odeset (settings, "InitialSlope", rhs(start_time, initial));
  endif
  [times, solution] = feval (options.solver, rhs, [start_time end_time], initial, settings);
  endpoint_tolerance = 8 * eps (1) * max ([realmin() abs(start_time) abs(end_time)]);
  if (numel (times) < 2 || ! isfinite (times(end)) || times(end) <= start_time ...
      || abs (times(end) - end_time) > endpoint_tolerance ...
      || any (! isfinite (solution(end, :))))
    error ("ob_run: %s failed to reach time %.17g with finite states", options.solver, end_time);
  endif
  states = clamp_states (unpack_states (solution(end, :)', states, ids), ids, limits);
  accepted = numel (times) - 1;
endfunction

function value = adaptive_rhs (time, y, model, edges, order, ids, routes, limits, packed_ids, template, end_time)
  states = unpack_states (y, template, ids);
  % Adaptive step accumulation can overshoot its requested endpoint by an ulp.
  % Keep every such stage on the left side of this segment's discontinuity.
  left_limit = time >= end_time;
  if (left_limit), time = end_time; endif
  current = ob_runtime_eval (model, edges, order, time, states, left_limit);
  k = derivatives (current, ids, routes, limits);
  value = pack_states (k, packed_ids);
endfunction

function y = pack_states (states, ids)
  % Fast path: when every path is a flat scalar index (the common case for
  % models without nested continuous subsystems), extract and concatenate all
  % state vectors in one vectorized cellfun call rather than a scalar loop.
  if (all (cellfun (@isscalar, ids)))
    flat_ids = cell2mat (ids);
    parts = cellfun (@(s) double(s(:)), states(flat_ids), 'UniformOutput', false);
  else
    parts = cell (numel(ids), 1);
    for j = 1:numel(ids)
      value = get_state (states, ids{j});
      parts{j} = double(value(:));
    endfor
  endif
  y = vertcat (parts{:});
endfunction

function states = unpack_states (y, states, ids)
  offset = 0;
  for path = ids
    value = get_state (states, path{1}); count = numel (value);
    value = reshape (y(offset + (1:count)), size (value));
    states = put_state (states, path{1}, value);
    offset += count;
  endfor
endfunction

function next = set_integrator_states (states, ids, k, scale)
  next = states;
  for j = 1:numel (ids)
    next = put_state (next, ids{j}, get_state (states, ids{j}) + scale * k{j});
  endfor
endfunction

function value = get_state (states, path)
  if (numel (path) == 1), value = states{path(1)};
  else value = get_state (states{path(1)}.child.states, path(2:end)); endif
endfunction

function states = put_state (states, path, value)
  if (numel (path) == 1), states{path(1)} = value;
  else
    states{path(1)}.child.states = put_state (states{path(1)}.child.states, path(2:end), value);
  endif
endfunction

function boundaries = enabled_boundaries (model, states, begin, finish)
  boundaries = [];
  for id = category_ids(model,'boundary_ids',{'Step','Conditional Subsystem'})
    block = model.blocks(id);
    if (strcmp (block.type, 'Step'))
      event = block.value(1);
      if (event > begin && event < finish), boundaries(end + 1) = event; endif
    elseif (strcmp (block.type, 'Conditional Subsystem'))
      state = states{id};
      descriptor = ob_runtime_execution (model,id);
      options = descriptor.options;
      if (strcmp (options.mode, 'enabled') && state.initialized && state.was_enabled)
        boundaries = [boundaries enabled_boundaries(state.child.model, state.child.states, begin, finish)];
      endif
    endif
  endfor
endfunction

function yes = has_sources (model)
  yes = isfield(model,'runtime_info') && isstruct(model.runtime_info) && isscalar(model.runtime_info) ...
        && all(isfield(model.runtime_info,{'kind','sources'})) ...
        && ischar(model.runtime_info.kind) && strcmp(model.runtime_info.kind,'octave-blocks-runtime-info-v1') ...
        && iscell(model.runtime_info.sources) && numel(model.runtime_info.sources)==numel(model.blocks);
endfunction

function ids = category_ids (model, field, types)
  if (isfield(model,'runtime_info'))
    info = model.runtime_info;
    if (isstruct(info) && isscalar(info) && all(isfield(info,{'kind',field})) ...
        && ischar(info.kind) && strcmp(info.kind,'octave-blocks-runtime-info-v1'))
      candidate = info.(field);
      if (isnumeric(candidate) && isreal(candidate) && ndims(candidate)==2 && rows(candidate)==1 ...
          && all(isfinite(candidate)) && all(candidate==fix(candidate)) ...
          && all(candidate>=1 & candidate<=numel(model.blocks)) && all(diff(candidate)>0))
        ids = candidate; return;
      endif
    endif
  endif
  ids = reshape (find (ismember({model.blocks.type},types)), 1, []);
endfunction

function require_inputs (inputs, count, type)
  if (numel (inputs) != count)
    error ("ob_run: %s needs %d input(s); got %d", type, count, numel (inputs));
  endif
endfunction
