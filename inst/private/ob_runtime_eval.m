function [current, states] = ob_runtime_eval (model, edges, order, time, states, left_limit = false, sample = [], inherited_interval = [], events = struct (), flow = struct ())
  info = [];
  if (isfield(model,'runtime_info')), info = model.runtime_info; endif
  % A prepared evaluation plan carries numeric dispatch codes and its own
  % source/loop maps; it is trusted inside a same-version cache.  Without it
  % (older checkpoints, other cache kinds), types dispatch by name and the
  % cache structure is checked per call.
  planned = isfield (info, 'plan') && isscalar (info) && isfield (info, 'kind') ...
            && strcmp (info.kind, 'octave-blocks-runtime-info-v1');
  if (planned)
    plan = info.plan;
    % A plan prepared by the engine carries the evaluation program of its
    % context's execution order for models without lifecycle blocks (see
    % ob_program_eval).  Every caller evaluates a model with its context's
    % order, and for these acyclic graphs any order that evaluates each
    % block after its sources gives the same values, so ORDER is not
    % compared here (that comparison cost as much as the evaluation saves).
    if (isfield (plan, 'program'))
      current = ob_program_eval (plan.program, plan.parameters, model, time, states, left_limit, flow);
      return;
    endif
  endif
  count = numel (model.blocks);
  current = cell (1, count);
  blocks = model.blocks;
  if (planned)
    cached = true;
    codes = plan.codes;
    source_map = plan.sources;
    has_loops = plan.loops;
    if (has_loops)
      loops = model.algebraic_loops;
      loop_at = plan.loop_at;
      solved = false (1, numel (loops));
    endif
  else
    loops = {};
    if (isfield (model, 'algebraic_loops')), loops = model.algebraic_loops; endif
    % Preparation validates immutable graph indices. At a solver stage check
    % cache structure/version; do not rescan the complete loop map's values.
    cached = isstruct(info) && isscalar(info) ...
             && all(isfield(info,{'kind','loop_at','sources'})) ...
             && ischar(info.kind) && strcmp(info.kind,'octave-blocks-runtime-info-v1') ...
             && isnumeric(info.loop_at) && isreal(info.loop_at) ...
             && rows(info.loop_at)==1 && numel(info.loop_at)==count ...
             && iscell(info.sources) && numel(info.sources)==count;
    if (cached)
      loop_at = info.loop_at;
      source_map = info.sources;
    else
      loop_at = zeros (1, count);
      if (!isempty(loops))
        % Build the loop membership vector in one pass using native accumarray-
        % style indexing rather than a k-iteration scalar write loop.
        lens   = cellfun (@numel, loops);
        groups = repelem (1:numel(loops), lens);
        ids_flat = [loops{:}];
        loop_at(ids_flat) = groups;
      endif
      % Resolve every block's inputs once; the lookup has no side effects.
      source_map = cell (1, count);
      for id = 1:count, source_map{id} = edges(edges(:, 2) == id, 1)'; endfor
    endif
    codes = zeros (1, count);
    for id = 1:count, codes(id) = type_code (blocks(id).type); endfor
    has_loops = ! isempty (loops);
    solved = false (1, numel (loops));
  endif
  % State outputs (code 18) never change during an evaluation, and the
  % execution order puts each state block before all of its readers, so
  % assign them together and leave them out of the loop.
  held = codes(order) == 18;
  if (any (held))
    current(order(held)) = states(order(held));
    order = order(! held);
  endif
  has_modes = isfield(flow,'modes');
  conditional_ready = false;
  for id = order
    if (has_loops)
      group = loop_at(id);
      if (group)
        if (! solved(group))
          [current, states] = ob_algebraic_solve (model, edges, loops{group}, current, states, time);
          solved(group) = true;
        endif
        continue;
      endif
    endif
    code = codes(id);
    sources = source_map{id};
    % Codes are ordered by how often solver stages meet them.  Each branch
    % keeps the input-count check and message of the named dispatch.
    if (code == 5)
      % Gain
      if (numel (sources) != 1), require_inputs (sources, 1, blocks(id).type); endif
      current{id} = blocks(id).value * current{sources};
    elseif (code == 6)
      % Sum
      if (numel (sources) != 2), require_inputs (sources, 2, blocks(id).type); endif
      current{id} = current{sources(1)} + current{sources(2)};
    elseif (code == 12)
      % Scope, Inport, Outport
      if (numel (sources) != 1), require_inputs (sources, 1, blocks(id).type); endif
      current{id} = current{sources};
    elseif (code == 8 || code == 9 || code == 10)
      % Saturation, Dead Zone, Switch
      mode = [];
      if (has_modes), mode = flow.modes{id}; endif
      current{id} = ob_control_output (blocks(id), current(sources), id, mode);
    elseif (code == 20)
      % The plan carries the prepared parameters (see ob_runtime_parameters).
      if (planned), params = plan.parameters{id};
      else params = ob_runtime_parameters (model, id); endif
      current{id} = ob_delay_output (params, states{id}, time, left_limit);
    elseif (code == 11)
      % Function
      if (isempty (sources)), error ('ob_run: Function needs an input'); endif
      current{id} = feval (blocks(id).name, current{sources});
    elseif (code == 7)
      % Product
      if (numel (sources) != 2), require_inputs (sources, 2, blocks(id).type); endif
      current{id} = current{sources(1)} * current{sources(2)};
    elseif (code == 2)
      % Constant
      if (! isempty (sources)), require_inputs (sources, 0, blocks(id).type); endif
      current{id} = blocks(id).value;
    elseif (code == 3)
      % Time
      if (! isempty (sources)), require_inputs (sources, 0, blocks(id).type); endif
      current{id} = time;
    elseif (code == 4)
      % Step
      if (! isempty (sources)), require_inputs (sources, 0, blocks(id).type); endif
      value = blocks(id).value;
      if (! isnumeric (value) || numel (value) != 3)
        error ("ob_run: Step value must be [time initial final]");
      endif
      if (time < value(1) || (left_limit && time == value(1)))
        current{id} = value(2);
      else
        current{id} = value(3);
      endif
    elseif (code == 1)
      % External Input
      if (! isempty (sources)), require_inputs (sources, 0, blocks(id).type); endif
      current{id} = ob_input_value (model.inputs{blocks(id).value}, time, left_limit);
    elseif (code == 19)
      params = ob_runtime_parameters (model, id);
      current{id} = min (max (states{id}, params.lower), params.upper);
    elseif (code == 13)
      % Multiple Function
      if (isempty (sources)), error ('ob_run: Function needs an input'); endif
      returned = cell (1, blocks(id).value);
      [returned{:}] = feval (blocks(id).name, current{sources});
      current{id} = returned;
    elseif (code == 14)
      % Function Output
      if (numel (sources) != 1), require_inputs (sources, 1, blocks(id).type); endif
      current{id} = current{sources}{blocks(id).value};
    elseif (code == 16)
      % Conditional Output
      if (numel (sources) != 1), require_inputs (sources, 1, blocks(id).type); endif
      current{id} = current{sources}.outputs{blocks(id).value};
    elseif (code == 17)
      % Rate Transition
      if (numel (sources) != 1), require_inputs (sources, 1, blocks(id).type); endif
      if (! isempty (sample) && sample(id))
        validate_discrete_input (states{id}, current{sources}, id);
        states{id} = current{sources};
      endif
      current{id} = states{id};
    elseif (code == 15)
      % Conditional Subsystem
      block = blocks(id);
      inputs = current(sources);
      if (isempty (sample)), sample = false (1, count); endif
      % Most RHS graphs contain no atomic child. Prepare child-only flags
      % once, lazily, rather than on every evaluation of every flat body.
      if (!conditional_ready)
        has_children = isfield(flow,'children');
        has_origin = isfield(events,'origin');
        has_spacing = isfield(events,'spacing');
        has_options = isfield(events,'options');
        has_reconcile = isfield(events,'reconcile');
        has_paths = isfield(events,'paths');
        accepted = isfield(events,'accepted') && events.accepted;
        descriptor_fields = {'kind','options','needs_flow','clocked','continuous_controls', ...
                             'input_ports','output_ids','output_ports'};
        option_fields = {'mode','states','outputs','initial_outputs','initial_control','control'};
        conditional_map = {};
        if (cached && isfield(info,'conditional') && iscell(info.conditional) ...
            && numel(info.conditional)==count)
          conditional_map = info.conditional;
        endif
        conditional_ready = true;
      endif
      child_events = struct ('origin',time,'paths',{{}});
      if (has_origin), child_events.origin = events.origin; endif
      if (has_spacing), child_events.spacing = events.spacing; endif
      if (has_options), child_events.options = events.options; endif
      if (has_reconcile), child_events.reconcile = events.reconcile; endif
      child_flow = struct ();
      if (has_children && !isempty(flow.children{id}))
        child_flow = flow.children{id};
      endif
      child_events.flow = child_flow;
      child_events.accepted = accepted;
      descriptor = [];
      if (!isempty(conditional_map)), descriptor = conditional_map{id}; endif
      if (!(isstruct(descriptor) && isscalar(descriptor) ...
            && all(isfield(descriptor,descriptor_fields)) ...
            && ischar(descriptor.kind) && strcmp(descriptor.kind,'octave-blocks-execution-descriptor-v1') ...
            && isstruct(descriptor.options) && isscalar(descriptor.options) ...
            && all(isfield(descriptor.options,option_fields))))
        descriptor = ob_runtime_execution (model,id);
      endif
      execution = descriptor.options;
      child_events.execution_descriptor = descriptor;
      if (has_paths)
        for path = events.paths
          if (numel(path{1}) > 1 && path{1}(1) == id)
            child_events.paths{end+1} = path{1}(2:end);
          endif
        endfor
      endif
      if (sample(id) || !isempty(child_events.paths))
        interval = inherited_interval;
        if (sample(id) && model.sample_times(id,1) > 0)
          interval = model.sample_times(id,1);
        endif
        fixed_interval = sample(id) && model.sample_times(id,1) > 0;
        states{id} = ob_conditional_eval (block.value, states{id}, inputs, time, interval, sample(id), child_events, fixed_interval);
      elseif (accepted && strcmp(execution.control,'continuous'))
        if (strcmp(execution.mode,'enabled'))
          states{id} = ob_conditional_control (block.value,states{id},inputs,time,child_events);
        else
          states{id} = ob_conditional_eval (block.value,states{id},inputs,time,[],true,child_events);
        endif
      elseif (accepted && strcmp(execution.mode,'enabled') && descriptor.continuous_controls)
        states{id} = ob_conditional_gate_flow (block.value,states{id},inputs,time,child_events);
      endif
      if (strcmp (execution.mode, 'enabled') && descriptor.needs_flow)
        states{id} = ob_conditional_flow (block.value, states{id}, inputs, time, left_limit, child_flow, descriptor);
      endif
      current{id} = states{id};
    else
      error ("ob_run: unknown block type '%s'", blocks(id).type);
    endif
  endfor
endfunction

function code = type_code (type)
  % Named dispatch for models without a prepared evaluation plan; the codes
  % match ob_prepare_runtime_model's plan.
  switch (type)
    case 'External Input', code = 1;
    case 'Constant', code = 2;
    case 'Time', code = 3;
    case 'Step', code = 4;
    case 'Gain', code = 5;
    case 'Sum', code = 6;
    case 'Product', code = 7;
    case 'Saturation', code = 8;
    case 'Dead Zone', code = 9;
    case 'Switch', code = 10;
    case 'Function', code = 11;
    case {'Scope', 'Inport', 'Outport'}, code = 12;
    case 'Multiple Function', code = 13;
    case 'Function Output', code = 14;
    case 'Conditional Subsystem', code = 15;
    case 'Conditional Output', code = 16;
    case 'Rate Transition', code = 17;
    case {'Unit Delay', 'Discrete Integrator', 'Integrator'}, code = 18;
    case 'Limited Integrator', code = 19;
    case 'Transport Delay', code = 20;
    otherwise, code = 0;
  endswitch
endfunction

function validate_discrete_input (state, input, id)
  if (! isnumeric (input) || ! isreal (input) || ! size_equal (state, input) ...
      || any (! isfinite (input(:))))
    error ("ob_run: discrete input at block %d must be finite, real, and match its state shape", id);
  endif
endfunction

function require_inputs (inputs, count, type)
  if (numel (inputs) != count)
    error ("ob_run: %s needs %d input(s); got %d", type, count, numel (inputs));
  endif
endfunction
