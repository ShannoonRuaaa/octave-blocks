function signals = ob_model_inputs (model, required = false)
  % Partial diagrams may omit datasets; runnable models require every root port.
  % strcmp is the builtin equivalent of ismember here (child executions call
  % this for every hit, and ismember's argument validation dominated it).
  types = {model.blocks.type};
  count = sum (strcmp (types, 'Inport') | strcmp (types, 'External Input'));
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
        signal = signals{port};
        if (isstruct (signal) && isscalar (signal) && numfields (signal) == 4 ...
            && all (isfield (signal, {'t', 'values', 'shape', 'method'})))
          % A complete signal record: ob_input_signal's struct form would
          % unpack exactly these fields and apply the same checks.
          signals{port} = ob_input_signal (signal.t, signal.values, signal.shape, signal.method);
        else
          signals{port} = ob_input_signal (signal);
        endif
      catch err
        error ('ob_model_inputs: root Inport %d: %s', port, err.message);
      end_try_catch
    endif
  endfor
endfunction
