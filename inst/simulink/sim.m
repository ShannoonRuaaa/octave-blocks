function varargout = sim (varargin)
  % Simulink-compatible sim for Octave Blocks; see ob_simulink and SIMULINK_API.md.
  varargout = cell (1, max (1, nargout));
  [varargout{:}] = ob_simulink ('sim', varargin{:});
endfunction
