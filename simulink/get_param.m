function varargout = get_param (varargin)
  % Simulink-compatible get_param for Octave Blocks; see ob_simulink and SIMULINK_API.md.
  varargout = cell (1, max (1, nargout));
  [varargout{:}] = ob_simulink ('get_param', varargin{:});
endfunction
