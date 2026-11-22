function yes = ob_conditional_may_widen (model, shapes)
  % Cheap screen for ob_expand_initial_outputs and ob_conditional_output_shapes:
  % scalar data (input SHAPES, one [rows cols] or [] per Inport) through
  % blocks with scalar values keeps every signal scalar; only Function
  % blocks (whose result shape is unknown) or non-scalar data can make a
  % conditional port wider than its scalar initial output.
  yes = any (cellfun (@(s) ! isempty (s) && prod (s) != 1, shapes)) || wide_body (model);
endfunction

function yes = wide_body (model)
  yes = false;
  for k = 1:numel (model.blocks)
    block = model.blocks(k);
    if (strcmp (block.type, 'Function'))
      yes = true;
    elseif (strcmp (block.type, 'Subsystem'))
      inner = block.value;
      if (isfield (inner, 'execution') && isstruct (inner.execution) ...
          && isfield (inner.execution, 'initial_outputs') && iscell (inner.execution.initial_outputs))
        yes = any (cellfun (@(v) numel (v) != 1, inner.execution.initial_outputs));
      endif
      yes = yes || wide_body (inner);
    elseif (any (strcmp (block.type, {'Constant', 'Gain', 'Unit Delay', 'Discrete Integrator', ...
                                       'Integrator', 'Rate Transition'})))
      yes = isnumeric (block.value) && numel (block.value) > 1;
    elseif (isstruct (block.value) && isfield (block.value, 'initial'))
      yes = numel (block.value.initial) > 1;
    endif
    if (yes), return; endif
  endfor
endfunction
