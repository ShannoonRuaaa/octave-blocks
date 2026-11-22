function [value, message] = ob_accelerate_call (name, varargin)
  % Evaluate one Function block for an accelerated (MEX) run.
  %
  %   [value, message] = ob_accelerate_call (name, input1, ...)
  %
  % ob_accelerate passes a handle to this function to MEX builds whose
  % model has Function blocks without a C mapping; their ob_external_call
  % hook calls it with mexCallMATLAB.  It calls the function the way
  % ob_runtime_eval does (feval by name, from this private folder, with the
  % block's inputs) and returns the error message instead of throwing, so an
  % error never unwinds through the compiled code while the simulation
  % thread waits.  The gateway checks the value's class and shape.
  message = '';
  try
    value = feval (name, varargin{:});
  catch err
    value = [];
    message = err.message;
    if (isempty (message)), message = 'unknown error'; endif
  end_try_catch
endfunction
