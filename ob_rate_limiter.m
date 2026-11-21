function model = ob_rate_limiter (rising_rate, falling_rate, Ts = 0.1, y0 = 0, offset = 0)
% OB_RATE_LIMITER  Build a Simulink-style discrete Rate Limiter subsystem.
%   MODEL = OB_RATE_LIMITER(R, F[, Ts[, Y0[, OFFSET]]]) limits the slew rate
%   of the input signal between falling_rate (F <= 0) and rising_rate (R >= 0)
%   over each sample period Ts > 0:
%       y[k] = y[k-1] + sat_{[F*Ts, R*Ts]}(u[k] - y[k-1])
%   Built from native primitives for full Octave + C99 ob_codegen parity.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/ratelimiter.html

  if (nargin < 2 || nargin > 5)
    error ('ob_rate_limiter: supply rising_rate, falling_rate[, Ts, y0, offset]');
  endif
  for value = {rising_rate,falling_rate,Ts,y0,offset}
    validateattributes (value{1}, {'numeric'}, {'scalar','real','finite'});
  endfor
  R = double(rising_rate); F = double(falling_rate); Ts = double(Ts);
  y0 = double(y0); offset = double(offset);
  if (R < 0 || F > 0 || ! all(isfinite([R F]*Ts)))
    error ('ob_rate_limiter: require finite step limits with falling_rate <= 0 <= rising_rate');
  endif
  if (! isscalar (Ts) || ! isfinite (Ts) || Ts <= 0 || ! isscalar (offset) || offset < 0 || offset >= Ts)
    error ('ob_rate_limiter: Ts must be positive and 0 <= offset < Ts');
  endif

  blocks = struct ( ...
    'type',  {'Inport', 'Unit Delay', 'Gain', 'Sum', 'Saturation', 'Sum', 'Outport'}, ...
    'value', {1, y0, -1, [], [F * Ts, R * Ts], [], 1}, ...
    'name',  {'u', 'y_prev', '-y_prev', 'du', 'SlewSat', 'y', 'out'}, ...
    'x',     {0.08, 0.55, 0.25, 0.38, 0.55, 0.74, 0.90}, ...
    'y',     {0.60, 0.20, 0.20, 0.60, 0.60, 0.60, 0.60});
  edges = [1 1 4 1; ...
           2 1 3 1; ...
           3 1 4 2; ...
           4 1 5 1; ...
           5 1 6 1; ...
           2 1 6 2; ...
           6 1 2 1; ...
           6 1 7 1];
  rates = zeros (numel (blocks), 2);
  rates(2, :) = [Ts, offset];
  model = struct ('blocks', blocks, 'edges', edges, 'sample_times', rates, ...
                  'execution', struct ('mode', 'virtual'));
  model = ob_hold_builder_output (model, 7, y0, [Ts offset]);
endfunction
