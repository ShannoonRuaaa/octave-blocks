function model = ob_pulse_generator (amplitude = 1, period = 10, pulse_width = 5, phase_delay = 0)
% OB_PULSE_GENERATOR  Build a Simulink-style time-based Pulse Generator source.
%   MODEL = OB_PULSE_GENERATOR([AMP[, PERIOD[, WIDTH[, DELAY]]]]) outputs AMP
%   for PHASE_DELAY + k*PERIOD <= t < PHASE_DELAY + (k + WIDTH/100)*PERIOD,
%   k = 0, 1, 2, ..., and 0 otherwise, including before PHASE_DELAY.
%   Defaults are Simulink's: amplitude 1, period 10, pulse width 5 (percent
%   of the period) and phase delay 0.  AMP may be a real array; the output
%   has its shape (Simulink's vector Amplitude).  PERIOD > 0,
%   0 < WIDTH < 100 and DELAY are finite real scalars.
%
%   Only PulseType = 'Time based' with TimeSource = 'Use simulation time'
%   is modelled; 'Sample based' pulses and vector Period, PulseWidth or
%   PhaseDelay are not.  The source has no inputs (place it in a Subsystem
%   block) and reads simulation time from a native Time block.  Edges are
%   located in cycle units with a few-ulp tolerance, so samples that land
%   on an edge in decimal arithmetic (t = 0.25 with PERIOD = 0.1) take the
%   value after the edge, as in Simulink.
%
%   Simulink's time-based Pulse Generator registers its edges as solver
%   breakpoints.  Octave Blocks evaluates it at the solver's times: run
%   with zero_crossings = true (rk4 or ode45) for downstream integrators to
%   see the edges exactly; without it they are smeared over a solver step.
%   With a fixed-step solver, Simulink refuses to run unless the step
%   divides PERIOD, the pulse duration and PHASE_DELAY ("... need to be
%   integer multiples of the fixed step size"); this source has no such
%   check and simply samples the pulse at the solver's steps.
%   Built from native Time, Constant, Gain, Sum, floor/abs Function and
%   Switch blocks for strict C99 ob_codegen and ob_accelerate parity.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/pulsegenerator.html

  validateattributes (amplitude, {'numeric'}, {'nonempty', '2d', 'real', 'finite', 'nonsparse'}, ...
                      'ob_pulse_generator', 'amplitude');
  validateattributes (period, {'numeric'}, {'scalar', 'real', 'finite', 'positive'}, ...
                      'ob_pulse_generator', 'period');
  validateattributes (pulse_width, {'numeric'}, {'scalar', 'real', 'finite', '>', 0, '<', 100}, ...
                      'ob_pulse_generator', 'pulse_width');
  validateattributes (phase_delay, {'numeric'}, {'scalar', 'real', 'finite'}, ...
                      'ob_pulse_generator', 'phase_delay');
  amp = double (amplitude); T = double (period);
  w = double (pulse_width) / 100; delay = double (phase_delay);

  % Cycle coordinate x = (t - delay)/T.  Rounding in t, delay and 1/T moves
  % x by at most ~2*eps*(|x| + |delay|/T); tol = 8*eps*(|x| + 1 + |delay|/T)
  % covers it, so x within tol below an edge counts as on the edge.
  %   cycle = floor(x + tol),  phase = x - cycle
  %   y = (x + tol >= 0) && (phase - w + tol < 0) ? amp : 0
  model = ob_builder_block ();
  [model, t] = ob_builder_block (model, 'Time', [], 't', 0.04, 0.50);
  [model, c] = ob_builder_block (model, 'Constant', -delay, '-delay', 0.04, 0.80);
  [model, tau] = ob_builder_block (model, 'Sum', [], 't - delay', 0.12, 0.60, [t c]);
  [model, x] = ob_builder_block (model, 'Gain', 1 / T, 'cycles', 0.20, 0.60, tau);
  [model, ax] = ob_builder_block (model, 'Function', [], 'abs', 0.28, 0.85, x);
  [model, c] = ob_builder_block (model, 'Constant', 1 + abs (delay) / T, 'margin', 0.28, 0.98);
  [model, s] = ob_builder_block (model, 'Sum', [], '|x| + margin', 0.36, 0.90, [ax c]);
  [model, tol] = ob_builder_block (model, 'Gain', 8 * eps, 'tolerance', 0.44, 0.90, s);
  [model, xt] = ob_builder_block (model, 'Sum', [], 'x + tol', 0.52, 0.60, [x tol]);
  [model, cycle] = ob_builder_block (model, 'Function', [], 'floor', 0.58, 0.45, xt);
  [model, neg] = ob_builder_block (model, 'Gain', -1, '-cycle', 0.64, 0.45, cycle);
  [model, phase] = ob_builder_block (model, 'Sum', [], 'phase', 0.70, 0.35, [x neg]);
  [model, c] = ob_builder_block (model, 'Constant', -w, '-width', 0.70, 0.20);
  [model, s] = ob_builder_block (model, 'Sum', [], 'phase - width', 0.76, 0.28, [phase c]);
  [model, fall] = ob_builder_block (model, 'Sum', [], 'fall', 0.80, 0.40, [s tol]);
  [model, on] = ob_builder_block (model, 'Constant', amp, 'amplitude', 0.80, 0.75);
  [model, off] = ob_builder_block (model, 'Constant', zeros (size (amp)), 'zero', 0.80, 0.08);
  [model, duty] = ob_builder_block (model, 'Switch', 0, 'duty', 0.86, 0.45, [off fall on]);
  [model, gate] = ob_builder_block (model, 'Switch', 0, 'delay', 0.92, 0.50, [duty xt off]);
  model = ob_builder_block (model, 'Outport', 1, 'y', 0.97, 0.50, gate);
endfunction
