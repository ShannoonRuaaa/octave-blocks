function varargout = ob_conditional_buffers (action, varargin)
  % Simulink's shared Outport buffers in an enabled body with inner clocks
  % (ob_conditional_gating): a clocked block that drives an Outport
  % directly shows that Outport's held value to every reader until it
  % executes after the body is (re)initialized, and again after the Outport
  % is reset while disabled (simulink-conditional-outputs-reference.json,
  % gating_*).  The block's state, which is its output between hits, holds
  % that value; a Unit Delay or Discrete Integrator keeps its real state as
  % the pending capture that its next hit commits, so every evaluation,
  % flow and checkpoint sees the same buffer.  Actions:
  %   state = ob_conditional_buffers ('init', state, child, descriptor, time, events, major, reset_source)
  %       initialize the body (ob_runtime_engine 'init-child') with each
  %       shared block that does not execute at TIME starting from its
  %       port's held value;
  %   child = ob_conditional_buffers ('substitute', child, gating, ports, values)
  %       PORTS were just reset to VALUES while disabled;
  %   gating = ob_conditional_buffers ('analyse', source, descriptor)
  %       the gating analysis of a body model or of a compiled child runtime;
  %   yes = ob_conditional_buffers ('hit', period, offset, origin, time)
  %       whether a clock hits at TIME (origin + offset + k*period).
  switch (action)
    case 'init', varargout{1} = init (varargin{:});
    case 'substitute', varargout{1} = substitute (varargin{:});
    case 'analyse', varargout{1} = analyse (varargin{:});
    case 'hit', varargout{1} = clock_hit (varargin{:});
    otherwise, error ('ob_conditional_buffers: unknown action %s', action);
  endswitch
endfunction

function state = init (state, child, descriptor, time, events, major, reset_source)
  if (isempty (state.gating) || ! isfield (state.gating, 'paths'))
    state.gating = analyse (child, descriptor);
  endif
  gating = state.gating;
  skip = [];
  do
    % Shared blocks that do not execute now start from their port's value.
    model = child; plan = zeros (1, 0); real = {};
    for port = find (gating.shared > 0)
      gate = gating.shared(port);
      if (any (skip == gate) || clock_hit (gating.rates(gate, 1), gating.rates(gate, 2), events.origin, time))
        continue;
      endif
      location = gating.paths{gate};
      diagram = ob_model_at (model, location(1:end-1));
      initial = diagram.blocks(location(end)).value;
      % Until its port's shape is known the block keeps its own condition.
      if (! size_equal (state.outputs{port}, initial)), continue; endif
      diagram.blocks(location(end)).value = state.outputs{port};
      model = ob_set_model_at (model, location(1:end-1), diagram);
      plan(end+1) = gate; real{end+1} = initial;
    endfor
    runtime = ob_runtime_engine ('init-child', model, time, events.options, events.origin, ...
                                 true, major, events, reset_source);
    % The hit test mirrors the runtime's clocks; should it ever disagree,
    % initialize again without that block's substitution.
    missed = plan(cellfun (@(h) ! isempty (h) && h(end) == time, runtime.sample_hits(plan)));
    skip = [skip missed];
  until (isempty (missed))
  for k = 1:numel (plan)
    gate = plan(k);
    runtime.model.blocks(gate).value = real{k};
    if (gating.delayed(gate))
      runtime.pending{gate} = real{k}; runtime.pending_valid(gate) = true;
    endif
  endfor
  state.child = runtime;
endfunction

function child = substitute (child, gating, ports, values)
  for k = 1:numel (ports)
    gate = gating.shared(ports(k));
    if (gate == 0 || ! size_equal (values{k}, child.states{gate})), continue; endif
    if (gating.delayed(gate) && ! child.pending_valid(gate))
      % Its next hit outputs the state it would have output.
      child.pending{gate} = child.states{gate}; child.pending_valid(gate) = true;
    endif
    child.states{gate} = values{k};
  endfor
endfunction

function gating = analyse (source, descriptor)
  % SOURCE: the body model to initialize (with its inputs) or a compiled
  % child runtime (contexts checkpointed before the analysis was cached).
  count = numel (descriptor.output_ids);
  if (isfield (source, 'kind'))
    flat = source.model; signal_map = source.signal_map; edges = source.edges;
    paths = source.block_paths;
  else
    [flat, signal_map, paths] = ob_compile_model (source);
    [~, edges] = ob_execution_order (flat, true);
  endif
  out_blocks = zeros (1, count);
  for output = 1:count
    id = descriptor.output_ids(output); port = descriptor.output_ports(output);
    for item = signal_map
      if (isequal (item.path, id)), out_blocks(port) = item.outputs(1); break; endif
    endfor
  endfor
  types = {flat.blocks.type};
  gating = ob_conditional_gating (types, flat.sample_times, edges, out_blocks);
  gating.out_blocks = out_blocks;
  gating.rates = double (flat.sample_times);
  gating.delayed = strcmp (types, 'Unit Delay') | strcmp (types, 'Discrete Integrator');
  gating.paths = paths;
endfunction

function yes = clock_hit (period, offset, origin, time)
  % The same hit times as the runtime's clocks: origin + offset + k*period.
  k = round ((time - origin - offset) / period);
  candidate = origin + offset + k * period;
  yes = k >= 0 && abs (candidate - time) <= 8 * eps (1) * max ([realmin() abs(origin) abs(candidate) abs(time)]);
endfunction
