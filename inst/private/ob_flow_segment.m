function [next, count, times, samples] = ob_flow_segment (model, edges, order, ids, states, begin, finish, options, flow = struct (), monitor = [])
  % Propagate one smooth flow segment without discrete/lifecycle dispatch.
  % Samples are accepted solver outputs; trial RHS evaluations remain private.
  if (! valid_time (begin) || ! valid_time (finish) || finish <= begin ...
      || ! isfinite (finish - begin))
    error ('ob_run: a flow segment needs finite increasing endpoint times');
  endif
  if (! isempty (monitor) && ! isa (monitor, 'function_handle'))
    error ('ob_run: a flow monitor must be a function handle');
  endif
  if (! iscell (ids)), ids = num2cell (reshape (ids, 1, [])); endif
  count = 1; next = states;
  times = [begin; finish]; samples = {states; states};
  if (isempty (ids))
    if (! isempty (monitor)), checked_monitor (finish, states); endif
    return;
  endif
  initial = pack_states (states, ids);
  % numfields is the builtin equivalent of isempty (fieldnames (struct)).
  has_flow = numfields (flow) > 0;
  % The trusted plan's evaluation program, as ob_runtime_eval would use it.
  program = []; parameters = {};
  if (isfield (model, 'runtime_info'))
    info = model.runtime_info;
    if (isfield (info, 'plan') && isscalar (info) && isfield (info, 'kind') ...
        && strcmp (info.kind, 'octave-blocks-runtime-info-v1') && isfield (info.plan, 'program'))
      program = info.plan.program; parameters = info.plan.parameters;
    endif
  endif
  packed_ids = num2cell (1:numel(ids));
  routes = derivative_routes (model, edges, ids, states);
  % Flat paths whose states are all scalars unpack solver vectors directly
  % (the general unpack yields the same double scalars) and pack finite
  % double scalar derivatives without per-integrator conversion.
  flat_ids = [];
  if (all (cellfun ('numel', ids) == 1))
    candidate = [ids{:}];
    if (all (cellfun ('prodofsize', states(candidate)) == 1)), flat_ids = candidate; endif
  endif
  if (strcmp (options.solver, 'rk4'))
    h = finish - begin;
    k1 = rhs (begin, initial);
    k2 = rhs (begin + h/2, initial + h/2*k1);
    k3 = rhs (begin + h/2, initial + h/2*k2);
    k4 = rhs (finish, initial + h*k3);
    final = initial + h/6*(k1 + 2*k2 + 2*k3 + k4);
    if (any (! isfinite (final)))
      error ('ob_run: rk4 flow produced nonfinite states');
    endif
    next = unpack_states (final, states, ids);
    samples = {states; next}; count = 1;
    if (! isempty (monitor)), checked_monitor (finish, next); endif
    return;
  endif

  % Native solvers use local elapsed time.  A physically short segment at a
  % large absolute origin must not look like coincident endpoints to IDA.
  duration = finish - begin;
  monitor_stopped = false; stopped_elapsed = []; stopped_state = [];
  last_monitored_time = begin;
  maxstep = min (options.maxstep, duration);
  if (strcmp (options.solver, 'ode45') && isa (options.reltol, 'double') ...
      && isa (options.abstol, 'double') && isa (maxstep, 'double') ...
      && ob_dormand_prince ('available'))
    % ode45 itself, without its per-call option handling (ob_dormand_prince).
    output = [];
    if (! isempty (monitor)), output = @accepted_output; endif
    [elapsed, solution] = ob_dormand_prince (@elapsed_rhs, 0, duration, initial, ...
                                             options.reltol, options.abstol, maxstep, output);
  else
    settings = ob_ode_settings ('RelTol', options.reltol, 'AbsTol', options.abstol, ...
                                'MaxStep', maxstep, 'Refine', 1);
    if (! isempty (monitor)), settings = ob_ode_settings (settings, 'OutputFcn', @accepted_output); endif
    if (strcmp (options.solver, 'ode15s'))
      settings = ob_ode_settings (settings, 'InitialSlope', rhs (begin, initial));
    endif
    [elapsed, solution] = feval (options.solver, @elapsed_rhs, [0 duration], initial, settings);
  endif
  elapsed = elapsed(:);
  tolerance = 8 * eps (1) * max (realmin(), duration);
  if (numel (elapsed) < 2 || rows (solution) != numel (elapsed) ...
      || columns (solution) != numel (initial) || any (! isfinite (elapsed)) ...
      || any (diff (elapsed) <= 0) || elapsed(end) <= 0 ...
      || abs (elapsed(1)) > tolerance ...
      || elapsed(end) > duration + tolerance || any (! isfinite (solution(:))))
    error ('ob_run: %s returned invalid accepted flow samples', options.solver);
  endif
  if (monitor_stopped)
    % Refine=1 normally gives one accepted point per callback.  Trimming also
    % preserves the monitor's stop point if a solver batches accepted outputs.
    keep = elapsed < stopped_elapsed;
    elapsed = [elapsed(keep); stopped_elapsed];
    solution = [solution(keep, :); stopped_state(:)'];
  elseif (abs (elapsed(end) - duration) > tolerance)
    error ('ob_run: %s failed to reach time %.17g with finite states', options.solver, finish);
  endif
  physical = min (finish, begin + elapsed);
  % Several accepted local steps can round to one physical double timestamp.
  % Preserve the initial state exactly; retain the latest subsequent sample
  % at a repeated timestamp, matching forward progression without duplicates.
  selected = 1;
  for sample_index = 2:numel (physical)
    if (physical(sample_index) <= begin), continue; endif
    if (physical(sample_index) == physical(selected(end)))
      selected(end) = sample_index;
    else
      selected(end+1) = sample_index;
    endif
  endfor
  times = physical(selected);
  solution = solution(selected, :);
  if (numel (times) < 2 || any (diff (times) <= 0))
    error ('ob_run: %s flow samples cannot advance physical time', options.solver);
  endif
  count = numel (times) - 1;
  samples = cell (numel (times), 1);
  for sample_index = 1:numel (times)
    samples{sample_index} = unpack_states (solution(sample_index, :)', states, ids);
  endfor
  next = samples{end};

  function derivative = elapsed_rhs (local_time, vector)
    derivative = rhs (begin + local_time, vector);
  endfunction

  function derivative = rhs (stage_time, vector)
    if (isempty (flat_ids))
      trial = unpack_states (vector, states, ids);
    else
      trial = states;
      trial(flat_ids) = num2cell (vector);
    endif
    left_limit = stage_time >= finish;
    if (left_limit), stage_time = finish; endif
    if (! isempty (program))
      evaluated = ob_program_eval (program, parameters, model, stage_time, trial, left_limit, flow);
    elseif (!has_flow)
      evaluated = ob_runtime_eval (model, edges, order, stage_time, trial, left_limit);
    else
      evaluated = ob_runtime_eval (model, edges, order, stage_time, trial, ...
                                   left_limit, [], [], struct (), flow);
    endif
    if (! isempty (flat_ids))
      rates = evaluated(routes);
      if (all (cellfun ('isclass', rates, 'double')) && all (cellfun ('prodofsize', rates) == 1) ...
          && all (cellfun ('prodofsize', evaluated(flat_ids)) == 1))
        derivative = [rates{:}].';
        % With scalar integrator outputs these are derivatives ()'s checks.
        if (isreal (derivative) && ! issparse (derivative) && all (isfinite (derivative)))
          return;
        endif
      endif
    endif
    rates = derivatives (evaluated, ids, routes);
    derivative = pack_states (rates, packed_ids);
  endfunction

  function stop = accepted_output (callback_times, callback_values, flag)
    stop = false;
    if (! isempty (flag)), return; endif
    for point = 1:numel (callback_times)
      accepted_time = min (finish, begin + callback_times(point));
      if (accepted_time <= last_monitored_time), continue; endif
      last_monitored_time = accepted_time;
      accepted_vector = callback_values(:, point);
      accepted_states = unpack_states (accepted_vector, states, ids);
      if (checked_monitor (accepted_time, accepted_states))
        monitor_stopped = true; stopped_elapsed = callback_times(point);
        stopped_state = accepted_vector; stop = true;
        return;
      endif
    endfor
  endfunction

  function stop = checked_monitor (accepted_time, accepted_states)
    requested = monitor (accepted_time, accepted_states);
    if ((! isnumeric (requested) && ! islogical (requested)) ...
        || ! isscalar (requested) || ! isreal (requested) || ! isfinite (requested))
      error ('ob_run: a flow monitor must return a finite real scalar stop flag');
    endif
    stop = logical (requested);
  endfunction
endfunction

function routes = derivative_routes (model, edges, ids, states)
  routes = zeros (1, numel(ids));
  for item = 1:numel(ids)
    path = ids{item}; local_model = model; local_edges = edges; local_states = states;
    for core = path(1:end-1)
      child = local_states{core}.child;
      local_model = child.model; local_edges = child.edges; local_states = child.states;
    endfor
    id = path(end);
    info = [];
    if (isfield(local_model,'runtime_info')), info = local_model.runtime_info; endif
    if (isstruct(info) && isscalar(info) && all(isfield(info,{'kind','sources'})) ...
        && ischar(info.kind) && strcmp(info.kind,'octave-blocks-runtime-info-v1') && iscell(info.sources) ...
        && numel(info.sources)==numel(local_model.blocks))
      sources = info.sources{id};
    else
      sources = local_edges(local_edges(:,2)==id,1);
    endif
    if (numel(sources)!=1), error('ob_run: Integrator needs one input'); endif
    routes(item) = sources(1);
  endfor
endfunction

function rates = derivatives (current, integrators, routes)
  rates = cell (1, numel (integrators));
  for item = 1:numel (integrators)
    path = integrators{item}; local_current = current;
    for core = path(1:end-1)
      child = local_current{core}.child;
      local_current = child.current;
    endfor
    id = path(end);
    rates{item} = local_current{routes(item)};
    if (! isnumeric (rates{item}) || ! isreal (rates{item}) ...
        || ! size_equal (rates{item}, local_current{id}) ...
        || any (! isfinite (rates{item}(:))))
      error ('ob_run: Integrator block %s derivative must be finite, real, and match its state shape', ...
             strtrim (sprintf ('%d ', path)));
    endif
  endfor
endfunction

function vector = pack_states (states, ids)
  if (all (cellfun ('numel', ids) == 1))
    values = states([ids{:}]);
    % Full double scalars concatenate to the same vector without conversion.
    if (all (cellfun ('isclass', values, 'double')) && all (cellfun ('prodofsize', values) == 1))
      vector = [values{:}].';
      return;
    endif
    parts = cellfun (@(s) double(s(:)), values, 'UniformOutput', false);
  else
    parts = cell (numel(ids), 1);
    for item = 1:numel(ids)
      value = get_state (states, ids{item});
      parts{item} = double(value(:));
    endfor
  endif
  vector = vertcat (parts{:});
endfunction

function states = unpack_states (vector, states, ids)
  offset = 0;
  for path = ids
    value = get_state (states, path{1}); count = numel (value);
    states = put_state (states, path{1}, reshape (vector(offset + (1:count)), size (value)));
    offset += count;
  endfor
endfunction

function value = get_state (states, path)
  if (numel (path) == 1), value = states{path(1)};
  else value = get_state (states{path(1)}.child.states, path(2:end)); endif
endfunction

function states = put_state (states, path, value)
  if (numel (path) == 1), states{path(1)} = value;
  else states{path(1)}.child.states = put_state (states{path(1)}.child.states, path(2:end), value); endif
endfunction

function yes = valid_time (value)
  yes = isnumeric (value) && isreal (value) && isscalar (value) && isfinite (value);
endfunction
