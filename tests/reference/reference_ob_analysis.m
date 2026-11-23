function reference_ob_analysis (file)
  % Record Simulink linmod/trim results and Simulink step/sine traces for
  % test_ob_analysis (ob_linearize, ob_findop, ob_bode, ob_stepinfo).  Run in
  % MATLAB with Simulink:
  %   reference_ob_analysis ('simulink-analysis-reference.json')
  % Every model is built unsaved and closed again with close_system(name,0).
  % linmod and trim ship with Simulink.  When Control System Toolbox is
  % installed the producer also records bode/margin/stepinfo; otherwise the
  % 'toolboxes' field says so and the test checks those against analytic
  % values and the recorded Simulink traces instead.
  if exist ('OCTAVE_VERSION', 'builtin')
    error ('reference_ob_analysis: run this producer in MATLAB');
  end
  if nargin < 1, file = 'simulink-analysis-reference.json'; end
  load_system ('simulink');
  details = ver ('simulink');
  record = struct ('producer', 'reference_ob_analysis.m', ...
                   'matlab_version', version, ...
                   'simulink_version', [details(1).Version ' ' details(1).Release], ...
                   'note', 'Recorded by the producer in one MATLAB session.');
  record.toolboxes = struct ('bode', exist ('bode', 'file') > 0, ...
                             'margin', exist ('margin', 'file') > 0, ...
                             'stepinfo', exist ('stepinfo', 'file') > 0, ...
                             'linearize', exist ('linearize', 'file') > 0, ...
                             'findop', exist ('findop', 'file') > 0);
  record.linmod = struct ();
  record.trim = struct ();
  record.traces = struct ();

  % --- linmod -------------------------------------------------------------
  mdl = pendulum ();
  record.linmod.pend_default = lin (mdl);
  record.linmod.pend_inverted = lin (mdl, [pi; 0], 0);      % Simulink order: theta, omega
  record.linmod.pend_input = lin (mdl, [0.3; -0.2], 0.4);
  [x, u, y, dx] = trim (mdl, [0.5; 0], 0.5, [], [], 1, []);
  record.trim.pend_fixed_u = struct ('x', x, 'u', u, 'y', y, 'dx', dx, 'states', {states(mdl)});
  [x, u, y, dx] = trim (mdl, [0.5; 0], 0, pi/4, [], [], 1);
  record.trim.pend_target_y = struct ('x', x, 'u', u, 'y', y, 'dx', dx, 'states', {states(mdl)});
  close_system (mdl, 0);

  mdl = 'ob_an_ssd'; new_system (mdl);
  sub = subsystem (mdl, 'plant');
  add_block ('simulink/Continuous/State-Space', [sub '/SS'], 'A', '[-1 2; 0 -3]', ...
             'B', '[1; 2]', 'C', '[1 1]', 'D', '0.5', 'InitialCondition', '[0.3; -0.2]');
  add_line (sub, 'In1/1', 'SS/1'); add_line (sub, 'SS/1', 'Out1/1');
  wire_io (mdl, 'plant');
  record.linmod.ss_feedthrough = lin (mdl);
  close_system (mdl, 0);

  mdl = 'ob_an_mimo'; new_system (mdl);
  add_block ('simulink/Sources/In1', [mdl '/u'], 'PortDimensions', '2');
  add_block ('simulink/Sources/In1', [mdl '/v']);
  add_block ('simulink/Continuous/State-Space', [mdl '/SS'], 'A', '[-1 0; 0 -2]', ...
             'B', 'eye(2)', 'C', '[1 1; 1 -1]', 'D', '[0 0.5; 0 0]', 'InitialCondition', '[0; 0]');
  add_block ('simulink/Math Operations/Gain', [mdl '/G'], 'Gain', '2');
  add_block ('simulink/Sinks/Out1', [mdl '/y']);
  add_block ('simulink/Sinks/Out1', [mdl '/w']);
  add_line (mdl, 'u/1', 'SS/1'); add_line (mdl, 'SS/1', 'y/1');
  add_line (mdl, 'v/1', 'G/1'); add_line (mdl, 'G/1', 'w/1');
  record.linmod.mimo_vector = lin (mdl);
  close_system (mdl, 0);

  % Inner Outports are not model outputs: In1 -> Subsystem(x' = u, y = x + 0.5u) -> Out1.
  mdl = 'ob_an_inner'; new_system (mdl);
  sub = subsystem (mdl, 'plant');
  add_block ('simulink/Continuous/Integrator', [sub '/x'], 'InitialCondition', '0');
  add_block ('simulink/Math Operations/Gain', [sub '/half'], 'Gain', '0.5');
  add_block ('simulink/Math Operations/Sum', [sub '/sum'], 'Inputs', '++');
  add_line (sub, 'In1/1', 'x/1'); add_line (sub, 'In1/1', 'half/1');
  add_line (sub, 'x/1', 'sum/1'); add_line (sub, 'half/1', 'sum/2'); add_line (sub, 'sum/1', 'Out1/1');
  wire_io (mdl, 'plant');
  record.linmod.inner_outport = lin (mdl);
  close_system (mdl, 0);

  mdl = 'ob_an_tf'; new_system (mdl);
  add_block ('simulink/Sources/In1', [mdl '/u']);
  add_block ('simulink/Continuous/Transfer Fcn', [mdl '/tf'], 'Numerator', '4', 'Denominator', '[1 2]');
  add_block ('simulink/Sinks/Out1', [mdl '/y']);
  add_line (mdl, 'u/1', 'tf/1'); add_line (mdl, 'tf/1', 'y/1');
  record.linmod.tf_first_order = lin (mdl);
  [x, u, y, dx] = trim (mdl, 0, 0, 3, [], [], 1);
  record.trim.tf_target_y = struct ('x', x, 'u', u, 'y', y, 'dx', dx, 'states', {states(mdl)});
  close_system (mdl, 0);

  mdl = 'ob_an_sat'; new_system (mdl);
  add_block ('simulink/Sources/In1', [mdl '/u']);
  add_block ('simulink/Discontinuities/Saturation', [mdl '/sat'], 'UpperLimit', '1', 'LowerLimit', '-1');
  add_block ('simulink/Continuous/Integrator', [mdl '/x'], 'InitialCondition', '0');
  add_block ('simulink/Sinks/Out1', [mdl '/y']);
  add_line (mdl, 'u/1', 'sat/1'); add_line (mdl, 'sat/1', 'x/1'); add_line (mdl, 'x/1', 'y/1');
  record.linmod.saturation_inside = lin (mdl, 0, 0.5);
  record.linmod.saturation_beyond = lin (mdl, 0, 2);
  % linmod's default block-by-block linearization and its 'v5' numerical
  % perturbation (reproduced by ob_linearize 'Method','v5') are both recorded.
  [A, B, C, D] = linmod (mdl, 0, 2, [1e-5 0], 'v5');
  record.linmod.saturation_beyond_v5 = struct ('A', A, 'B', B, 'C', C, 'D', D, ...
      'sizes', [size(A) size(B) size(C) size(D)], 'states', {states(mdl)}, 'x', 0, 'u', 2);
  [A, B, C, D] = linmod (mdl, 0, 0.5, [1e-5 0], 'v5');
  record.linmod.saturation_inside_v5 = struct ('A', A, 'B', B, 'C', C, 'D', D, ...
      'sizes', [size(A) size(B) size(C) size(D)], 'states', {states(mdl)}, 'x', 0, 'u', 0.5);
  % Exactly at a limit 'v5' takes the forward (right-hand) slope.
  record.linmod.saturation_upper_v5 = lin5 (mdl, 0, 1, 1e-5);
  record.linmod.saturation_lower_v5 = lin5 (mdl, 0, -1, 1e-5);
  close_system (mdl, 0);

  % linmod 'v5' step rule on smooth nonlinear models: x' = -x^2 (state
  % perturbation) and x' = u^2 (input perturbation).  A forward difference
  % with h = del*(1 + 1e-3*|v|) gives A = -2x - h and B = 2u + h.
  mdl = 'ob_an_sq'; new_system (mdl);
  add_block ('simulink/Continuous/Integrator', [mdl '/x'], 'InitialCondition', '1');
  add_block ('simulink/Math Operations/Product', [mdl '/sq'], 'Inputs', '2');
  add_block ('simulink/Math Operations/Gain', [mdl '/g'], 'Gain', '-1');
  add_block ('simulink/Sinks/Out1', [mdl '/y']);
  add_line (mdl, 'x/1', 'sq/1'); add_line (mdl, 'x/1', 'sq/2');
  add_line (mdl, 'sq/1', 'g/1'); add_line (mdl, 'g/1', 'x/1'); add_line (mdl, 'x/1', 'y/1');
  record.linmod.square_x1_v5 = lin5 (mdl, 1, [], 1e-5);
  record.linmod.square_x100_v5 = lin5 (mdl, 100, [], 1e-5);
  record.linmod.square_x1_v5_del2 = lin5 (mdl, 1, [], 1e-2);
  record.linmod.square_x1 = lin (mdl, 1, []);
  close_system (mdl, 0);
  mdl = 'ob_an_usq'; new_system (mdl);
  add_block ('simulink/Sources/In1', [mdl '/u']);
  add_block ('simulink/Math Operations/Product', [mdl '/sq'], 'Inputs', '2');
  add_block ('simulink/Continuous/Integrator', [mdl '/x'], 'InitialCondition', '0');
  add_block ('simulink/Sinks/Out1', [mdl '/y']);
  add_line (mdl, 'u/1', 'sq/1'); add_line (mdl, 'u/1', 'sq/2');
  add_line (mdl, 'sq/1', 'x/1'); add_line (mdl, 'x/1', 'y/1');
  record.linmod.input_square_u100_v5 = lin5 (mdl, 0, 100, 1e-2);
  close_system (mdl, 0);

  % Integrator with output limits, x' = -x + u, linearized inside its limits.
  mdl = 'ob_an_lim'; new_system (mdl);
  add_block ('simulink/Sources/In1', [mdl '/u']);
  add_block ('simulink/Math Operations/Sum', [mdl '/sum'], 'Inputs', '+-');
  add_block ('simulink/Continuous/Integrator', [mdl '/x'], 'InitialCondition', '0.2', ...
             'LimitOutput', 'on', 'UpperSaturationLimit', '10', 'LowerSaturationLimit', '-10');
  add_block ('simulink/Sinks/Out1', [mdl '/y']);
  add_line (mdl, 'u/1', 'sum/1'); add_line (mdl, 'sum/1', 'x/1');
  add_line (mdl, 'x/1', 'sum/2'); add_line (mdl, 'x/1', 'y/1');
  record.linmod.limited_integrator = lin (mdl);
  % trim with u = 20 held: x' = 0 for every x past the upper limit.
  [x, u, y, dx] = trim (mdl, 0, 20, [], [], 1, []);
  record.trim.limited_beyond = struct ('x', x, 'u', u, 'y', y, 'dx', dx, 'states', {states(mdl)});
  close_system (mdl, 0);

  % --- traces for ob_stepinfo and ob_bode ----------------------------------
  grid = 0:0.01:10;
  record.traces.step_underdamped = step_trace ('ob_an_step2', '4', '[1 1.2 4]', 0, 1, grid);
  record.traces.step_nonminimum = step_trace ('ob_an_nmp', '[-1 1]', '[1 2 1]', 0, 1, grid);
  record.traces.step_offset = step_trace ('ob_an_off', '3', '[1 1]', 2, 1, grid);
  record.traces.sine_resonant = sine_trace (grid);
  names = fieldnames (record.traces);
  if record.toolboxes.stepinfo
    for k = 1:3
      tr = record.traces.(names{k});
      record.traces.(names{k}).stepinfo = stepinfo (tr.y, tr.t, tr.yfinal, tr.yinit);
    end
  end
  if record.toolboxes.margin
    [gm, pm, wcg, wcp] = margin (tf (1, [1 3 2 0]));
    record.margin_type1 = struct ('Gm', gm, 'Pm', pm, 'Wcg', wcg, 'Wcp', wcp);
  end

  fid = fopen (file, 'w');
  if fid < 0, error ('reference_ob_analysis: cannot write %s', file); end
  fprintf (fid, '%s', jsonencode (record));
  fclose (fid);
  fprintf ('wrote %s\n', file);
end

function mdl = pendulum ()
  % theta'' = u - sin(theta) - 0.2 theta', y = theta; ICs omega 0.1, theta 0.
  mdl = 'ob_an_pend'; new_system (mdl);
  add_block ('simulink/Sources/In1', [mdl '/u']);
  add_block ('simulink/Math Operations/Sum', [mdl '/s'], 'Inputs', '+--');
  add_block ('simulink/Continuous/Integrator', [mdl '/omega'], 'InitialCondition', '0.1');
  add_block ('simulink/Continuous/Integrator', [mdl '/theta'], 'InitialCondition', '0');
  add_block ('simulink/Math Operations/Trigonometric Function', [mdl '/sin'], 'Operator', 'sin');
  add_block ('simulink/Math Operations/Gain', [mdl '/damp'], 'Gain', '0.2');
  add_block ('simulink/Sinks/Out1', [mdl '/y']);
  add_line (mdl, 'u/1', 's/1'); add_line (mdl, 'sin/1', 's/2'); add_line (mdl, 'damp/1', 's/3');
  add_line (mdl, 's/1', 'omega/1'); add_line (mdl, 'omega/1', 'theta/1');
  add_line (mdl, 'theta/1', 'sin/1'); add_line (mdl, 'omega/1', 'damp/1');
  add_line (mdl, 'theta/1', 'y/1');
end

function sub = subsystem (mdl, name)
  sub = [mdl '/' name];
  add_block ('simulink/Ports & Subsystems/Subsystem', sub);
  delete_line (sub, 'In1/1', 'Out1/1');
end

function wire_io (mdl, name)
  add_block ('simulink/Sources/In1', [mdl '/u']);
  add_block ('simulink/Sinks/Out1', [mdl '/y']);
  add_line (mdl, 'u/1', [name '/1']); add_line (mdl, [name '/1'], 'y/1');
end

function names = states (mdl)
  [~, ~, str] = feval (mdl, [], [], [], 0);
  names = cellfun (@(s) regexprep (s, ['^' mdl '/'], ''), str(:)', 'UniformOutput', false);
end

function r = lin (mdl, varargin)
  [A, B, C, D] = linmod (mdl, varargin{:});
  r = struct ('A', A, 'B', B, 'C', C, 'D', D, 'sizes', [size(A) size(B) size(C) size(D)], ...
              'states', {states(mdl)});
  if numel (varargin) >= 1, r.x = varargin{1}; end
  if numel (varargin) >= 2, r.u = varargin{2}; end
end

function r = lin5 (mdl, x, u, del)
  % linmod's numerical 'v5' method with perturbation DEL at time 0.
  [A, B, C, D] = linmod (mdl, x, u, [del 0], 'v5');
  r = struct ('A', A, 'B', B, 'C', C, 'D', D, 'sizes', [size(A) size(B) size(C) size(D)], ...
              'states', {states(mdl)}, 'x', x, 'u', u, 'del', del);
end

function r = step_trace (mdl, num, den, offset, amplitude, grid)
  % Step (time 0, 0 -> amplitude) -> Transfer Fcn -> + offset -> Out1, ode4.
  new_system (mdl);
  add_block ('simulink/Sources/Step', [mdl '/step'], 'Time', '0', 'Before', '0', 'After', num2str (amplitude));
  add_block ('simulink/Continuous/Transfer Fcn', [mdl '/tf'], 'Numerator', num, 'Denominator', den);
  add_block ('simulink/Sources/Constant', [mdl '/c'], 'Value', num2str (offset));
  add_block ('simulink/Math Operations/Sum', [mdl '/sum'], 'Inputs', '++');
  add_block ('simulink/Sinks/Out1', [mdl '/y']);
  add_line (mdl, 'step/1', 'tf/1'); add_line (mdl, 'tf/1', 'sum/1');
  add_line (mdl, 'c/1', 'sum/2'); add_line (mdl, 'sum/1', 'y/1');
  out = sim (mdl, 'Solver', 'ode4', 'FixedStep', '0.01', 'StopTime', num2str (grid(end)), ...
             'SaveFormat', 'Array', 'SaveTime', 'on', 'TimeSaveName', 'tout', ...
             'SaveOutput', 'on', 'OutputSaveName', 'yout');
  close_system (mdl, 0);
  r = struct ('num', str2num (num), 'den', str2num (den), 'offset', offset, ...
              'amplitude', amplitude, 't', out.tout(:)', 'y', out.yout(:)', ...
              'yinit', offset, 'yfinal', offset + amplitude * polyval (str2num (num), 0) / polyval (str2num (den), 0), ...
              'solver', 'ode4', 'step', 0.01);
end

function r = sine_trace (grid)
  % Sine (amplitude 1, 2.8 rad/s) -> 4/(s^2+0.4s+4) -> Out1, ode45 tight,
  % output on [50, 60] where the transient has decayed (exp(-0.2*50)).
  mdl = 'ob_an_sine'; new_system (mdl);
  add_block ('simulink/Sources/Sine Wave', [mdl '/sine'], 'Amplitude', '1', 'Frequency', '2.8');
  add_block ('simulink/Continuous/Transfer Fcn', [mdl '/tf'], 'Numerator', '4', 'Denominator', '[1 0.4 4]');
  add_block ('simulink/Sinks/Out1', [mdl '/y']);
  add_line (mdl, 'sine/1', 'tf/1'); add_line (mdl, 'tf/1', 'y/1');
  times = 50 + grid;
  out = sim (mdl, 'Solver', 'ode45', 'RelTol', '1e-10', 'AbsTol', '1e-12', ...
             'StopTime', '60', 'OutputOption', 'SpecifiedOutputTimes', 'OutputTimes', mat2str (times), ...
             'SaveFormat', 'Array', 'SaveTime', 'on', 'TimeSaveName', 'tout', ...
             'SaveOutput', 'on', 'OutputSaveName', 'yout');
  close_system (mdl, 0);
  keep = out.tout >= 50 - 1e-9;
  r = struct ('w', 2.8, 'num', 4, 'den', [1 0.4 4], 't', out.tout(keep)', 'y', out.yout(keep)', ...
              'solver', 'ode45', 'reltol', 1e-10, 'abstol', 1e-12);
end
