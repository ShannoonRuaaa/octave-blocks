function sys = ob_linearize (model, varargin)
% OB_LINEARIZE  Linearize a continuous model about an operating point (linmod).
%   SYS = OB_LINEARIZE(MODEL) linearizes MODEL about its initial states with
%   zero root inputs at time 0, as Simulink linmod(sys) does.
%   SYS = OB_LINEARIZE(MODEL, X0, U0) uses state vector X0 and input U0
%   (either may be [] for the default).  Name-value options:
%     'Time'          linearization time t0 (default 0)
%     'Perturbation'  relative step DEL (default 1e-5, linmod's default)
%     'Method'        'central' (default): state/input j is perturbed by
%                     h = DEL*(1 + |x_j|) both ways, (f(+h) - f(-h))/(2h);
%                     'v5': linmod(...,'v5')'s rule, the forward difference
%                     (f(+h) - f(0))/h with h = DEL*(1 + 1e-3*|x_j|)
%   The result describes
%       dx = A*(x - x0) + B*(u - u0) + dx0,   y = C*(x - x0) + D*(u - u0) + y0
%   with fields A, B, C, D, x0, u0, y0, dx0, t0 and
%     state_names   one name per state element, 'subsystem/block(k)'
%     state_paths   hierarchical block path of each state block
%     state_index   [state block number, element] for each row of x
%     input_ports   root Inport numbers;  input_index  [port, element] per u
%     output_ports  root Outport numbers; output_index [port, element] per y
%     output_paths  block paths of the root Outports
%
%   States are the elements of every continuous Integrator in depth-first
%   block order (Simulink orders its states differently; use state_names).
%   Inputs are the elements of the root Inports in port order; a port's shape
%   comes from its model.inputs dataset, or from a cell U0 = {u1, u2, ...},
%   and is scalar otherwise.  Outputs are the root Outports only, in port
%   order; Scopes and Outports inside subsystems are not outputs.
%   Limited Integrator states are linearized inside their limits; X0 must lie
%   strictly between them and the block must not have a reset port.  Unit
%   Delay, Discrete Integrator, Transport Delay, Rate Transition and
%   conditional subsystem states raise ob_linearize:unsupported.
%
%   The model is compiled once; each perturbation is one evaluation of the
%   compiled graph at time t0.  Both methods perturb the whole model, like
%   linmod's numerical 'v5' method, so discontinuities are judged at the
%   operating point: a Saturation beyond its limit gives zero gain, where
%   linmod's default block-by-block method keeps its unity gain.
%   With 'Method','v5' the result is that of linmod(sys, x, u, [DEL t0], 'v5')
%   (same step, same one-sided slope at a kink: a Saturation exactly at its
%   upper limit gives gain 0, exactly at its lower limit gain 1).  The
%   default central differences are more accurate on smooth models
%   (dx = -x^2 at x = 1 gives A = -2, where 'v5' gives -2 - 1.001*DEL) and
%   give the mean of the one-sided slopes at a kink (0.5 for that Saturation).
%
%   Example:
%     sys = ob_linearize (model, [], 0.5, 'Time', 0);
%     sys5 = ob_linearize (model, [], 0.5, 'Method', 'v5');   % as linmod 'v5'
%     resp = ob_bode (sys);
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/linmod.html

  if (nargin < 1)
    error ('ob_linearize: supply a model[, x0, u0, name, value...]');
  endif
  [x0, u0, opts] = parse_arguments (varargin);
  ctx = ob_linearize_context ('ob_linearize', model, x0, u0, opts.Time);
  ob_linearize_limits (ctx, ctx.x0, 'strict');
  sys = ob_linearize_jacobian (ctx, ctx.x0, ctx.u0, opts.Perturbation, opts.Method);
endfunction

function [x0, u0, opts] = parse_arguments (args)
  x0 = []; u0 = [];
  positional = 0;
  while (positional < numel (args) && positional < 2 && ! ischar (args{positional + 1}))
    positional += 1;
  endwhile
  if (positional >= 1), x0 = args{1}; endif
  if (positional >= 2), u0 = args{2}; endif
  rest = args(positional + 1:end);
  opts = struct ('Time', 0, 'Perturbation', 1e-5, 'Method', 'central');
  if (mod (numel (rest), 2) != 0)
    error ('ob_linearize:arguments', 'ob_linearize: options must be name-value pairs');
  endif
  for k = 1:2:numel (rest)
    name = rest{k}; value = rest{k + 1};
    if (! ischar (name))
      error ('ob_linearize:arguments', 'ob_linearize: option names must be strings');
    endif
    switch (lower (name))
      case 'time'
        validateattributes (value, {'numeric'}, {'scalar', 'real', 'finite'}, 'ob_linearize', 'Time');
        opts.Time = double (value);
      case 'perturbation'
        validateattributes (value, {'numeric'}, {'scalar', 'real', 'finite', 'positive'}, ...
                            'ob_linearize', 'Perturbation');
        opts.Perturbation = double (value);
      case 'method'
        if (! ischar (value) || ! any (strcmpi (value, {'central', 'v5'})))
          error ('ob_linearize:arguments', 'ob_linearize: Method must be ''central'' or ''v5''');
        endif
        opts.Method = lower (value);
      otherwise
        error ('ob_linearize:arguments', 'ob_linearize: unknown option ''%s''', name);
    endswitch
  endfor
endfunction
