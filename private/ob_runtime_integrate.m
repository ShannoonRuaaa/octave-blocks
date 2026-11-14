function [states, accepted, events, memory, reached, dispatch_flow] = ob_runtime_integrate (model, edges, order, ids, states, start_time, end_time, options, memory = struct ())
  accepted = 0;
  dispatch_flow = struct ();
  reached = end_time;
  events = struct ('time', {}, 'path', {}, 'type', {}, 'channel', {}, ...
                  'side', {}, 'direction', {}, 'boundary', {});
  event_mode = isfield (options, 'zero_crossings') && options.zero_crossings;
  if (isempty (ids) && ! event_mode)
    states = refresh_endpoint (model, edges, order, states, end_time);
    return;
  endif
  if (! iscell (ids)), ids = num2cell (reshape (ids, 1, [])); endif
  boundaries = [start_time end_time];
  boundaries = [boundaries enabled_boundaries(model, states, start_time, end_time)];
  for port = 1:numel (model.inputs)
    knots = model.inputs{port}.t;
    boundaries = [boundaries knots(knots > start_time & knots < end_time)'];
  endfor
  boundaries = unique (boundaries);
  if (event_mode)
    [states, accepted, events, memory, reached, dispatch_flow] = ob_integrate_events (model, edges, order, ids, states, boundaries, options, memory);
    states = refresh_endpoint (model, edges, order, states, reached);
    return;
  endif
  % The active graph is fixed throughout these smooth segments. Resolve each
  % derivative's source once, before solver stages change only numeric states.
  routes = derivative_routes (model, edges, ids, states);
  for segment = 1:numel (boundaries)-1
    begin = boundaries(segment); finish = boundaries(segment + 1);
    h = finish - begin;
    if (! strcmp (options.solver, "rk4"))
      [states, count] = adaptive_segment (model, edges, order, ids, routes, states, begin, finish, options);
      accepted += count;
      continue;
    endif
    accepted += 1;
    initial = ob_runtime_eval (model, edges, order, begin, states);
    k1 = derivatives (initial, ids, routes);
    stage = set_integrator_states (states, ids, k1, h / 2);
    middle = ob_runtime_eval (model, edges, order, begin + h / 2, stage);
    k2 = derivatives (middle, ids, routes);
    stage = set_integrator_states (states, ids, k2, h / 2);
    middle = ob_runtime_eval (model, edges, order, begin + h / 2, stage);
    k3 = derivatives (middle, ids, routes);
    stage = set_integrator_states (states, ids, k3, h);
    endpoint = ob_runtime_eval (model, edges, order, finish, stage, true);
    k4 = derivatives (endpoint, ids, routes);
    for j = 1:numel (ids)
      value = get_state (states, ids{j});
      value += h / 6 * (k1{j} + 2*k2{j} + 2*k3{j} + k4{j});
      states = put_state (states, ids{j}, value);
    endfor
  endfor
  states = refresh_endpoint (model, edges, order, states, end_time);
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

function routes = derivative_routes (model, edges, ids, states)
  routes = zeros (1, numel(ids));
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
    require_inputs (sources, 1, 'Integrator');
    routes(j) = sources(1);
  endfor
endfunction

function k = derivatives (current, integrators, routes)
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
  endfor
endfunction

function [states, accepted] = adaptive_segment (model, edges, order, ids, routes, states, start_time, end_time, options)
  initial = pack_states (states, ids);
  settings = odeset ("RelTol", options.reltol, "AbsTol", options.abstol, ...
                     "MaxStep", min (options.maxstep, end_time - start_time), "Refine", 1);
  packed_ids = num2cell (1:numel(ids));
  rhs = @(time, y) adaptive_rhs (time, y, model, edges, order, ids, routes, packed_ids, states, end_time);
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
  states = unpack_states (solution(end, :)', states, ids);
  accepted = numel (times) - 1;
endfunction

function value = adaptive_rhs (time, y, model, edges, order, ids, routes, packed_ids, template, end_time)
  states = unpack_states (y, template, ids);
  % Adaptive step accumulation can overshoot its requested endpoint by an ulp.
  % Keep every such stage on the left side of this segment's discontinuity.
  left_limit = time >= end_time;
  if (left_limit), time = end_time; endif
  current = ob_runtime_eval (model, edges, order, time, states, left_limit);
  k = derivatives (current, ids, routes);
  value = pack_states (k, packed_ids);
endfunction

function y = pack_states (states, ids)
  parts = cell (numel(ids), 1);
  for j = 1:numel(ids)
    value = get_state (states, ids{j});
    parts{j} = double(value(:));
  endfor
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
