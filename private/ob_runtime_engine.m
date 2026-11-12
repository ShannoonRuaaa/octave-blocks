function value = ob_runtime_engine (action, varargin)
  switch (action)
    case 'init'
      value = initialize (varargin{:});
    case 'step'
      validate_context (varargin{1});
      value = advance (varargin{:});
    case 'outputs'
      validate_context (varargin{1});
      value = outputs (varargin{:});
    case 'execute'
      validate_context (varargin{1});
      value = execute_child (varargin{:});
    case 'flow-hit'
      validate_context (varargin{1});
      frame = struct ();
      if (numel(varargin)>4), frame = varargin{5}; endif
      value = execute_child (varargin{1:4}, true, frame);
    case 'gate-hit'
      validate_context (varargin{1});
      value = execute_gate_child (varargin{:});
    case 'init-child'
      value = initialize (varargin{:});
    case 'clock-hit'
      validate_context (varargin{1});
      value = execute_clocked_child (varargin{:});
    otherwise
      error ('ob_runtime: unknown operation');
  endswitch
endfunction

function runtime = initialize (model, start_time, options, origin = [], embedded = false, major = true, events = struct ())
  if (! valid_time (start_time))
    error ('ob_runtime_init: start_time must be a finite real numeric scalar');
  endif
  options = ob_solver_options (options);
  runtime.kind = 'octave-blocks-runtime-v1';
  [runtime.model, runtime.signal_map, runtime.block_paths] = ob_compile_model (model);
  runtime.model.continuous_controls = ob_has_continuous_control (runtime.model);
  if (runtime.model.continuous_controls && ! options.zero_crossings)
    error ('ob_runtime_init: continuous subsystem controls require zero_crossings=true');
  endif
  runtime.root_block_count = numel (model.blocks);
  [runtime.order, runtime.edges, runtime.stateful, runtime.model.algebraic_loops] = ...
      ob_execution_order (runtime.model, true);
  runtime.model = ob_prepare_runtime_model (runtime.model);
  if (! isempty (runtime.model.algebraic_loops))
    runtime.model.algebraic_paths = runtime.block_paths;
  endif
  runtime.options = options;
  runtime.types = {runtime.model.blocks.type};
  runtime.rates = runtime.model.sample_times;
  runtime.delayed = strcmp (runtime.types, 'Unit Delay') | strcmp (runtime.types, 'Discrete Integrator');
  runtime.transitions = strcmp (runtime.types, 'Rate Transition');
  discrete = runtime.delayed | runtime.transitions | strcmp (runtime.types, 'Conditional Subsystem');
  runtime.explicit = discrete & runtime.rates(:, 1)' > 0;
  runtime.inherited = discrete & ! runtime.explicit;
  runtime.integrators = find (strcmp (runtime.types, 'Integrator'));
  n = numel (runtime.model.blocks);
  runtime.states = runtime.pending = cell (1, n);
  runtime.pending_valid = false (1, n);
  runtime.sample_hits = cell (1, n);
  runtime.ticks = zeros (1, n);
  runtime.next_hits = Inf (1, n);
  if (isempty(origin)), origin = start_time; endif
  runtime.time = double (start_time); runtime.start_time = double (origin);
  runtime.embedded = embedded;
  runtime.nested_clocks = struct ('path', {}, 'rate', {}, 'tick', {}, 'next', {});
  if (!embedded), runtime.nested_clocks = ob_nested_clocks(runtime.model, origin); endif
  runtime.integration_steps = 0;
  runtime.events = struct ('time', {}, 'path', {}, 'type', {}, 'channel', {}, ...
                          'side', {}, 'direction', {}, 'boundary', {});
  runtime.event_memory = struct ();
  for id = reshape (find (runtime.stateful), 1, [])
    if (strcmp (runtime.types{id}, 'Conditional Subsystem'))
      runtime.states{id} = ob_conditional_state (runtime.model.blocks(id).value, runtime.time);
    else
      runtime.states{id} = runtime.model.blocks(id).value;
    endif
  endfor
  % Accepted algebraic signals are per-context guesses, separate from delayed
  % state.  Minor solver evaluations may use them without committing updates.
  for group = runtime.model.algebraic_loops
    for id = group{1}
      path = runtime.block_paths{id};
      diagram = ob_model_at (model, path(1:end-1));
      block = diagram.blocks(path(end));
      guess = 0;
      if (isfield (block, 'algebraic_initial') && ! isempty (block.algebraic_initial))
        guess = block.algebraic_initial;
      endif
      runtime.states{id} = guess;
    endfor
  endfor
  if (embedded)
    [runtime.ticks, runtime.next_hits] = ob_clock_rebase (runtime.rates, runtime.explicit, origin, runtime.time);
  endif
  for id = reshape (find (runtime.explicit & !embedded), 1, [])
    period = runtime.rates(id, 1); offset = runtime.rates(id, 2);
    if (! isfinite (runtime.time + period) || runtime.time + period <= runtime.time)
      error ('ob_run: sample period at block %d cannot advance the start time', id);
    endif
    runtime.next_hits(id) = runtime.time + offset;
    if (! isfinite (runtime.next_hits(id)) || runtime.next_hits(id) < runtime.time ...
        || (offset > 0 && runtime.next_hits(id) <= runtime.time))
      error ('ob_run: sample offset at block %d cannot advance the start time', id);
    endif
  endfor
  runtime = process_hits (runtime, runtime.time, major, [], events);
  if (embedded), runtime.major_current = runtime.current; endif
endfunction

function runtime = advance (runtime, next_time)
  if (! isfield (runtime, 'event_memory')), runtime.event_memory = struct (); endif
  if (! isfield (runtime, 'events'))
    runtime.events = struct ('time', {}, 'path', {}, 'type', {}, 'channel', {}, ...
                            'side', {}, 'direction', {}, 'boundary', {});
  endif
  if (valid_time (next_time)), next_time = double (next_time); endif
  if (! valid_time (next_time) || next_time <= runtime.time ...
      || ! isfinite (next_time - runtime.time))
    error ('ob_runtime_step: next_time must be finite and greater than the current time');
  endif
  dt = next_time - runtime.time;
  event_dispatches = 0;
  for id = reshape (find (runtime.inherited & runtime.delayed), 1, [])
    source = runtime.edges(runtime.edges(:, 2) == id, 1);
    runtime.pending{id} = capture (runtime.types{id}, runtime.states{id}, runtime.current{source}, dt, id);
    runtime.pending_valid(id) = true;
  endfor
  while (runtime.time < next_time)
    nested = [];
    if (isfield(runtime,'nested_clocks') && !isempty(runtime.nested_clocks))
      nested = [runtime.nested_clocks.next];
    endif
    event = min ([runtime.next_hits nested Inf]);
    at_output = ! (event < next_time && ! time_equal (event, next_time, runtime.start_time, clock_spacing(runtime)));
    if (at_output), event = next_time; endif
    if (event <= runtime.time)
      error ('ob_run: discrete schedule cannot advance time');
    endif
    continuous_paths = ob_continuous_paths (runtime.model, runtime.states);
    scheduled = event;
    [runtime.states, accepted, crossings, runtime.event_memory, reached, dispatch_flow] = ob_runtime_integrate (runtime.model, runtime.edges, ...
        runtime.order, continuous_paths, runtime.states, runtime.time, event, runtime.options, runtime.event_memory);
    reconcile = ! isempty (fieldnames(dispatch_flow));
    if (reached < runtime.time || (reached == runtime.time && !reconcile))
      error ('ob_run: accepted event cannot advance time');
    endif
    if (! isempty(crossings) || reconcile)
      event_dispatches += 1;
      if (event_dispatches > 1000)
        error ('ob_run: accepted event limit exceeded; possible control chattering');
      endif
    endif
    if (reconcile)
      event = reached; at_output = false;
    elseif (time_equal(reached,scheduled,runtime.start_time,clock_spacing(runtime)))
      event = scheduled;
      if (isfield(runtime.event_memory,'time') && runtime.event_memory.time == reached)
        runtime.event_memory.time = event;
      endif
    else
      event = reached; at_output = false;
    endif
    runtime.integration_steps += accepted;
    for crossing = crossings
      crossing.path = public_event_path (runtime, crossing.path);
      runtime.events(end+1) = crossing;
    endfor
    frame = struct ();
    if (reconcile), frame.reconcile = true; frame.flow = dispatch_flow; endif
    runtime = process_hits (runtime, event, at_output, [], frame);
  endwhile
endfunction

function path = public_event_path (runtime, compiled)
  path = runtime.block_paths{compiled(1)};
  if (numel (compiled) > 1)
    child = runtime.states{compiled(1)}.child;
    path = [path(1:end-1) public_event_path(child,compiled(2:end))];
  elseif (! isempty(path) && path(end) == 0)
    path(end) = [];
  endif
endfunction

function runtime = process_hits (runtime, time, at_output, inherited_interval = [], events = struct ())
  events.accepted = true;
  events.options = runtime.options;
  if (!isfield(events,'origin')), events.origin = runtime.start_time; endif
  if (!isfield(events,'paths')), events.paths = {}; endif
  if (!isfield(events,'spacing')), events.spacing = clock_spacing(runtime); endif
  reconcile = isfield(events,'reconcile') && events.reconcile;
  if (reconcile), at_output = false; events.paths = {}; endif
  nested_due = [];
  if (!reconcile && isfield(runtime,'nested_clocks') && !isempty(runtime.nested_clocks))
    for k = 1:numel(runtime.nested_clocks)
      if (!(time == runtime.start_time && runtime.nested_clocks(k).rate(2) > 0) ...
          && time_equal(runtime.nested_clocks(k).next,time,runtime.start_time,events.spacing))
        nested_due(end+1) = k;
        events.paths{end+1} = runtime.nested_clocks(k).path;
      endif
    endfor
  endif
  if (!reconcile && isfield(runtime,'embedded') && runtime.embedded)
    [runtime.ticks, runtime.next_hits] = ob_clock_rebase(runtime.rates,runtime.explicit,runtime.start_time,time,events.spacing);
  endif
  due = false (size (runtime.explicit));
  for id = reshape (find (runtime.explicit), 1, [])
    if (reconcile), continue; endif
    due(id) = ! (time == runtime.start_time && runtime.rates(id, 2) > 0) ...
              && time_equal (runtime.next_hits(id), time, runtime.start_time, events.spacing);
  endfor
  % Commit all previous captures simultaneously before evaluating any input.
  commits = runtime.delayed & runtime.pending_valid & (due | (at_output & runtime.inherited));
  for id = reshape (find (commits), 1, [])
    runtime.states{id} = runtime.pending{id};
    runtime.pending_valid(id) = false;
  endfor
  sampled = runtime.transitions | strcmp (runtime.types, 'Conditional Subsystem');
  sample = sampled & (due | (at_output & runtime.inherited));
  % Enabled bodies with inherited control sample at the union of inner clocks.
  for path = events.paths
    id = path{1}(1);
    if (runtime.inherited(id) && strcmp(runtime.types{id},'Conditional Subsystem'))
      descriptor = ob_runtime_execution (runtime.model,id);
      execution = descriptor.options;
      if (strcmp(execution.mode,'enabled') && strcmp(execution.control,'sampled'))
        sample(id) = true;
      endif
    endif
  endfor
  flow = struct ();
  if (isfield(events,'flow')), flow = events.flow; endif
  [runtime.current, runtime.states] = ob_runtime_eval (runtime.model, runtime.edges, ...
      runtime.order, time, runtime.states, false, sample, inherited_interval, events, flow);
  hit = due | (at_output & runtime.inherited) | sample;
  for id = reshape (find (hit), 1, [])
    runtime.sample_hits{id}(end + 1) = time;
  endfor
  for id = reshape (find (due & runtime.delayed), 1, [])
    source = runtime.edges(runtime.edges(:, 2) == id, 1);
    runtime.pending{id} = capture (runtime.types{id}, runtime.states{id}, ...
                                  runtime.current{source}, runtime.rates(id, 1), id);
    runtime.pending_valid(id) = true;
  endfor
  for id = reshape (find (due), 1, [])
    previous_hit = runtime.next_hits(id);
    runtime.ticks(id) += 1;
    if (runtime.ticks(id) > flintmax ())
      error ('ob_run: sample tick counter overflow at block %d', id);
    endif
    runtime.next_hits(id) = runtime.start_time + runtime.rates(id, 2) + runtime.ticks(id) * runtime.rates(id, 1);
    if (! isfinite (runtime.next_hits(id)) || runtime.next_hits(id) <= previous_hit || runtime.next_hits(id) <= time)
      error ('ob_run: sample period at block %d cannot advance event time', id);
    endif
  endfor
  runtime.time = time;
  for k = nested_due
    previous = runtime.nested_clocks(k).next;
    tick = runtime.nested_clocks(k).tick + 1;
    rate = runtime.nested_clocks(k).rate;
    next = runtime.start_time + rate(2) + tick * rate(1);
    if (tick > flintmax() || !isfinite(next) || next <= previous || next <= time)
      error ('ob_run: nested sample tick cannot advance event time');
    endif
    runtime.nested_clocks(k).tick = tick;
    runtime.nested_clocks(k).next = next;
  endfor
endfunction

function runtime = execute_clocked_child (runtime, time, signals, interval, major, events)
  if (!valid_time(time) || time < runtime.time ...
      || (major && (!valid_time(interval) || interval < 0 ...
                    || (interval == 0 && time != runtime.time))))
    error ('ob_runtime: clocked child needs monotone time and a positive major interval');
  endif
  candidate = runtime.model; candidate.inputs = signals;
  runtime.model.inputs = ob_model_inputs(candidate,true);
  runtime.embedded = true;
  if (major && interval > 0)
    captured = runtime.current;
    if (isfield(runtime,'major_current')), captured = runtime.major_current; endif
    for id = reshape(find(runtime.inherited & runtime.delayed),1,[])
      source = runtime.edges(runtime.edges(:,2)==id,1);
      runtime.pending{id} = capture(runtime.types{id},runtime.states{id},captured{source},interval,id);
      runtime.pending_valid(id) = true;
    endfor
  endif
  inherited_interval = [];
  if (major), inherited_interval = interval; endif
  runtime = process_hits(runtime,time,major,inherited_interval,events);
  if (major), runtime.major_current = runtime.current; endif
endfunction

function runtime = execute_child (runtime, time, signals, interval, continuous = false, events = struct ())
  % Called only by an active atomic parent. Do not traverse inactive time.
  if ((! continuous && ! isempty (runtime.integrators)) || any (runtime.explicit))
    error ('ob_runtime: conditional child must use inherited discrete execution');
  endif
  if (! valid_time (time) || time < runtime.time || (! continuous && time == runtime.time) ...
      || ! valid_time (interval) || interval < 0 ...
      || (interval == 0 && (!continuous || time != runtime.time)))
    error ('ob_runtime: child execution must advance time with a positive interval');
  endif
  candidate = runtime.model;
  candidate.inputs = signals;
  runtime.model.inputs = ob_model_inputs (candidate, true);
  captured = runtime.current;
  if (continuous && isfield (runtime, 'major_current')), captured = runtime.major_current; endif
  for id = reshape (find (runtime.inherited & runtime.delayed), 1, [])
    if (interval == 0), continue; endif
    source = runtime.edges(runtime.edges(:, 2) == id, 1);
    runtime.pending{id} = capture (runtime.types{id}, runtime.states{id}, captured{source}, interval, id);
    runtime.pending_valid(id) = true;
  endfor
  runtime = process_hits (runtime, time, true, interval, events);
  if (continuous), runtime.major_current = runtime.current; endif
endfunction

function runtime = execute_gate_child (runtime, time, signals, events)
  if (! valid_time(time) || time < runtime.time)
    error ('ob_runtime: accepted gate time must be monotone');
  endif
  candidate = runtime.model; candidate.inputs = signals;
  runtime.model.inputs = ob_model_inputs (candidate,true);
  runtime = process_hits (runtime,time,false,[],events);
endfunction

function value = outputs (runtime, path, port)
  if (! isnumeric (path) || ! isreal (path) || (! isempty (path) && ! isvector (path)) ...
      || any (! isfinite (path(:))) || any (path(:) < 1 | path(:) != fix(path(:))) ...
      || ! isnumeric (port) || ! isreal (port) || ! isscalar (port) ...
      || ! isfinite (port) || port < 1 || port != fix (port))
    error ('ob_runtime_outputs: supply a positive integer block path and port');
  endif
  if (isempty (path))
    if (port != 1), error ('ob_runtime_outputs: select a block path for a numbered port'); endif
    value = cell (1, runtime.root_block_count);
    for item = runtime.signal_map
      if (numel (item.path) == 1 && ! isempty (item.outputs))
        value{item.path} = runtime.current{item.outputs(1)};
      endif
    endfor
    return;
  endif
  path = double (path(:)');
  for item = runtime.signal_map
    if (isequal (item.path, path))
      if (port > numel (item.outputs)), error ('ob_runtime_outputs: output port does not exist'); endif
      value = runtime.current{item.outputs(port)};
      return;
    endif
  endfor
  for id = reshape (find (strcmp (runtime.types, 'Conditional Subsystem')), 1, [])
    prefix = runtime.block_paths{id}(1:end-1);
    if (numel (path) > numel (prefix) && isequal (path(1:numel(prefix)), prefix))
      relative = path(numel(prefix)+1:end);
      diagram = ob_model_at (runtime.model.blocks(id).value, relative(1:end-1));
      if (relative(end) > numel (diagram.blocks)), error ('ob_runtime_outputs: block path does not exist'); endif
      [unused, count] = ob_block_ports (diagram.blocks(relative(end)));
      if (port > count), error ('ob_runtime_outputs: output port does not exist'); endif
      if (! runtime.states{id}.initialized)
        error ('ob_runtime_outputs: conditional child has not executed');
      endif
      value = outputs (runtime.states{id}.child, relative, port);
      return;
    endif
  endfor
  error ('ob_runtime_outputs: block path does not exist');
endfunction

function next = capture (type, state, input, interval, id)
  if (! isnumeric (input) || ! isreal (input) || ! isequal (size (state), size (input)) ...
      || any (! isfinite (input(:))))
    error ('ob_run: discrete input at block %d must be finite, real, and match its state shape', id);
  endif
  if (strcmp (type, 'Unit Delay')), next = input;
  else next = state + interval * input; endif
  if (any (! isfinite (next(:))))
    error ('ob_run: discrete update at block %d produced nonfinite state', id);
  endif
endfunction

function yes = valid_time (value)
  yes = isnumeric (value) && isreal (value) && isscalar (value) && isfinite (value);
endfunction

function yes = time_equal (a, b, origin, spacing = Inf)
  % Preserve decimal coincidence without merging a whole short-period hit at
  % large absolute times; the bound includes inactive descendants' clocks.
  yes = isfinite (a) && isfinite (b) ...
        && abs (a - b) <= min (spacing/16, 8 * eps(1) * max([realmin() abs(origin) abs(a) abs(b)]));
endfunction

function spacing = clock_spacing (runtime)
  periods = runtime.rates(runtime.explicit,1)';
  if (isfield(runtime,'nested_clocks') && !isempty(runtime.nested_clocks))
    for clock = runtime.nested_clocks, periods(end+1) = clock.rate(1); endfor
  endif
  spacing = min ([periods Inf]);
endfunction

function validate_context (runtime)
  required = {'kind', 'model', 'root_block_count', 'signal_map', 'block_paths', ...
              'order', 'edges', 'stateful', 'options', 'types', 'rates', ...
              'delayed', 'transitions', 'explicit', 'inherited', 'integrators', ...
              'states', 'pending', 'pending_valid', 'sample_hits', 'ticks', ...
              'next_hits', 'start_time', 'time', 'integration_steps', 'current'};
  if (! isstruct (runtime) || ! isscalar (runtime) || ! isfield (runtime, 'kind') ...
      || ! isequal (runtime.kind, 'octave-blocks-runtime-v1') ...
      || ! all (isfield (runtime, required)) || ! valid_time (runtime.time))
    error ('ob_runtime: expected a context returned by ob_runtime_init');
  endif
endfunction
