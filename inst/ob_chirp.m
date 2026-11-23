function model = ob_chirp (f1 = 0.1, T = 100, f2 = 1)
% OB_CHIRP  Build a Simulink-style Chirp Signal (linear swept sine) source.
%   MODEL = OB_CHIRP([F1[, T[, F2]]]) generates
%       y(t) = sin(2*pi*(F1*t + (F2 - F1)/(2*T)*t^2))
%   whose frequency sweeps linearly from F1 Hz at t = 0 to F2 Hz at t = T
%   and keeps sweeping afterwards, as Simulink's block does.  Parameter
%   names and defaults are Simulink's: initial frequency f1 = 0.1 Hz,
%   target time T = 100 s and frequency at target time f2 = 1 Hz.
%
%   F1, T and F2 are finite real scalars or vectors of one common length
%   (scalars expand, VectorParams1D); vector parameters give a column
%   vector output, one swept sine per element.  T must be positive.  The
%   chirp uses absolute simulation time, like Simulink's clock-based
%   block.  Scale the amplitude with a Gain block (the Simulink block has
%   no amplitude parameter).  The source has no inputs; place it in a
%   Subsystem block.  Built from native Time, Product, Gain, Sum and sin
%   Function blocks for strict C99 ob_codegen and ob_accelerate parity.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/chirpsignal.html

  validateattributes (f1, {'numeric'}, {'nonempty', 'vector', 'real', 'finite'}, 'ob_chirp', 'f1');
  validateattributes (T, {'numeric'}, {'nonempty', 'vector', 'real', 'finite', 'positive'}, 'ob_chirp', 'T');
  validateattributes (f2, {'numeric'}, {'nonempty', 'vector', 'real', 'finite'}, 'ob_chirp', 'f2');
  sizes = [numel(f1) numel(T) numel(f2)];
  n = max (sizes);
  if (any (sizes != 1 & sizes != n))
    error ('ob_chirp: vector f1, T and f2 must have the same length (scalars expand)');
  endif
  f1 = double (f1(:)) .* ones (n, 1);
  T = double (T(:)) .* ones (n, 1);
  f2 = double (f2(:)) .* ones (n, 1);

  % phase = k1*t + k2*t^2 with k1 = 2*pi*f1 and k2 = pi*(f2 - f1)/T; with
  % vector parameters each Gain scales the scalar time into a column.
  model = ob_builder_block ();
  [model, t] = ob_builder_block (model, 'Time', [], 't', 0.08, 0.50);
  [model, t2] = ob_builder_block (model, 'Product', [], 't^2', 0.24, 0.72, [t t]);
  [model, quadratic] = ob_builder_block (model, 'Gain', pi * (f2 - f1) ./ T, 'k2*t^2', 0.40, 0.72, t2);
  [model, linear] = ob_builder_block (model, 'Gain', 2 * pi * f1, 'k1*t', 0.40, 0.28, t);
  [model, phase] = ob_builder_block (model, 'Sum', [], 'phase', 0.58, 0.50, [linear quadratic]);
  [model, y] = ob_builder_block (model, 'Function', [], 'sin', 0.74, 0.50, phase);
  model = ob_builder_block (model, 'Outport', 1, 'y', 0.92, 0.50, y);
endfunction
