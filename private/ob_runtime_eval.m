function [current, states] = ob_runtime_eval (model, edges, order, time, states, left_limit = false, sample = [], inherited_interval = [], events = struct (), flow = struct ())
  current = cell (1, numel (model.blocks));
  if (isempty (sample)), sample = false (1, numel (model.blocks)); endif
  loop_at = zeros (1, numel (model.blocks)); loops = {};
  if (isfield (model, 'algebraic_loops')), loops = model.algebraic_loops; endif
  cached = isfield(model,'runtime_info') && isstruct(model.runtime_info) ...
           && isfield(model.runtime_info,'kind') ...
           && strcmp(model.runtime_info.kind,'octave-blocks-runtime-info-v1');
  if (cached)
    info = model.runtime_info;
    loop_at = info.loop_at;
    source_map = info.sources;
  else
    for k = 1:numel (loops), loop_at(loops{k}) = k; endfor
  endif
  solved = false (1, numel (loops));
  for id = order
    group = loop_at(id);
    if (group)
      if (! solved(group))
        [current, states] = ob_algebraic_solve (model, edges, loops{group}, current, states, time);
        solved(group) = true;
      endif
      continue;
    endif
    block = model.blocks(id);
    if (cached), sources = source_map{id};
    else sources = edges(edges(:, 2) == id, 1); endif
    inputs = current(sources(:)');
    switch (block.type)
      case 'External Input'
        require_inputs (inputs, 0, block.type);
        current{id} = ob_input_value (model.inputs{block.value}, time, left_limit);
      case "Constant"
        require_inputs (inputs, 0, block.type);
        current{id} = block.value;
      case "Time"
        require_inputs (inputs, 0, block.type);
        current{id} = time;
      case "Step"
        require_inputs (inputs, 0, block.type);
        if (! isnumeric (block.value) || numel (block.value) != 3)
          error ("ob_run: Step value must be [time initial final]");
        endif
        if (time < block.value(1) || (left_limit && time == block.value(1)))
          current{id} = block.value(2);
        else
          current{id} = block.value(3);
        endif
      case {'Gain', 'Sum', 'Product', 'Saturation', 'Dead Zone', 'Switch', ...
            'Function', 'Scope', 'Inport', 'Outport'}
        mode = [];
        if (isfield (flow, 'modes')), mode = flow.modes{id}; endif
        current{id} = ob_direct_output (block, inputs, id, mode);
      case 'Multiple Function'
        if (isempty (inputs)), error ('ob_run: Function needs an input'); endif
        returned = cell (1, block.value);
        [returned{:}] = feval (block.name, inputs{:});
        current{id} = returned;
      case 'Function Output'
        require_inputs (inputs, 1, block.type);
        current{id} = inputs{1}{block.value};
      case 'Conditional Subsystem'
        child_events = struct ('origin',time,'paths',{{}});
        if (isfield(events,'origin')), child_events.origin = events.origin; endif
        if (isfield(events,'spacing')), child_events.spacing = events.spacing; endif
        if (isfield(events,'options')), child_events.options = events.options; endif
        if (isfield(events,'reconcile')), child_events.reconcile = events.reconcile; endif
        child_flow = struct ();
        if (isfield(flow,'children') && !isempty(flow.children{id}))
          child_flow = flow.children{id};
        endif
        child_events.flow = child_flow;
        accepted = isfield(events,'accepted') && events.accepted;
        child_events.accepted = accepted;
        descriptor = ob_runtime_execution (model,id);
        execution = descriptor.options;
        child_events.execution_descriptor = descriptor;
        if (isfield(events,'paths'))
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
      case 'Conditional Output'
        require_inputs (inputs, 1, block.type);
        current{id} = inputs{1}.outputs{block.value};
      case "Rate Transition"
        require_inputs (inputs, 1, block.type);
        if (sample(id))
          validate_discrete_input (states{id}, inputs{1}, id);
          states{id} = inputs{1};
        endif
        current{id} = states{id};
      case {"Unit Delay", "Discrete Integrator", "Integrator"}
        current{id} = states{id};
      otherwise
        error ("ob_run: unknown block type '%s'", block.type);
    endswitch
  endfor
endfunction

function validate_discrete_input (state, input, id)
  if (! isnumeric (input) || ! isreal (input) || ! isequal (size (state), size (input)) ...
      || any (! isfinite (input(:))))
    error ("ob_run: discrete input at block %d must be finite, real, and match its state shape", id);
  endif
endfunction

function require_inputs (inputs, count, type)
  if (numel (inputs) != count)
    error ("ob_run: %s needs %d input(s); got %d", type, count, numel (inputs));
  endif
endfunction
