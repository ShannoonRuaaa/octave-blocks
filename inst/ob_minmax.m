function model = ob_minmax (func = 'min', inputs = 2)
% OB_MINMAX  Build a Simulink-style multi-input MinMax subsystem.
%   MODEL = OB_MINMAX([FUNC[, INPUTS]]) outputs the element-wise minimum
%   (FUNC = 'min', Simulink's default) or maximum (FUNC = 'max') of its
%   INPUTS >= 2 input ports.  Scalar inputs expand against vector or matrix
%   inputs, as in Simulink; non-scalar inputs must have the same size.  Do
%   not mix a row with a column vector: the engine broadcasts them into a
%   matrix of all element pairs, where Simulink's 1-D vectors pair element
%   by element.  Sample time is inherited.
%
%   Any finite inputs compare exactly, including realmax against -realmax
%   and adjacent subnormals: each comparison drives its Switch with
%   0.5*a - 0.5*b + (atan(a) - atan(b)), which is finite and has the sign
%   of a - b (the plain difference would overflow to Inf, which a Switch
%   control rejects).
%
%   Simulink's default Inputs = 1 (reduction over the elements of a single
%   input) is not supported: the engine has no element-reduction primitive
%   that exports to C, so INPUTS = 1 raises an error and the default here
%   is 2.
%
%   Built as a cascade of native Gain/Sum/Switch comparisons for full
%   Octave, strict C99 ob_codegen and ob_accelerate parity; each Switch
%   registers a zero-crossing guard (Simulink's ZeroCross = on).
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/minmax.html

  if (! ischar (func) || rows (func) != 1 || ! any (strcmpi (func, {'min', 'max'})))
    error ('ob_minmax: func must be ''min'' or ''max''');
  endif
  validateattributes (inputs, {'numeric'}, {'scalar', 'real', 'finite', 'integer', 'positive'}, 'ob_minmax', 'inputs');
  if (inputs < 2)
    error ('ob_minmax: inputs = 1 (reduction over the elements of one input) is not supported; use 2 or more inputs');
  endif
  is_max = strcmpi (func, 'max');
  n = double (inputs);

  model = ob_builder_block ();
  ports = zeros (1, n);
  for k = 1:n
    [model, ports(k)] = ob_builder_block (model, 'Inport', k, sprintf ('u%d', k), 0.06, 0.85 - 0.7 * (k - 1) / (n - 1));
  endfor
  [model, data] = ob_builder_broadcast (model, ports, 0.18, 0.40);
  acc = data(1);
  for k = 2:n
    x = 0.40 + 0.45 * (k - 1) / n;
    if (is_max)    % acc >= u_k ? acc : u_k
      [model, acc] = ob_builder_select (model, acc, data(k), acc, data(k), sprintf ('max%d', k), x, 0.50);
    else           % acc >= u_k ? u_k : acc
      [model, acc] = ob_builder_select (model, acc, data(k), data(k), acc, sprintf ('min%d', k), x, 0.50);
    endif
  endfor
  model = ob_builder_block (model, 'Outport', 1, 'y', 0.94, 0.50, acc);
endfunction
