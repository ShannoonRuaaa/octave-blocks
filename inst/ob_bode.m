function resp = ob_bode (varargin)
% OB_BODE  Frequency response and stability margins of a continuous system.
%   RESP = OB_BODE(A, B, C, D) or RESP = OB_BODE(SYS), where SYS is a struct
%   with fields A, B, C, D such as ob_linearize returns, evaluates
%       H(jw) = C*(jw*I - A)^-1*B + D
%   on an automatic frequency grid.  RESP = OB_BODE(..., W) uses the
%   frequencies W (rad/s, positive, finite).  RESP has fields
%     w        frequencies as a row vector (rad/s)
%     H        p-by-m-by-K complex response
%     mag      |H| (absolute, as MATLAB bode returns it); mag_db = 20*log10|H|
%     phase    unwrapped phase in degrees, p-by-m-by-K
%     Gm, Pm, Wcg, Wcp   margins as MATLAB margin returns them (SISO only):
%              Gm is the gain margin (absolute) measured at the phase
%              crossover frequency Wcg, Pm the phase margin in degrees at the
%              gain crossover frequency Wcp.  Without a crossover the margin
%              is Inf and its frequency NaN.  For MIMO systems all four are NaN.
%     margins  every crossover, as MATLAB allmargin names them:
%              GainMargin, GMFrequency, PhaseMargin, PMFrequency
%
%   The phase is unwrapped along frequency from far below the slowest pole or
%   zero, starting on the branch of the low-frequency asymptote: k poles
%   (zeros) at s = 0 contribute -90k (+90k) degrees, and the gain sign and
%   the other poles and zeros contribute their combined angle at w -> 0
%   wrapped into (-180, 180].  So 1/s^2 starts at -180 degrees, -1/(s+1) at
%   +180, 1/(s-1) at -180 and (1-s)/(s+1)^2 at 0 (falling to -270).  The
%   phase is computed on that dense grid and sampled at W, so a coarse W
%   does not confuse the unwrapping.  Margins are found on the same grid, at
%   every 0 dB crossing and every -180 + 360k degree crossing, and refined
%   with fzero on the exact H.  Gm is the gain margin closest to 0 dB and Pm
%   the phase margin of least magnitude (MATLAB margin reports the minimum
%   margins).  Pm is wrapped into (-180, 180].  Continuous time only;
%   delay margins and closed-loop stability flags are not computed.
%
%   Special cases:
%   - At a frequency on an undamped pole (a pole on the imaginary axis that
%     the channel sees) H is Inf, mag and mag_db are Inf and phase is NaN.
%   - When |H| = 1 over the whole grid (a static gain of 1, an all-pass
%     system) there is no isolated gain crossover: Pm = Inf, Wcp = NaN.
%   - Repeated poles or zeros at s = 0 that eig splits numerically (by about
%     eps^(1/k) for k of them) are counted as lying at s = 0, and the grid
%     and margin search stay 100 times above that split, where H(jw) can be
%     evaluated accurately.  A response requested at a lower W is returned
%     but is limited by that rounding.
%
%   Example:
%     resp = ob_bode (0, 1, 1, 0);                 % integrator 1/s
%     resp = ob_bode (ob_linearize (model), logspace (-1, 2, 100));
%
%   Reference:
%     https://www.mathworks.com/help/control/ref/dynamicsystem.bode.html
%     https://www.mathworks.com/help/control/ref/dynamicsystem.margin.html

  [A, B, C, D, w] = parse_arguments (varargin);
  warning ('off', 'Octave:singular-matrix', 'local');
  warning ('off', 'Octave:nearly-singular-matrix', 'local');
  p = rows (C); m = columns (B);
  [scales, split] = characteristic_frequencies (A, B, C, D);
  if (isempty (w))
    lo = floor (log10 (max (min (scales), 100 * split))) - 1; hi = ceil (log10 (max (scales))) + 1;
    w = logspace (lo, hi, max (200, 50 * (hi - lo)));
  endif
  w = double (w(:)');
  % Dense internal grid: 40 points per decade from far below the slowest to
  % far above the fastest dynamics (but above any numerical split of roots
  % at s = 0), refined around lightly damped modes.
  floor_w = max (1e-6 * min (scales), 100 * split);
  hi = max (max (w), 1e6 * max (scales));
  grid = logspace (log10 (floor_w), log10 (hi), ceil (40 * log10 (hi / floor_w)) + 1);
  grid = [grid, resonance_points(A, B, C, D)];
  [dense, unused, back] = unique ([w, grid]);
  user = back(1:numel (w));
  first = find (dense >= floor_w * (1 - 1e-12), 1);   % reliable part starts here
  Hd = response (A, B, C, D, dense);
  phase_d = zeros (size (Hd));
  for i = 1:p
    for j = 1:m
      phase_d(i, j, :) = unwrapped_phase (squeeze (Hd(i, j, :)).', dense, first, ...
                                          A, B(:, j), C(i, :), D(i, j));
    endfor
  endfor
  H = Hd(:, :, user);
  mag = abs (H);
  resp = struct ('w', w, 'H', H, 'mag', mag, 'mag_db', 20 * log10 (mag), ...
                 'phase', phase_d(:, :, user), ...
                 'Gm', NaN, 'Pm', NaN, 'Wcg', NaN, 'Wcp', NaN, ...
                 'margins', struct ('GainMargin', zeros (1, 0), 'GMFrequency', zeros (1, 0), ...
                                    'PhaseMargin', zeros (1, 0), 'PMFrequency', zeros (1, 0)));
  if (p == 1 && m == 1)
    keep = first:numel (dense);
    resp = margins (resp, A, B, C, D, dense(keep), squeeze (Hd)(keep).', squeeze (phase_d)(keep).');
  endif
endfunction

function [A, B, C, D, w] = parse_arguments (args)
  w = [];
  if (numel (args) >= 1 && isstruct (args{1}))
    if (numel (args) > 2)
      error ('ob_bode:arguments', 'ob_bode: supply (sys[, w]) or (A, B, C, D[, w])');
    endif
    sys = args{1};
    if (! isscalar (sys) || ! all (isfield (sys, {'A', 'B', 'C', 'D'})))
      error ('ob_bode:arguments', 'ob_bode: SYS must be a scalar struct with fields A, B, C and D');
    endif
    A = sys.A; B = sys.B; C = sys.C; D = sys.D;
    if (numel (args) == 2), w = args{2}; endif
  else
    if (numel (args) < 4 || numel (args) > 5)
      error ('ob_bode:arguments', 'ob_bode: supply (sys[, w]) or (A, B, C, D[, w])');
    endif
    [A, B, C, D] = args{1:4};
    if (numel (args) == 5), w = args{5}; endif
  endif
  names = {'A', 'B', 'C', 'D'}; values = {A, B, C, D};
  for k = 1:4
    v = values{k};
    if (! isnumeric (v) || ! isreal (v) || issparse (v) || ndims (v) > 2 || any (! isfinite (v(:))))
      error ('ob_bode:matrix', 'ob_bode: %s must be a finite real full numeric matrix', names{k});
    endif
  endfor
  A = double (A); B = double (B); C = double (C); D = double (D);
  n = rows (A);
  if (columns (A) != n)
    error ('ob_bode:dimensions', 'ob_bode: A must be square');
  endif
  if (isempty (B)), B = zeros (n, columns (D)); endif
  if (isempty (C)), C = zeros (rows (D), n); endif
  if (rows (B) != n || columns (C) != n || rows (D) != rows (C) || columns (D) != columns (B))
    error ('ob_bode:dimensions', 'ob_bode: dimensions must be A(n,n), B(n,m), C(p,n), D(p,m)');
  endif
  if (rows (D) == 0 || columns (D) == 0)
    error ('ob_bode:dimensions', 'ob_bode: the system needs at least one input and one output');
  endif
  if (! isempty (w) || (numel (args) == 2 || numel (args) == 5))
    if (! isnumeric (w) || ! isreal (w) || ! isvector (w) || isempty (w) ...
        || any (! isfinite (w)) || any (w <= 0))
      error ('ob_bode:frequency', 'ob_bode: W must be a nonempty vector of positive finite frequencies');
    endif
  endif
endfunction

function H = response (A, B, C, D, w)
  H = zeros (rows (C), columns (B), numel (w));
  for k = 1:numel (w)
    H(:, :, k) = evaluate (A, B, C, D, w(k));
  endfor
endfunction

function h = evaluate (A, B, C, D, w)
  % H(jw); an entry is Inf where jw is a pole that its channel sees.
  n = rows (A);
  if (n == 0), h = D; return; endif
  I = eye (n);
  M = 1i * w * I - A;
  if (rcond (M) > 10 * n * eps)
    h = C * (M \ B) + D;
    return;
  endif
  % jw is (numerically) an eigenvalue of A.  The entry (i, j) is infinite
  % when that mode is both controllable from input j and observable from
  % output i; other entries are finite and taken as the mean of the values
  % just above and below w.
  [U, S, V] = svd (M);
  s = diag (S);
  null = s <= 10 * n * eps * max (s);
  null(end) = true;
  seen = abs (C * V(:, null)) * abs (U(:, null)' * B);
  infinite = seen > sqrt (eps) * max (1, norm (C, 1) * norm (B, 1));
  delta = 1e-6 * w;
  h = (C * ((1i * (w + delta) * I - A) \ B) + C * ((1i * (w - delta) * I - A) \ B)) / 2 + D;
  h(infinite) = Inf;
endfunction

function z = channel_zeros (A, b, c, d)
  n = rows (A);
  if (n == 0), z = zeros (0, 1); return; endif
  z = eig ([A b; c d], blkdiag (eye (n), 0));
  z = z(isfinite (z));
endfunction

function [rest, k, radius] = split_origin (r, scale)
  % Roots R of a matrix (pencil) of norm SCALE: K of them counted as lying
  % at s = 0, RADIUS the largest magnitude among those K, REST the others.
  % k repeated roots at 0 are split by eig by about SCALE*eps^(1/k), so the
  % k smallest are taken as a cluster at 0 when all are within
  % 10*SCALE*eps^(1/k), within 1e-2*SCALE, and 100 times below the next.
  r = r(:);
  mags = abs (r);
  [sorted, order] = sort (mags);
  k = 0; radius = 0;
  if (scale == 0)
    k = numel (r); rest = zeros (0, 1); return;
  endif
  for j = numel (sorted):-1:1
    next = Inf;
    if (j < numel (sorted)), next = sorted(j + 1); endif
    if (sorted(j) <= min (10 * scale * eps ^ (1 / j), 1e-2 * scale) && sorted(j) <= 1e-2 * next)
      k = j; radius = sorted(j);
      break;
    endif
  endfor
  rest = r(order(k + 1:end));
endfunction

function [poles, kp, radius] = system_poles (A)
  [poles, kp, radius] = split_origin (eig (A), norm (A, 1));
endfunction

function [zs, kz, radius] = system_zeros (A, b, c, d)
  [zs, kz, radius] = split_origin (channel_zeros (A, b, c, d), norm ([A b; c d], 1));
endfunction

function [scales, split] = characteristic_frequencies (A, B, C, D)
  % Magnitudes of the poles and channel zeros away from s = 0, and the
  % largest numerical split of the roots counted as lying at s = 0.
  [roots_all, unused, split] = system_poles (A);
  for i = 1:rows (C)
    for j = 1:columns (B)
      [zs, unused, radius] = system_zeros (A, B(:, j), C(i, :), D(i, j));
      roots_all = [roots_all; zs];
      split = max (split, radius);
    endfor
  endfor
  scales = abs (roots_all);
  scales = scales(scales > 0);
  if (isempty (scales)), scales = 1; endif
endfunction

function points = resonance_points (A, B, C, D)
  % Extra samples across each complex pole/zero's resonance band so the
  % phase is unwrapped correctly through lightly damped modes.
  points = zeros (1, 0);
  roots_all = eig (A);
  for i = 1:rows (C)
    for j = 1:columns (B)
      roots_all = [roots_all; channel_zeros(A, B(:, j), C(i, :), D(i, j))];
    endfor
  endfor
  for r = roots_all.'
    if (abs (imag (r)) > 0)
      width = max (abs (real (r)), 1e-9 * abs (r));
      band = abs (imag (r)) + width * linspace (-8, 8, 33);
      points = [points band(band > 0)];
    endif
  endfor
endfunction

function phase = unwrapped_phase (h, w, first, A, b, c, d)
  % Continuous phase in degrees on increasing W, branch fixed at W(FIRST) by
  % the low-frequency asymptote K*(jw)^k.  Samples where H is Inf (an
  % undamped pole) or exactly 0 (an undamped zero) have no phase (NaN).
  phase = zeros (size (h));
  if (all (h == 0)), return; endif
  phase(:) = NaN;
  ok = find (isfinite (h) & h != 0);
  if (isempty (ok)), return; endif
  raw = angle (h(ok)) * 180 / pi;
  steps = diff (raw);
  steps = steps - 360 * round (steps / 360);
  values = raw(1) + [0 cumsum(steps)];
  % Branch at the first reliable frequency: H = K*prod(s - z)/prod(s - p)
  % with K real.  Roots at the origin give +-90 degrees each; the gain sign
  % and the other roots' angles there are combined and wrapped into
  % (-180, 180].
  ref = find (ok >= first, 1);
  if (isempty (ref)), ref = 1; endif
  w1 = w(ok(ref));
  [z, kz] = system_zeros (A, b, c, d);
  [poles, kp] = system_poles (A);
  k = kz - kp;
  factors = sum (angle (1i * w1 - z)) - sum (angle (1i * w1 - poles)) + k * pi / 2;
  gain_angle = pi * (cos (angle (h(ok(ref))) - factors) < 0);
  other = (gain_angle + factors - k * pi / 2) * 180 / pi;
  other -= 360 * ceil ((other - 180) / 360);
  target = 90 * k + other;
  values += 360 * round ((target - values(ref)) / 360);
  phase(ok) = values;
endfunction

function resp = margins (resp, A, B, C, D, w, h, phase)
  % Samples without a phase (H Inf or 0 on the imaginary axis) are skipped.
  ok = isfinite (h) & isfinite (phase);
  w = w(ok); h = h(ok); phase = phase(ok);
  logmag = log (abs (h));
  s = log (w);
  gm = []; wgm = []; pm = []; wpm = [];
  opts = optimset ('TolX', 1e-14);
  % Phase crossovers: phase = -180 + 360k for any integer k.
  band = floor ((phase + 180) / 360);
  for i = find (band(1:end-1) != band(2:end))
    level = -180 + 360 * max (band(i), band(i + 1));
    f = @(x) local_phase (A, B, C, D, exp (x), w(i), h(i), phase(i)) - level;
    x = refine (f, s(i), s(i + 1), opts);
    hc = evaluate (A, B, C, D, exp (x));
    if (isfinite (hc) && abs (hc) > 0)
      gm(end + 1) = 1 / abs (hc); wgm(end + 1) = exp (x);
    endif
  endfor
  % Gain crossovers: |H| = 1.  Samples within 1e-12 of 0 dB count as on it;
  % a run of such samples between two others is one crossing (at its middle
  % sample), a run touching either end of the grid is none, so |H| = 1
  % everywhere gives no crossing rather than one per sample.
  level = logmag;
  level(abs (level) < 1e-12) = 0;
  sg = sign (level);
  nonzero = find (sg != 0);
  f = @(x) log (abs (evaluate (A, B, C, D, exp (x))));
  for t = 1:numel (nonzero) - 1
    a = nonzero(t); b = nonzero(t + 1);
    if (b == a + 1)
      if (sg(a) == sg(b)), continue; endif
      x = refine (f, s(a), s(b), opts); i = a;
    else
      i = floor ((a + b) / 2); x = s(i);
    endif
    ph = local_phase (A, B, C, D, exp (x), w(i), h(i), phase(i));
    value = ph + 180;
    value -= 360 * ceil ((value - 180) / 360);
    pm(end + 1) = value; wpm(end + 1) = exp (x);
  endfor
  resp.margins = struct ('GainMargin', gm, 'GMFrequency', wgm, ...
                         'PhaseMargin', pm, 'PMFrequency', wpm);
  if (isempty (gm)), resp.Gm = Inf; resp.Wcg = NaN;
  else
    [unused, k] = min (abs (log (gm))); resp.Gm = gm(k); resp.Wcg = wgm(k);
  endif
  if (isempty (pm)), resp.Pm = Inf; resp.Wcp = NaN;
  else
    [unused, k] = min (abs (pm)); resp.Pm = pm(k); resp.Wcp = wpm(k);
  endif
endfunction

function x = refine (f, a, b, opts)
  fa = f (a); fb = f (b);
  if (fa == 0), x = a; return; endif
  if (fb == 0), x = b; return; endif
  if (sign (fa) == sign (fb)), x = (a + b) / 2; return; endif
  x = fzero (f, [a b], opts);
endfunction

function ph = local_phase (A, B, C, D, w, w_ref, h_ref, phase_ref)
  % Phase continued from the grid point (w_ref, phase_ref); the dense grid
  % keeps the change between neighbours below 180 degrees.
  delta = (angle (evaluate (A, B, C, D, w)) - angle (h_ref)) * 180 / pi;
  ph = phase_ref + delta - 360 * round (delta / 360);
endfunction
