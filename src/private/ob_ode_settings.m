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

%!test
%! expected = odeset ('RelTol', 1e-7, 'AbsTol', 1e-9, 'MaxStep', 0.25, 'Refine', 1);
%! actual = ob_ode_settings ('RelTol', 1e-7, 'AbsTol', 1e-9, 'MaxStep', 0.25, 'Refine', 1);
%! assert (isequal (fieldnames (actual), fieldnames (expected)));
%! assert (isequal (actual, expected));
%! handle = @(t, y, flag) false;
%! assert (isequal (ob_ode_settings (actual, 'OutputFcn', handle), odeset (expected, 'OutputFcn', handle)));
%! assert (isequal (ob_ode_settings (actual, 'InitialSlope', [1; 2]), odeset (expected, 'InitialSlope', [1; 2])));
