function model = ob_dead_zone_dynamic ()
% OB_DEAD_ZONE_DYNAMIC  Build a Simulink-style Dead Zone Dynamic subsystem.
%   MODEL = OB_DEAD_ZONE_DYNAMIC() outputs zero inside a dead zone whose
%   bounds are signals, with Simulink's port order:
%     Inport 1: up (upper bound)
%     Inport 2: u  (signal)
%     Inport 3: lo (lower bound)
%   and Simulink's priority when the bounds cross (lo > up):
%       y = (u >= up) ? u - up : ((u > lo) ? 0 : u - lo)
%   Scalar ports expand against vector or matrix ports, as in Simulink; the
%   output has the common shape.  Non-scalar ports must have the same size
%   (a row mixed with a column vector broadcasts into a matrix in the
%   engine, unlike Simulink's element-wise 1-D vectors).  The block has no
%   parameters and an inherited sample time.
%
%   Built from native Gain/Sum/Switch primitives (the mask's u_GTE_up and
%   u_GT_lo comparisons and two Switches) for full Octave, strict C99
%   ob_codegen and ob_accelerate parity; both comparisons register
%   zero-crossing guards.  The Switches select the bound to subtract,
%       c = (u >= up) ? up : ((u > lo) ? u : lo),     y = u - c
%   which gives the same doubles (u - u is +0, never -0) without computing
%   the unused differences, and the comparisons use finite signals with the
%   exact sign of u - up and lo - u (0.5*a - 0.5*b + atan(a) - atan(b)).
%   So any finite inputs work, e.g. up = 1e308 with u = -1e308; only an
%   output beyond realmax overflows, as in Simulink.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/deadzonedynamic.html

  B = @ob_builder_block;
  model = B ();
  [model, up] = B (model, 'Inport', 1, 'up', 0.06, 0.82);
  [model, u] = B (model, 'Inport', 2, 'u', 0.06, 0.50);
  [model, lo] = B (model, 'Inport', 3, 'lo', 0.06, 0.18);
  [model, e] = ob_builder_broadcast (model, [up u lo], 0.16, 0.40);
  % u_GT_lo: lo >= u ? lo : u (u > lo keeps u, giving 0);  u_GTE_up: u >= up ? up : inner
  [model, inner] = ob_builder_select (model, e(3), e(2), e(3), e(2), 'u_GT_lo', 0.56, 0.30);
  [model, bound] = ob_builder_select (model, e(2), e(1), e(1), inner, 'u_GTE_up', 0.72, 0.50);
  [model, neg] = B (model, 'Gain', -1, '-bound', 0.80, 0.62, bound);
  [model, y] = B (model, 'Sum', [], 'u - bound', 0.86, 0.50, [e(2) neg]);
  model = B (model, 'Outport', 1, 'y', 0.94, 0.50, y);
endfunction
