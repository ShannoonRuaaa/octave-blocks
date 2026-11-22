function varargout = load_system (varargin)
  % Simulink-compatible load_system for Octave Blocks; see ob_simulink and SIMULINK_API.md.
  [varargout{1:nargout}] = ob_simulink ('load_system', varargin{:});
endfunction
