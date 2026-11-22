function varargout = open_system (varargin)
  % Simulink-compatible open_system for Octave Blocks; see ob_simulink and SIMULINK_API.md.
  [varargout{1:nargout}] = ob_simulink ('open_system', varargin{:});
endfunction
