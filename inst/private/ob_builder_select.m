function [model, id] = ob_builder_select (model, a, b, when_ge, when_lt, name, x, y)
% OB_BUILDER_SELECT  Native "a >= b ? when_ge : when_lt" selection.
%   [MODEL, ID] = OB_BUILDER_SELECT (MODEL, A, B, WHEN_GE, WHEN_LT, NAME, X, Y)
%   adds a Switch with threshold 0 that passes WHEN_GE where A >= B and
%   WHEN_LT elsewhere.  Its control is ob_builder_difference (A, B): finite
%   for all finite doubles and exactly of the sign of A - B, so realmax
%   against -realmax compares correctly instead of overflowing.  With B
%   empty the control is A itself (A >= 0).  All arguments except NAME, X
%   and Y are block indices (output port 1).
%
%   The strict relations follow by swapping operands or data inputs:
%       a >  b  ==  !(b >= a),     a <  b  ==  !(a >= b).
%   The Switch registers a zero-crossing guard on the control (it vanishes
%   where A == B), like the ZeroCross=on comparisons inside the Simulink
%   blocks this models.

  control = a;
  if (! isempty (b))
    [model, control] = ob_builder_difference (model, a, b, name, x, y + 0.05);
  endif
  [model, id] = ob_builder_block (model, 'Switch', 0, name, x, y, [when_ge control when_lt]);
endfunction
