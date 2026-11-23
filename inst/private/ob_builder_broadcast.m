function [model, expanded, zero] = ob_builder_broadcast (model, ids, x, y)
% OB_BUILDER_BROADCAST  Scalar expansion of builder signals, Simulink style.
%   [MODEL, EXPANDED, ZERO] = OB_BUILDER_BROADCAST (MODEL, IDS, X, Y) adds
%   native blocks so that every signal in IDS (block indices, output port 1)
%   has the common broadcast shape of all of them:
%       ZERO        = 0*u1 + 0*u2 + ... + 0*un    (zeros of the common shape)
%       EXPANDED(k) = u_k + ZERO
%   Values are copied exactly (u + 0 == u for finite u).  The engine Switch
%   needs data inputs of identical shapes, so builders route their data
%   signals through this before selecting; Gain and Sum broadcast in ob_run
%   and in ob_codegen, so the expansion exports to C.
%
%   The common shape follows the engine's (Octave's) broadcasting, not
%   Simulink's 1-D vectors: a 1-by-n row and an n-by-1 column combine into
%   an n-by-n matrix (each row element against each column element), where
%   Simulink pairs the two vectors element by element.  Builders therefore
%   document that non-scalar inputs must have the same size.  Sizes that
%   do not broadcast at all (1-by-2 with 1-by-3) raise the usual
%   nonconformant error when the model runs.  No run-time check rejects
%   the row/column case: it would cost one more Switch per input, with a
%   zero-crossing guard per element, in every model, although scalar
%   signals (the usual case) never need it.

  count = numel (ids);
  zeros_of = zeros (1, count);
  for k = 1:count
    [model, zeros_of(k)] = ob_builder_block (model, 'Gain', 0, sprintf ('0*%s', model.blocks(ids(k)).name), ...
                                             x, y + 0.04 * (k - 1), ids(k));
  endfor
  zero = zeros_of(1);
  for k = 2:count
    [model, zero] = ob_builder_block (model, 'Sum', [], sprintf ('zeros%d', k), x + 0.03, y, [zero zeros_of(k)]);
  endfor
  expanded = zeros (1, count);
  for k = 1:count
    [model, expanded(k)] = ob_builder_block (model, 'Sum', [], sprintf ('%s (expanded)', model.blocks(ids(k)).name), ...
                                             x + 0.06, y + 0.04 * (k - 1), [ids(k) zero]);
  endfor
endfunction
