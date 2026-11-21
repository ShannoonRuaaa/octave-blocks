function model = ob_pid_controller (P = 1, I = 0, D = 0, N = 100, options = struct ())
% OB_PID_CONTROLLER  Build a Simulink-style continuous or discrete PID controller.
%   MODEL = OB_PID_CONTROLLER(P,I,D[,N[,OPTIONS]]) returns a virtual subsystem
%   compatible with ob_run (rk4, ode45, ode15s), zero-crossing detection,
%   save/load, the Qt editor, and strict C99 ob_codegen.
%
%   Parallel form (default):
%       u_unsat(s) = P*e + I*(1/s)*e + D*(N / (1 + N/s))*e
%   Ideal form (options.form = 'ideal'):
%       u_unsat(s) = P*(e + I*(1/s)*e + D*(N / (1 + N/s))*e)
%
%   OPTIONS fields (all optional):
%     form      : 'parallel' (default) or 'ideal'
%     domain    : 'continuous' (default) or 'discrete'
%     Ts        : positive discrete sample period (default 0.1 when discrete)
%     offset    : nonnegative discrete sample offset (default 0)
%     x0_i      : initial integrator state (default 0)
%     x0_d      : initial derivative filter state (default 0)
%     limits    : [] (unlimited, default) or [lower upper] output saturation
%     Kb        : back-calculation anti-windup gain (default 0; active when
%                 limits is nonempty and I != 0)
%     two_dof   : false (default, 1 Inport: error e) or true (2 Inports:
%                 reference r on port 1, measurement y on port 2)
%     b         : proportional setpoint weight for 2-DOF (default 1)
%     c         : derivative setpoint weight for 2-DOF (default 1)
%
%   References:
%     https://www.mathworks.com/help/simulink/slref/discretepidcontroller.html
%     https://www.mathworks.com/help/simulink/slref/discretepidcontroller2dof.html

  if (nargin > 5)
    error ('ob_pid_controller: supply P[, I, D, N, options]');
  endif
  P = valid_scalar (P, 'P');
  I = valid_scalar (I, 'I');
  D = valid_scalar (D, 'D');
  N = valid_scalar (N, 'N');
  if (D != 0 && N <= 0)
    error ('ob_pid_controller: derivative filter coefficient N must be positive when D != 0');
  endif

  cfg = parse_pid_options (options);
  if (strcmp (cfg.form, 'ideal'))
    Ki = P * I;
    Kd = P * D;
  else
    Ki = I;
    Kd = D;
  endif
  Kp = P;
  if (!all(isfinite([Ki Kd])))
    error ('ob_pid_controller: effective gains must remain finite');
  endif

  has_i = (Ki != 0);
  has_d = (Kd != 0);
  has_sat = ! isempty (cfg.limits);
  has_aw = has_sat && has_i && (cfg.Kb != 0);
  is_disc = strcmp (cfg.domain, 'discrete');

  blocks = struct ('type', {}, 'value', {}, 'name', {}, 'x', {}, 'y', {});
  edges = zeros (0, 4);
  rates = zeros (0, 2);

  function id = add_block (type, value, name, x, y, rate)
    if (nargin < 6), rate = [0 0]; endif
    id = numel (blocks) + 1;
    blocks(id) = struct ('type', type, 'value', value, 'name', name, 'x', x, 'y', y);
    rates(id, :) = rate;
  endfunction

  function wire (src, dst, dst_port)
    if (nargin < 3), dst_port = 1; endif
    edges(end + 1, :) = [src 1 dst dst_port];
  endfunction

  if (cfg.two_dof)
    id_r = add_block ('Inport', 1, 'r', 0.06, 0.70);
    id_y = add_block ('Inport', 2, 'y', 0.06, 0.30);
    id_neg_y = add_block ('Gain', -1, '-y', 0.14, 0.30);
    wire (id_y, id_neg_y, 1);

    % Error signal e = r - y (used by I branch)
    id_e = add_block ('Sum', [], 'e = r - y', 0.22, 0.50);
    wire (id_r, id_e, 1);
    wire (id_neg_y, id_e, 2);

    % Proportional input e_p = b*r - y
    if (cfg.b == 1)
      id_ep = id_e;
    else
      id_br = add_block ('Gain', cfg.b, 'b*r', 0.14, 0.80);
      wire (id_r, id_br, 1);
      id_ep = add_block ('Sum', [], 'b*r - y', 0.22, 0.80);
      wire (id_br, id_ep, 1);
      wire (id_neg_y, id_ep, 2);
    endif

    % Derivative input e_d = c*r - y
    if (cfg.c == 1)
      id_ed = id_e;
    else
      id_cr = add_block ('Gain', cfg.c, 'c*r', 0.14, 0.15);
      wire (id_r, id_cr, 1);
      id_ed = add_block ('Sum', [], 'c*r - y', 0.22, 0.15);
      wire (id_cr, id_ed, 1);
      wire (id_neg_y, id_ed, 2);
    endif
  else
    id_e = add_block ('Inport', 1, 'e', 0.08, 0.50);
    id_ep = id_e;
    id_ed = id_e;
  endif

  branch_ids = [];

  % Proportional branch
  if (Kp != 0 || (! has_i && ! has_d))
    id_p = add_block ('Gain', Kp, 'P', 0.42, 0.80);
    wire (id_ep, id_p, 1);
    branch_ids(end + 1) = id_p;
  endif

  % Integral branch (with optional back-calculation anti-windup)
  if (has_i)
    id_ki = add_block ('Gain', Ki, 'I', 0.34, 0.50);
    wire (id_e, id_ki, 1);
    if (is_disc)
      id_int = add_block ('Discrete Integrator', cfg.x0_i, 'Integrator', 0.56, 0.50, [cfg.Ts cfg.offset]);
    else
      id_int = add_block ('Integrator', cfg.x0_i, 'Integrator', 0.56, 0.50);
    endif
    if (has_aw)
      id_int_sum = add_block ('Sum', [], 'I + AW', 0.45, 0.50);
      wire (id_ki, id_int_sum, 1);
      wire (id_int_sum, id_int, 1);
    else
      wire (id_ki, id_int, 1);
    endif
    branch_ids(end + 1) = id_int;
  endif

  % Filtered Derivative branch:
  %   d_out = N * (Kd * e_d - x_d),   dx_d/dt = d_out
  if (has_d)
    id_kd = add_block ('Gain', Kd, 'D', 0.30, 0.20);
    wire (id_ed, id_kd, 1);
    if (is_disc)
      id_xd = add_block ('Discrete Integrator', cfg.x0_d, 'Filter State', 0.58, 0.12, [cfg.Ts cfg.offset]);
    else
      id_xd = add_block ('Integrator', cfg.x0_d, 'Filter State', 0.58, 0.12);
    endif
    id_neg_xd = add_block ('Gain', -1, '-x_d', 0.40, 0.12);
    wire (id_xd, id_neg_xd, 1);
    id_d_err = add_block ('Sum', [], 'D*e - x_d', 0.46, 0.20);
    wire (id_kd, id_d_err, 1);
    wire (id_neg_xd, id_d_err, 2);
    id_n = add_block ('Gain', N, 'N', 0.58, 0.24);
    wire (id_d_err, id_n, 1);
    wire (id_n, id_xd, 1);
    branch_ids(end + 1) = id_n;
  endif

  % Sum active branches
  if (numel (branch_ids) == 1)
    id_unsat = branch_ids(1);
  else
    id_unsat = branch_ids(1);
    for k = 2:numel (branch_ids)
      id_sum = add_block ('Sum', [], 'PID Sum', 0.62+0.08*(k-1), 0.50);
      wire (id_unsat, id_sum, 1);
      wire (branch_ids(k), id_sum, 2);
      id_unsat = id_sum;
    endfor
  endif

  % Optional output saturation & back-calculation anti-windup
  if (has_sat)
    id_sat = add_block ('Saturation', cfg.limits, 'Saturation', 0.82, 0.50);
    wire (id_unsat, id_sat, 1);
    id_out_src = id_sat;
    if (has_aw)
      id_neg_unsat = add_block ('Gain', -1, '-u_unsat', 0.72, 0.72);
      wire (id_unsat, id_neg_unsat, 1);
      id_aw_err = add_block ('Sum', [], 'u_sat - u_unsat', 0.82, 0.72);
      wire (id_sat, id_aw_err, 1);
      wire (id_neg_unsat, id_aw_err, 2);
      id_kb = add_block ('Gain', cfg.Kb, 'Kb', 0.62, 0.72);
      wire (id_aw_err, id_kb, 1);
      wire (id_kb, id_int_sum, 2);
    endif
  else
    id_out_src = id_unsat;
  endif

  if (is_disc)
    initial = cfg.x0_i*has_i - N*cfg.x0_d*has_d;
    if (has_sat), initial = min(max(initial,cfg.limits(1)),cfg.limits(2)); endif
    sampled = add_block ('Rate Transition', initial, 'Sampled output', 0.87, 0.50, [cfg.Ts cfg.offset]);
    wire (id_out_src, sampled, 1);
    id_out_src = sampled;
  endif
  id_out = add_block ('Outport', 1, 'u', 0.96, 0.50);
  wire (id_out_src, id_out, 1);

  model = struct ('blocks', blocks, 'edges', edges);
  if (any (rates(:, 1) > 0))
    model.sample_times = rates;
  endif
  model.execution = struct ('mode', 'virtual');
endfunction

function value = valid_scalar (value, name)
  if (! isnumeric (value) || ! isreal (value) || ! isscalar (value) || ! isfinite (value))
    error ('ob_pid_controller: %s must be a finite real scalar', name);
  endif
  value = double (value);
endfunction

function cfg = parse_pid_options (options)
  if (! isstruct (options) || ! isscalar (options))
    error ('ob_pid_controller: options must be a scalar struct');
  endif
  cfg = struct ('form', 'parallel', 'domain', 'continuous', 'Ts', 0.1, ...
                'offset', 0, 'x0_i', 0, 'x0_d', 0, 'limits', [], 'Kb', 0, ...
                'two_dof', false, 'b', 1, 'c', 1);
  names = fieldnames (options);
  for k = 1:numel (names)
    key = names{k};
    if (! isfield (cfg, key))
      error ('ob_pid_controller: unknown option "%s"', key);
    endif
    cfg.(key) = options.(key);
  endfor
  if (! ischar (cfg.form) || ! any (strcmp (cfg.form, {'parallel', 'ideal'})))
    error ('ob_pid_controller: form must be "parallel" or "ideal"');
  endif
  if (! ischar (cfg.domain) || ! any (strcmp (cfg.domain, {'continuous', 'discrete'})))
    error ('ob_pid_controller: domain must be "continuous" or "discrete"');
  endif
  cfg.Ts = valid_scalar (cfg.Ts, 'Ts');
  cfg.offset = valid_scalar (cfg.offset, 'offset');
  if (strcmp (cfg.domain, 'discrete') && (cfg.Ts <= 0 || cfg.offset < 0 || cfg.offset >= cfg.Ts))
    error ('ob_pid_controller: discrete Ts must be positive and 0 <= offset < Ts');
  endif
  cfg.x0_i = valid_scalar (cfg.x0_i, 'x0_i');
  cfg.x0_d = valid_scalar (cfg.x0_d, 'x0_d');
  cfg.Kb = valid_scalar (cfg.Kb, 'Kb');
  cfg.b = valid_scalar (cfg.b, 'b');
  cfg.c = valid_scalar (cfg.c, 'c');
  if (! (islogical(cfg.two_dof) || isnumeric(cfg.two_dof)) ...
      || ! isscalar(cfg.two_dof) || ! isreal(cfg.two_dof) || ! any(cfg.two_dof == [false true]))
    error ('ob_pid_controller: two_dof must be a scalar boolean');
  endif
  cfg.two_dof = logical (cfg.two_dof);
  if (! isempty (cfg.limits))
    if (! isnumeric (cfg.limits) || ! isreal (cfg.limits) || numel (cfg.limits) != 2 ...
        || any (! isfinite (cfg.limits)) || cfg.limits(1) > cfg.limits(2))
      error ('ob_pid_controller: limits must be [lower upper] with lower <= upper');
    endif
    cfg.limits = double (cfg.limits(:)');
  endif
endfunction
