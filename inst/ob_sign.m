function model = ob_sign ()
% OB_SIGN  Build a Simulink-style Sign (signum) subsystem.
%   MODEL = OB_SIGN() outputs +1 where u > 0, 0 where u == 0 and -1 where
%   u < 0, element by element for scalar, vector or matrix u, with an
%   inherited sample time (Simulink's only parameter, SampleTime = -1).
%   Built from native Gain, Constant, Sum and Switch primitives for full
%   Octave, strict C99 ob_codegen and ob_accelerate parity.
%
%   Unlike a plain Function block named 'sign', the two Switches register
%   zero-crossing guards at u = 0 (Simulink's ZeroCross = on), so with
%   zero_crossings enabled the solver locates each sign change instead of
%   integrating across it.  The +1/0/-1 levels are derived from u (0*u + c),
%   so they always have the input's shape; the 0 level is +0 even for
%   u = -0, as in Simulink.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/sign.html

  B = @ob_builder_block;
  model = B ();
  [model, u] = B (model, 'Inport', 1, 'u', 0.06, 0.50);
  [model, zero] = B (model, 'Gain', 0, '0*u', 0.20, 0.30, u);
  [model, c0] = B (model, 'Constant', 0, '0', 0.20, 0.46);
  [model, zero_level] = B (model, 'Sum', [], 'Zero level', 0.34, 0.40, [zero c0]);   % +0, also for u = -0
  [model, c1] = B (model, 'Constant', 1, '+1', 0.20, 0.88);
  [model, one] = B (model, 'Sum', [], 'Positive level', 0.34, 0.80, [zero c1]);
  [model, cm1] = B (model, 'Constant', -1, '-1', 0.20, 0.10);
  [model, minus_one] = B (model, 'Sum', [], 'Negative level', 0.34, 0.16, [zero cm1]);
  % NonPos: u >= 0 ? 0 : -1;  Sign: -u >= 0 (u <= 0) ? NonPos : +1
  [model, nonpos] = B (model, 'Switch', 0, 'NonPos', 0.52, 0.34, [zero_level u minus_one]);
  [model, neg] = B (model, 'Gain', -1, '-u', 0.40, 0.60, u);
  [model, sgn] = B (model, 'Switch', 0, 'Sign', 0.74, 0.50, [nonpos neg one]);
  model = B (model, 'Outport', 1, 'y', 0.92, 0.50, sgn);
endfunction
