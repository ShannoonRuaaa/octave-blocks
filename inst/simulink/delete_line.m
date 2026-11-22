function varargout = delete_line (varargin)
  % Simulink-compatible delete_line for Octave Blocks; see ob_simulink and SIMULINK_API.md.
  [varargout{1:nargout}] = ob_simulink ('delete_line', varargin{:});
endfunction
