function [states, accepted, events, memory, reached, dispatch_flow] = ob_runtime_integrate (model, edges, order, ids, states, start_time, end_time, options, memory = struct (), plan = 'lookup')
  accepted = 0;
  if (nargout > 2)
    % Callers taking only states and steps skip building the event outputs.
    dispatch_flow = struct ();
    reached = end_time;
    events = struct ('time', {}, 'path', {}, 'type', {}, 'channel', {}, ...
                    'side', {}, 'direction', {}, 'boundary', {});
  endif
  event_mode = isfield (options, 'zero_crossings') && options.zero_crossings;
  % A prepared plan (ob_prepare_runtime_model) supplies trusted index lists;
  % older caches use the validated category lookups.  Callers that already
  % looked it up pass it in place of 'lookup'.
  if (ischar (plan)), plan = runtime_plan (model); endif
  if (isempty (plan)), delays = ob_runtime_type_ids (model, 'delay_ids', 'Transport Delay');
  else delays = plan.delay_blocks; endif
  if (isempty (ids) && ! event_mode && isempty (delays))
    states = refresh_endpoint (model, edges, order, states, end_time, plan);
    return;
  endif
  if (! iscell (ids)), ids = num2cell (reshape (ids, 1, [])); endif
  boundaries = [start_time end_time];
  if (isempty (plan) || ! isempty (plan.boundary_blocks))
    boundaries = [boundaries enabled_boundaries(model, states, start_time, end_time)];
  endif
  if (!isempty(model.inputs))
    % Gather every input signal's knot vector in one vectorized pass rather
    % than a scalar-append loop over ports.
    all_knots = cellfun (@(sig) sig.t(sig.t > start_time & sig.t < end_time)', ...
                         model.inputs, 'UniformOutput', false);
    boundaries = [boundaries all_knots{:}];
  endif
  % unique () of an already increasing pair is the pair itself.
  if (numel (boundaries) != 2 || ! (boundaries(1) < boundaries(2)))
    boundaries = unique (boundaries);
  endif
  if (event_mode)
    [states, accepted, events, memory, reached, dispatch_flow] = ob_integrate_events (model, edges, order, ids, states, boundaries, options, memory);
    states = refresh_endpoint (model, edges, order, states, reached, plan);
    return;
  endif
  if (! isempty (delays))
    boundaries = delay_boundaries (model, states, delays, boundaries, plan);
  endif
  % The active graph is fixed throughout these smooth segments. Resolve each
  % derivative's source once, before solver stages change only numeric states.
  [routes, limits] = derivative_routes (model, edges, ids, states, plan);
  % Flat integrators without limits take a lighter path: same arithmetic in
  % the same order, with scalar double states packed into vectors (element-
  % wise IEEE operations give identical bits) and fewer interpreted calls.
  flat = all (cellfun ('numel', ids) == 1) && all (cellfun ('isempty', limits));
  if (flat), flat_ids = [ids{:}]; endif
  % Solver stages evaluate through the plan's program when it has one.
  program = runtime_program (plan, order);
  for segment = 1:numel (boundaries)-1
    begin = boundaries(segment); finish = boundaries(segment + 1);
    h = finish - begin;
    initial = [];
    if (segment > 1 && ! isempty (delays))
      % An interior boundary is not an accepted hit, so only its left limit
      % has been recorded.  Record the right limit too: a discontinuity there
      % (a Step between output times, a delayed jump) is then stored as a
      % jump, not smeared over the next segment or turned into a near-vertical
      % slope by the first adaptive interior point.
      initial = evaluate (model, edges, order, program, plan, begin, states, false);
      states = record_delays (model, delays, states, initial, begin, 'right', plan);
    endif
    if (isempty (ids))
      % Only delay histories advance; no state is integrated.
    elseif (! strcmp (options.solver, "rk4"))
      [states, count, times, solution] = adaptive_segment (model, edges, order, ids, routes, limits, ...
                                                           states, begin, finish, options, program, plan);
      accepted += count;
      if (! isempty (delays))
        % Accepted interior solver points refine the delayed signal history.
        for point = 2:numel (times)-1
          sample = clamp_states (unpack_states (solution(point, :)', states, ids), ids, limits);
          evaluated = evaluate (model, edges, order, program, plan, times(point), sample, false);
          states = record_delays (model, delays, states, evaluated, times(point), 'right', plan);
        endfor
      endif
    % (The condition below also assigns packed, the scalar double state row.)
    elseif (flat && ! isempty (program) && ! isempty (packed = scalar_row (states(flat_ids))))
      accepted += 1;
      states = packed_rk4 (model, program, plan.parameters, states, flat_ids, routes, packed, ...
                           initial, begin, finish, h);
    elseif (flat)
      accepted += 1;
      if (isempty (initial)), initial = evaluate (model, edges, order, program, plan, begin, states, false); endif
      packed = scalar_row (states(flat_ids));
      % With scalar states every stage's integrator outputs are scalars too.
      scalar = ! isempty (packed);
      [k1, v1] = flat_derivatives (initial, flat_ids, routes, scalar);
      stage = flat_stage (states, flat_ids, packed, k1, v1, h / 2);
      middle = evaluate (model, edges, order, program, plan, begin + h / 2, stage, false);
      [k2, v2] = flat_derivatives (middle, flat_ids, routes, scalar);
      stage = flat_stage (states, flat_ids, packed, k2, v2, h / 2);
      middle = evaluate (model, edges, order, program, plan, begin + h / 2, stage, false);
      [k3, v3] = flat_derivatives (middle, flat_ids, routes, scalar);
      stage = flat_stage (states, flat_ids, packed, k3, v3, h);
      endpoint = evaluate (model, edges, order, program, plan, finish, stage, true);
      [k4, v4] = flat_derivatives (endpoint, flat_ids, routes, scalar);
      if (! isempty (packed) && ! isempty (v1) && ! isempty (v2) && ! isempty (v3) && ! isempty (v4))
        states(flat_ids) = num2cell (packed + h / 6 * (v1 + 2*v2 + 2*v3 + v4));
      else
        for j = 1:numel (flat_ids)
          value = states{flat_ids(j)};
          value += h / 6 * (k1{j} + 2*k2{j} + 2*k3{j} + k4{j});
          states{flat_ids(j)} = value;
        endfor
      endif
    else
      accepted += 1;
      % Fixed steps decide saturation from the step's initial state, so a
      % step that reaches a bound lands on it rather than stopping short.
      step_limits = saturation_at (states, ids, limits);
      % The right-limit record above cannot change any output at 'begin'
      % (delays read history before it), so its evaluation is the first stage.
      if (isempty (initial)), initial = evaluate (model, edges, order, program, plan, begin, states, false); endif
      k1 = derivatives (initial, ids, routes, step_limits);
      stage = set_integrator_states (states, ids, k1, h / 2);
      middle = evaluate (model, edges, order, program, plan, begin + h / 2, stage, false);
      k2 = derivatives (middle, ids, routes, step_limits);
      stage = set_integrator_states (states, ids, k2, h / 2);
      middle = evaluate (model, edges, order, program, plan, begin + h / 2, stage, false);
      k3 = derivatives (middle, ids, routes, step_limits);
      stage = set_integrator_states (states, ids, k3, h);
      endpoint = evaluate (model, edges, order, program, plan, finish, stage, true);
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
      evaluated = evaluate (model, edges, order, program, plan, finish, states, true);
      states = record_delays (model, delays, states, evaluated, finish, 'left', plan);
    endif
  endfor
  if (isempty (plan) || plan.conditional)
    states = refresh_endpoint (model, edges, order, states, end_time, plan);
  endif
endfunction

function plan = runtime_plan (model)
  plan = [];
  if (isfield (model, 'runtime_info'))
    info = model.runtime_info;
    if (isfield (info, 'plan') && isscalar (info) && isfield (info, 'kind') ...
        && strcmp (info.kind, 'octave-blocks-runtime-info-v1'))
      plan = info.plan;
    endif
  endif
endfunction

function program = runtime_program (plan, order)
  % The trusted plan's evaluation program, as ob_runtime_eval uses it
  % (built for the context's order, which every caller passes).
  program = [];
  if (! isempty (plan) && isfield (plan, 'program')), program = plan.program; endif
endfunction

function current = evaluate (model, edges, order, program, plan, time, states, left_limit)
  % ob_runtime_eval (model, edges, order, time, states, left_limit), through
  % the program when there is one (the same values, fewer interpreted steps).
  if (isempty (program))
    current = ob_runtime_eval (model, edges, order, time, states, left_limit);
  else
    current = ob_program_eval (program, plan.parameters, model, time, states, left_limit, []);
  endif
endfunction

function row = scalar_row (values)
  % Row of the values when every one is a full real double scalar, else [].
  row = [];
  if (all (cellfun ('isclass', values, 'double')) && all (cellfun ('prodofsize', values) == 1))
    row = [values{:}];
    if (issparse (row) || ! isreal (row)), row = []; endif
  endif
endfunction

function states = packed_rk4 (model, program, parameters, states, ids, routes, packed, initial, begin, finish, h)
  % The flat RK4 branch for scalar double states and a prepared program,
  % in one call: the same stage times, stage states and arithmetic, with the
  % evaluations made through ob_program_eval and flat_derivatives' fast
  % check inlined.  A stage whose derivatives are not all finite real full
  % double scalars takes flat_derivatives and flat_stage themselves, which
  % report the same first error or continue with the cell arithmetic.
  if (isempty (initial))
    initial = ob_program_eval (program, parameters, model, begin, states, false, []);
  endif
  k1 = initial(routes);
  v1 = [];
  if (all (cellfun ('isclass', k1, 'double')) && all (cellfun ('prodofsize', k1) == 1))
    v1 = [k1{:}];
    if (issparse (v1) || ! isreal (v1) || ! all (isfinite (v1))), v1 = []; endif
  endif
  if (isempty (v1))
    [k1, v1] = flat_derivatives (initial, ids, routes, true);
    stage = flat_stage (states, ids, packed, k1, v1, h / 2);
  else
    stage = states; stage(ids) = num2cell (packed + h / 2 * v1);
  endif
  middle = ob_program_eval (program, parameters, model, begin + h / 2, stage, false, []);
  k2 = middle(routes);
  v2 = [];
  if (all (cellfun ('isclass', k2, 'double')) && all (cellfun ('prodofsize', k2) == 1))
    v2 = [k2{:}];
    if (issparse (v2) || ! isreal (v2) || ! all (isfinite (v2))), v2 = []; endif
  endif
  if (isempty (v2))
    [k2, v2] = flat_derivatives (middle, ids, routes, true);
    stage = flat_stage (states, ids, packed, k2, v2, h / 2);
  else
    stage = states; stage(ids) = num2cell (packed + h / 2 * v2);
  endif
  middle = ob_program_eval (program, parameters, model, begin + h / 2, stage, false, []);
  k3 = middle(routes);
  v3 = [];
  if (all (cellfun ('isclass', k3, 'double')) && all (cellfun ('prodofsize', k3) == 1))
    v3 = [k3{:}];
    if (issparse (v3) || ! isreal (v3) || ! all (isfinite (v3))), v3 = []; endif
  endif
  if (isempty (v3))
    [k3, v3] = flat_derivatives (middle, ids, routes, true);
    stage = flat_stage (states, ids, packed, k3, v3, h);
  else
    stage = states; stage(ids) = num2cell (packed + h * v3);
  endif
  endpoint = ob_program_eval (program, parameters, model, finish, stage, true, []);
  k4 = endpoint(routes);
  v4 = [];
  if (all (cellfun ('isclass', k4, 'double')) && all (cellfun ('prodofsize', k4) == 1))
    v4 = [k4{:}];
    if (issparse (v4) || ! isreal (v4) || ! all (isfinite (v4))), v4 = []; endif
  endif
  if (isempty (v4)), [k4, v4] = flat_derivatives (endpoint, ids, routes, true); endif
  if (! isempty (v1) && ! isempty (v2) && ! isempty (v3) && ! isempty (v4))
    states(ids) = num2cell (packed + h / 6 * (v1 + 2*v2 + 2*v3 + v4));
  else
    for j = 1:numel (ids)
      value = states{ids(j)};
      value += h / 6 * (k1{j} + 2*k2{j} + 2*k3{j} + k4{j});
      states{ids(j)} = value;
    endfor
  endif
endfunction

function [k, row] = flat_derivatives (current, ids, routes, scalar)
  % Derivatives of flat, unlimited integrators.  row packs them when all are
  % finite full real double scalars and every state is scalar (the caller's
  % scalar flag, or a check here); otherwise the per-integrator checks run
  % and report the first failure, as derivatives () does.
  k = current(routes);
  % scalar_row (k), inlined: this runs at every solver stage.
  if ((scalar || all (cellfun ('prodofsize', current(ids)) == 1)) ...
      && all (cellfun ('isclass', k, 'double')) && all (cellfun ('prodofsize', k) == 1))
    row = [k{:}];
    if (! issparse (row) && isreal (row) && all (isfinite (row))), return; endif
  endif
  row = [];
  for j = 1:numel (ids)
    value = k{j};
    if (! isnumeric (value) || ! isreal (value) ...
        || ! size_equal (value, current{ids(j)}) ...
        || any (! isfinite (value(:))))
      error ("ob_run: Integrator block %s derivative must be finite, real, and match its state shape", ...
             strtrim (sprintf ('%d ', ids(j))));
    endif
  endfor
endfunction

function stage = flat_stage (states, ids, packed, k, row, scale)
  stage = states;
  if (! isempty (packed) && ! isempty (row))
    stage(ids) = num2cell (packed + scale * row);
  else
    for j = 1:numel (ids)
      stage{ids(j)} = states{ids(j)} + scale * k{j};
    endfor
  endif
endfunction

function boundaries = delay_boundaries (model, states, delays, boundaries, plan)
  % Delayed discontinuities become segment boundaries, and no segment is
  % longer than the shortest delay.  Solver stages then read only recorded
  % history: time - delay never passes the segment's start.
  begin = boundaries(1); finish = boundaries(end);
  shortest = Inf;
  added = false;
  for id = delays
    if (isempty (plan)), params = ob_runtime_parameters (model, id);
    else
      params = plan.parameters{id};
      if (! isstruct (params)), params = ob_block_parameters (model.blocks(id)); endif
    endif
    shortest = min (shortest, params.delay);
    jumps = ob_transport_delay('jumps', params, states{id}, begin, finish, boundaries);
    added = added || ! isempty (jumps);
    boundaries = [boundaries jumps];
  endfor
  % The incoming boundaries are already sorted and unique.
  if (added), boundaries = unique (boundaries); endif
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

function states = record_delays (model, delays, states, current, time, side, plan)
  if (! isempty (plan))
    % The trusted plan's own source map and parameters, as
    % ob_runtime_parameters would return them.
    for id = delays
      source = plan.sources{id};
      require_inputs (source, 1, 'Transport Delay');
      params = plan.parameters{id};
      if (! isstruct (params)), params = ob_block_parameters (model.blocks(id)); endif
      states{id} = ob_transport_delay ('record', params, states{id}, time, current{source}, side, id);
    endfor
    return;
  endif
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

function states = refresh_endpoint (model, edges, order, states, end_time, plan)
  % Preserve the left-limit child snapshot before a major hit can disable it.
  % Ordinary flat models need no additional evaluation after the solver stages.
  if (isempty (plan)), ids = category_ids(model,'conditional_ids',{'Conditional Subsystem'});
  else ids = plan.conditional_blocks; endif
  for id = ids
    descriptor = ob_runtime_execution (model,id);
    if (states{id}.initialized && states{id}.was_enabled ...
        && descriptor.needs_flow)
      [unused, states] = ob_runtime_eval (model, edges, order, end_time, states, true);
      break;
    endif
  endfor
endfunction

function [routes, limits] = derivative_routes (model, edges, ids, states, plan)
  routes = zeros (1, numel(ids));
  limits = cell (1, numel(ids));
  if (! isempty (plan) && all (cellfun ('numel', ids) == 1))
    % Flat Integrators (no Limited Integrator) with one input each: routes
    % are their sources, read from the plan's own trusted source map.
    flat_ids = [ids{:}];
    if (! any (plan.codes(flat_ids) == 19))
      sources = plan.sources(flat_ids);
      if (all (cellfun ('numel', sources) == 1))
        routes(:) = [sources{:}];
        return;
      endif
    endif
  endif
  % Top-level paths share one cache check rather than one per integrator.
  top_sources = has_sources (model);
  for j = 1:numel(ids)
    path = ids{j};
    if (numel (path) == 1)
      id = path; local_model = model;
      if (top_sources), sources = model.runtime_info.sources{id};
      else sources = edges(edges(:,2)==id,1); endif
      if (isempty (plan)), limited = strcmp (model.blocks(id).type, 'Limited Integrator');
      else limited = plan.codes(id) == 19; endif
    else
      local_model = model; local_edges = edges; local_states = states;
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
      limited = strcmp (local_model.blocks(id).type, 'Limited Integrator');
    endif
    if (limited)
      params = ob_runtime_parameters (local_model, id);
      has_reset = ! strcmp (params.reset, 'none');
      require_inputs (sources, 1 + has_reset, 'Limited Integrator');
      % Both level modes hold the state while the reset signal is nonzero.
      limits{j} = struct ('lower', params.lower, 'upper', params.upper, ...
                          'level', any (strcmp (params.reset, {'level', 'level hold'})), 'reset', 0);
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

function [states, accepted, times, solution] = adaptive_segment (model, edges, order, ids, routes, limits, states, start_time, end_time, options, program, plan)
  initial = pack_states (states, ids);
  maxstep = min (options.maxstep, end_time - start_time);
  packed_ids = num2cell (1:numel(ids));
  % Flat, unlimited integrators with scalar double states unpack and pack
  % solver vectors directly; the values are the same as the general path's.
  flat_ids = [];
  if (all (cellfun ('numel', ids) == 1) && all (cellfun ('isempty', limits)) ...
      && ! isempty (scalar_row (states([ids{:}]))))
    flat_ids = [ids{:}];
  endif
  rhs = @(time, y) adaptive_rhs (time, y, model, edges, order, ids, routes, limits, packed_ids, states, end_time, flat_ids, program, plan);
  if (lean_ode45 (options, maxstep))
    [times, solution] = ob_dormand_prince (rhs, start_time, end_time, initial, ...
                                           options.reltol, options.abstol, maxstep);
  else
    settings = ob_ode_settings ("RelTol", options.reltol, "AbsTol", options.abstol, ...
                                "MaxStep", maxstep, "Refine", 1);
    if (strcmp (options.solver, "ode15s"))
      settings = ob_ode_settings (settings, "InitialSlope", rhs(start_time, initial));
    endif
    [times, solution] = feval (options.solver, rhs, [start_time end_time], initial, settings);
  endif
  endpoint_tolerance = 8 * eps (1) * max ([realmin() abs(start_time) abs(end_time)]);
  if (numel (times) < 2 || ! isfinite (times(end)) || times(end) <= start_time ...
      || abs (times(end) - end_time) > endpoint_tolerance ...
      || any (! isfinite (solution(end, :))))
    error ("ob_run: %s failed to reach time %.17g with finite states", options.solver, end_time);
  endif
  states = clamp_states (unpack_states (solution(end, :)', states, ids), ids, limits);
  accepted = numel (times) - 1;
endfunction

function yes = lean_ode45 (options, maxstep)
  % ob_dormand_prince reproduces this Octave's ode45 for double tolerances
  % and step bounds; other classes keep ode45's own validation and arithmetic.
  yes = strcmp (options.solver, "ode45") && isa (options.reltol, "double") ...
        && isa (options.abstol, "double") && isa (maxstep, "double") ...
        && ob_dormand_prince ("available");
endfunction

function value = adaptive_rhs (time, y, model, edges, order, ids, routes, limits, packed_ids, template, end_time, flat_ids, program, plan)
  if (isempty (flat_ids))
    states = unpack_states (y, template, ids);
  else
    states = template;
    states(flat_ids) = num2cell (y);
  endif
  % Adaptive step accumulation can overshoot its requested endpoint by an ulp.
  % Keep every such stage on the left side of this segment's discontinuity.
  left_limit = time >= end_time;
  if (left_limit), time = end_time; endif
  % evaluate (), inlined: this runs at every adaptive stage.
  if (isempty (program))
    current = ob_runtime_eval (model, edges, order, time, states, left_limit);
  else
    current = ob_program_eval (program, plan.parameters, model, time, states, left_limit, []);
  endif
  if (isempty (flat_ids))
    k = derivatives (current, ids, routes, limits);
  else
    [k, row] = flat_derivatives (current, flat_ids, routes, true);
    if (! isempty (row)), value = row.'; return; endif
  endif
  value = pack_states (k, packed_ids);
endfunction

function y = pack_states (states, ids)
  % Flat scalar paths (models without nested continuous subsystems) read the
  % states directly; full double scalars concatenate without conversion.
  if (all (cellfun ('numel', ids) == 1))
    values = states([ids{:}]);
    if (all (cellfun ('isclass', values, 'double')) && all (cellfun ('prodofsize', values) == 1))
      y = [values{:}].';
      return;
    endif
    parts = cellfun (@(s) double(s(:)), values, 'UniformOutput', false);
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
  plan = runtime_plan (model);
  if (isempty (plan)), ids = category_ids(model,'boundary_ids',{'Step','Conditional Subsystem'});
  else ids = plan.boundary_blocks; endif
  for id = ids
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
