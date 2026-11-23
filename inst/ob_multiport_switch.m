function model = ob_multiport_switch (n_data_ports = 3, data_port_order = 'One-based contiguous', default_port = 'Last data port')
% OB_MULTIPORT_SWITCH  Build a Simulink-style Multiport Switch subsystem.
%   MODEL = OB_MULTIPORT_SWITCH([N[, ORDER[, DEFAULT]]]) routes one of N >= 2
%   data inputs to the output.  Inport 1 is the scalar control, Inports
%   2..N+1 are the data inputs and, when DEFAULT is 'Additional data port',
%   Inport N+2 is the default data input.
%
%   ORDER is 'One-based contiguous' (default) or 'Zero-based contiguous'
%   (also 'one-based'/'zero-based', or a logical scalar that is true for
%   zero-based; numbers are rejected).  As in Simulink, a fractional control is truncated toward
%   zero (Simulink warns "Non integer control signal truncated"): control
%   2.7 selects data port 2 and, zero-based, control -0.5 selects data port
%   0.  A control whose truncation is outside the data port range selects
%   the default port: the last data port (DEFAULT = 'Last data port',
%   Simulink's default) or the extra Inport N+2 (DEFAULT = 'Additional data
%   port').
%
%   Data inputs must share one shape (scalar, vector or matrix).  The
%   control is finite and real: a scalar selects one data input, and a
%   control of the data shape selects element-wise, as in Simulink (control
%   [1;3] with data [10;11], [20;21], [30;31] gives [10;31]).  Sample time
%   is inherited.
%   Built from native Switch blocks for ob_run, zero crossings, strict C99
%   ob_codegen and ob_accelerate parity.
%
%   Differences from Simulink: DiagnosticForDefault = 'Error' (the library
%   default) stops a Simulink simulation when the control leaves the data
%   port range; this subsystem always behaves as 'None' and routes the
%   default port.  A NaN control is rejected by ob_run (Switch inputs must be
%   finite).  'Specify indices' and Inputs = 1 (Index Vector mode) are not
%   supported.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/multiportswitch.html

  validateattributes (n_data_ports, {'numeric'}, {'scalar', 'real', 'finite', 'integer', '>=', 2}, ...
                      'ob_multiport_switch', 'n_data_ports');
  n = double (n_data_ports);
  base = port_base (data_port_order);
  additional = default_mode (default_port);

  model = ob_builder_block ();
  [model, ctrl] = ob_builder_block (model, 'Inport', 1, 'control', 0.06, 0.92);
  data = zeros (1, n);
  for k = 1:n
    [model, data(k)] = ob_builder_block (model, 'Inport', k + 1, sprintf ('data %d', k - 1 + base), ...
                                         0.06, 0.80 - 0.66 * (k - 1) / max (1, n - 1));
  endfor
  fallback = data(n);
  if (additional)
    [model, fallback] = ob_builder_block (model, 'Inport', n + 2, 'default', 0.06, 0.06);
    % control >= base + n is above the range: route the default port.
    [model, chain] = ob_builder_block (model, 'Switch', base + n, 'above range', 0.30, 0.50, ...
                                       [fallback ctrl data(n)]);
  else
    chain = data(n);
  endif
  % Fold the ports from the top: control >= base + k keeps the upper
  % selection, otherwise data port k (truncation of a positive control).
  for k = n-1:-1:1
    [model, chain] = ob_builder_block (model, 'Switch', base + k, sprintf ('port %d', k - 1 + base), ...
                                       0.30 + 0.45 * (n - k) / n, 0.50, [chain ctrl data(k)]);
  endfor
  % Below the range, also the default port: fix(control) < 1 means
  % control < 1 (one-based); fix(control) < 0 means control <= -1
  % (zero-based), tested as -control >= 1.
  if (base == 1)
    [model, guard] = ob_builder_block (model, 'Switch', 1, 'below range', 0.82, 0.50, [chain ctrl fallback]);
  else
    [model, negated] = ob_builder_block (model, 'Gain', -1, '-control', 0.70, 0.88, ctrl);
    [model, guard] = ob_builder_block (model, 'Switch', 1, 'below range', 0.82, 0.50, [fallback negated chain]);
  endif
  model = ob_builder_block (model, 'Outport', 1, 'y', 0.94, 0.50, guard);
endfunction

function base = port_base (order)
  % Only a logical scalar is a flag (true = zero-based): the number 1 would
  % read as "one-based" next to Simulink's setting names, so it is rejected.
  if (islogical (order) && isscalar (order))
    base = double (! order);
    return;
  endif
  if (! ischar (order) || ! isrow (order))
    error ('ob_multiport_switch: data_port_order must be ''One-based contiguous'', ''Zero-based contiguous'' or a logical scalar');
  endif
  switch (lower (strtrim (order)))
    case {'one-based contiguous', 'one-based'}, base = 1;
    case {'zero-based contiguous', 'zero-based'}, base = 0;
    case 'specify indices'
      error ('ob_multiport_switch: data_port_order ''Specify indices'' is not supported');
    otherwise
      error ('ob_multiport_switch: data_port_order must be ''One-based contiguous'' or ''Zero-based contiguous''');
  endswitch
endfunction

function additional = default_mode (port)
  if (! ischar (port) || ! isrow (port))
    error ('ob_multiport_switch: default_port must be ''Last data port'' or ''Additional data port''');
  endif
  switch (lower (strtrim (port)))
    case {'last data port', 'last'}, additional = false;
    case {'additional data port', 'additional'}, additional = true;
    otherwise
      error ('ob_multiport_switch: default_port must be ''Last data port'' or ''Additional data port''');
  endswitch
endfunction
