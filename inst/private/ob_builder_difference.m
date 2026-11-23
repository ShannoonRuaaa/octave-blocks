function [model, id] = ob_builder_difference (model, a, b, name, x, y)
% OB_BUILDER_DIFFERENCE  Finite native signal with the sign of A - B.
%   [MODEL, ID] = OB_BUILDER_DIFFERENCE (MODEL, A, B, NAME, X, Y) adds the
%   blocks for
%       D = 0.5*A - 0.5*B + (atan(A) - atan(B))
%   (Gain 0.5, Gain -0.5, Sum; C-mapped Functions atan, atan, minus; Sum)
%   and returns the index of the block that outputs D.  A and B are block
%   indices (output port 1); NAME, X and Y label and place the blocks.
%
%   For all finite doubles D is finite and sign(D) == sign(A - B), with
%   D == 0 exactly when A == B, so it can drive a Switch (threshold 0)
%   where the plain difference A - B would overflow to +-Inf (realmax
%   against -realmax), which a Switch control and the C exporter's
%   finiteness check both reject:
%     - |0.5*A - 0.5*B| <= realmax and |atan(A) - atan(B)| <= pi, and
%       realmax + pi rounds to realmax, so no term overflows;
%     - both terms are monotone in A - B, so neither has the opposite sign;
%     - halving is exact above 2^-1021, so 0.5*A - 0.5*B is nonzero for
%       distinct A and B there; below it, where halving can merge two
%       subnormals, atan is the identity (in Octave and in C), so the atan
%       term is the exact nonzero difference A - B.
%   D is smooth and vanishes only where A == B, so zero-crossing guards on
%   it locate the same instants as guards on A - B.

  [model, half_a] = ob_builder_block (model, 'Gain', 0.5, [model.blocks(a).name '/2'], x - 0.10, y + 0.02, a);
  [model, half_b] = ob_builder_block (model, 'Gain', -0.5, ['-' model.blocks(b).name '/2'], x - 0.10, y + 0.06, b);
  [model, halves] = ob_builder_block (model, 'Sum', [], [name ' halves'], x - 0.07, y + 0.04, [half_a half_b]);
  [model, atan_a] = ob_builder_block (model, 'Function', [], 'atan', x - 0.10, y + 0.10, a);
  [model, atan_b] = ob_builder_block (model, 'Function', [], 'atan', x - 0.10, y + 0.14, b);
  [model, angles] = ob_builder_block (model, 'Function', [], 'minus', x - 0.07, y + 0.12, [atan_a atan_b]);
  [model, id] = ob_builder_block (model, 'Sum', [], [name ' difference'], x - 0.04, y + 0.06, [halves angles]);
endfunction
