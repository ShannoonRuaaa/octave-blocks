function model = ob_logical_operator (op = 'AND', inputs = 2)
% OB_LOGICAL_OPERATOR  Build a Simulink-style Logical Operator subsystem.
%   MODEL = OB_LOGICAL_OPERATOR([OP[, INPUTS]]) combines INPUTS signals,
%   each nonzero element counting as true, and outputs 1 (true) or 0:
%     'AND'  (Simulink's default)  all inputs true
%     'OR'                         at least one input true
%     'NAND' / 'NOR'               negations of AND / OR
%     'XOR'                        an odd number of inputs true
%     'NXOR'                       an even number of inputs true
%     'NOT'                        the single input false (INPUTS = 1)
%   INPUTS defaults to 2 (Simulink's default), or 1 for 'NOT', and must be
%   at least 2 for the other operators.  Scalar inputs expand against
%   vector or matrix inputs, as in Simulink; the output has the common
%   shape.  Non-scalar inputs must have the same size: a row mixed with a
%   column vector broadcasts into a matrix of all element pairs in the
%   engine, where Simulink's 1-D vectors pair element by element.  OP is
%   case-insensitive.  Sample time is inherited.
%
%   Limits: the output is double 0/1 rather than Simulink's default boolean;
%   Simulink's single-input reduction (INPUTS = 1 with an operator other
%   than NOT, applied across the elements of one vector) is not supported.
%
%   Each input becomes b = |sign(u)| (exactly 0 or 1).  AND multiplies the
%   b's, OR takes sign(b1 + b2 + ...), XOR chains |acc - b|, and the
%   negated forms subtract from 1.  Every stage is a two-input Sum or a
%   C-mapped Function (sign, abs, times, minus), so the subsystem runs in
%   full Octave, strict C99 ob_codegen and ob_accelerate.  Like Simulink's
%   Logic block, which has no ZeroCross parameter, it registers no
%   zero-crossing guards.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/logicaloperator.html

  operators = {'AND', 'OR', 'NAND', 'NOR', 'XOR', 'NXOR', 'NOT'};
  if (! ischar (op) || rows (op) != 1 || ! any (strcmpi (op, operators)))
    error ('ob_logical_operator: op must be AND, OR, NAND, NOR, XOR, NXOR or NOT');
  endif
  op = upper (op);
  if (nargin < 2 && strcmp (op, 'NOT')), inputs = 1; endif
  validateattributes (inputs, {'numeric'}, {'scalar', 'real', 'finite', 'integer', 'positive'}, ...
                      'ob_logical_operator', 'inputs');
  n = double (inputs);
  if (strcmp (op, 'NOT') && n != 1)
    error ('ob_logical_operator: NOT takes exactly 1 input');
  elseif (! strcmp (op, 'NOT') && n < 2)
    error ('ob_logical_operator: %s needs inputs >= 2 (single-input reduction over elements is not supported)', op);
  endif

  B = @ob_builder_block;
  model = B ();
  truth = zeros (1, n);
  for k = 1:n
    yk = 0.85 - 0.7 * (k - 1) / max (1, n - 1);
    [model, port] = B (model, 'Inport', k, sprintf ('u%d', k), 0.06, yk);
    [model, s] = B (model, 'Function', [], 'sign', 0.16, yk, port);
    [model, truth(k)] = B (model, 'Function', [], 'abs', 0.26, yk, s);
  endfor
  acc = truth(1);
  switch (op)
    case {'AND', 'NAND'}
      for k = 2:n
        [model, acc] = B (model, 'Function', [], 'times', 0.30 + 0.4 * k / n, 0.50, [acc truth(k)]);
      endfor
    case {'OR', 'NOR'}
      for k = 2:n
        [model, acc] = B (model, 'Sum', [], sprintf ('Count%d', k), 0.30 + 0.35 * k / n, 0.50, [acc truth(k)]);
      endfor
      [model, acc] = B (model, 'Function', [], 'sign', 0.70, 0.50, acc);
    case {'XOR', 'NXOR'}
      for k = 2:n
        x = 0.30 + 0.4 * k / n;
        [model, step] = B (model, 'Function', [], 'minus', x, 0.50, [acc truth(k)]);
        [model, acc] = B (model, 'Function', [], 'abs', x + 0.04, 0.50, step);
      endfor
  endswitch
  if (any (strcmp (op, {'NAND', 'NOR', 'NXOR', 'NOT'})))
    [model, c1] = B (model, 'Constant', 1, '1', 0.74, 0.85);
    [model, neg] = B (model, 'Gain', -1, 'Negate', 0.76, 0.50, acc);
    [model, acc] = B (model, 'Sum', [], op, 0.84, 0.50, [c1 neg]);
  endif
  model = B (model, 'Outport', 1, 'y', 0.94, 0.50, acc);
endfunction
