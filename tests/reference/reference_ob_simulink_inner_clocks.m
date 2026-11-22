function reference_ob_simulink_inner_clocks (file)
  % Record live Simulink traces for Enabled Subsystems whose bodies hold
  % blocks with their own sample times: Discrete-Time Integrators and Unit
  % Delays with explicit periods and offsets, several rates in one body, Rate
  % Transitions across those rates (deterministic and plain hold), an enable
  % sampled at the inner clock union, and a root Rate Transition feeding a
  % continuous Integrator.  Run in MATLAB with Simulink:
  %   reference_ob_simulink_inner_clocks ('simulink-inner-clocks-reference.json')
  % Every model is built unsaved and closed again.  test_ob_simulink_extended
  % rebuilds each case in Octave Blocks from the recorded parameters.
  if exist ('OCTAVE_VERSION', 'builtin')
    error ('reference_ob_simulink_inner_clocks: run this producer in MATLAB');
  end
  if nargin < 1, file = 'simulink-inner-clocks-reference.json'; end
  load_system ('simulink');
  details = ver ('simulink');
  record = struct ('producer', 'reference_ob_simulink_inner_clocks.m', ...
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
  if fid < 0, error ('reference_ob_simulink_inner_clocks: cannot write %s', file); end
  fprintf (fid, '%s', jsonencode (record));
  fclose (fid);
end

function scenarios = scenario_table ()
  % Model names match the builders below and in test_ob_simulink_extended.m.
  % Sample times are [period offset]; logging is at every 1/16 s base step.
  scenarios = {};
  pulse = struct ('times', [0 0.375 0.875 1.125 1.625], 'values', [0 1 0 1 0]);
  for states = {'held', 'reset'}
    p = struct ('enable', pulse, 'enable_sample', 0.125, 'states', states{1}, ...
                'clocks', [0.125 0; 0.25 0], 'initial_outputs', [0 0]);
    scenarios{end+1} = scenario (['euler_two_rates_' states{1}], 'euler_rates', ...
        'Forward Euler at 0.125 s and 0.25 s in one enabled body (ob_enabled_multirate_example)', ...
        p, discrete (1/16, 2), {'fast', 'slow'});
  end
  p = struct ('enable', pulse, 'enable_sample', 0.125, 'states', 'held', ...
              'clocks', [0.25 0.0625; 0.25 0.125], 'initial_outputs', [0 0]);
  scenarios{end+1} = scenario ('euler_offsets', 'euler_rates', ...
      'Forward Euler at 0.25 s with offsets 0.0625 and 0.125', p, discrete (1/16, 2), {'first', 'second'});
  % The enable is sampled every base step (1/16 s); the body only runs at its
  % 0.125 and 0.25 s hits, so the effective control clock is their union.
  union = struct ('times', [0 0.3 0.8 1.3 1.8], 'values', [0 1 0 1 0]);
  p = struct ('enable', union, 'enable_sample', 1/16, 'states', 'held', ...
              'clocks', [0.125 0; 0.25 0], 'initial_outputs', [0 0]);
  scenarios{end+1} = scenario ('euler_union_control', 'euler_rates', ...
      'Enable changes off the inner grids; inner clocks 0.125 and 0.25', p, discrete (1/16, 2), {'fast', 'slow'});
  for transfer = {'deterministic', 'hold'}
    p = struct ('enable', pulse, 'enable_sample', 0.125, 'states', 'held', 'transfer', transfer{1}, ...
                'fast', 0.125, 'slow', 0.25, 'offset_clock', [0.25 0.0625], ...
                'delay_initials', [-1 -2 -5], 'transition_initials', [-3 -4], 'initial_output', -9);
    scenarios{end+1} = scenario (['delays_rate_transition_' transfer{1}], 'delay_rates', ...
        'Unit Delays at 0.125, 0.25 and [0.25 0.0625] s with fast-to-slow and slow-to-fast Rate Transitions', ...
        p, discrete (1/16, 2), {'fast_delay', 'slow_delay', 'fast_to_slow', 'slow_to_fast', 'offset_delay'});
  end
  c = struct ('solver', 'ode45', 'fixed_step', [], 'start_time', 0, 'stop_time', 2, ...
              'reltol', 1e-10, 'abstol', 1e-12, 'output_times', 0:0.05:2);
  for transfer = {'deterministic', 'hold'}
    p = struct ('period', 0.25, 'initial', 0, 'transfer', transfer{1});
    scenarios{end+1} = scenario (['root_rate_transition_' transfer{1} '_ode4'], 'root_transition', ...
        'Clock -> Rate Transition (0.25 s) -> Integrator', p, fixed ('ode4', 0.05, 2), {'held', 'integral'});
    scenarios{end+1} = scenario (['root_rate_transition_' transfer{1} '_ode45'], 'root_transition', ...
        'Clock -> Rate Transition (0.25 s) -> Integrator', p, c, {'held', 'integral'});
  end
end

function s = scenario (id, model, description, parameters, config, columns)
  s = config;
  s.id = id; s.model = model; s.description = description;
  s.parameters = parameters; s.columns = columns;
end

function c = fixed (solver, h, stop)
  c = struct ('solver', solver, 'fixed_step', h, 'start_time', 0, 'stop_time', stop, ...
              'reltol', [], 'abstol', [], 'output_times', []);
end

function c = discrete (h, stop)
  c = fixed ('FixedStepDiscrete', h, stop);
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
               'StartTime', num (s.start_time), 'StopTime', num (s.stop_time));
    if isempty (s.fixed_step)
      set_param (name, 'SolverType', 'Variable-step', 'Solver', s.solver, ...
                 'RelTol', num (s.reltol), 'AbsTol', num (s.abstol), 'MaxStep', 'auto', ...
                 'OutputOption', 'SpecifiedOutputTimes', 'OutputTimes', mat2str (s.output_times, 17));
    else
      set_param (name, 'SolverType', 'Fixed-step', 'Solver', s.solver, 'FixedStep', num (s.fixed_step));
    end
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
    case 'euler_rates'
      add_block ('simulink/Sources/Constant', [m '/Slope'], 'Value', '1');
      add_workspace (m, 'Enable', p.enable, p.enable_sample);
      sub = [m '/Child'];
      add_block ('simulink/Ports & Subsystems/Enabled Subsystem', sub);
      set_param ([sub '/Enable'], 'StatesWhenEnabling', p.states);
      delete_line (sub, 'In1/1', 'Out1/1');
      add_block ('simulink/Sinks/Out1', [sub '/Out2']);
      for k = 1:2
        block = sprintf ('Euler%d', k);
        add_block ('simulink/Discrete/Discrete-Time Integrator', [sub '/' block], ...
                   'IntegratorMethod', 'Integration: Forward Euler', 'InitialCondition', '0', ...
                   'SampleTime', num (p.clocks(k, :)));
        add_line (sub, 'In1/1', [block '/1']);
        add_line (sub, [block '/1'], sprintf ('Out%d/1', k));
        set_param (sprintf ('%s/Out%d', sub, k), 'InitialOutput', num (p.initial_outputs(k)), ...
                   'OutputWhenDisabled', 'held');
      end
      add_line (m, 'Slope/1', 'Child/1'); add_line (m, 'Enable/1', 'Child/Enable');
      add_outport (m, 1, 'Child/1'); add_outport (m, 2, 'Child/2');
    case 'delay_rates'
      add_block ('simulink/Sources/Clock', [m '/Time']);
      add_workspace (m, 'Enable', p.enable, p.enable_sample);
      sub = [m '/Child'];
      add_block ('simulink/Ports & Subsystems/Enabled Subsystem', sub);
      set_param ([sub '/Enable'], 'StatesWhenEnabling', p.states);
      delete_line (sub, 'In1/1', 'Out1/1');
      for k = 2:5, add_block ('simulink/Sinks/Out1', sprintf ('%s/Out%d', sub, k)); end
      add_block ('simulink/Discrete/Unit Delay', [sub '/Fast'], 'InitialCondition', num (p.delay_initials(1)), ...
                 'SampleTime', num (p.fast));
      add_block ('simulink/Discrete/Unit Delay', [sub '/Slow'], 'InitialCondition', num (p.delay_initials(2)), ...
                 'SampleTime', num (p.slow));
      add_block ('simulink/Discrete/Unit Delay', [sub '/Offset'], 'InitialCondition', num (p.delay_initials(3)), ...
                 'SampleTime', num (p.offset_clock));
      add_transition (sub, 'FastToSlow', p.transfer, p.slow, p.transition_initials(1));
      add_transition (sub, 'SlowToFast', p.transfer, p.fast, p.transition_initials(2));
      add_line (sub, 'In1/1', 'Fast/1'); add_line (sub, 'In1/1', 'Slow/1'); add_line (sub, 'In1/1', 'Offset/1');
      add_line (sub, 'Fast/1', 'FastToSlow/1'); add_line (sub, 'Slow/1', 'SlowToFast/1');
      add_line (sub, 'Fast/1', 'Out1/1'); add_line (sub, 'Slow/1', 'Out2/1');
      add_line (sub, 'FastToSlow/1', 'Out3/1'); add_line (sub, 'SlowToFast/1', 'Out4/1');
      add_line (sub, 'Offset/1', 'Out5/1');
      for k = 1:5
        set_param (sprintf ('%s/Out%d', sub, k), 'InitialOutput', num (p.initial_output), ...
                   'OutputWhenDisabled', 'held');
      end
      add_line (m, 'Time/1', 'Child/1'); add_line (m, 'Enable/1', 'Child/Enable');
      for k = 1:5, add_outport (m, k, sprintf ('Child/%d', k)); end
    case 'root_transition'
      add_block ('simulink/Sources/Clock', [m '/Time']);
      add_transition (m, 'Hold', p.transfer, p.period, p.initial);
      add_block ('simulink/Continuous/Integrator', [m '/State'], 'InitialCondition', '0');
      add_line (m, 'Time/1', 'Hold/1'); add_line (m, 'Hold/1', 'State/1');
      add_outport (m, 1, 'Hold/1'); add_outport (m, 2, 'State/1');
    otherwise
      error ('reference_ob_simulink_inner_clocks: unknown model %s', s.model);
  end
end

function add_transition (parent, name, transfer, period, initial)
  % 'deterministic' keeps the library defaults (data integrity and
  % deterministic transfer); 'hold' turns both off, a plain sample and hold.
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
    error ('reference_ob_simulink_inner_clocks: outport %s is not port %d', name, port);
  end
  add_line (m, source, [name '/1']);
end
