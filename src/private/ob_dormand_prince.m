function [times, solution] = ob_dormand_prince (fcn, t0, tf, x0, reltol, abstol, maxstep, monitor = [])
  % ode45 (fcn, [t0 tf], x0, odeset ('RelTol', reltol, 'AbsTol', abstol,
  % 'MaxStep', maxstep, 'Refine', 1, 'OutputFcn', monitor)) of Octave 11.3,
  % without its per-call option handling.
  %
  % Octave's ode45 runs odedefaults, odeset (inputParser), rmfield and
  % odemergeopts (validateattributes) on every call: about 5 ms, once per
  % solver segment, which dominated adaptive runs with short output
  % intervals.  This is the same algorithm with the same arithmetic, written
  % out for the one configuration the engine uses: a two-element time span,
  % scalar double tolerances, no events, mass matrix or NonNegative, normal
  % (not norm) error control and Refine 1.  The expressions below are those
  % of ode45, starting_stepsize, integrate_adaptive (with kahan),
  % runge_kutta_45_dorpri and AbsRel_norm, in the same order and with the
  % same operand shapes, so every value is bit-identical, every right-hand
  % side is called with the same arguments in the same order, and accepted
  % steps reach the monitor (as OutputFcn (t, x, [])) exactly as before.
  % The 'init' and 'done' OutputFcn calls are not made: the engine's
  % monitors ignore every call with a flag.
  %
  % ob_dormand_prince ('available') says whether this Octave's ode45 is the
  % reproduced one (Octave 11.3); callers use ode45 itself otherwise.
  % Returns times (column) and solution (one row per time) like ode45's
  % [t, y] outputs.
  persistent available;
  if (ischar (fcn))
    if (isempty (available)), available = strcmp (OCTAVE_VERSION, '11.3.0'); endif
    times = available;
    return;
  endif
  persistent a = [0           0          0           0        0          0;
                  1/5         0          0           0        0          0;
                  3/40        9/40       0           0        0          0;
                  44/45      -56/15      32/9        0        0          0;
                  19372/6561 -25360/2187 64448/6561 -212/729  0          0;
                  9017/3168  -355/33     46732/5247  49/176  -5103/18656 0];
  persistent b = [0, 1/5, 3/10, 4/5, 8/9, 1, 1];
  persistent c = [35/384, 0, 500/1113, 125/192, -2187/6784, 11/84];
  persistent c_prime = [5179/57600, 0, 7571/16695, 393/640, ...
                        -92097/339200, 187/2100, 1/40];
  order = 5;
  have_monitor = ! isempty (monitor);
  x0 = x0(:);
  dir = sign (tf - t0);

  % ode45: InitialStep = direction * starting_stepsize (...).
  d0 = abs_rel_norm (x0, x0, abstol, reltol, zeros (size (x0)));
  y = fcn (t0, x0);
  d1 = abs_rel_norm (y, y, abstol, reltol, zeros (size (y)));
  if (d0 < 1e-5 || d1 < 1e-5)
    h0 = 1e-6;
  else
    h0 = .01 * (d0 / d1);
  endif
  x1 = x0 + h0 * y;
  yh = fcn (t0+h0, x1);
  d2 = (1 / h0) * abs_rel_norm (yh - y, yh - y, abstol, reltol, zeros (size (yh - y)));
  if (max (d1, d2) <= 1e-15)
    h1 = max (1e-6, h0 * 1e-3);
  else
    h1 = (1e-2 / max (d1, d2)) ^(1 / (order+1));
  endif
  dt = dir * min (100 * h0, h1);

  % integrate_adaptive with Refine 1.
  t_old = t0; last_accepted = t0;
  x_old = x0;
  output_t = zeros (1, 64); output_t(1) = t0;
  output_x = zeros (numel (x0), 64); output_x(:, 1) = x0;
  dt = dir * min (abs (dt), maxstep);
  comp = 0.0;
  facmin = 0.8;
  facmax = 1.5;
  fac = 0.38^(1/(order+1));
  unhandledtermination = true;
  ireject = 0;
  k_vals = [];
  iout = 1;
  while (dir * t_old < dir * tf)
    % kahan (t_old, comp, dt)
    kahan_y = dt - comp;
    t_new = t_old + kahan_y;
    comp = (t_new - t_old) - kahan_y;
    % runge_kutta_45_dorpri (fcn, t_old, x_old, dt, options, k_vals, t_new)
    s = t_old + dt * b;
    cc = dt * c;
    aa = dt * a;
    k = zeros (rows (x_old), 7);
    if (! isempty (k_vals))
      k(:,1) = k_vals(:,end);
    else
      k(:,1) = fcn (t_old, x_old);
    endif
    k(:,2) = fcn (s(2), x_old + k(:,1)   * aa(2, 1).'  );
    k(:,3) = fcn (s(3), x_old + k(:,1:2) * aa(3, 1:2).');
    k(:,4) = fcn (s(4), x_old + k(:,1:3) * aa(4, 1:3).');
    k(:,5) = fcn (s(5), x_old + k(:,1:4) * aa(5, 1:4).');
    k(:,6) = fcn (s(6), x_old + k(:,1:5) * aa(6, 1:5).');
    x_new = x_old + k(:,1:6) * cc(:);
    k(:,7) = fcn (t_new, x_new);
    cc_prime = dt * c_prime;
    x_est = x_old + k * cc_prime(:);
    err = abs_rel_norm (x_new, x_old, abstol, reltol, x_est);
    if (err <= 1)
      ireject = 0;
      last_accepted = t_new;
      iout += 1;
      output_x(:, iout) = x_new;
      output_t(iout) = t_new;
      if (have_monitor && monitor (output_t(iout), output_x(:, iout), []))
        unhandledtermination = false;
        break;
      endif
      t_old = t_new;
      x_old = x_new;
      k_vals = k;
    else
      ireject += 1;
      if (ireject >= 5_000)
        error (["integrate_adaptive: Solving was not successful. ", ...
                " The iterative integration loop exited at time", ...
                " t = %f before the endpoint at tend = %f was reached. ", ...
                " This happened because the iterative integration loop", ...
                " did not find a valid solution at this time stamp. ", ...
                " Try to reduce the value of 'InitialStep' and/or", ...
                " 'MaxStep' with the command 'odeset'.\n"],
               t_old, tf);
      endif
    endif
    err += eps;
    dt *= min (facmax, max (facmin, fac * (1 / err)^(1 / (order + 1))));
    dt = dir * min (abs (dt), maxstep);
    if (! (abs (dt) > eps (last_accepted)))
      break;
    endif
    dt = dir * min (abs (dt), abs (tf - t_old));
  endwhile
  if (dir * last_accepted < dir * tf && unhandledtermination)
    warning ("integrate_adaptive:unexpected_termination",
             [" Solving was not successful. ", ...
              " The iterative integration loop exited at time", ...
              " t = %f before the endpoint at tend = %f was reached. ", ...
              " This may happen if the stepsize becomes too small. ", ...
              " Try to reduce the value of 'InitialStep'", ...
              " and/or 'MaxStep' with the command 'odeset'."],
             last_accepted, tf);
  endif
  times = output_t(1:iout).';
  solution = output_x(:, 1:iout).';
endfunction

function retval = abs_rel_norm (x, x_old, AbsTol, RelTol, y)
  % AbsRel_norm without NormControl.
  sc = max (AbsTol(:), RelTol .* max (abs (x), abs (x_old)));
  retval = max (abs (x - y) ./ sc);
endfunction

%!test
%! % Bit-identical to Octave's ode45 on a nonlinear system, accepted steps
%! % and right-hand side calls included.
%! if (ob_dormand_prince ('available'))
%!   f = @(t, y) [y(2); -sin(y(1)) + 0.1*cos(3*t)];
%!   for config = {{1e-6, 1e-9, 0.7}, {1e-10, 1e-12, 0.05}, {1e-3, 1e-6, 2}}
%!     [r, a, m] = config{1}{:};
%!     [t1, y1] = ode45 (f, [0.3 4.1], [1; 0], odeset ('RelTol', r, 'AbsTol', a, 'MaxStep', m, 'Refine', 1));
%!     [t2, y2] = ob_dormand_prince (f, 0.3, 4.1, [1; 0], r, a, m);
%!     assert (isequal (t1, t2) && isequal (y1, y2));
%!   endfor
%!   [t1, y1] = ode45 (@(t, y) -2*y, [0 1], 1, odeset ('RelTol', 1e-8, 'AbsTol', 1e-10, 'MaxStep', 1, 'Refine', 1));
%!   [t2, y2] = ob_dormand_prince (@(t, y) -2*y, 0, 1, 1, 1e-8, 1e-10, 1);
%!   assert (isequal (t1, t2) && isequal (y1, y2));
%! endif

%!test
%! % A monitor stop ends integration after the stopping step, as OutputFcn does.
%! if (ob_dormand_prince ('available'))
%!   stop_after = @(t, y, flag) isempty (flag) && t > 0.5;
%!   options = odeset ('RelTol', 1e-6, 'AbsTol', 1e-9, 'MaxStep', 0.1, 'Refine', 1, 'OutputFcn', stop_after);
%!   [t1, y1] = ode45 (@(t, y) cos (t) * y, [0 2], [1; 2], options);
%!   [t2, y2] = ob_dormand_prince (@(t, y) cos (t) * y, 0, 2, [1; 2], 1e-6, 1e-9, 0.1, stop_after);
%!   assert (isequal (t1, t2) && isequal (y1, y2));
%!   assert (t2(end) > 0.5 && t2(end-1) <= 0.5);
%! endif
