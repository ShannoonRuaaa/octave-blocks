function varargout = set_param (varargin)
  % Simulink-compatible set_param for Octave Blocks; see ob_simulink and SIMULINK_API.md.
  [varargout{1:nargout}] = ob_simulink ('set_param', varargin{:});
endfunction
