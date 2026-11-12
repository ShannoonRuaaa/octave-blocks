function [signals, control] = ob_conditional_signals (model, inputs, time, prepare = true)
  ports = sum (strcmp ({model.blocks.type}, 'Inport'));
  if (numel (inputs) != ports+1)
    error ('ob_run: conditional Subsystem needs its data ports followed by one control port');
  endif
  control = inputs{end};
  if ((! isnumeric(control) && ! islogical(control)) || ! isreal(control) ...
      || ! isscalar(control) || ! isfinite(control))
    error ('ob_run: conditional control must be a finite real scalar');
  endif
  signals = cell (1, ports);
  if (! prepare), return; endif
  for port = 1:ports
    value = inputs{port};
    if (! isnumeric(value) || ! isreal(value) || isempty(value) ...
        || ndims(value)>2 || any(! isfinite(value(:))))
      error ('ob_run: conditional data input %d must be a finite real numeric matrix', port);
    endif
    value = full (double(value));
    signals{port} = ob_input_signal (time, value(:)', size(value));
  endfor
endfunction
