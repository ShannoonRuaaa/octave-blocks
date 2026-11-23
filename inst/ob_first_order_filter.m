function model = ob_first_order_filter (kind, tau, gain = 1, Ts = 0, method = 'zoh', x0 = 0, offset = 0)
% OB_FIRST_ORDER_FILTER  Build a continuous or discretized first-order filter.
%   MODEL = OB_FIRST_ORDER_FILTER(KIND, TAU[, GAIN[, Ts[, METHOD[, X0[, OFFSET]]]]])
%   builds one of
%     'lowpass'   H(s) = GAIN / (TAU*s + 1)
%     'highpass'  H(s) = GAIN * TAU*s / (TAU*s + 1)          (washout)
%     'leadlag'   H(s) = GAIN * (TZ*s + 1) / (TP*s + 1),  TAU = [TZ TP]
%   with TAU, TP > 0 (TZ may be any finite real).  All three are realized
%   on the lag state x' = (u - x)/TP, so y = GAIN*x (lowpass),
%   GAIN*(u - x) (highpass) or GAIN*(TZ/TP*u + (1 - TZ/TP)*x) (leadlag),
%   and X0 is the initial value of that lag state: X0 = u0 starts the
%   filter in steady state for a constant input u0.
%
%   Ts = 0 (default) builds the continuous filter (ob_state_space).
%   Ts > 0 discretizes it with ob_c2d_state_space using METHOD 'zoh'
%   (default) or 'tustin' and builds ob_discrete_state_space with sample
%   time [Ts OFFSET]; X0 keeps its meaning (the discrete state is scaled so
%   that X0 = u0 is again a steady state).
%
%   This is an Octave Blocks convenience wrapper over ob_state_space,
%   ob_c2d_state_space and ob_discrete_state_space, not a Simulink block:
%   the continuous form equals Simulink's Transfer Fcn with the numerator
%   and denominator above.  Simulink's discrete 'Transfer Fcn First
%   Order', 'Transfer Fcn Lead or Lag' and 'Transfer Fcn Real Zero' blocks
%   are parameterized by their z-domain pole and zero instead; build those
%   with ob_discrete_transfer_function.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/transferfcn.html

  if (nargin < 2)
    error ('ob_first_order_filter: supply kind, tau[, gain, Ts, method, x0, offset]');
  endif
  if (! ischar (kind) || ! isrow (kind))
    error ('ob_first_order_filter: kind must be ''lowpass'', ''highpass'' or ''leadlag''');
  endif
  validateattributes (gain, {'numeric'}, {'scalar', 'real', 'finite'}, 'ob_first_order_filter', 'gain');
  validateattributes (Ts, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'}, 'ob_first_order_filter', 'Ts');
  validateattributes (x0, {'numeric'}, {'scalar', 'real', 'finite'}, 'ob_first_order_filter', 'x0');
  validateattributes (offset, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'}, ...
                      'ob_first_order_filter', 'offset');
  if (! ischar (method) || ! isrow (method) || ! any (strcmpi (method, {'zoh', 'tustin'})))
    error ('ob_first_order_filter: method must be ''zoh'' or ''tustin''');
  endif
  g = double (gain); Ts = double (Ts); x0 = double (x0); offset = double (offset);
  if (Ts == 0 && offset != 0)
    error ('ob_first_order_filter: offset needs a positive Ts');
  endif
  if (Ts > 0 && offset >= Ts)
    error ('ob_first_order_filter: offset must satisfy 0 <= offset < Ts');
  endif

  switch (lower (kind))
    case {'lowpass', 'highpass'}
      validateattributes (tau, {'numeric'}, {'scalar', 'real', 'finite', 'positive'}, ...
                          'ob_first_order_filter', 'tau');
      tp = double (tau);
      if (strcmpi (kind, 'lowpass')), C = g; D = 0; else C = -g; D = g; endif
    case 'leadlag'
      validateattributes (tau, {'numeric'}, {'numel', 2, 'real', 'finite'}, 'ob_first_order_filter', 'tau');
      tz = double (tau(1)); tp = double (tau(2));
      if (tp <= 0)
        error ('ob_first_order_filter: leadlag needs tau = [tz tp] with tp > 0');
      endif
      D = g * tz / tp; C = g - D;
    otherwise
      error ('ob_first_order_filter: kind must be ''lowpass'', ''highpass'' or ''leadlag''');
  endswitch
  A = -1 / tp; B = 1 / tp;

  if (Ts == 0)
    model = ob_state_space (A, B, C, D, x0);
  else
    [Ad, Bd, Cd, Dd] = ob_c2d_state_space (A, B, C, D, Ts, lower (method));
    % Steady state for a constant input u0 is x = u0 continuously and
    % w = Bd/(1 - Ad)*u0 for the discretized realization.
    model = ob_discrete_state_space (Ad, Bd, Cd, Dd, Ts, x0 * Bd / (1 - Ad), offset);
  endif
endfunction
