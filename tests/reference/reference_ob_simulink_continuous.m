function reference_ob_simulink_continuous (file)
  % Record live Simulink traces for continuous (zero-crossing) conditional
  % controls and for Switch, Saturation and Dead Zone crossings that feed
  % Integrators, under the variable-step solvers ode45 and ode15s with
  % zero-crossing detection on.  Run in MATLAB with Simulink:
  %   reference_ob_simulink_continuous ('simulink-continuous-reference.json')
  % Every model is built unsaved and closed again.  Each case records its
  % block parameters, so test_ob_simulink_extended can rebuild the same model
  % in Octave Blocks.
  %
  % Several cases add a Simulink-only "recorder": a Triggered Subsystem
  % (either edge, compatibility initial state, so it never fires at the start)
  % that samples the Clock whenever the guard signal crosses zero.  Its column
  % holds the time at which Simulink located the most recent crossing; the
  % Octave test compares it with Octave's result.events.
  if exist ('OCTAVE_VERSION', 'builtin')
    error ('reference_ob_simulink_continuous: run this producer in MATLAB');
  end
  if nargin < 1, file = 'simulink-continuous-reference.json'; end
  load_system ('simulink');
  details = ver ('simulink');
  record = struct ('producer', 'reference_ob_simulink_continuous.m', ...
                   'matlab_version', version, ...
                   'simulink_version', [details(1).Version ' ' details(1).Release], ...
                   'note', 'Recorded by the producer in one MATLAB session.');
  record.cases = struct ();
  scenarios = scenario_table ();
  for k = 1:numel (scenarios)
    s = scenarios{k};
    record.cases.(s.id) = run_case (s);
    r = record.cases.(s.id);
    fprintf ('%-34s ok=%d n=%d %.2fs %s\n', s.id, r.ok, numel (r.t), r.seconds, r.error);
  end
  fid = fopen (file, 'w');
  if fid < 0, error ('reference_ob_simulink_continuous: cannot write %s', file); end
  fprintf (fid, '%s', jsonencode (record));
  fclose (fid);
end

function scenarios = scenario_table ()
  % Model names match the builders below and in test_ob_simulink_extended.m.
  % The pulse control is sin(gain * (t + offset)): with gain 2*pi and offset
  % -0.23 it is positive on (0.23, 0.73) and (1.23, 1.73), so every crossing
  % lies between output times.  The 'ongrid' case uses offset -0.2, whose
  % crossings coincide with output times.
  scenarios = {};
  grid = 0:0.1:2;
  pulse = struct ('offset', -0.23, 'gain', 2*pi);
  for solver = {'ode45', 'ode15s'}
    sv = solver{1};
    c = variable (sv, grid);
    policies = {'held', 'held'; 'reset', 'held'; 'reset', 'reset'; 'held', 'reset'};
    for k = 1:size (policies, 1)
      p = pulse; p.data = 2; p.initial_state = 3; p.initial_output = -9;
      p.states = policies{k, 1}; p.outputs = policies{k, 2};
      scenarios{end+1} = scenario (sprintf ('en_int_%s_%s_%s', policies{k, :}, sv), 'enabled_integrator', ...
          'Enabled Integrator of a constant, continuous sine enable', p, c, {'output', 'recorder'});
    end
    p.offset = -0.2; p.states = 'held'; p.outputs = 'held';
    scenarios{end+1} = scenario (['en_int_ongrid_' sv], 'enabled_integrator', ...
        'Enabled Integrator, enable crossings at output times', p, c, {'output', 'recorder'});
    for outputs = {'held', 'reset'}
      p = pulse; p.initial_output = 0; p.outputs = outputs{1};
      scenarios{end+1} = scenario (['en_feed_' outputs{1} '_' sv], 'enabled_feedthrough', ...
          'Enabled Gain of the Clock (no state), integrated at the root', p, c, ...
          {'output', 'integral', 'recorder'});
    end
    for direction = {'up', 'down'}
      p = struct ('threshold', 0.35, 'high', 1, 'low', -1, 'initial_output', -9);
      if strcmp (direction{1}, 'down'), p.high = -1; p.low = 1; end
      scenarios{end+1} = scenario (['en_switch_' direction{1} '_' sv], 'enabled_switch', ...
          'Enable driven by a Time-controlled Switch', p, variable (sv, 0:0.1:1), {'output', 'recorder'});
    end
    p = pulse; p.delay_period = 0.125; p.delay_initial = -7; p.initial_output = -9;
    scenarios{end+1} = scenario (['en_inner_clock_' sv], 'enabled_inner_clock', ...
        'Continuous enable around a 0.125 s Unit Delay and an Integrator', p, c, ...
        {'delay', 'integral', 'recorder'});
    for mode = {'rising', 'falling', 'either'}
      for init = {'zero', 'negative', 'compatibility'}
        p = pulse; p.trigger = mode{1}; p.initial_trigger = init{1}; p.initial_output = -9;
        scenarios{end+1} = scenario (sprintf ('trig_%s_%s_%s', mode{1}, init{1}, sv), 'triggered_clock', ...
            'Triggered sample of the Clock, continuous sine trigger', p, c, {'output'});
      end
    end
    for mode = {'rising', 'either'}
      p = pulse; p.trigger = mode{1}; p.initial_trigger = 'negative'; p.initial_output = -9;
      p.delay_initial = -7;
      scenarios{end+1} = scenario (sprintf ('trig_delay_%s_%s', mode{1}, sv), 'triggered_delay', ...
          'Triggered Unit Delay of the Clock, continuous sine trigger', p, c, {'output'});
    end
    p = struct ('threshold', 0.37, 'high', 3, 'low', -2, 'initial_state', 0);
    scenarios{end+1} = scenario (['sw_time_' sv], 'switch_time', ...
        'Time-driven Switch selects the derivative', p, variable (sv, 0:0.1:1), {'state', 'recorder'});
    p = struct ('threshold', 0.5, 'high', 0.25, 'initial_state', 0);
    scenarios{end+1} = scenario (['sw_state_' sv], 'switch_state', ...
        'State-driven Switch: x'' = cos t until x = 0.5, then 0.25', p, variable (sv, 0:0.1:1.5), ...
        {'state', 'recorder'});
    p = struct ('gain', 2*pi, 'lower', -0.5, 'upper', 0.5, 'initial_state', 0);
    scenarios{end+1} = scenario (['sat_int_' sv], 'saturation_integrator', ...
        'Integral of a saturated sine', p, c, {'state'});
    scenarios{end+1} = scenario (['dz_int_' sv], 'deadzone_integrator', ...
        'Integral of a dead-zoned sine', p, c, {'state'});
  end
end

function s = scenario (id, model, description, parameters, config, columns)
  s = config;
  s.id = id; s.model = model; s.description = description;
  s.parameters = parameters; s.columns = columns;
end

function c = variable (solver, times)
  c = struct ('solver', solver, 'reltol', 1e-8, 'abstol', 1e-10, 'maxstep', 0.1, ...
              'zero_cross', 'UseLocalSettings', 'start_time', times(1), 'stop_time', times(end), ...
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
    set_param (name, 'SaveFormat', 'Array', 'SaveOutput', 'on', 'OutputSaveName', 'yout', ...
               'SaveTime', 'on', 'TimeSaveName', 'tout', 'SaveState', 'off', 'LimitDataPoints', 'off', ...
               'SignalLogging', 'off', 'ReturnWorkspaceOutputs', 'on', ...
               'StartTime', num (s.start_time), 'StopTime', num (s.stop_time), ...
               'SolverType', 'Variable-step', 'Solver', s.solver, ...
               'RelTol', num (s.reltol), 'AbsTol', num (s.abstol), 'MaxStep', num (s.maxstep), ...
               'OutputOption', 'SpecifiedOutputTimes', 'OutputTimes', mat2str (s.output_times, 17), ...
               'ZeroCrossControl', s.zero_cross);
    tic; out = sim (name); r.seconds = toc;
    r.t = out.get ('tout');
    r.y = out.get ('yout');
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

function text = num (value)
  text = num2str (value, 17);
end

function build_model (m, s)
  p = s.parameters;
  add_block ('simulink/Sources/Clock', [m '/Time']);
  switch s.model
    case 'enabled_integrator'
      control = add_pulse (m, p);
      add_block ('simulink/Sources/Constant', [m '/Data'], 'Value', num (p.data));
      sub = add_enabled (m, 'Child', p.states);
      add_block ('simulink/Continuous/Integrator', [sub '/State'], 'InitialCondition', num (p.initial_state));
      add_line (sub, 'In1/1', 'State/1'); add_line (sub, 'State/1', 'Out1/1');
      set_param ([sub '/Out1'], 'InitialOutput', num (p.initial_output), 'OutputWhenDisabled', p.outputs);
      add_line (m, 'Data/1', 'Child/1'); add_line (m, control, 'Child/Enable');
      add_outport (m, 1, 'Child/1');
      add_recorder (m, control, 2);
    case 'enabled_feedthrough'
      control = add_pulse (m, p);
      sub = add_enabled (m, 'Child', 'held');
      add_block ('simulink/Math Operations/Gain', [sub '/Gain'], 'Gain', '1');
      add_line (sub, 'In1/1', 'Gain/1'); add_line (sub, 'Gain/1', 'Out1/1');
      set_param ([sub '/Out1'], 'InitialOutput', num (p.initial_output), 'OutputWhenDisabled', p.outputs);
      add_line (m, 'Time/1', 'Child/1'); add_line (m, control, 'Child/Enable');
      add_block ('simulink/Continuous/Integrator', [m '/Integral'], 'InitialCondition', '0');
      add_line (m, 'Child/1', 'Integral/1');
      add_outport (m, 1, 'Child/1'); add_outport (m, 2, 'Integral/1');
      add_recorder (m, control, 3);
    case 'enabled_switch'
      add_block ('simulink/Sources/Constant', [m '/High'], 'Value', num (p.high));
      add_block ('simulink/Sources/Constant', [m '/Low'], 'Value', num (p.low));
      add_block ('simulink/Signal Routing/Switch', [m '/Gate'], 'Criteria', 'u2 >= Threshold', ...
                 'Threshold', num (p.threshold));
      add_line (m, 'High/1', 'Gate/1'); add_line (m, 'Time/1', 'Gate/2'); add_line (m, 'Low/1', 'Gate/3');
      add_block ('simulink/Sources/Constant', [m '/Data'], 'Value', '1');
      sub = add_enabled (m, 'Child', 'held');
      add_block ('simulink/Continuous/Integrator', [sub '/State'], 'InitialCondition', '0');
      add_line (sub, 'In1/1', 'State/1'); add_line (sub, 'State/1', 'Out1/1');
      set_param ([sub '/Out1'], 'InitialOutput', num (p.initial_output), 'OutputWhenDisabled', 'held');
      add_line (m, 'Data/1', 'Child/1'); add_line (m, 'Gate/1', 'Child/Enable');
      add_outport (m, 1, 'Child/1');
      add_recorder (m, 'Gate/1', 2);
    case 'enabled_inner_clock'
      control = add_pulse (m, p);
      sub = add_enabled (m, 'Child', 'held');
      add_block ('simulink/Discrete/Unit Delay', [sub '/Delay'], 'InitialCondition', num (p.delay_initial), ...
                 'SampleTime', num (p.delay_period));
      add_line (sub, 'In1/1', 'Delay/1'); add_line (sub, 'Delay/1', 'Out1/1');
      add_block ('simulink/Sources/Constant', [sub '/One'], 'Value', '1');
      add_block ('simulink/Continuous/Integrator', [sub '/State'], 'InitialCondition', '0');
      add_block ('simulink/Sinks/Out1', [sub '/Out2']);
      add_line (sub, 'One/1', 'State/1'); add_line (sub, 'State/1', 'Out2/1');
      set_param ([sub '/Out1'], 'InitialOutput', num (p.initial_output), 'OutputWhenDisabled', 'held');
      set_param ([sub '/Out2'], 'InitialOutput', num (p.initial_output), 'OutputWhenDisabled', 'held');
      add_line (m, 'Time/1', 'Child/1'); add_line (m, control, 'Child/Enable');
      add_outport (m, 1, 'Child/1'); add_outport (m, 2, 'Child/2');
      add_recorder (m, control, 3);
    case {'triggered_clock', 'triggered_delay'}
      control = add_pulse (m, p);
      sub = [m '/Child'];
      add_block ('simulink/Ports & Subsystems/Triggered Subsystem', sub);
      set_param ([sub '/Trigger'], 'TriggerType', p.trigger, 'InitialTriggerSignalState', p.initial_trigger);
      if strcmp (s.model, 'triggered_delay')
        delete_line (sub, 'In1/1', 'Out1/1');
        add_block ('simulink/Discrete/Unit Delay', [sub '/Delay'], 'InitialCondition', num (p.delay_initial), ...
                   'SampleTime', '-1');
        add_line (sub, 'In1/1', 'Delay/1'); add_line (sub, 'Delay/1', 'Out1/1');
      end
      set_param ([sub '/Out1'], 'InitialOutput', num (p.initial_output));
      add_line (m, 'Time/1', 'Child/1'); add_line (m, control, 'Child/Trigger');
      add_outport (m, 1, 'Child/1');
      % Without a continuous state Simulink replaces ode45/ode15s by
      % VariableStepDiscrete; an unused Integrator keeps the requested solver.
      add_block ('simulink/Sources/Constant', [m '/Zero'], 'Value', '0');
      add_block ('simulink/Continuous/Integrator', [m '/Keep solver'], 'InitialCondition', '0');
      add_block ('simulink/Sinks/Terminator', [m '/End']);
      add_line (m, 'Zero/1', 'Keep solver/1'); add_line (m, 'Keep solver/1', 'End/1');
    case 'switch_time'
      add_block ('simulink/Sources/Constant', [m '/High'], 'Value', num (p.high));
      add_block ('simulink/Sources/Constant', [m '/Low'], 'Value', num (p.low));
      add_block ('simulink/Signal Routing/Switch', [m '/Select'], 'Criteria', 'u2 >= Threshold', ...
                 'Threshold', num (p.threshold));
      add_block ('simulink/Continuous/Integrator', [m '/State'], 'InitialCondition', num (p.initial_state));
      add_line (m, 'High/1', 'Select/1'); add_line (m, 'Time/1', 'Select/2'); add_line (m, 'Low/1', 'Select/3');
      add_line (m, 'Select/1', 'State/1');
      add_outport (m, 1, 'State/1');
      guard = add_guard (m, 'Time/1', p.threshold);
      add_recorder (m, guard, 2);
    case 'switch_state'
      add_block ('simulink/Sources/Constant', [m '/High'], 'Value', num (p.high));
      add_block ('simulink/Math Operations/Trigonometric Function', [m '/Low'], 'Operator', 'cos');
      add_block ('simulink/Signal Routing/Switch', [m '/Select'], 'Criteria', 'u2 >= Threshold', ...
                 'Threshold', num (p.threshold));
      add_block ('simulink/Continuous/Integrator', [m '/State'], 'InitialCondition', num (p.initial_state));
      add_line (m, 'Time/1', 'Low/1');
      add_line (m, 'High/1', 'Select/1'); add_line (m, 'State/1', 'Select/2'); add_line (m, 'Low/1', 'Select/3');
      add_line (m, 'Select/1', 'State/1');
      add_outport (m, 1, 'State/1');
      guard = add_guard (m, 'State/1', p.threshold);
      add_recorder (m, guard, 2);
    case {'saturation_integrator', 'deadzone_integrator'}
      add_block ('simulink/Math Operations/Gain', [m '/Scale'], 'Gain', num (p.gain));
      add_block ('simulink/Math Operations/Trigonometric Function', [m '/Wave'], 'Operator', 'sin');
      if strcmp (s.model, 'saturation_integrator')
        add_block ('simulink/Discontinuities/Saturation', [m '/Limit'], 'LowerLimit', num (p.lower), ...
                   'UpperLimit', num (p.upper));
      else
        add_block ('simulink/Discontinuities/Dead Zone', [m '/Limit'], 'LowerValue', num (p.lower), ...
                   'UpperValue', num (p.upper));
      end
      add_block ('simulink/Continuous/Integrator', [m '/State'], 'InitialCondition', num (p.initial_state));
      add_line (m, 'Time/1', 'Scale/1'); add_line (m, 'Scale/1', 'Wave/1');
      add_line (m, 'Wave/1', 'Limit/1'); add_line (m, 'Limit/1', 'State/1');
      add_outport (m, 1, 'State/1');
    otherwise
      error ('reference_ob_simulink_continuous: unknown model %s', s.model);
  end
end

function control = add_pulse (m, p)
  % sin(gain * (t + offset)) from the same primitive chain the Octave model
  % uses: Clock, Constant offset, Sum, Gain, sin.
  add_block ('simulink/Sources/Constant', [m '/Offset'], 'Value', num (p.offset));
  add_block ('simulink/Math Operations/Sum', [m '/Phase'], 'Inputs', '++');
  add_block ('simulink/Math Operations/Gain', [m '/Scale'], 'Gain', num (p.gain));
  add_block ('simulink/Math Operations/Trigonometric Function', [m '/Control'], 'Operator', 'sin');
  add_line (m, 'Time/1', 'Phase/1'); add_line (m, 'Offset/1', 'Phase/2');
  add_line (m, 'Phase/1', 'Scale/1'); add_line (m, 'Scale/1', 'Control/1');
  control = 'Control/1';
end

function guard = add_guard (m, source, threshold)
  % source - threshold, the Switch's own zero-crossing guard.
  add_block ('simulink/Sources/Constant', [m '/Negative threshold'], 'Value', num (-threshold));
  add_block ('simulink/Math Operations/Sum', [m '/Guard'], 'Inputs', '++');
  add_line (m, source, 'Guard/1'); add_line (m, 'Negative threshold/1', 'Guard/2');
  guard = 'Guard/1';
end

function sub = add_enabled (m, name, states)
  sub = [m '/' name];
  add_block ('simulink/Ports & Subsystems/Enabled Subsystem', sub);
  set_param ([sub '/Enable'], 'StatesWhenEnabling', states);
  delete_line (sub, 'In1/1', 'Out1/1');
end

function add_recorder (m, source, port)
  % Simulink-only probe: the Clock sampled at every located crossing of
  % 'source'; -1 until the first crossing.
  r = [m '/Recorder'];
  add_block ('simulink/Ports & Subsystems/Triggered Subsystem', r);
  set_param ([r '/Trigger'], 'TriggerType', 'either', 'InitialTriggerSignalState', 'compatibility');
  set_param ([r '/Out1'], 'InitialOutput', '-1');
  add_line (m, 'Time/1', 'Recorder/1');
  add_line (m, source, 'Recorder/Trigger');
  add_outport (m, port, 'Recorder/1');
end

function add_outport (m, port, source)
  name = sprintf ('Y%d', port);
  add_block ('simulink/Sinks/Out1', [m '/' name]);
  if str2double (get_param ([m '/' name], 'Port')) ~= port
    error ('reference_ob_simulink_continuous: outport %s is not port %d', name, port);
  end
  add_line (m, source, [name '/1']);
end
