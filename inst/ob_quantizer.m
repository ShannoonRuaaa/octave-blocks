function model = ob_quantizer (interval = 0.5, Ts = 0, offset = 0)
% OB_QUANTIZER  Build a Simulink-style Quantizer subsystem.
%   MODEL = OB_QUANTIZER([INTERVAL[, Ts[, OFFSET]]]) rounds its input to the
%   nearest multiple of INTERVAL > 0, halves away from zero:
%       y = INTERVAL .* round(u ./ INTERVAL)
%   computed in that order (a true division, not u * (1/INTERVAL)), so
%   half-way quotients round exactly as in Simulink, e.g. u = 0.15 with
%   INTERVAL = 0.1 gives 0.1.  INTERVAL may be a scalar or an array that
%   broadcasts element-wise against u.  The defaults are Simulink's:
%   QuantizationInterval = 0.5 and SampleTime = -1 (inherited).  Set Ts = 0
%   (or -1) to inherit the rate, or Ts > 0 with 0 <= OFFSET < Ts to sample
%   and hold the output; the held output starts at zeros(size(INTERVAL)),
%   so with Ts > 0 the input must have INTERVAL's shape (scalar for a
%   scalar INTERVAL).  For a vector input with Ts > 0 pass the interval
%   expanded to the input's shape, e.g. repmat(0.5, 1, n); otherwise the
%   engine's Rate Transition hold stops the run with "ob_run: discrete
%   input at block N must be finite, real, and match its state shape",
%   where Simulink would accept the scalar.
%
%   Built from a Constant, C-mapped rdivide and round Functions and a Gain
%   for full Octave, strict C99 ob_codegen and ob_accelerate parity.  Like
%   Simulink's Quantizer it registers no zero-crossing guards.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/quantizer.html

  validateattributes (interval, {'numeric'}, {'nonempty', '2d', 'real', 'finite', 'positive'}, ...
                      'ob_quantizer', 'interval');
  [Ts, offset] = ob_builder_rate ('ob_quantizer', Ts, offset);
  q = full (double (interval));

  B = @ob_builder_block;
  model = B ();
  [model, u] = B (model, 'Inport', 1, 'u', 0.08, 0.50);
  [model, qc] = B (model, 'Constant', q, 'Interval', 0.08, 0.20);
  [model, ratio] = B (model, 'Function', [], 'rdivide', 0.30, 0.50, [u qc]);
  [model, steps] = B (model, 'Function', [], 'round', 0.50, 0.50, ratio);
  if (isscalar (q))
    [model, y] = B (model, 'Gain', q, 'Scale', 0.70, 0.50, steps);
  else
    [model, y] = B (model, 'Function', [], 'times', 0.70, 0.50, [qc steps]);
  endif
  [model, out] = B (model, 'Outport', 1, 'y', 0.90, 0.50, y);
  if (Ts > 0)
    model = ob_hold_builder_output (model, out, zeros (size (q)), [Ts offset]);
  endif
endfunction
