function varargout = add_line (varargin)
  % Simulink-compatible add_line for Octave Blocks; see ob_simulink and SIMULINK_API.md.
  [varargout{1:nargout}] = ob_simulink ('add_line', varargin{:});
endfunction
