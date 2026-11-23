function model = ob_saturation_dynamic ()
% OB_SATURATION_DYNAMIC  Build a Simulink-style Saturation Dynamic subsystem.
%   MODEL = OB_SATURATION_DYNAMIC() limits a signal to bounds supplied as
%   signals, with Simulink's port order:
%     Inport 1: up (upper limit)
%     Inport 2: u  (signal)
%     Inport 3: lo (lower limit)
%   and Simulink's priority when the limits cross (lo > up):
%       y = (u > up) ? up : ((u < lo) ? lo : u)
%   Scalar ports expand against vector or matrix ports, as in Simulink; the
%   output has the common shape.  Non-scalar ports must have the same size
%   (a row mixed with a column vector broadcasts into a matrix in the
%   engine, unlike Simulink's element-wise 1-D vectors).  The block has no
%   parameters (the library mask only sets data types) and an inherited
%   sample time.
%
%   Built from native Gain/Sum/Switch primitives for full Octave, strict
%   C99 ob_codegen and ob_accelerate parity; the two comparisons register
%   zero-crossing guards like the Relational Operators inside the mask.
%   Their controls are finite signals with the exact sign of u - lo and
%   up - u (0.5*a - 0.5*b + atan(a) - atan(b)), so any finite limits work,
%   including +-realmax as "no limit".
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/saturationdynamic.html

  B = @ob_builder_block;
  model = B ();
  [model, up] = B (model, 'Inport', 1, 'up', 0.06, 0.82);
  [model, u] = B (model, 'Inport', 2, 'u', 0.06, 0.50);
  [model, lo] = B (model, 'Inport', 3, 'lo', 0.06, 0.18);
  [model, e] = ob_builder_broadcast (model, [up u lo], 0.16, 0.40);
  % Inner: u >= lo ? u : lo;  outer: up >= u ? inner : up
  [model, inner] = ob_builder_select (model, e(2), e(3), e(2), e(3), 'LowerLimit', 0.58, 0.36);
  [model, y] = ob_builder_select (model, e(1), e(2), inner, e(1), 'UpperLimit', 0.80, 0.50);
  model = B (model, 'Outport', 1, 'y', 0.94, 0.50, y);
endfunction
