function value = ob_runtime_engine (action, varargin)
  switch (action)
    case 'step'
      validate_context (varargin{1});
      value = advance (varargin{:});
    case 'init'
      value = initialize (varargin{:});
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

function runtime = initialize (model, start_time, options, origin = [], embedded = false, major = true, events = struct (), reset_source = [])
  if (! valid_time (start_time))
    error ('ob_runtime_init: start_time must be a finite real numeric scalar');
  endif
  options = ob_solver_options (options);
  runtime.kind = 'octave-blocks-runtime-v1';
  % Conditional subsystems hold scalar InitialOutputs expanded to their port
  % shapes from the start, also when their first evaluation comes after it
  % (explicit sample offset), as Simulink and the C exporters do.  Embedded
  % children are expanded by their conditional parent (ob_conditional_eval).
  % A malformed model is left to ob_compile_model, which reports it.
  if (! embedded)
    try
      model = ob_expand_initial_outputs (model);
    catch
    end_try_catch
  endif
  [runtime.model, runtime.signal_map, runtime.block_paths] = ob_compile_model (model);
  runtime.model.continuous_controls = ob_has_continuous_control (runtime.model);
  if (runtime.model.continuous_controls && ! options.zero_crossings)
    error ('ob_runtime_init: continuous subsystem controls require zero_crossings=true');
  endif
  runtime.root_block_count = numel (model.blocks);
  [runtime.order, runtime.edges, runtime.stateful, runtime.model.algebraic_loops] = ...
      ob_execution_order (runtime.model, true);
  runtime.model = ob_prepare_runtime_model (runtime.model, runtime.order);
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
  if (! embedded), ob_require_runtime_support (model, options); endif
  runtime.reset_memory = cell (1, n);
  for id = reshape (find (runtime.stateful), 1, [])
    if (strcmp (runtime.types{id}, 'Conditional Subsystem'))
      descriptor = ob_runtime_execution (runtime.model,id);
      runtime.states{id} = ob_conditional_state (runtime.model.blocks(id).value, runtime.time, descriptor.options);
    elseif (strcmp (runtime.types{id}, 'Transport Delay'))
      runtime.states{id} = ob_transport_delay ('init');
    elseif (strcmp (runtime.types{id}, 'Limited Integrator'))
      params = ob_runtime_parameters (runtime.model, id);
      runtime.states{id} = params.initial;
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
  if (!isempty(reset_source))
    runtime = ob_restore_reset_children(runtime,reset_source);
  endif
  runtime = process_hits (runtime, runtime.time, major, [], events);
  if (embedded), runtime.major_current = runtime.current; endif
endfunction

function runtime = advance (runtime, next_time)
  if (! isfield (runtime, 'event_memory')), runtime.event_memory = struct (); endif
  if (! isfield (runtime, 'events'))
    runtime.events = struct ('time', {}, 'path', {}, 'type', {}, 'channel', {}, ...
                            'side', {}, 'direction', {}, 'boundary', {});
  endif
  % valid_time (double (x)) equals valid_time (x), so one check suffices
  % (valid_time and runtime_plan are inlined: every step runs them).
  valid = isnumeric (next_time) && isreal (next_time) && isscalar (next_time) && isfinite (next_time);
  if (valid), next_time = double (next_time); endif
  if (! valid || next_time <= runtime.time ...
      || ! isfinite (next_time - runtime.time))
    error ('ob_runtime_step: next_time must be finite and greater than the current time');
  endif
  plan = [];
  if (isfield (runtime.model, 'runtime_info'))
    info = runtime.model.runtime_info;
    if (isfield (info, 'plan') && isscalar (info) && isfield (info, 'kind') ...
        && strcmp (info.kind, 'octave-blocks-runtime-info-v1'))
      plan = info.plan;
    endif
  endif
  if (! isempty (plan) && lite_step (runtime, plan))
    % Without clocks, discrete blocks, conditional bodies, resets, events or
    % unlearned delay shapes, the general loop below makes exactly one
    % integration to next_time and a hit whose only effects are the output
    % evaluation, the delays' right-limit records and the time update.
    [runtime.states, accepted] = ob_runtime_integrate (runtime.model, runtime.edges, ...
        runtime.order, num2cell (plan.integrator_blocks), runtime.states, runtime.time, ...
        next_time, runtime.options, runtime.event_memory, plan);
    runtime.integration_steps += accepted;
    if (isfield (plan, 'program'))
      % ob_runtime_eval's own program path, without its call overhead.
      runtime.current = ob_program_eval (plan.program, plan.parameters, runtime.model, ...
                                         next_time, runtime.states, false, []);
    else
      [runtime.current, runtime.states] = ob_runtime_eval (runtime.model, runtime.edges, ...
          runtime.order, next_time, runtime.states);
    endif
    for id = plan.delay_blocks
      source = plan.sources{id};
      runtime.states{id} = ob_transport_delay ('record', plan.parameters{id}, runtime.states{id}, ...
                                               next_time, runtime.current{source}, 'right', id);
    endfor
    runtime.time = next_time;
    return;
  endif
  dt = next_time - runtime.time;
  event_dispatches = 0;
  spacing = clock_spacing (runtime);
  captures = runtime.inherited & runtime.delayed;
  if (any (captures))
    for id = reshape (find (captures), 1, [])
      source = block_source (runtime, id, plan);
      runtime.pending{id} = capture (runtime.types{id}, runtime.states{id}, runtime.current{source}, dt, id);
      runtime.pending_valid(id) = true;
    endfor
  endif
  while (runtime.time < next_time)
    nested = [];
    if (isfield(runtime,'nested_clocks') && !isempty(runtime.nested_clocks))
      nested = [runtime.nested_clocks.next];
    endif
    event = min ([runtime.next_hits nested Inf]);
    at_output = ! (event < next_time && ! time_equal (event, next_time, runtime.start_time, spacing));
    if (at_output), event = next_time; endif
    if (event <= runtime.time)
      error ('ob_run: discrete schedule cannot advance time');
    endif
    if (! isempty (plan) && ! plan.conditional)
      % Without conditional bodies the continuous paths are the integrators.
      continuous_paths = num2cell (plan.integrator_blocks);
    else
      continuous_paths = ob_continuous_paths (runtime.model, runtime.states);
    endif
    scheduled = event;
    [runtime.states, accepted, crossings, runtime.event_memory, reached, dispatch_flow] = ob_runtime_integrate (runtime.model, runtime.edges, ...
        runtime.order, continuous_paths, runtime.states, runtime.time, event, runtime.options, runtime.event_memory, plan);
    % numfields is the builtin equivalent of isempty (fieldnames (struct)).
    reconcile = numfields (dispatch_flow) > 0;
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
    elseif (time_equal(reached,scheduled,runtime.start_time,spacing))
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
    frame = struct ('spacing',spacing);
    if (reconcile), frame.reconcile = true; frame.flow = dispatch_flow; endif
    runtime = process_hits (runtime, event, at_output, [], frame, plan);
  endwhile
endfunction

function yes = lite_step (runtime, plan)
  % True when process_hits would only evaluate outputs and record delays.
  % Each condition below rules out one of its other effects (clocked hits,
  % pending captures, sampled blocks, conditional or nested-clock dispatch,
  % integrator resets, delay-shape probes, zero-crossing reconciliation).
  % plan.lite (no conditional, Unit Delay, Discrete Integrator or Rate
  % Transition blocks and no resettable integrator) implies that the
  % explicit, delayed and transition masks are all false.
  yes = plan.lite && all (runtime.next_hits == Inf) ...
        && ! (isfield (runtime.options, 'zero_crossings') && runtime.options.zero_crossings) ...
        && ! (isfield (runtime, 'embedded') && runtime.embedded) ...
        && ! (isfield (runtime, 'nested_clocks') && ! isempty (runtime.nested_clocks));
  for id = plan.delay_blocks
    if (! yes), return; endif
    yes = ! isempty (runtime.states{id}.shape);
  endfor
endfunction

function plan = runtime_plan (model)
  % The prepared evaluation plan, or [] for caches that predate it.
  plan = [];
  if (isfield (model, 'runtime_info'))
    info = model.runtime_info;
    if (isfield (info, 'plan') && isscalar (info) && isfield (info, 'kind') ...
        && strcmp (info.kind, 'octave-blocks-runtime-info-v1'))
      plan = info.plan;
    endif
  endif
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

function runtime = process_hits (runtime, time, at_output, inherited_interval = [], events = struct (), plan = 'lookup')
  % plan: the caller's runtime_plan (runtime.model), or 'lookup'.
  if (ischar (plan)), plan = runtime_plan (runtime.model); endif
  events.accepted = true;
  events.options = runtime.options;
  if (!isfield(events,'origin')), events.origin = runtime.start_time; endif
  if (!isfield(events,'paths')), events.paths = {}; endif
  if (!isfield(events,'spacing')), events.spacing = clock_spacing(runtime); endif
  reconcile = isfield(events,'reconcile') && events.reconcile;
  if (reconcile), at_output = false; events.paths = {}; endif
  nested_due = [];
  if (!reconcile && isfield(runtime,'nested_clocks') && !isempty(runtime.nested_clocks))
    % Vectorize the nested-clock due check using native struct-field extraction
    % and element-wise arithmetic rather than a scalar iteration.
    nc = runtime.nested_clocks;
    nexts   = [nc.next];
    offsets2 = reshape([nc.rate], 2, []);   % 2-by-K; row 2 = rate(2) = offset
    at_start = (time == runtime.start_time) & (offsets2(2,:) > 0);
    sp = events.spacing;
    tol = min(sp/16, 8*eps(1) * max([realmin() abs(runtime.start_time) abs(time)]));
    due_mask = !at_start & isfinite(nexts) & (abs(nexts - time) <= tol);
    nested_due = find(due_mask);
    if (!isempty(nested_due))
      events.paths = [events.paths {nc(nested_due).path}];
    endif
  endif
  if (!reconcile && isfield(runtime,'embedded') && runtime.embedded)
    [runtime.ticks, runtime.next_hits] = ob_clock_rebase(runtime.rates,runtime.explicit,runtime.start_time,time,events.spacing);
  endif
  due = false (size (runtime.explicit));
  % Index loops below are guarded by any (): most hits have no work there.
  if (!reconcile && any (runtime.explicit))
    for id = reshape (find (runtime.explicit), 1, [])
      due(id) = ! (time == runtime.start_time && runtime.rates(id, 2) > 0) ...
                && time_equal (runtime.next_hits(id), time, runtime.start_time, events.spacing);
    endfor
  endif
  % Commit all previous captures simultaneously before evaluating any input.
  commits = runtime.delayed & runtime.pending_valid & (due | (at_output & runtime.inherited));
  if (any (commits))
    for id = reshape (find (commits), 1, [])
      runtime.states{id} = runtime.pending{id};
      runtime.pending_valid(id) = false;
    endfor
  endif
  if (isempty (plan)), sampled = runtime.transitions | strcmp (runtime.types, 'Conditional Subsystem');
  else sampled = runtime.transitions | plan.conditional_mask; endif
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
  % Both helpers return at once without resettable integrators or delays.
  if (isempty (plan) || ! isempty (plan.resettable))
    runtime = apply_integrator_resets (runtime, time, sample, inherited_interval, events, flow);
  endif
  if (isempty (plan)), delays = ob_runtime_type_ids (runtime.model, 'delay_ids', 'Transport Delay');
  else delays = plan.delay_blocks; endif
  if (! isempty (delays))
    runtime = learn_delay_shapes (runtime, delays, time, sample, inherited_interval, events, flow);
  endif
  if (! isempty (plan) && isfield (plan, 'program'))
    % ob_runtime_eval's program path (no sampled or lifecycle blocks).
    runtime.current = ob_program_eval (plan.program, plan.parameters, runtime.model, ...
                                       time, runtime.states, false, flow);
  else
    [runtime.current, runtime.states] = ob_runtime_eval (runtime.model, runtime.edges, ...
        runtime.order, time, runtime.states, false, sample, inherited_interval, events, flow);
  endif
  for id = delays
    % Accepted hits record the right limit of each delayed input.
    source = block_source (runtime, id, plan);
    params = ob_runtime_parameters (runtime.model, id);
    runtime.states{id} = ob_transport_delay ('record', params, runtime.states{id}, ...
                                             time, runtime.current{source}, 'right', id);
  endfor
  hit = due | (at_output & runtime.inherited) | sample;
  if (any (hit))
    for id = reshape (find (hit), 1, [])
      runtime.sample_hits{id}(end + 1) = time;
    endfor
  endif
  for id = reshape (find (due & runtime.delayed), 1, [])
    source = block_source (runtime, id, plan);
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

function runtime = apply_integrator_resets (runtime, time, sample, inherited_interval, events, flow)
  % Limited Integrator resets are sampled at accepted hits.  A side-effect-free
  % evaluation supplies each reset signal; triggered states return to their
  % initial value before the committed evaluation, so it is visible at once.
  resettable = [];
  for id = ob_runtime_type_ids (runtime.model, 'limited_ids', 'Limited Integrator')
    params = ob_runtime_parameters (runtime.model, id);
    if (! strcmp (params.reset, 'none')), resettable(end+1) = id; endif
  endfor
  if (isempty (resettable)), return; endif
  if (! isfield (runtime, 'reset_memory') || numel (runtime.reset_memory) != numel (runtime.states))
    runtime.reset_memory = cell (1, numel (runtime.states));
  endif
  probe = ob_runtime_eval (runtime.model, runtime.edges, runtime.order, time, ...
                           runtime.states, false, sample, inherited_interval, events, flow);
  fixed_step = isfield (runtime, 'options') && strcmp (runtime.options.solver, 'rk4');
  for id = resettable
    params = ob_runtime_parameters (runtime.model, id);
    sources = block_source (runtime, id);
    signal = probe{sources(2)};
    if ((! isnumeric (signal) && ! islogical (signal)) || ! isreal (signal) ...
        || ! isscalar (signal) || ! isfinite (signal))
      error ('ob_run: Limited Integrator block %d reset must be a finite real scalar', id);
    endif
    signal = double (signal);
    previous = runtime.reset_memory{id};
    switch (params.reset)
      case 'level'
        % Simulink 'level': reset while the signal is nonzero and when it
        % changes from nonzero to zero.  RK4 samples that change at the next
        % hit, as Simulink ode4 does at its next major step.  Adaptive
        % solvers need no sampled reset for it: the hold ends when the
        % signal becomes zero, with the state still at the initial value
        % from the last nonzero hit, so a reset at that instant (where
        % Simulink's variable-step solvers apply it) changes nothing.
        fire = signal != 0 || (fixed_step && ! isempty (previous) && previous != 0);
      case 'level hold'
        % Simulink 'level hold': reset only while the signal is nonzero.
        fire = signal != 0;
      otherwise
        fire = false;
        if (! isempty (previous))
          before = sign (previous); after = sign (signal);
          rising = (before < 0 && after >= 0) || (before == 0 && after > 0);
          falling = (before > 0 && after <= 0) || (before == 0 && after < 0);
          fire = (rising && any (strcmp (params.reset, {'rising', 'either'}))) ...
                 || (falling && any (strcmp (params.reset, {'falling', 'either'})));
        endif
    endswitch
    if (fire), runtime.states{id} = params.initial; endif
    runtime.reset_memory{id} = signal;
  endfor
endfunction

function runtime = learn_delay_shapes (runtime, delays, time, sample, inherited_interval, events, flow)
  % A Transport Delay with a scalar initial output learns its input shape
  % when it first records, after the first committed evaluation.  Learn it
  % before that evaluation instead, so the very first output is already
  % broadcast to the input shape.  The probe evaluation is side-effect free:
  % its returned states are discarded, so no conditional child commits twice.
  % If it fails, the committed evaluation reports any real model error.
  pending = [];
  for id = delays
    if (isempty (runtime.states{id}.shape))
      params = ob_runtime_parameters (runtime.model, id);
      if (isscalar (params.initial)), pending(end+1) = id; endif
    endif
  endfor
  if (isempty (pending)), return; endif
  try
    probe = ob_runtime_eval (runtime.model, runtime.edges, runtime.order, time, ...
                             runtime.states, false, sample, inherited_interval, events, flow);
  catch
    return;  % Fall back to learning the shapes at the first record.
  end_try_catch
  for id = pending
    try
      source = block_source (runtime, id);
      params = ob_runtime_parameters (runtime.model, id);
      runtime.states{id} = ob_transport_delay ('shape', params, runtime.states{id}, probe{source}, id);
    catch
      % The first record validates this input and reports its error.
    end_try_catch
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
      source = block_source (runtime,id);
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
    source = block_source (runtime,id);
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
  % A flat root block normally occupies its own signal-map slot. Virtual and
  % nested interfaces retain the general lookup unless this exact path agrees.
  if (path(1)<=numel(runtime.signal_map))
    item = runtime.signal_map(path(1));
    if (isequal(item.path,path))
      if (port>numel(item.outputs)), error('ob_runtime_outputs: output port does not exist'); endif
      value = runtime.current{item.outputs(port)};
      return;
    endif
  endif
  for item = runtime.signal_map
    if (isequal (item.path, path))
      if (port > numel (item.outputs)), error ('ob_runtime_outputs: output port does not exist'); endif
      value = runtime.current{item.outputs(port)};
      return;
    endif
  endfor
  for id = conditional_ids (runtime)
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

function source = block_source (runtime, id, plan = [])
  % A prepared plan carries its own complete source map.
  if (! isempty (plan))
    source = plan.sources{id}; return;
  endif
  if (isfield(runtime.model,'runtime_info'))
    info = runtime.model.runtime_info;
    if (isstruct(info) && isscalar(info) && all(isfield(info,{'kind','sources'})) ...
        && ischar(info.kind) && strcmp(info.kind,'octave-blocks-runtime-info-v1') ...
        && iscell(info.sources) && numel(info.sources)==numel(runtime.model.blocks))
      source = info.sources{id}; return;
    endif
  endif
  source = runtime.edges(runtime.edges(:,2)==id,1);
endfunction

function ids = conditional_ids (runtime)
  if (isfield(runtime.model,'runtime_info'))
    info = runtime.model.runtime_info;
    if (isstruct(info) && isscalar(info) && all(isfield(info,{'kind','conditional_ids'})) ...
        && ischar(info.kind) && strcmp(info.kind,'octave-blocks-runtime-info-v1'))
      candidate = info.conditional_ids;
      if (isnumeric(candidate) && isreal(candidate) && ndims(candidate)==2 && rows(candidate)==1 ...
          && all(isfinite(candidate)) && all(candidate==fix(candidate)) ...
          && all(candidate>=1 & candidate<=numel(runtime.model.blocks)) && all(diff(candidate)>0))
        ids = candidate; return;
      endif
    endif
  endif
  ids = reshape(find(strcmp(runtime.types,'Conditional Subsystem')),1,[]);
endfunction

function next = capture (type, state, input, interval, id)
  if (! isnumeric (input) || ! isreal (input) || ! size_equal (state, input) ...
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
    % Extract all nested-clock periods in one vectorized operation instead of
    % a scalar-append loop.  [structs.field] returns a 1-by-N numeric row when
    % each field is a 1-by-2 rate vector; take every other element (column 1).
    nested_rates = [runtime.nested_clocks.rate];
    periods = [periods nested_rates(1:2:end)];
  endif
  spacing = min ([periods Inf]);
endfunction

function validate_context (runtime)
  % The required field list is a constant of this code (built once).
  persistent required = {'kind', 'model', 'root_block_count', 'signal_map', 'block_paths', ...
              'order', 'edges', 'stateful', 'options', 'types', 'rates', ...
              'delayed', 'transitions', 'explicit', 'inherited', 'integrators', ...
              'states', 'pending', 'pending_valid', 'sample_hits', 'ticks', ...
              'next_hits', 'start_time', 'time', 'integration_steps', 'current'};
  % strcmp settles ordinary contexts; isequal keeps its broader matching
  % (e.g. character codes) for anything else.
  if (! isstruct (runtime) || ! isscalar (runtime) || ! isfield (runtime, 'kind') ...
      || ! ((ischar (runtime.kind) && strcmp (runtime.kind, 'octave-blocks-runtime-v1')) ...
            || isequal (runtime.kind, 'octave-blocks-runtime-v1')) ...
      || ! all (isfield (runtime, required)) || ! valid_time (runtime.time))
    error ('ob_runtime: expected a context returned by ob_runtime_init');
  endif
endfunction
