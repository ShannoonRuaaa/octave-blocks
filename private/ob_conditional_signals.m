function [signals, control] = ob_conditional_signals (model, inputs, time, prepare = true, ports = [])
  if (isempty(ports)), ports = sum (strcmp ({model.blocks.type}, 'Inport')); endif
  combined = ob_is_combined_mode (ob_execution_mode(model));
  if (numel (inputs) != ports+1+combined)
    error ('ob_run: conditional Subsystem needs data ports followed by its control ports (enable then trigger for combined modes)');
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
