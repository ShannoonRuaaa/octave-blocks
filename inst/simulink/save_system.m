function varargout = save_system (varargin)
  % Simulink-compatible save_system for Octave Blocks; see ob_simulink and SIMULINK_API.md.
  [varargout{1:nargout}] = ob_simulink ('save_system', varargin{:});
endfunction
