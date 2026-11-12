function signals = ob_model_inputs (model, required = false)
  % Partial diagrams may omit datasets; runnable models require every root port.
  count = sum (ismember ({model.blocks.type}, {'Inport','External Input'}));
  signals = {};
  if (isfield (model, 'inputs')), signals = model.inputs; endif
  if (! iscell (signals) || (! isempty (signals) && ! isvector (signals)))
    error ('ob_model_inputs: model.inputs must be a cell vector indexed by root input port');
  endif
  signals = signals(:)';
  if (numel (signals) > count)
    error ('ob_model_inputs: input datasets exceed the number of root Inports');
  endif
  for port = 1:count
    if (numel (signals) < port || isempty (signals{port}))
      if (required)
        error ('ob_model_inputs: configure a dataset for root Inport %d', port);
      endif
      signals{port} = [];
    else
      try
        signals{port} = ob_input_signal (signals{port});
      catch err
        error ('ob_model_inputs: root Inport %d: %s', port, err.message);
      end_try_catch
    endif
  endfor
endfunction
