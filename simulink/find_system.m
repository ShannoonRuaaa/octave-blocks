function varargout = find_system (varargin)
  % Simulink-compatible find_system for Octave Blocks; see ob_simulink and SIMULINK_API.md.
  varargout = cell (1, max (1, nargout));
  [varargout{:}] = ob_simulink ('find_system', varargin{:});
endfunction
