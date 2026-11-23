function sys = ob_linearize_jacobian (ctx, x, u, del, method = 'central')
  % Finite-difference linearization of a compiled ob_linearize_context at
  % (X, U).  Returns the documented ob_linearize result struct.
  %   METHOD 'central': state/input j is perturbed by h = DEL*(1 + |value_j|)
  %     in both directions, (f(+h) - f(-h)) / (2h).  Error O(h^2) on smooth
  %     models; at a kink it gives the mean of the one-sided slopes.
  %   METHOD 'v5': Simulink linmod(...,'v5')'s rule, a forward difference
  %     (f(+h) - f(0)) / h with h = DEL*(1 + 1e-3*|value_j|).  Error O(h);
  %     at a kink it gives the right-hand slope, as linmod 'v5' does.
  [dx0, y0] = ob_linearize_eval (ctx, x, u);
  forward = strcmp (method, 'v5');
  n = numel (x); m = numel (u); p = numel (y0);
  A = zeros (n, n); C = zeros (p, n);
  for j = 1:n
    xp = x; xm = x;
    if (forward)
      h = del * (1 + 1e-3 * abs (x(j)));
      xp(j) += h;
      [dxp, yp] = ob_linearize_eval (ctx, xp, u);
      A(:, j) = (dxp - dx0) / h;
      C(:, j) = (yp - y0) / h;
    else
      h = del * (1 + abs (x(j)));
      xp(j) += h; xm(j) -= h;
      [dxp, yp] = ob_linearize_eval (ctx, xp, u);
      [dxm, ym] = ob_linearize_eval (ctx, xm, u);
      A(:, j) = (dxp - dxm) / (2 * h);
      C(:, j) = (yp - ym) / (2 * h);
    endif
  endfor
  B = zeros (n, m); D = zeros (p, m);
  for j = 1:m
    up = u; um = u;
    if (forward)
      h = del * (1 + 1e-3 * abs (u(j)));
      up(j) += h;
      [dxp, yp] = ob_linearize_eval (ctx, x, up);
      B(:, j) = (dxp - dx0) / h;
      D(:, j) = (yp - y0) / h;
    else
      h = del * (1 + abs (u(j)));
      up(j) += h; um(j) -= h;
      [dxp, yp] = ob_linearize_eval (ctx, x, up);
      [dxm, ym] = ob_linearize_eval (ctx, x, um);
      B(:, j) = (dxp - dxm) / (2 * h);
      D(:, j) = (yp - ym) / (2 * h);
    endif
  endfor
  sys = struct ('A', A, 'B', B, 'C', C, 'D', D, ...
                'x0', x, 'u0', u, 'y0', y0, 'dx0', dx0, 't0', ctx.t0, ...
                'state_names', {ctx.state_names}, 'state_paths', {ctx.state_paths}, ...
                'state_index', ctx.state_index, ...
                'input_ports', ctx.input_ports, 'input_index', ctx.input_index, ...
                'output_ports', ctx.output_ports, 'output_index', ctx.output_index, ...
                'output_paths', {ctx.output_paths});
endfunction
