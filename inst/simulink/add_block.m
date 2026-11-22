function varargout = add_block (varargin)
  % Simulink-compatible add_block for Octave Blocks; see ob_simulink and SIMULINK_API.md.
  [varargout{1:nargout}] = ob_simulink ('add_block', varargin{:});
endfunction
