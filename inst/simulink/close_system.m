function varargout = close_system (varargin)
  % Simulink-compatible close_system for Octave Blocks; see ob_simulink and SIMULINK_API.md.
  [varargout{1:nargout}] = ob_simulink ('close_system', varargin{:});
endfunction
