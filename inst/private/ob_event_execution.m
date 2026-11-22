function descriptor = ob_event_execution (model, events = struct ())
  % A parent passes its trusted compiled descriptor to child lifecycle code.
  % Legacy/private callers without that descriptor retain full body validation.
  if (isstruct (events) && isscalar (events) && isfield (events, 'execution_descriptor'))
    candidate = events.execution_descriptor;
    if (isstruct (candidate) && isscalar (candidate) ...
        && all (isfield (candidate, {'kind','options','needs_flow','clocked','continuous_controls'})) ...
        && strcmp (candidate.kind, 'octave-blocks-execution-descriptor-v1'))
      descriptor = candidate;
      return;
    endif
  endif
  options = ob_execution_options (model);
  inner_clocks = ob_has_inner_clocks (model);
  continuous_controls = ob_has_continuous_control (model);
  continuous_enabled = strcmp (options.mode, 'enabled') && strcmp (options.control, 'continuous');
  needs_flow = continuous_enabled || continuous_controls || ob_has_continuous (model) || inner_clocks;
  output_ids = reshape (find (strcmp ({model.blocks.type}, 'Outport')), 1, []);
  descriptor = struct ('kind','octave-blocks-execution-descriptor-v1', ...
      'options',options,'needs_flow',needs_flow, ...
      'clocked',strcmp(options.mode,'enabled') && inner_clocks, ...
      'continuous_controls',continuous_controls, ...
      'input_ports',sum(strcmp({model.blocks.type},'Inport')), ...
      'output_ids',output_ids,'output_ports',[model.blocks(output_ids).value]);
endfunction
