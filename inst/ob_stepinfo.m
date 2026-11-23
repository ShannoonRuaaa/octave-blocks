function info = ob_stepinfo (y, t, varargin)
% OB_STEPINFO  Step-response characteristics of sampled response data.
%   INFO = OB_STEPINFO(Y, T) computes rise time, settling time and the other
%   characteristics of MATLAB stepinfo(y,t) for a response Y sampled at
%   strictly increasing times T.
%   INFO = OB_STEPINFO(Y, T, YFINAL) uses the steady-state value YFINAL
%   (default: the last sample of each channel).
%   INFO = OB_STEPINFO(Y, T, YFINAL, YINIT) measures relative to the initial
%   value YINIT (default 0, as in MATLAB; pass Y(1) for responses that start
%   from an offset).  Either may be [] for its default.
%   Name-value options (or one struct with these fields):
%     'SettlingTimeThreshold'  ST in (0, 1), default 0.02
%     'RiseTimeLimits'         [lo hi] with 0 <= lo <= hi <= 1, default [0.1 0.9]
%   With ynorm = (y - yinit)/(yfinal - yinit), INFO has fields
%     RiseTime       time for ynorm to first rise from lo to hi
%     TransientTime  first time after which |y - yfinal| <= ST*max|y - yfinal|
%     SettlingTime   first time after which |y - yfinal| <= ST*|yfinal - yinit|
%     SettlingMin, SettlingMax   min and max of y once ynorm has reached hi
%     Overshoot      max(0, 100*(max(ynorm) - 1)), percent
%     Undershoot     max(0, -100*min(ynorm)), percent
%     Peak, PeakTime peak of |y - yinit| and the (first) time it occurs
%     SteadyState    yfinal
%   Threshold crossings are interpolated linearly between samples.  A
%   response still outside the band at its last sample has SettlingTime NaN
%   (and TransientTime NaN likewise); a level that is never reached gives a
%   NaN RiseTime and SettlingMin/SettlingMax.  When yfinal equals yinit the
%   normalized quantities (RiseTime, SettlingTime, SettlingMin, SettlingMax,
%   Overshoot, Undershoot) are NaN.  Y may be an NS-by-NY matrix (one channel
%   per column, NS = numel(T)); INFO is then an NY-by-1 struct array and
%   YFINAL/YINIT may be scalars or NY-element vectors.  Without YFINAL an
%   unsettled response is measured against its last sample, which may
%   understate overshoot; supply the true final value when it is known.
%
%   Example:
%     result = ob_run (model, 0:0.01:10);
%     info = ob_stepinfo (ob_scope_data (result, 3), result.t);
%
%   Reference:
%     https://www.mathworks.com/help/control/ref/dynamicsystem.stepinfo.html

  if (nargin < 2)
    error ('ob_stepinfo:arguments', 'ob_stepinfo: supply response data y and times t');
  endif
  if (! isnumeric (y) || ! isreal (y) || issparse (y) || ndims (y) > 2 || isempty (y) ...
      || any (! isfinite (y(:))))
    error ('ob_stepinfo:data', 'ob_stepinfo: Y must be a nonempty finite real numeric vector or matrix');
  endif
  if (! isnumeric (t) || ! isreal (t) || ! isvector (t) || numel (t) < 2 ...
      || any (! isfinite (t(:))))
    error ('ob_stepinfo:time', 'ob_stepinfo: T must be a finite real vector with at least two samples');
  endif
  t = double (t(:));
  if (any (diff (t) <= 0))
    error ('ob_stepinfo:time', 'ob_stepinfo: T must be strictly increasing');
  endif
  y = double (y);
  if (isvector (y)), y = y(:); endif
  if (rows (y) != numel (t))
    error ('ob_stepinfo:data', 'ob_stepinfo: Y must have one row per time sample (%d)', numel (t));
  endif
  ny = columns (y);
  [yfinal, yinit, st, rt] = parse_options (varargin, ny);
  if (isempty (yfinal)), yfinal = y(end, :); endif
  for k = ny:-1:1
    info(k, 1) = channel (y(:, k), t, yfinal(k), yinit(k), st, rt);
  endfor
endfunction

function [yfinal, yinit, st, rt] = parse_options (args, ny)
  yfinal = []; yinit = zeros (1, ny);
  positional = 0;
  while (positional < numel (args) && positional < 2 && ! ischar (args{positional + 1}) ...
         && ! isstruct (args{positional + 1}))
    positional += 1;
    value = args{positional};
    if (isempty (value)), continue; endif
    name = {'YFINAL', 'YINIT'}{positional};
    if (! isnumeric (value) || ! isreal (value) || any (! isfinite (value(:))) ...
        || ! (isscalar (value) || numel (value) == ny))
      error ('ob_stepinfo:value', 'ob_stepinfo: %s must be a finite real scalar or one value per channel', name);
    endif
    value = double (value(:)') .* ones (1, ny);
    if (positional == 1), yfinal = value; else yinit = value; endif
  endwhile
  rest = args(positional + 1:end);
  st = 0.02; rt = [0.1 0.9];
  if (numel (rest) == 1 && isstruct (rest{1}) && isscalar (rest{1}))
    names = fieldnames (rest{1});
    values = struct2cell (rest{1});
    rest = [names(:)'; values(:)'](:)';
  elseif (mod (numel (rest), 2) != 0)
    error ('ob_stepinfo:arguments', 'ob_stepinfo: options must be name-value pairs or one struct');
  endif
  for k = 1:2:numel (rest)
    name = rest{k}; value = rest{k + 1};
    if (! ischar (name))
      error ('ob_stepinfo:arguments', 'ob_stepinfo: option names must be strings');
    endif
    switch (lower (name))
      case 'settlingtimethreshold'
        if (! isnumeric (value) || ! isreal (value) || ! isscalar (value) || ! (value > 0 && value < 1))
          error ('ob_stepinfo:option', 'ob_stepinfo: SettlingTimeThreshold must be a scalar in (0, 1)');
        endif
        st = double (value);
      case 'risetimelimits'
        if (! isnumeric (value) || ! isreal (value) || numel (value) != 2 || any (! isfinite (value)) ...
            || value(1) < 0 || value(2) > 1 || value(1) > value(2))
          error ('ob_stepinfo:option', 'ob_stepinfo: RiseTimeLimits must be [lo hi] with 0 <= lo <= hi <= 1');
        endif
        rt = double (value(:)');
      otherwise
        error ('ob_stepinfo:arguments', 'ob_stepinfo: unknown option ''%s''', name);
    endswitch
  endfor
endfunction

function s = channel (y, t, yfinal, yinit, st, rt)
  [peak, at] = max (abs (y - yinit));
  err = abs (y - yfinal);
  s = struct ('RiseTime', NaN, 'TransientTime', settle (t, err, st * max (err)), ...
              'SettlingTime', NaN, 'SettlingMin', NaN, 'SettlingMax', NaN, ...
              'Overshoot', NaN, 'Undershoot', NaN, 'Peak', peak, ...
              'PeakTime', t(at), 'SteadyState', yfinal);
  dy = yfinal - yinit;
  if (dy == 0), return; endif
  ynorm = (y - yinit) / dy;
  t_lo = crossing (t, ynorm, rt(1));
  if (! isnan (t_lo))
    first = find (t >= t_lo, 1);
    t_hi = crossing (t(max (first - 1, 1):end), ynorm(max (first - 1, 1):end), rt(2));
    s.RiseTime = t_hi - t_lo;          % NaN when the upper limit is never reached
  endif
  s.SettlingTime = settle (t, err, st * abs (dy));
  risen = find (ynorm >= rt(2), 1);
  if (! isempty (risen))
    s.SettlingMin = min (y(risen:end)); s.SettlingMax = max (y(risen:end));
  endif
  s.Overshoot = max (0, 100 * (max (ynorm) - 1));
  s.Undershoot = max (0, -100 * min (ynorm));
endfunction

function tc = crossing (t, v, level)
  % First time V reaches LEVEL, interpolated within the sample interval.
  k = find (v >= level, 1);
  if (isempty (k)), tc = NaN;
  elseif (k == 1), tc = t(1);
  else
    tc = t(k - 1) + (level - v(k - 1)) / (v(k) - v(k - 1)) * (t(k) - t(k - 1));
  endif
endfunction

function ts = settle (t, err, band)
  % First time after which ERR stays within BAND, interpolated within the
  % interval where it last leaves the band; NaN if the final sample is out.
  outside = find (err > band);
  if (isempty (outside)), ts = t(1);
  elseif (outside(end) == numel (t)), ts = NaN;
  else
    k = outside(end);
    ts = t(k) + (err(k) - band) / (err(k) - err(k + 1)) * (t(k + 1) - t(k));
  endif
endfunction
