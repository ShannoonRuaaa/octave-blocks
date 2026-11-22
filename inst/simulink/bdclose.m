function varargout = bdclose (varargin)
  % Simulink-compatible bdclose for Octave Blocks; see ob_simulink and SIMULINK_API.md.
  [varargout{1:nargout}] = ob_simulink ('bdclose', varargin{:});
endfunction
