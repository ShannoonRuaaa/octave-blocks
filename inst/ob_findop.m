function [op, sys] = ob_findop (model, varargin)
% OB_FINDOP  Find a steady-state operating point of a continuous model (trim).
%   OP = OB_FINDOP(MODEL, X0, U0) searches for states x and inputs u with
%   dx/dt = 0, starting from X0 and U0 ([] selects the model's initial states
%   and zero inputs).  As in Simulink trim, states and inputs are free unless
%   fixed:
%   OP = OB_FINDOP(MODEL, X0, U0, Y0, IX, IU, IY) holds x(IX) = X0(IX) and
%   u(IU) = U0(IU), and requires y(IY) = Y0(IY).  Indices refer to the state,
%   input and output vectors of ob_linearize; pass [] to skip one.
%   [OP, SYS] = OB_FINDOP(...) also returns ob_linearize's result at OP,
%   under the same rules (a Limited Integrator on a limit raises
%   ob_findop:unsupported when SYS is requested).
%   Name-value options (after the positional arguments):
%     'Time'          time t0 at which the model is evaluated (default 0)
%     'Perturbation'  relative finite-difference step (default 1e-5)
%     'Method'        'central' (default) or 'v5': the difference rule for
%                     SYS, as in ob_linearize
%     'AbsTol', 'RelTol'  convergence: max|r| <= AbsTol + RelTol*max|[x;u]|
%                     where r = [dx; y(IY) - Y0(IY)] (defaults 1e-9, 1e-9)
%     'MaxIter'       fsolve iteration limit (default 400)
%   OP has fields x, u, y, dx (as trim returns them), residual (max|r|),
%   converged (residual within tolerance), info and output (from fsolve),
%   t0, state_names, input_index and output_index.
%
%   The residual and its Jacobian [A B; C D] (restricted to the free
%   variables and IY) come from one compiled model; fsolve receives the
%   Jacobian ('Jacobian','on') and solves the possibly non-square system in
%   the least-squares sense.  Unlike trim, the IX/IU/IY specifications are
%   hard constraints, not "as close as possible" targets, and no derivative
%   targets (trim's DX0/IDX) are supported.  The same states are supported as
%   in ob_linearize.  A Limited Integrator state in X0 must lie within its
%   limits, and it may settle on a limit: its outward derivative is zero
%   there, as in ob_run, so every value past the limit also has dx = 0.
%   OP.x then holds the limit itself (the value ob_run can reach), not the
%   arbitrary point past it where the solver stopped.  Simulink trim
%   reports such a point past the limit instead (for x' = -x + u, limits
%   +-10, u = 20 held, trim returns x = 10.67 and moves u to 10; OP.x is
%   10 with u = 20).
%
%   Example:
%     op = ob_findop (model, [0; 0.5], 0.5, [], [], 1, []);   % hold u = 0.5
%     sys = ob_linearize (model, op.x, op.u);
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/trim.html

  if (nargin < 1)
    error ('ob_findop: supply a model[, x0, u0, y0, ix, iu, iy, name, value...]');
  endif
  [pos, opts] = parse_arguments (varargin);
  ctx = ob_linearize_context ('ob_findop', model, pos{1}, pos{2}, opts.Time);
  ob_linearize_limits (ctx, ctx.x0, 'closed');
  n = numel (ctx.x0); m = numel (ctx.u0); p = rows (ctx.output_index);
  y0 = pos{3};
  ix = index_list (pos{4}, n, 'IX'); iu = index_list (pos{5}, m, 'IU');
  iy = index_list (pos{6}, p, 'IY');
  if (isempty (y0))
    if (! isempty (iy))
      error ('ob_findop:output', 'ob_findop: IY requires the output targets Y0');
    endif
    y0 = zeros (p, 1);
  else
    validateattributes (y0, {'numeric'}, {'real', 'finite', 'vector', 'numel', p}, 'ob_findop', 'Y0');
    y0 = double (y0(:));
  endif
  fx = setdiff (1:n, ix); fu = setdiff (1:m, iu);
  x = ctx.x0; u = ctx.u0;
  z0 = [x(fx); u(fu)];
  residual_fn = @(z) residual (ctx, z, x, u, fx, fu, y0, iy, opts.Perturbation);
  info = 1; output = struct ('iterations', 0, 'successful', 0, 'funcCount', 1);
  if (! isempty (z0))
    fs = optimset ('Jacobian', 'on', 'TolFun', 1e-14, 'TolX', 1e-14, ...
                   'MaxIter', opts.MaxIter, 'MaxFunEvals', 10 * opts.MaxIter);
    [z, unused, info, output] = fsolve (residual_fn, z0, fs);
    x(fx) = z(1:numel (fx)); u(fu) = z(numel (fx) + 1:end);
  endif
  % A free Limited Integrator state beyond a limit (where the outward
  % derivative is zero) is moved onto the limit, the value ob_run reaches.
  x = ob_linearize_limits (ctx, x, 'clamp');
  [dx, y] = ob_linearize_eval (ctx, x, u);
  r = [dx; y(iy) - y0(iy)];
  res = 0;
  if (! isempty (r)), res = max (abs (r)); endif
  scale = 0;
  if (! isempty ([x; u])), scale = max (abs ([x; u])); endif
  op = struct ('x', x, 'u', u, 'y', y, 'dx', dx, 'residual', res, ...
               'converged', res <= opts.AbsTol + opts.RelTol * scale, ...
               'info', info, 'output', output, 't0', ctx.t0, ...
               'state_names', {ctx.state_names}, 'input_index', ctx.input_index, ...
               'output_index', ctx.output_index);
  if (nargout > 1)
    ob_linearize_limits (ctx, x, 'strict');
    sys = ob_linearize_jacobian (ctx, x, u, opts.Perturbation, opts.Method);
  endif
endfunction

function [r, J] = residual (ctx, z, x, u, fx, fu, y0, iy, del)
  x(fx) = z(1:numel (fx)); u(fu) = z(numel (fx) + 1:end);
  [dx, y] = ob_linearize_eval (ctx, x, u);
  r = [dx; y(iy) - y0(iy)];
  if (nargout > 1)
    J = zeros (numel (r), numel (z));
    for j = 1:numel (z)
      h = del * (1 + abs (z(j)));
      xp = x; up = u; xm = x; um = u;
      if (j <= numel (fx))
        xp(fx(j)) += h; xm(fx(j)) -= h;
      else
        up(fu(j - numel (fx))) += h; um(fu(j - numel (fx))) -= h;
      endif
      [dxp, yp] = ob_linearize_eval (ctx, xp, up);
      [dxm, ym] = ob_linearize_eval (ctx, xm, um);
      J(:, j) = ([dxp; yp(iy)] - [dxm; ym(iy)]) / (2 * h);
    endfor
  endif
endfunction

function list = index_list (value, count, name)
  if (isempty (value)), list = zeros (1, 0); return; endif
  validateattributes (value, {'numeric'}, {'vector', 'integer', 'positive', '<=', count}, ...
                      'ob_findop', name);
  list = double (value(:)');
  if (numel (unique (list)) != numel (list))
    error ('ob_findop:index', 'ob_findop: %s must not repeat an index', name);
  endif
endfunction

function [pos, opts] = parse_arguments (args)
  pos = cell (1, 6);
  positional = 0;
  while (positional < numel (args) && positional < 6 && ! ischar (args{positional + 1}))
    positional += 1;
    pos{positional} = args{positional};
  endwhile
  rest = args(positional + 1:end);
  opts = struct ('Time', 0, 'Perturbation', 1e-5, 'AbsTol', 1e-9, 'RelTol', 1e-9, 'MaxIter', 400, 'Method', 'central');
  if (mod (numel (rest), 2) != 0)
    error ('ob_findop:arguments', 'ob_findop: options must be name-value pairs');
  endif
  for k = 1:2:numel (rest)
    name = rest{k}; value = rest{k + 1};
    if (! ischar (name))
      error ('ob_findop:arguments', 'ob_findop: option names must be strings');
    endif
    switch (lower (name))
      case 'time'
        validateattributes (value, {'numeric'}, {'scalar', 'real', 'finite'}, 'ob_findop', 'Time');
        opts.Time = double (value);
      case 'perturbation'
        validateattributes (value, {'numeric'}, {'scalar', 'real', 'finite', 'positive'}, 'ob_findop', 'Perturbation');
        opts.Perturbation = double (value);
      case 'abstol'
        validateattributes (value, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'}, 'ob_findop', 'AbsTol');
        opts.AbsTol = double (value);
      case 'reltol'
        validateattributes (value, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'}, 'ob_findop', 'RelTol');
        opts.RelTol = double (value);
      case 'maxiter'
        validateattributes (value, {'numeric'}, {'scalar', 'integer', 'positive'}, 'ob_findop', 'MaxIter');
        opts.MaxIter = double (value);
      case 'method'
        if (! ischar (value) || ! any (strcmpi (value, {'central', 'v5'})))
          error ('ob_findop:arguments', 'ob_findop: Method must be ''central'' or ''v5''');
        endif
        opts.Method = lower (value);
      otherwise
        error ('ob_findop:arguments', 'ob_findop: unknown option ''%s''', name);
    endswitch
  endfor
endfunction
