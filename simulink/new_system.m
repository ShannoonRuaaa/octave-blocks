function varargout = new_system (varargin)
  % Simulink-compatible new_system for Octave Blocks; see ob_simulink and SIMULINK_API.md.
  [varargout{1:nargout}] = ob_simulink ('new_system', varargin{:});
endfunction
