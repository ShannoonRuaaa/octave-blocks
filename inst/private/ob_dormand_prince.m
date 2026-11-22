% SPDX-License-Identifier: GPL-3.0-or-later
% Copyright (C) 2006-2026 The Octave Project Developers
% Copyright (C) 2026 Shannon Ruan
%
% Adapted for Octave Blocks from GNU Octave 11.3.0 solver implementation.
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See COPYING.
% Sources and adaptation details: doc/LICENSING.md.

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
