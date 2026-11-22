function settings = ob_ode_settings (varargin)
  % odeset (NAME, VALUE, ...) for canonical option names, without running
  % odeset's inputParser for every solver segment (about 2.5 ms per call).
  % The default record comes from odeset itself, so the field set and order
  % match its result exactly; options are assigned as values, as odeset does.
  % An existing settings struct may be passed first, as with odeset.
  persistent template;
  if (isempty (template)), template = odeset (); endif
  first = 1;
  if (nargin > 0 && isstruct (varargin{1}))
    settings = varargin{1}; first = 2;
  else
    settings = template;
  endif
  for k = first:2:numel (varargin)
    settings.(varargin{k}) = varargin{k+1};
  endfor
endfunction
