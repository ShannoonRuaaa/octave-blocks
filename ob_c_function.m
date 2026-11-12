function [expression, arity] = ob_c_function (name)
  % Only actual builtin implementations may be mapped to C math/operators.
  unary = {"sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", ...
           "tanh", "exp", "log", "log10", "sqrt", "abs", "floor", "ceil", "round", ...
           "sign", "uminus"};
  binary = {"power", "atan2", "hypot", "plus", "times", "minus", "rdivide"};
  if (! any (strcmp (name, [unary binary])))
    error ("ob_codegen: unsupported Function '%s'; arbitrary Octave functions cannot yet be exported", name);
  endif
  info = functions (str2func (name));
  if (exist (name, "builtin") != 5 || ! isempty (info.file))
    error ("ob_codegen: Function '%s' is shadowed or is not the supported builtin", name);
  endif
  arity = 1 + any (strcmp (name, binary));
  switch (name)
    case "abs", expression = "fabs(INPUT_A)";
    case "sign", expression = "(isnan(INPUT_A) ? NAN : (double)((INPUT_A > 0.0) - (INPUT_A < 0.0)))";
    case "uminus", expression = "(-INPUT_A)";
    case "power", expression = "pow(INPUT_A, INPUT_B)";
    case "plus", expression = "(INPUT_A + INPUT_B)";
    case "minus", expression = "(INPUT_A - INPUT_B)";
    case "times", expression = "(INPUT_A * INPUT_B)";
    case "rdivide", expression = "(INPUT_A / INPUT_B)";
    otherwise
      if (arity == 1), expression = [name "(INPUT_A)"]; else expression = [name "(INPUT_A, INPUT_B)"]; endif
  endswitch
endfunction
