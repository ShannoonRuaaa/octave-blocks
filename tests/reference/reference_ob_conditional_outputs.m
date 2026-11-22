function reference_ob_conditional_outputs (file)
  % Record live Simulink traces and parameter probes that pin down when the
  % Outports of conditional subsystems take new values:
  %   - enabled bodies with inner clocks whose Outports are driven by blocks
  %     at different rates (mixed-rate Sums, inherited Gains, a constant, an
  %     inherited Forward Euler, a held Rate Transition) under held and reset
  %     states, with per-port OutputWhenDisabled;
  %   - the same question for a body with a continuous Integrator (ode4);
  %   - a scalar InitialOutput on a vector port of a clocked body;
  %   - OutputWhenDisabled 'reset' on a Triggered Subsystem Outport and mixed
  %     per-port policies in an Enabled and Triggered Subsystem;
  %   - set_param/get_param probes for Outport OutputWhenDisabled and
  %     InitialOutput, Enable StatesWhenEnabling and the model's
  %     SimulationMode.
  % Run in MATLAB with Simulink:
  %   reference_ob_conditional_outputs ('simulink-conditional-outputs-reference.json')
  % Every model is built unsaved and closed again.  test_ob_simulink_extended
  % rebuilds each case in Octave Blocks from the recorded parameters, and
  % test_ob_simulink_api_reference checks the probes.
  if exist ('OCTAVE_VERSION', 'builtin')
    error ('reference_ob_conditional_outputs: run this producer in MATLAB');
  end
  if nargin < 1, file = 'simulink-conditional-outputs-reference.json'; end
  load_system ('simulink');
  details = ver ('simulink');
  record = struct ('producer', 'reference_ob_conditional_outputs.m', ...
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
  try
    record.api = api_probes ();
  catch err
    record.api = struct ('error', err.message);
  end
  fid = fopen (file, 'w');
  if fid < 0, error ('reference_ob_conditional_outputs: cannot write %s', file); end
  fprintf (fid, '%s', jsonencode (record));
  fclose (fid);
end

function scenarios = scenario_table ()
  % Model names match the builders below and in test_ob_simulink_extended.m.
  % Sample times are [period offset]; logging is at every 1/16 s base step.
  scenarios = {};
  pulse = struct ('times', [0 0.375 0.875 1.125 1.625], 'values', [0 1 0 1 0]);
  outputs = {'held', 'held', 'held', 'held', 'held', 'reset', 'held', 'held', 'reset'};
  for states = {'held', 'reset'}
    p = struct ('enable', pulse, 'enable_sample', 0.125, 'data_sample', 0.125, 'states', states{1}, ...
                'fast', 0.125, 'slow', 0.25, 'fast_initial', -1, 'slow_initial', -2, ...
                'euler_initial', -3, 'transition_initial', -4, 'transition_period', 0.25, ...
                'constant', 7, 'constant_sample', 'inf', 'initial_output', -9);
    p.outputs = outputs;
    scenarios{end+1} = scenario (['gating_' states{1}], 'gating', ...
        'Enabled body with 0.125 s and 0.25 s Unit Delays: mixed-rate, inherited, constant, inherited Euler and Rate Transition outputs', ...
        p, discrete (1/16, 2), {'fast_plus_slow', 'twice_slow', 'thrice_data', 'data_plus_slow', 'constant', ...
                                'slow_reset', 'inherited_euler', 'data_to_slow', 'fast_reset'});
  end
  for states = {'held', 'reset'}
    p = struct ('enable', pulse, 'enable_sample', 0.125, 'states', states{1}, 'slope', 1, ...
                'integrator_initial', -4, 'slow', 0.25, 'slow_initial', -2, 'initial_output', -9);
    scenarios{end+1} = scenario (['gating_continuous_' states{1}], 'gating_continuous', ...
        'Enabled body with a continuous Integrator and a 0.25 s Unit Delay (ode4)', ...
        p, fixed ('ode4', 1/16, 2), {'integral', 'slow_delay', 'integral_plus_slow'});
  end
  p = struct ('enable', pulse, 'enable_sample', 0.125, 'data_sample', 0.125, 'gain', [1 2], ...
              'slow', 0.25, 'delay_initial', [0 0], 'initial_outputs', {{-4, [7 8]}});
  p.outputs = {'reset', 'held'};
  scenarios{end+1} = scenario ('vector_inner_clock', 'vector_clock', ...
      'Enabled: 0.25 s vector Unit Delay with a scalar InitialOutput (reset) and a vector pass-through', ...
      p, discrete (1/16, 2), {'delay_1', 'delay_2', 'pass_1', 'pass_2'});
  p = struct ('trigger', pulse, 'trigger_sample', 0.125, 'data_sample', 0.125, 'trigger_type', 'rising', ...
              'initial_trigger', 'zero', 'gain', 2, 'initial_outputs', [-9 -5]);
  p.outputs = {'reset', 'held'};
  scenarios{end+1} = scenario ('triggered_reset_port', 'triggered_ports', ...
      'Triggered: OutputWhenDisabled reset on one Outport (Simulink keeps triggered outputs held)', ...
      p, discrete (1/16, 2), {'sample', 'gain'});
  square = struct ('times', 0:0.125:2, 'values', repmat ([-1 1], 1, 9));
  square.values = square.values(1:numel (square.times));
  p = struct ('enable', pulse, 'trigger', square, 'sample', 0.125, 'data_sample', 0.125, ...
              'trigger_type', 'rising', 'initial_trigger', 'zero', 'states', 'held', ...
              'gain', -1, 'initial_outputs', [-9 5]);
  p.outputs = {'held', 'reset'};
  scenarios{end+1} = scenario ('combined_mixed_ports', 'combined_ports', ...
      'Enabled and Triggered: held and reset Outports', p, discrete (1/16, 2), {'sample', 'negated'});
end

function s = scenario (id, model, description, parameters, config, columns)
  s = config;
  s.id = id; s.model = model; s.description = description;
  s.parameters = parameters; s.columns = columns;
end

function c = fixed (solver, h, stop)
  c = struct ('solver', solver, 'fixed_step', h, 'start_time', 0, 'stop_time', stop);
end

function c = discrete (h, stop)
  c = fixed ('FixedStepDiscrete', h, stop);
end

function r = run_case (s)
  r = attempt_case (s);
  if ~r.ok && isfield (s.parameters, 'constant_sample')
    % A constant-sample-time Constant inside the enabled body may be
    % rejected; retry with an inherited one and keep the first error.
    first = r.error;
    s.parameters.constant_sample = '-1';
    r = attempt_case (s);
    r.first_error = first;
  end
end

function r = attempt_case (s)
  r = rmfield (s, 'id');
  r.ok = false; r.error = ''; r.simulink_solver = ''; r.warnings = {}; r.seconds = NaN;
  r.t = []; r.y = []; r.multitasking = ''; r.single_task_transitions = '';
  name = ['ob_ref_' s.id];
  name = name(1:min (end, 60));
  try
    if bdIsLoaded (name), close_system (name, 0); end
    new_system (name);
    cleanup = onCleanup (@() close_system (name, 0));
    build_model (name, s);
    % Mixed-rate blocks without Rate Transitions need single-tasking; keep
    % the defaults on record.
    try
      r.multitasking = get_param (name, 'EnableMultiTasking');
      set_param (name, 'EnableMultiTasking', 'off');
    catch
    end
    try
      r.single_task_transitions = get_param (name, 'SingleTaskRateTransMsg');
      set_param (name, 'SingleTaskRateTransMsg', 'none');
    catch
    end
    set_param (name, 'SaveFormat', 'Array', 'SaveOutput', 'on', 'OutputSaveName', 'yout', ...
               'SaveTime', 'on', 'TimeSaveName', 'tout', 'SaveState', 'off', 'LimitDataPoints', 'off', ...
               'SignalLogging', 'off', 'ReturnWorkspaceOutputs', 'on', ...
               'StartTime', num (s.start_time), 'StopTime', num (s.stop_time), ...
               'SolverType', 'Fixed-step', 'Solver', s.solver, 'FixedStep', num (s.fixed_step));
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
  if numel (value) == 1
    text = num2str (value, 17);
  else
    text = mat2str (value, 17);
  end
end

function build_model (m, s)
  p = s.parameters;
  switch s.model
    case 'gating'
      add_block ('simulink/Sources/Digital Clock', [m '/Data'], 'SampleTime', num (p.data_sample));
      add_workspace (m, 'Enable', p.enable, p.enable_sample);
      sub = enabled_child (m, p.states, 9);
      add_block ('simulink/Discrete/Unit Delay', [sub '/Fast'], 'InitialCondition', num (p.fast_initial), ...
                 'SampleTime', num (p.fast));
      add_block ('simulink/Discrete/Unit Delay', [sub '/Slow'], 'InitialCondition', num (p.slow_initial), ...
                 'SampleTime', num (p.slow));
      add_block ('simulink/Math Operations/Sum', [sub '/FastPlusSlow'], 'Inputs', '++');
      add_block ('simulink/Math Operations/Gain', [sub '/TwiceSlow'], 'Gain', '2');
      add_block ('simulink/Math Operations/Gain', [sub '/ThriceData'], 'Gain', '3');
      add_block ('simulink/Math Operations/Sum', [sub '/DataPlusSlow'], 'Inputs', '++');
      add_block ('simulink/Sources/Constant', [sub '/Seven'], 'Value', num (p.constant), ...
                 'SampleTime', p.constant_sample);
      add_block ('simulink/Discrete/Discrete-Time Integrator', [sub '/Euler'], ...
                 'IntegratorMethod', 'Integration: Forward Euler', 'InitialCondition', num (p.euler_initial), ...
                 'SampleTime', '-1');
      add_transition (sub, 'DataToSlow', 'hold', p.transition_period, p.transition_initial);
      add_line (sub, 'In1/1', 'Fast/1'); add_line (sub, 'In1/1', 'Slow/1');
      add_line (sub, 'Fast/1', 'FastPlusSlow/1'); add_line (sub, 'Slow/1', 'FastPlusSlow/2');
      add_line (sub, 'FastPlusSlow/1', 'Out1/1');
      add_line (sub, 'Slow/1', 'TwiceSlow/1'); add_line (sub, 'TwiceSlow/1', 'Out2/1');
      add_line (sub, 'In1/1', 'ThriceData/1'); add_line (sub, 'ThriceData/1', 'Out3/1');
      add_line (sub, 'In1/1', 'DataPlusSlow/1'); add_line (sub, 'Slow/1', 'DataPlusSlow/2');
      add_line (sub, 'DataPlusSlow/1', 'Out4/1');
      add_line (sub, 'Seven/1', 'Out5/1');
      add_line (sub, 'Slow/1', 'Out6/1');
      add_line (sub, 'In1/1', 'Euler/1'); add_line (sub, 'Euler/1', 'Out7/1');
      add_line (sub, 'In1/1', 'DataToSlow/1'); add_line (sub, 'DataToSlow/1', 'Out8/1');
      add_line (sub, 'Fast/1', 'Out9/1');
      for k = 1:9
        set_param (sprintf ('%s/Out%d', sub, k), 'InitialOutput', num (p.initial_output), ...
                   'OutputWhenDisabled', p.outputs{k});
      end
      add_line (m, 'Data/1', 'Child/1'); add_line (m, 'Enable/1', 'Child/Enable');
      for k = 1:9, add_outport (m, k, sprintf ('Child/%d', k)); end
    case 'gating_continuous'
      add_block ('simulink/Sources/Constant', [m '/Slope'], 'Value', num (p.slope));
      add_workspace (m, 'Enable', p.enable, p.enable_sample);
      sub = enabled_child (m, p.states, 3);
      add_block ('simulink/Continuous/Integrator', [sub '/State'], 'InitialCondition', num (p.integrator_initial));
      add_block ('simulink/Discrete/Unit Delay', [sub '/Slow'], 'InitialCondition', num (p.slow_initial), ...
                 'SampleTime', num (p.slow));
      add_block ('simulink/Math Operations/Sum', [sub '/StatePlusSlow'], 'Inputs', '++');
      add_line (sub, 'In1/1', 'State/1'); add_line (sub, 'State/1', 'Out1/1');
      add_line (sub, 'State/1', 'Slow/1'); add_line (sub, 'Slow/1', 'Out2/1');
      add_line (sub, 'State/1', 'StatePlusSlow/1'); add_line (sub, 'Slow/1', 'StatePlusSlow/2');
      add_line (sub, 'StatePlusSlow/1', 'Out3/1');
      for k = 1:3
        set_param (sprintf ('%s/Out%d', sub, k), 'InitialOutput', num (p.initial_output), ...
                   'OutputWhenDisabled', 'held');
      end
      add_line (m, 'Slope/1', 'Child/1'); add_line (m, 'Enable/1', 'Child/Enable');
      for k = 1:3, add_outport (m, k, sprintf ('Child/%d', k)); end
    case 'vector_clock'
      add_block ('simulink/Sources/Digital Clock', [m '/Data'], 'SampleTime', num (p.data_sample));
      add_block ('simulink/Math Operations/Gain', [m '/Spread'], 'Gain', num (p.gain));
      add_workspace (m, 'Enable', p.enable, p.enable_sample);
      sub = enabled_child (m, 'held', 2);
      add_block ('simulink/Discrete/Unit Delay', [sub '/Slow'], 'InitialCondition', num (p.delay_initial), ...
                 'SampleTime', num (p.slow));
      add_line (sub, 'In1/1', 'Slow/1'); add_line (sub, 'Slow/1', 'Out1/1');
      add_line (sub, 'In1/1', 'Out2/1');
      for k = 1:2
        set_param (sprintf ('%s/Out%d', sub, k), 'InitialOutput', num (p.initial_outputs{k}), ...
                   'OutputWhenDisabled', p.outputs{k});
      end
      add_line (m, 'Data/1', 'Spread/1'); add_line (m, 'Spread/1', 'Child/1');
      add_line (m, 'Enable/1', 'Child/Enable');
      add_outport (m, 1, 'Child/1'); add_outport (m, 2, 'Child/2');
    case 'triggered_ports'
      add_block ('simulink/Sources/Digital Clock', [m '/Data'], 'SampleTime', num (p.data_sample));
      add_workspace (m, 'Trigger', p.trigger, p.trigger_sample);
      sub = [m '/Child'];
      add_block ('simulink/Ports & Subsystems/Triggered Subsystem', sub);
      set_param ([sub '/Trigger'], 'TriggerType', p.trigger_type, 'InitialTriggerSignalState', p.initial_trigger);
      add_block ('simulink/Math Operations/Gain', [sub '/Gain'], 'Gain', num (p.gain));
      add_block ('simulink/Sinks/Out1', [sub '/Out2']);
      add_line (sub, 'In1/1', 'Gain/1'); add_line (sub, 'Gain/1', 'Out2/1');
      for k = 1:2
        set_param (sprintf ('%s/Out%d', sub, k), 'InitialOutput', num (p.initial_outputs(k)));
        try
          set_param (sprintf ('%s/Out%d', sub, k), 'OutputWhenDisabled', p.outputs{k});
        catch
          % Recorded separately by the API probes.
        end
      end
      add_line (m, 'Data/1', 'Child/1'); add_line (m, 'Trigger/1', 'Child/Trigger');
      add_outport (m, 1, 'Child/1'); add_outport (m, 2, 'Child/2');
    case 'combined_ports'
      add_block ('simulink/Sources/Digital Clock', [m '/Data'], 'SampleTime', num (p.data_sample));
      add_workspace (m, 'Enable', p.enable, p.sample);
      add_workspace (m, 'Trigger', p.trigger, p.sample);
      sub = [m '/Child'];
      add_block ('simulink/Ports & Subsystems/Enabled and Triggered Subsystem', sub);
      set_param ([sub '/Enable'], 'StatesWhenEnabling', p.states);
      set_param ([sub '/Trigger'], 'TriggerType', p.trigger_type, 'InitialTriggerSignalState', p.initial_trigger);
      add_block ('simulink/Math Operations/Gain', [sub '/Gain'], 'Gain', num (p.gain));
      add_block ('simulink/Sinks/Out1', [sub '/Out2']);
      add_line (sub, 'In1/1', 'Gain/1'); add_line (sub, 'Gain/1', 'Out2/1');
      for k = 1:2
        set_param (sprintf ('%s/Out%d', sub, k), 'InitialOutput', num (p.initial_outputs(k)), ...
                   'OutputWhenDisabled', p.outputs{k});
      end
      add_line (m, 'Data/1', 'Child/1'); add_line (m, 'Enable/1', 'Child/Enable');
      add_line (m, 'Trigger/1', 'Child/Trigger');
      add_outport (m, 1, 'Child/1'); add_outport (m, 2, 'Child/2');
    otherwise
      error ('reference_ob_conditional_outputs: unknown model %s', s.model);
  end
end

function sub = enabled_child (m, states, count)
  % Enabled Subsystem 'Child' with In1 and Out1..Out<count>, unconnected.
  sub = [m '/Child'];
  add_block ('simulink/Ports & Subsystems/Enabled Subsystem', sub);
  set_param ([sub '/Enable'], 'StatesWhenEnabling', states);
  delete_line (sub, 'In1/1', 'Out1/1');
  for k = 2:count, add_block ('simulink/Sinks/Out1', sprintf ('%s/Out%d', sub, k)); end
end

function add_transition (parent, name, transfer, period, initial)
  % 'hold' turns data integrity and deterministic transfer off.
  block = [parent '/' name];
  add_block ('simulink/Signal Attributes/Rate Transition', block, ...
             'OutPortSampleTime', num (period), 'InitialCondition', num (initial));
  if strcmp (transfer, 'hold')
    set_param (block, 'Integrity', 'off', 'Deterministic', 'off');
  end
end

function add_workspace (m, name, data, sample)
  % Piecewise-constant source held after its last time.  R2026b rejects
  % Interpolate off without OutputAfterFinalValue 'Holding final value'.
  add_block ('simulink/Sources/From Workspace', [m '/' name], ...
             'VariableName', mat2str ([data.times(:) data.values(:)], 17), 'Interpolate', 'off', ...
             'OutputAfterFinalValue', 'Holding final value', 'SampleTime', num (sample));
end

function add_outport (m, port, source)
  name = sprintf ('Y%d', port);
  add_block ('simulink/Sinks/Out1', [m '/' name]);
  if str2double (get_param ([m '/' name], 'Port')) ~= port
    error ('reference_ob_conditional_outputs: outport %s is not port %d', name, port);
  end
  add_line (m, source, [name '/1']);
end

% --- parameter probes -------------------------------------------------------

function api = api_probes ()
  % Each probe records ok, the error message and the value read back.
  name = 'ob_ref_conditional_api';
  if bdIsLoaded (name), close_system (name, 0); end
  new_system (name);
  cleanup = onCleanup (@() close_system (name, 0));
  add_block ('simulink/Ports & Subsystems/Enabled Subsystem', [name '/E']);
  add_block ('simulink/Ports & Subsystems/Triggered Subsystem', [name '/T']);
  add_block ('simulink/Ports & Subsystems/Enabled and Triggered Subsystem', [name '/ET']);
  add_block ('simulink/Sinks/Out1', [name '/Root']);
  out = [name '/E/Out1'];
  api = struct ();
  api.outport_default_output = read_probe (out, 'OutputWhenDisabled');
  api.outport_default_initial = read_probe (out, 'InitialOutput');
  api.enable_default_states = read_probe ([name '/E/Enable'], 'StatesWhenEnabling');
  api.outport_set_reset = set_probe (out, 'OutputWhenDisabled', 'reset');
  api.outport_set_capital_reset = set_probe (out, 'OutputWhenDisabled', 'Reset');
  api.outport_set_capital_held = set_probe (out, 'OutputWhenDisabled', 'HELD');
  api.outport_set_bogus = set_probe (out, 'OutputWhenDisabled', 'bogus');
  api.outport_set_initial_matrix = set_probe (out, 'InitialOutput', '[1 2;3 4]');
  api.outport_set_initial_undefined = set_probe (out, 'InitialOutput', 'ob_undefined_variable_xyz');
  api.outport_set_initial_numeric = set_probe (out, 'InitialOutput', 3);
  api.outport_set_initial_empty = set_probe (out, 'InitialOutput', '[]');
  api.root_set_reset = set_probe ([name '/Root'], 'OutputWhenDisabled', 'reset');
  api.triggered_set_reset = set_probe ([name '/T/Out1'], 'OutputWhenDisabled', 'reset');
  api.combined_set_reset = set_probe ([name '/ET/Out1'], 'OutputWhenDisabled', 'reset');
  api.enable_set_reset = set_probe ([name '/E/Enable'], 'StatesWhenEnabling', 'reset');
  api.enable_set_capital_reset = set_probe ([name '/E/Enable'], 'StatesWhenEnabling', 'Reset');
  api.enable_set_bogus = set_probe ([name '/E/Enable'], 'StatesWhenEnabling', 'bogus');
  api.simulation_mode_default = read_probe (name, 'SimulationMode');
  modes = {'accelerator', 'rapid-accelerator', 'normal', 'Accelerator', 'Rapid Accelerator', ...
           'rapid accelerator', 'external', 'bogus'};
  fields = {'accelerator', 'rapid_accelerator', 'normal', 'capital_accelerator', 'rapid_accelerator_words', ...
            'rapid_accelerator_space', 'external', 'bogus'};
  for k = 1:numel (modes)
    api.(['simulation_mode_' fields{k}]) = set_probe (name, 'SimulationMode', modes{k});
  end
  set_param (name, 'SimulationMode', 'normal');
  api.simulation_mode_enum = struct ('ok', false, 'message', '', 'value', {{}});
  try
    params = get_param (name, 'ObjectParameters');
    api.simulation_mode_enum.value = params.SimulationMode.Enum;
    api.simulation_mode_enum.ok = true;
  catch err
    api.simulation_mode_enum.message = err.message;
  end
  % sim() accepts SimulationMode as a name/value model parameter.
  api.sim_simulation_mode_parameter = struct ('ok', false, 'message', '', 'value', '');
  try
    sim_name = 'ob_ref_conditional_sim';
    if bdIsLoaded (sim_name), close_system (sim_name, 0); end
    new_system (sim_name);
    sim_cleanup = onCleanup (@() close_system (sim_name, 0));
    add_block ('simulink/Sources/Constant', [sim_name '/C']);
    add_block ('simulink/Sinks/Out1', [sim_name '/Y']);
    add_line (sim_name, 'C/1', 'Y/1');
    result = sim (sim_name, 'SimulationMode', 'normal', 'StopTime', '1', 'ReturnWorkspaceOutputs', 'on');
    api.sim_simulation_mode_parameter.ok = true;
    api.sim_simulation_mode_parameter.value = class (result);
  catch err
    api.sim_simulation_mode_parameter.message = err.message;
  end
end

function probe = read_probe (path, parameter)
  probe = struct ('ok', false, 'message', '', 'value', '');
  try
    probe.value = get_param (path, parameter);
    probe.ok = true;
  catch err
    probe.message = err.message;
  end
end

function probe = set_probe (path, parameter, value)
  probe = struct ('ok', false, 'message', '', 'value', '');
  try
    set_param (path, parameter, value);
    probe.ok = true;
    probe.value = get_param (path, parameter);
  catch err
    probe.message = err.message;
  end
end
