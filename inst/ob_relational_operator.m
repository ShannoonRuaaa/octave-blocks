function model = ob_relational_operator (op = '<=')
% OB_RELATIONAL_OPERATOR  Build a Simulink-style Relational Operator subsystem.
%   MODEL = OB_RELATIONAL_OPERATOR([OP]) compares Inport 1 (u1) with
%   Inport 2 (u2) element by element, OP being '==', '~=' (or '!='), '<',
%   '<=' (Simulink's default), '>=' or '>', and outputs 1 where the
%   relation holds and 0 elsewhere.  A scalar input expands against a
%   vector or matrix input, as in Simulink.  Non-scalar inputs must have
%   the same size: a row with a column vector broadcasts into a matrix of
%   all element pairs in the engine, where Simulink's 1-D vectors pair
%   element by element.  Sample time is inherited.
%
%   Limits: the output is double 0/1 rather than Simulink's default
%   boolean (OutDataTypeStr = boolean), since engine signals are real
%   doubles; the one-input operators isInf, isNaN and isFinite are not
%   provided (engine signals are finite).
%
%   The comparison signal d = 0.5*u1 - 0.5*u2 + (atan(u1) - atan(u2)) is
%   finite and has exactly the sign of u1 - u2 for all finite operands, so
%   1e308 > -1e308 and subnormals such as 4.9e-324 > 0 compare as in
%   Simulink (u1 - u2 itself would overflow to Inf, which a Switch control
%   rejects).  Built from native Gain/Sum/Switch and C-mapped atan, minus
%   (and abs for '==' and '~=') Functions for full
%   Octave, strict C99 ob_codegen and ob_accelerate parity; the Switch
%   registers a zero-crossing guard (Simulink's ZeroCross = on).
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/relationaloperator.html

  ops = {'==', '~=', '!=', '<', '<=', '>=', '>'};
  if (! ischar (op) || rows (op) != 1 || ! any (strcmp (op, ops)))
    if (ischar (op) && any (strcmpi (op, {'isInf', 'isNaN', 'isFinite'})))
      error ('ob_relational_operator: one-input operator ''%s'' is not supported (engine signals are finite)', op);
    endif
    error ('ob_relational_operator: op must be one of ==, ~=, <, <=, >=, >');
  endif
  if (strcmp (op, '!=')), op = '~='; endif

  B = @ob_builder_block;
  model = B ();
  [model, u1] = B (model, 'Inport', 1, 'u1', 0.08, 0.70);
  [model, u2] = B (model, 'Inport', 2, 'u2', 0.08, 0.30);
  % d has the sign of u1 - u2 and is finite for all finite operands.
  [model, d] = ob_builder_difference (model, u1, u2, 'u1 - u2', 0.36, 0.50);
  % 0/1 levels of the comparison's shape; adding the constants turns the
  % -0 of 0*d (d < 0) into +0.
  [model, zero] = B (model, 'Gain', 0, '0*d', 0.46, 0.18, d);
  [model, c0] = B (model, 'Constant', 0, '0', 0.46, 0.06);
  [model, false_level] = B (model, 'Sum', [], 'False', 0.58, 0.14, [zero c0]);
  [model, c1] = B (model, 'Constant', 1, '1', 0.46, 0.94);
  [model, true_level] = B (model, 'Sum', [], 'True', 0.58, 0.86, [zero c1]);
  switch (op)
    case {'>=', '<'}            % d >= 0 (u1 >= u2)
      control = d;
    case {'<=', '>'}            % -d >= 0 (u2 >= u1)
      [model, control] = B (model, 'Gain', -1, '-d', 0.48, 0.50, d);
    otherwise                   % -|d| >= 0, i.e. u1 == u2
      [model, magnitude] = B (model, 'Function', [], 'abs', 0.46, 0.50, d);
      [model, control] = B (model, 'Gain', -1, '-|d|', 0.56, 0.50, magnitude);
  endswitch
  if (any (strcmp (op, {'>=', '<=', '=='})))
    data = [true_level control false_level];
  else
    data = [false_level control true_level];
  endif
  [model, sw] = B (model, 'Switch', 0, op, 0.76, 0.50, data);
  model = B (model, 'Outport', 1, 'y', 0.92, 0.50, sw);
endfunction
