function model = ob_backlash (width = 1, initial_output = 0, Ts = 0, offset = 0)
% OB_BACKLASH  Build a Simulink-style Backlash (mechanical play) subsystem.
%   MODEL = OB_BACKLASH([WIDTH[, INITIAL_OUTPUT[, Ts[, OFFSET]]]]) models
%   play of total width WIDTH >= 0 centred on the output:
%       y = y_prev + deadzone_[-WIDTH/2, WIDTH/2](u - y_prev)
%   The output holds while u stays within WIDTH/2 of it, follows u - WIDTH/2
%   once u pushes past the upper edge and u + WIDTH/2 past the lower edge.
%   The defaults are Simulink's: BacklashWidth = 1, InitialOutput = 0 and
%   SampleTime = -1 (inherited).  Set Ts = 0 (or -1) to inherit the rate,
%   or Ts > 0 with 0 <= OFFSET < Ts for a discrete block whose output is
%   held between sample hits.
%
%   INITIAL_OUTPUT fixes the signal shape: a scalar gives a scalar block.
%   For a vector or matrix input pass an INITIAL_OUTPUT of that shape, e.g.
%   repmat(0, 1, n) where Simulink would take its default scalar 0: the
%   engine's Unit Delay state does not expand a scalar initial condition,
%   so a scalar INITIAL_OUTPUT with a vector input stops the run with
%   "ob_run: discrete input at block N must be finite, real, and match its
%   state shape".  WIDTH is a scalar applied to every element.
%
%   With an inherited rate the play state advances once per ob_run output
%   (or integration) step, like Simulink under a fixed-step solver at that
%   step.  A coarse output grid can therefore miss input reversals that a
%   variable-step Simulink run resolves: give ob_run a grid fine enough for
%   the input.  The inherited-rate block uses a native Dead Zone, whose
%   zero-crossing guards mark the band edges (Simulink's ZeroCross = on).
%   With Ts > 0 the band is computed from abs, sign and times Functions
%   instead, so the discrete block registers no zero-crossing guards, as in
%   Simulink.  Built from native primitives (Unit Delay, Dead Zone or
%   Functions, Sum) for full Octave, strict C99 ob_codegen and
%   ob_accelerate parity.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/backlash.html

  validateattributes (width, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'}, 'ob_backlash', 'width');
  validateattributes (initial_output, {'numeric'}, {'nonempty', '2d', 'real', 'finite'}, ...
                      'ob_backlash', 'initial_output');
  [Ts, offset] = ob_builder_rate ('ob_backlash', Ts, offset);
  half = double (width) / 2;
  y0 = full (double (initial_output));

  B = @ob_builder_block;
  model = B ();
  [model, u] = B (model, 'Inport', 1, 'u', 0.08, 0.60);
  [model, prev] = B (model, 'Unit Delay', y0, 'y_prev', 0.55, 0.20);
  [model, neg] = B (model, 'Gain', -1, '-y_prev', 0.25, 0.20, prev);
  [model, gap] = B (model, 'Sum', [], 'u - y_prev', 0.38, 0.60, [u neg]);
  if (Ts > 0)
    % Discrete block: no zero-crossing guard (Simulink applies none to a
    % sampled Backlash), so the dead zone is sign(g) .* max(|g| - h, 0),
    % with max(z, 0) = (z + |z|)/2.  This gives the same doubles as the
    % native Dead Zone, +0 inside the band included.
    [model, mag] = B (model, 'Function', [], 'abs', 0.44, 0.75, gap);
    [model, ch] = B (model, 'Constant', -half, '-width/2', 0.44, 0.90);
    [model, excess] = B (model, 'Sum', [], '|g| - width/2', 0.50, 0.80, [mag ch]);
    [model, aexcess] = B (model, 'Function', [], 'abs', 0.54, 0.90, excess);
    [model, twice] = B (model, 'Sum', [], '2 max(excess, 0)', 0.58, 0.80, [excess aexcess]);
    [model, pos] = B (model, 'Gain', 0.5, 'max(excess, 0)', 0.62, 0.80, twice);
    [model, sgn] = B (model, 'Function', [], 'sign', 0.50, 0.45, gap);
    [model, signed] = B (model, 'Function', [], 'times', 0.66, 0.60, [sgn pos]);
    [model, c0] = B (model, 'Constant', 0, '0', 0.62, 0.45);
    [model, play] = B (model, 'Sum', [], 'Deadband', 0.70, 0.55, [signed c0]);   % +0, never -0
  else
    [model, play] = B (model, 'Dead Zone', [-half, half], 'Deadband', 0.55, 0.60, gap);
  endif
  [model, y] = B (model, 'Sum', [], 'y', 0.74, 0.60, [play prev]);
  model.edges(end+1, :) = [y 1 prev 1];
  [model, out] = B (model, 'Outport', 1, 'out', 0.92, 0.60, y);
  if (Ts > 0)
    rates = zeros (numel (model.blocks), 2);
    rates(prev, :) = [Ts, offset];
    model.sample_times = rates;
    model = ob_hold_builder_output (model, out, y0, [Ts offset]);
  endif
endfunction
