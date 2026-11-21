function varargout = delete_block (varargin)
  % Simulink-compatible delete_block for Octave Blocks; see ob_simulink and SIMULINK_API.md.
  [varargout{1:nargout}] = ob_simulink ('delete_block', varargin{:});
endfunction
