function reference_ob_simulink_delay_integrator (file)
  % Record live Simulink traces for Transport Delay and Integrator (output
  % limits and external reset) models, independently of Octave.  Run in
  % MATLAB with Simulink:
  %   reference_ob_simulink_delay_integrator ('simulink-delay-integrator-reference.json')
  % Every model is built unsaved and closed again.  Each case records its
  % Simulink block parameters as strings, so test_ob_simulink_delay_integrator
  % can build the same model in Octave Blocks and check either agreement or
  % a documented difference.  The dde23 entries are independent references
  % for the delay differential equations.
  if exist ('OCTAVE_VERSION', 'builtin')
    error ('reference_ob_simulink_delay_integrator: run this producer in MATLAB');
  end
  if nargin < 1, file = 'simulink-delay-integrator-reference.json'; end
  load_system ('simulink');
  details = ver ('simulink');
  record = struct ('producer', 'reference_ob_simulink_delay_integrator.m', ...
                   'matlab_version', version, ...
                   'simulink_version', [details(1).Version ' ' details(1).Release], ...
                   'note', 'Recorded by the producer in one MATLAB session.');
  record.cases = struct ();
  scenarios = scenario_table ();
  for k = 1:numel (scenarios)
    s = scenarios{k};
    record.cases.(s.id) = run_case (s);
    fprintf ('%-36s ok=%d n=%d %.2fs %s\n', s.id, record.cases.(s.id).ok, ...
             numel (record.cases.(s.id).t), record.cases.(s.id).seconds, record.cases.(s.id).error);
  end
  options = ddeset ('RelTol', 1e-10, 'AbsTol', 1e-12);
  record.dde23 = struct ();
  record.dde23.delay_s3_ode4_h01 = dde_case (@(t, y, z) -z, 1, 1, [0 6], 0:0.1:6, options);
  record.dde23.delay_s11_ode4_h01 = dde_case (@(t, y, z) -z, 0.35, 1, [0 4], 0:0.1:4, options);
  fid = fopen (file, 'w');
  if fid < 0, error ('reference_ob_simulink_delay_integrator: cannot write %s', file); end
  fprintf (fid, '%s', jsonencode (record));
  fclose (fid);
end

function scenarios = scenario_table ()
  % Transport Delay models.  Model names match the builders below and in
  % test_ob_simulink_delay_integrator.m.
  scenarios = {};
  td = @(delay, initial) struct ('DelayTime', delay, 'InitialOutput', initial);
  scenarios{end+1} = scenario ('delay_s1_ode4', 'delay', 'clock_td', 'Clock -> Transport Delay', ...
      td ('0.5', '7'), fixed (0.1, 0, 2));
  scenarios{end+1} = scenario ('delay_s1_ode45', 'delay', 'clock_td', 'Clock -> Transport Delay', ...
      td ('0.5', '7'), variable (1e-6, 1e-9, 0:0.1:2, ''));
  p = td ('0.35', '0'); p.Time = '1'; p.Before = '0'; p.After = '1'; p.InitialCondition = '0';
  scenarios{end+1} = scenario ('delay_s2_ode4', 'delay', 'step_td_integrator', ...
      'Step -> Transport Delay -> Integrator', p, fixed (0.1, 0, 3));
  scenarios{end+1} = scenario ('delay_s2_ode45', 'delay', 'step_td_integrator', ...
      'Step -> Transport Delay -> Integrator', p, variable (1e-6, 1e-9, 0:0.1:3, ''));
  p = td ('1', '1'); p.InitialCondition = '1'; p.Gain = '-1';
  scenarios{end+1} = scenario ('delay_s3_ode4_h01', 'delay', 'dde', 'x'' = -x(t-1)', p, fixed (0.1, 0, 6));
  scenarios{end+1} = scenario ('delay_s4_ode4', 'delay', 'clock_td', 'Delay shorter than the step', ...
      td ('0.03', '0'), fixed (0.1, 0, 1));
  scenarios{end+1} = scenario ('delay_s4b_ode4', 'delay', 'clock_td', 'Delay shorter than the step', ...
      td ('0.03', '7'), fixed (0.1, 0, 1));
  p = td ('0.2', '[5;6]'); p.Gain = '[1;-2]';
  scenarios{end+1} = scenario ('delay_s5_ode4', 'delay', 'clock_gain_td', 'Vector signal, vector initial output', ...
      p, fixed (0.1, 0, 1));
  p.InitialOutput = '3';
  scenarios{end+1} = scenario ('delay_s5b_ode4', 'delay', 'clock_gain_td', 'Vector signal, scalar initial output', ...
      p, fixed (0.1, 0, 1));
  p = td ('1', '0'); p.Value = '1'; p.Gain = '-0.5';
  scenarios{end+1} = scenario ('delay_s6_fixed05', 'delay', 'feedback', 'y = 1 - 0.5 y(t-1)', p, fixed (0.5, 0, 3));
  scenarios{end+1} = scenario ('delay_s6_fixed01', 'delay', 'feedback', 'y = 1 - 0.5 y(t-1)', p, fixed (0.1, 0, 3));
  scenarios{end+1} = scenario ('delay_s7_ode4', 'delay', 'sine_td', 'Sine Wave -> Transport Delay', ...
      td ('0.25', '0'), fixed (0.1, 0, 5));
  scenarios{end+1} = scenario ('delay_s8_ode4', 'delay', 'clock_td', 'Nonzero start time', ...
      td ('0.5', '7'), fixed (0.1, 1, 3));
  p = td ('0.5', '7'); p.InitialCondition = '0';
  scenarios{end+1} = scenario ('delay_s9_ode4', 'delay', 'clock_td_integrator', ...
      'Clock -> Transport Delay -> Integrator', p, fixed (0.1, 0, 2));
  scenarios{end+1} = scenario ('delay_s9_ode45', 'delay', 'clock_td_integrator', ...
      'Clock -> Transport Delay -> Integrator', p, variable (1e-10, 1e-12, 0:0.1:2, ''));
  p.DelayTime = '0.35';
  scenarios{end+1} = scenario ('delay_s9b_ode4', 'delay', 'clock_td_integrator', ...
      'Clock -> Transport Delay -> Integrator, delay off the step grid', p, fixed (0.1, 0, 2));
  p = td ('1', '0'); p.InitialCondition = '1'; p.Gain = '-1';
  scenarios{end+1} = scenario ('delay_s10_ode4_h01', 'delay', 'dde', ...
      'x'' = -x(t-1), initial output differs from x(0)', p, fixed (0.1, 0, 6));
  p = td ('0.35', '1'); p.InitialCondition = '1'; p.Gain = '-1';
  scenarios{end+1} = scenario ('delay_s11_ode4_h01', 'delay', 'dde', 'x'' = -x(t-0.35)', p, fixed (0.1, 0, 4));
  scenarios{end+1} = scenario ('delay_s12_ode4', 'delay', 'clock_td', 'Scalar input, vector initial output', ...
      td ('0.2', '[5;6]'), fixed (0.1, 0, 1));
  p = td ('0.2', '0'); p.Gain = '[1 2;3 4]';
  scenarios{end+1} = scenario ('delay_s13_ode4', 'delay', 'clock_gain_td', 'Matrix signal, scalar initial output', ...
      p, fixed (0.1, 0, 1));
  p = td ('1', '1'); p.InitialCondition = '[1;2]'; p.Gain = '-1';
  scenarios{end+1} = scenario ('delay_s14_ode4', 'delay', 'dde', 'Vector x'' = -x(t-1), scalar initial output', ...
      p, fixed (0.1, 0, 4));

  % Integrator with LimitOutput and ExternalReset.  ResetSteps rows are
  % Step blocks [time before after]; the reset signal is their sum.
  sq = '[0.5 -1 1;1 0 -2;1.5 0 2;2 0 -2;2.5 0 2]';
  sqs = '[0.55 -1 1;1.05 0 -2;1.55 0 2;2.05 0 -2;2.55 0 2]';
  gate = '[1 0 1;2 0 -1]';
  shifted = '[1.05 0 1;2.05 0 -1]';
  zs = '[1 -1 0;2 0 1;3 0 -1;4 0 -1]';
  g10 = (0:30) / 10;   % the recorded runs used these exact decimal times
  tight = {1e-8, 1e-10};
  scenarios{end+1} = scenario ('int_s1_ramp_ode4_h025', 'integrator', 'integrator', 'Ramp into the upper limit', ...
      integrator ('constant', '1', '0', '0', '1', 'none', ''), fixed (0.25, 0, 2));
  scenarios{end+1} = scenario ('int_s1_ramp_ode45_sparse', 'integrator', 'integrator', 'Ramp into the upper limit', ...
      integrator ('constant', '1', '0', '0', '1', 'none', ''), variable (1e-6, 1e-9, [0 0.7 2], 'EnableAll'));
  scenarios{end+1} = scenario ('int_s2_cos_ode4_h01', 'integrator', 'integrator', 'cos t within [-0.5, 0.5]', ...
      integrator ('cos', '', '0', '-0.5', '0.5', 'none', ''), fixed (0.1, 0, 7));
  scenarios{end+1} = scenario ('int_s3_vec_ode4_h025', 'integrator', 'integrator', 'Elementwise limits', ...
      integrator ('constant', '[1 -1 2]', '[0 0 0]', '[-0.5 -0.25 -1]', '[0.5 1 1]', 'none', ''), fixed (0.25, 0, 2));
  modes = {'rising', 'falling', 'either'};
  for m = 1:numel (modes)
    scenarios{end+1} = scenario (['int_s4_' modes{m} '_ode4'], 'integrator', 'integrator', ...
        'Square-wave reset, edges on the grid', integrator ('constant', '1', '0.25', '', '', modes{m}, sq), ...
        fixed (0.1, 0, 3));
  end
  scenarios{end+1} = scenario ('int_s4_either_ode45_zcon', 'integrator', 'integrator', ...
      'Square-wave reset, edges on the grid', integrator ('constant', '1', '0.25', '', '', 'either', sq), ...
      variable (tight{:}, g10, 'EnableAll'));
  scenarios{end+1} = scenario ('int_s5_rising_ode4', 'integrator', 'integrator', ...
      'Square-wave reset, edges between samples', integrator ('constant', '1', '0.25', '', '', 'rising', sqs), ...
      fixed (0.1, 0, 3));
  scenarios{end+1} = scenario ('int_s5_rising_ode45_zcon', 'integrator', 'integrator', ...
      'Square-wave reset, edges between samples', integrator ('constant', '1', '0.25', '', '', 'rising', sqs), ...
      variable (tight{:}, g10, 'EnableAll'));
  scenarios{end+1} = scenario ('int_s6_level_ode4', 'integrator', 'integrator', 'Level reset, gate [1, 2)', ...
      integrator ('constant', '1', '0.25', '', '', 'level', gate), fixed (0.1, 0, 3));
  scenarios{end+1} = scenario ('int_s6_levelshift_ode4', 'integrator', 'integrator', 'Level reset, gate [1.05, 2.05)', ...
      integrator ('constant', '1', '0.25', '', '', 'level', shifted), fixed (0.1, 0, 3));
  scenarios{end+1} = scenario ('int_s6_levelshift_ode45_zcon', 'integrator', 'integrator', ...
      'Level reset, gate [1.05, 2.05)', integrator ('constant', '1', '0.25', '', '', 'level', shifted), ...
      variable (tight{:}, g10, 'EnableAll'));
  scenarios{end+1} = scenario ('int_s6_levelshift_ode45_zcoff', 'integrator', 'integrator', ...
      'Level reset, gate [1.05, 2.05), zero crossings off', ...
      integrator ('constant', '1', '0.25', '', '', 'level', shifted), variable (tight{:}, g10, 'DisableAll'));
  scenarios{end+1} = scenario ('int_s6_levelhold_ode4', 'integrator', 'integrator', 'Level hold reset, gate [1, 2)', ...
      integrator ('constant', '1', '0.25', '', '', 'level hold', gate), fixed (0.1, 0, 3));
  scenarios{end+1} = scenario ('int_s6_levelhold_ode45_zcon', 'integrator', 'integrator', ...
      'Level hold reset, gate [1, 2)', integrator ('constant', '1', '0.25', '', '', 'level hold', gate), ...
      variable (tight{:}, g10, 'EnableAll'));
  scenarios{end+1} = scenario ('int_s7_icout_inward_ode4', 'integrator', 'integrator', ...
      'Initial condition outside the limits', integrator ('constant', '-1', '5', '-1', '2', 'none', ''), ...
      fixed (0.1, 0, 4));
  scenarios{end+1} = scenario ('int_s7_icout_reset_ode4', 'integrator', 'integrator', ...
      'Reset to a clipped initial condition', integrator ('constant', '-1', '5', '-1', '2', 'rising', sq), ...
      fixed (0.1, 0, 3));
  scenarios{end+1} = scenario ('int_s7_rpos0_level_ode4', 'integrator', 'integrator', ...
      'Level signal nonzero from t = 0', integrator ('constant', '1', '0.25', '', '', 'level', '[1 1 0]'), ...
      fixed (0.1, 0, 3));
  for m = 1:2
    scenarios{end+1} = scenario (['int_r1_zero_' modes{m} '_ode4'], 'integrator', 'integrator', ...
        'Edge sign rules through zero', integrator ('constant', '1', '0', '', '', modes{m}, zs), fixed (0.1, 0, 5));
  end
  scenarios{end+1} = scenario ('int_r2_satreset_rising_ode4', 'integrator', 'integrator', 'Reset while saturated', ...
      integrator ('constant', '1', '0.25', '0', '0.4', 'rising', sq), fixed (0.1, 0, 3));
  pulse = '[1.02 0 1;1.07 0 -1]';
  scenarios{end+1} = scenario ('int_r3_levelpulse_ode4', 'integrator', 'integrator', ...
      'Level pulse between samples', integrator ('constant', '1', '0.25', '', '', 'level', pulse), fixed (0.1, 0, 2));
  scenarios{end+1} = scenario ('int_r3_levelpulse_ode45_zcon', 'integrator', 'integrator', ...
      'Level pulse between samples', integrator ('constant', '1', '0.25', '', '', 'level', pulse), ...
      variable (tight{:}, (0:20) / 10, 'EnableAll'));
  pulse = '[1.02 -1 1;1.07 0 -2]';
  scenarios{end+1} = scenario ('int_r4b_truepulse_rising_ode4', 'integrator', 'integrator', ...
      'Rising pulse between samples', integrator ('constant', '1', '0.25', '', '', 'rising', pulse), fixed (0.1, 0, 2));
  scenarios{end+1} = scenario ('int_r4b_truepulse_rising_ode45_zcon', 'integrator', 'integrator', ...
      'Rising pulse between samples', integrator ('constant', '1', '0.25', '', '', 'rising', pulse), ...
      variable (tight{:}, (0:20) / 10, 'EnableAll'));
  scenarios{end+1} = scenario ('int_r5_ramp_ode4_h01_up099', 'integrator', 'integrator', ...
      'Limit reached inside an RK4 step', integrator ('constant', '1', '0', '0', '0.99', 'none', ''), fixed (0.1, 0, 1.5));
  scenarios{end+1} = scenario ('int_r5_ramp_ode4_h01_up1', 'integrator', 'integrator', ...
      'Limit reached at an RK4 step end', integrator ('constant', '1', '0', '0', '1', 'none', ''), fixed (0.1, 0, 1.5));
  scenarios{end+1} = scenario ('int_r7_stepinput_ode4', 'integrator', 'integrator', ...
      'Step input between RK4 grid points', integrator ('step', '[0.55 1 3]', '0', '0', '10', 'none', ''), ...
      fixed (0.1, 0, 1));
  scenarios{end+1} = scenario ('int_r7_stepinput_ode45_zcon', 'integrator', 'integrator', ...
      'Step input between RK4 grid points', integrator ('step', '[0.55 1 3]', '0', '0', '10', 'none', ''), ...
      variable (tight{:}, (0:10) / 10, 'EnableAll'));
end

function s = scenario (id, group, model, description, parameters, config)
  s = config;
  s.id = id; s.group = group; s.model = model; s.description = description;
  s.parameters = parameters;
end

function p = integrator (source, value, x0, low, high, reset, steps)
  % Simulink Integrator parameters plus the input and reset sources.  An
  % empty low limit leaves LimitOutput off.
  p = struct ('Input', source, 'InputValue', value, 'InitialCondition', x0, ...
              'LimitOutput', 'off', 'LowerSaturationLimit', '-inf', 'UpperSaturationLimit', 'inf', ...
              'ExternalReset', reset, 'ZeroCross', 'on', 'ResetSteps', steps);
  if ~isempty (low)
    p.LimitOutput = 'on'; p.LowerSaturationLimit = low; p.UpperSaturationLimit = high;
  end
end

function c = fixed (h, t0, t1)
  c = struct ('solver', 'ode4', 'fixed_step', h, 'reltol', [], 'abstol', [], 'zero_cross', '', ...
              'start_time', t0, 'stop_time', t1, 'output_times', []);
end

function c = variable (reltol, abstol, times, zero_cross)
  c = struct ('solver', 'ode45', 'fixed_step', [], 'reltol', reltol, 'abstol', abstol, ...
              'zero_cross', zero_cross, 'start_time', times(1), 'stop_time', times(end), ...
              'output_times', times);
end

function r = run_case (s)
  r = rmfield (s, 'id');
  r.ok = false; r.error = ''; r.simulink_solver = ''; r.warnings = {}; r.seconds = NaN;
  r.t = []; r.y = [];
  name = ['ob_ref_' s.id];
  name = name(1:min (end, 60));
  try
    if bdIsLoaded (name), close_system (name, 0); end
    new_system (name);
    cleanup = onCleanup (@() close_system (name, 0));
    build_model (name, s);
    set_param (name, 'SaveFormat', 'StructureWithTime', 'SaveOutput', 'on', 'OutputSaveName', 'yout', ...
               'SaveTime', 'on', 'TimeSaveName', 'tout', 'SaveState', 'off', 'LimitDataPoints', 'off', ...
               'SignalLogging', 'off', 'ReturnWorkspaceOutputs', 'on', ...
               'StartTime', num2str (s.start_time, 17), 'StopTime', num2str (s.stop_time, 17));
    if strcmp (s.solver, 'ode4')
      set_param (name, 'SolverType', 'Fixed-step', 'Solver', 'ode4', 'FixedStep', num2str (s.fixed_step, 17));
    else
      set_param (name, 'SolverType', 'Variable-step', 'Solver', 'ode45', ...
                 'RelTol', num2str (s.reltol, 17), 'AbsTol', num2str (s.abstol, 17), 'MaxStep', 'auto', ...
                 'OutputOption', 'SpecifiedOutputTimes', 'OutputTimes', mat2str (s.output_times, 17));
    end
    if ~isempty (s.zero_cross), set_param (name, 'ZeroCrossControl', s.zero_cross); end
    tic; out = sim (name); r.seconds = toc;
    r.t = out.get ('tout');
    logged = out.get ('yout');
    values = logged.signals(1).values;
    if ndims (values) == 3
      % Matrix signals: one row per sample, elements in column-major order.
      sz = size (values);
      values = reshape (permute (values, [3 1 2]), sz(3), []);
    end
    r.y = values;
    try
      diagnostics = out.SimulationMetadata.ExecutionInfo.WarningDiagnostics;
      for k = 1:numel (diagnostics)
        r.warnings{end+1} = diagnostics(k).Diagnostic.message;
      end
    catch
    end
    try, r.simulink_solver = out.SimulationMetadata.ModelInfo.SolverInfo.Solver; catch, end
    r.ok = true;
  catch err
    r.error = err.message;
  end
end

function build_model (m, s)
  p = s.parameters;
  switch s.model
    case 'clock_td'
      add_block ('simulink/Sources/Clock', [m '/Clock']);
      add_delay (m, p); add_block ('simulink/Sinks/Out1', [m '/Out1']);
      add_line (m, 'Clock/1', 'TD/1'); add_line (m, 'TD/1', 'Out1/1');
    case 'clock_gain_td'
      add_block ('simulink/Sources/Clock', [m '/Clock']);
      add_block ('simulink/Math Operations/Gain', [m '/G'], 'Gain', p.Gain);
      add_delay (m, p); add_block ('simulink/Sinks/Out1', [m '/Out1']);
      add_line (m, 'Clock/1', 'G/1'); add_line (m, 'G/1', 'TD/1'); add_line (m, 'TD/1', 'Out1/1');
    case 'clock_td_integrator'
      add_block ('simulink/Sources/Clock', [m '/Clock']);
      add_delay (m, p);
      add_block ('simulink/Continuous/Integrator', [m '/Int'], 'InitialCondition', p.InitialCondition);
      add_block ('simulink/Sinks/Out1', [m '/Out1']);
      add_line (m, 'Clock/1', 'TD/1'); add_line (m, 'TD/1', 'Int/1'); add_line (m, 'Int/1', 'Out1/1');
    case 'step_td_integrator'
      add_block ('simulink/Sources/Step', [m '/Step'], 'Time', p.Time, 'Before', p.Before, 'After', p.After);
      add_delay (m, p);
      add_block ('simulink/Continuous/Integrator', [m '/Int'], 'InitialCondition', p.InitialCondition);
      add_block ('simulink/Sinks/Out1', [m '/Out1']);
      add_line (m, 'Step/1', 'TD/1'); add_line (m, 'TD/1', 'Int/1'); add_line (m, 'Int/1', 'Out1/1');
    case 'dde'
      add_block ('simulink/Continuous/Integrator', [m '/x'], 'InitialCondition', p.InitialCondition);
      add_delay (m, p);
      add_block ('simulink/Math Operations/Gain', [m '/G'], 'Gain', p.Gain);
      add_block ('simulink/Sinks/Out1', [m '/Out1']);
      add_line (m, 'x/1', 'TD/1'); add_line (m, 'TD/1', 'G/1'); add_line (m, 'G/1', 'x/1');
      add_line (m, 'x/1', 'Out1/1');
    case 'feedback'
      add_block ('simulink/Sources/Constant', [m '/One'], 'Value', p.Value);
      add_block ('simulink/Math Operations/Sum', [m '/Sum'], 'Inputs', '++');
      add_delay (m, p);
      add_block ('simulink/Math Operations/Gain', [m '/G'], 'Gain', p.Gain);
      add_block ('simulink/Sinks/Out1', [m '/Out1']);
      add_line (m, 'One/1', 'Sum/1'); add_line (m, 'G/1', 'Sum/2'); add_line (m, 'Sum/1', 'TD/1');
      add_line (m, 'TD/1', 'G/1'); add_line (m, 'Sum/1', 'Out1/1');
    case 'sine_td'
      add_block ('simulink/Sources/Sine Wave', [m '/Sine'], 'Amplitude', '1', 'Bias', '0', ...
                 'Frequency', '1', 'Phase', '0', 'SampleTime', '0');
      add_delay (m, p); add_block ('simulink/Sinks/Out1', [m '/Out1']);
      add_line (m, 'Sine/1', 'TD/1'); add_line (m, 'TD/1', 'Out1/1');
    case 'integrator'
      build_integrator (m, p);
    otherwise
      error ('reference_ob_simulink_delay_integrator: unknown model %s', s.model);
  end
end

function add_delay (m, p)
  add_block ('simulink/Continuous/Transport Delay', [m '/TD'], ...
             'DelayTime', p.DelayTime, 'InitialOutput', p.InitialOutput);
end

function build_integrator (m, p)
  switch p.Input
    case 'cos'
      add_block ('simulink/Sources/Clock', [m '/Clock']);
      add_block ('simulink/Math Operations/Trigonometric Function', [m '/In'], 'Operator', 'cos');
      add_line (m, 'Clock/1', 'In/1');
    case 'step'
      v = str2num (p.InputValue); %#ok<ST2NM>
      add_block ('simulink/Sources/Step', [m '/In'], 'Time', num2str (v(1), 17), ...
                 'Before', num2str (v(2), 17), 'After', num2str (v(3), 17), 'SampleTime', '0');
    otherwise
      add_block ('simulink/Sources/Constant', [m '/In'], 'Value', p.InputValue);
  end
  block = [m '/Int'];
  add_block ('simulink/Continuous/Integrator', block);
  set_param (block, 'InitialCondition', p.InitialCondition, 'LimitOutput', p.LimitOutput);
  if strcmp (p.LimitOutput, 'on')
    set_param (block, 'LowerSaturationLimit', p.LowerSaturationLimit, ...
               'UpperSaturationLimit', p.UpperSaturationLimit);
  end
  set_param (block, 'ExternalReset', p.ExternalReset, 'ZeroCross', p.ZeroCross);
  add_line (m, 'In/1', 'Int/1');
  add_block ('simulink/Sinks/Out1', [m '/Out1']);
  add_line (m, 'Int/1', 'Out1/1');
  if ~strcmp (p.ExternalReset, 'none')
    steps = str2num (p.ResetSteps); %#ok<ST2NM>
    for j = 1:size (steps, 1)
      add_block ('simulink/Sources/Step', sprintf ('%s/S%d', m, j), 'Time', num2str (steps(j, 1), 17), ...
                 'Before', num2str (steps(j, 2), 17), 'After', num2str (steps(j, 3), 17), 'SampleTime', '0');
    end
    last = 'S1';
    for j = 2:size (steps, 1)
      sum_name = sprintf ('P%d', j);
      add_block ('simulink/Math Operations/Sum', [m '/' sum_name], 'Inputs', '++');
      add_line (m, [last '/1'], [sum_name '/1']);
      add_line (m, sprintf ('S%d/1', j), [sum_name '/2']);
      last = sum_name;
    end
    add_line (m, [last '/1'], 'Int/2');
  end
end

function d = dde_case (f, lag, history, span, times, options)
  tic; solution = dde23 (f, lag, history, span, options); d.seconds = toc;
  d.reltol = options.RelTol; d.abstol = options.AbsTol;
  d.t = times; d.y = deval (solution, times); d.steps = numel (solution.x) - 1;
end
