function params = ob_block_parameters (block)
  % Normalize the structured parameters of a Transport Delay or Limited
  % Integrator block.  Errors describe the accepted forms.
  %
  % Transport Delay:     [delay initial] or struct('delay',T,'initial',Y0)
  % Limited Integrator:  struct('initial',X0,'lower',L,'upper',U,'reset',MODE)
  %                      or a numeric X0 (no limits, no reset port).
  %                      MODE is none, rising, falling, either or level.
  if (! isstruct (block) || ! isscalar (block) || ! all (isfield (block, {'type', 'value'})))
    error ('ob_block_parameters: expected a block with type and value fields');
  endif
  switch (block.type)
    case 'Transport Delay'
      params = transport_delay (block.value);
    case 'Limited Integrator'
      params = limited_integrator (block.value);
    otherwise
      error ('ob_block_parameters: %s has no structured parameters', block.type);
  endswitch
endfunction

function params = transport_delay (value)
  if (isnumeric (value))
    if (! real_finite (value) || numel (value) != 2)
      error ('Transport Delay value must be [delay initial] or a struct with delay and initial fields');
    endif
    delay = value(1); initial = value(2);
  elseif (isstruct (value) && isscalar (value) && all (isfield (value, {'delay', 'initial'})))
    delay = value.delay; initial = value.initial;
  else
    error ('Transport Delay value must be [delay initial] or a struct with delay and initial fields');
  endif
  if (! isnumeric (delay) || ! isscalar (delay) || ! real_finite (delay) || delay <= 0)
    error ('Transport Delay delay must be a positive finite real scalar');
  endif
  if (! isnumeric (initial) || isempty (initial) || ! real_finite (initial) || ndims (initial) > 2)
    error ('Transport Delay initial output must be a nonempty finite real matrix');
  endif
  params = struct ('kind', 'transport-delay', 'delay', double (delay), ...
                   'initial', double (full (initial)));
endfunction

function params = limited_integrator (value)
  if (isnumeric (value))
    value = struct ('initial', value);
  endif
  if (! isstruct (value) || ! isscalar (value) || ! isfield (value, 'initial'))
    error ('Limited Integrator value must be a numeric initial state or a struct with an initial field');
  endif
  allowed = {'initial', 'lower', 'upper', 'reset'};
  extra = setdiff (fieldnames (value), allowed);
  if (! isempty (extra))
    error ('Limited Integrator has unknown parameter ''%s''', extra{1});
  endif
  initial = value.initial;
  if (! isnumeric (initial) || isempty (initial) || ! real_finite (initial) || ndims (initial) > 2)
    error ('Limited Integrator initial state must be a nonempty finite real matrix');
  endif
  initial = double (full (initial));
  lower = -Inf; upper = Inf; reset = 'none';
  if (isfield (value, 'lower') && ! isempty (value.lower)), lower = value.lower; endif
  if (isfield (value, 'upper') && ! isempty (value.upper)), upper = value.upper; endif
  if (isfield (value, 'reset') && ! isempty (value.reset)), reset = value.reset; endif
  lower = limit (lower, 'lower', initial); upper = limit (upper, 'upper', initial);
  if (any (lower(:) == Inf) || any (upper(:) == -Inf))
    error ('Limited Integrator lower limits cannot be +Inf and upper limits cannot be -Inf');
  endif
  if (any ((lower > upper)(:)))
    error ('Limited Integrator limits must satisfy lower <= upper');
  endif
  if (! ischar (reset) || rows (reset) > 1 ...
      || ! any (strcmp (reset, {'none', 'rising', 'falling', 'either', 'level'})))
    error ('Limited Integrator reset must be none, rising, falling, either, or level');
  endif
  % Like Simulink, an initial condition outside the limits is clipped.
  initial = min (max (initial, lower), upper);
  params = struct ('kind', 'limited-integrator', 'initial', initial, ...
                   'lower', lower, 'upper', upper, 'reset', reset);
endfunction

function bound = limit (bound, name, initial)
  if (! isnumeric (bound) || isempty (bound) || ! isreal (bound) || any (isnan (bound(:))) ...
      || ndims (bound) > 2 || (! isscalar (bound) && ! size_equal (bound, initial)))
    error ('Limited Integrator %s limit must be a real scalar or match the initial state shape', name);
  endif
  bound = double (full (bound));
endfunction

function yes = real_finite (value)
  yes = isreal (value) && all (isfinite (value(:)));
endfunction

%!test
%! p = ob_block_parameters (struct ('type', 'Transport Delay', 'value', [0.5 2]));
%! assert (p.delay, 0.5); assert (p.initial, 2);
%!test
%! p = ob_block_parameters (struct ('type', 'Transport Delay', 'value', struct ('delay', 1, 'initial', [1 2; 3 4])));
%! assert (p.initial, [1 2; 3 4]);
%!error <positive> ob_block_parameters (struct ('type', 'Transport Delay', 'value', [0 1]))
%!error <delay initial> ob_block_parameters (struct ('type', 'Transport Delay', 'value', 1))
%!test
%! p = ob_block_parameters (struct ('type', 'Limited Integrator', 'value', 3));
%! assert (p.lower, -Inf); assert (p.upper, Inf); assert (p.reset, 'none'); assert (p.initial, 3);
%!test
%! p = ob_block_parameters (struct ('type', 'Limited Integrator', ...
%!       'value', struct ('initial', 5, 'lower', -1, 'upper', 2, 'reset', 'rising')));
%! assert (p.initial, 2); assert (p.reset, 'rising');
%!error <lower <= upper> ob_block_parameters (struct ('type', 'Limited Integrator', 'value', struct ('initial', 0, 'lower', 1, 'upper', 0)))
%!error <reset must> ob_block_parameters (struct ('type', 'Limited Integrator', 'value', struct ('initial', 0, 'reset', 'sometimes')))
%!error <unknown parameter> ob_block_parameters (struct ('type', 'Limited Integrator', 'value', struct ('initial', 0, 'gain', 1)))
%!error <match the initial> ob_block_parameters (struct ('type', 'Limited Integrator', 'value', struct ('initial', [0 0], 'upper', [1 2 3])))
