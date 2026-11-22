function reference_ob_simulink_benchmarks (file, runs)
  % Record Simulink wall times and outputs for the nine shared engine
  % benchmark cases of benchmarks/ob_benchmark_models.m, built as equivalent
  % Simulink models with the same solvers, steps, tolerances and output
  % times.  Run in MATLAB with Simulink:
  %   reference_ob_simulink_benchmarks ('simulink-benchmark-reference.json')
  % Each case is simulated once to warm up (its time is kept as 'first'),
  % then 'runs' times (default 7) for the median normal-mode wall time.
  % Fast Restart is then turned on, the model warmed up again, and timed
  % 'runs' more times.  Times cover sim() only (no MATLAB startup, no model
  % construction).  The outputs let test_ob_simulink_benchmarks check that
  % Octave Blocks does equivalent work.  Every model is built unsaved and
  % closed again.
  if exist ('OCTAVE_VERSION', 'builtin')
    error ('reference_ob_simulink_benchmarks: run this producer in MATLAB');
  end
  if nargin < 1, file = 'simulink-benchmark-reference.json'; end
  if nargin < 2, runs = 7; end
  load_system ('simulink');
  details = ver ('simulink');
  record = struct ('producer', 'reference_ob_simulink_benchmarks.m', ...
                   'matlab_version', version, ...
                   'simulink_version', [details(1).Version ' ' details(1).Release], ...
                   'note', ['Recorded by the producer in one MATLAB session; times are sim() ' ...
                            'wall-clock seconds in Normal mode.'], ...
                   'computer', computer, 'cores', feature ('numcores'), 'runs', runs);
  record.cases = struct ();
  scenarios = scenario_table ();
  for k = 1:numel (scenarios)
    s = scenarios{k};
    record.cases.(s.id) = run_case (s, runs);
    r = record.cases.(s.id);
    fprintf ('%-18s ok=%d n=%d first %.3fs median %.4fs fast restart %.4fs %s\n', s.id, r.ok, ...
             numel (r.t), r.first_seconds, r.median_seconds, r.fast_restart_median_seconds, r.error);
  end
  fid = fopen (file, 'w');
  if fid < 0, error ('reference_ob_simulink_benchmarks: cannot write %s', file); end
  fprintf (fid, '%s', jsonencode (record));
  fclose (fid);
end

function scenarios = scenario_table ()
  % Same names, settings and output times as ob_benchmark_models.  An RK4
  % case takes one ode4 step per output interval, as Octave Blocks does.
  scenarios = {};
  scenarios{end+1} = scenario ('oscillator_rk4', 'oscillator', fixed (0.01, 20));
  scenarios{end+1} = scenario ('oscillator_ode45', 'oscillator', variable (0:0.1:20, 1e-8, 1e-10, 'off'));
  scenarios{end+1} = scenario ('dde_rk4', 'dde', fixed (0.01, 6));
  scenarios{end+1} = scenario ('dde_ode45', 'dde', variable (0:0.1:6, 1e-10, 1e-12, 'off'));
  scenarios{end+1} = scenario ('mackey_rk4', 'mackey', fixed (0.1, 300));
  scenarios{end+1} = scenario ('mackey_ode45', 'mackey', variable (0:1:300, 1e-6, 1e-8, 'off'));
  scenarios{end+1} = scenario ('control_zc_ode45', 'control', variable (0:0.01:10, 1e-6, 1e-9, 'on'));
  scenarios{end+1} = scenario ('conditional_rk4', 'conditional', fixed (0.01, 10));
  scenarios{end+1} = scenario ('linear10_rk4', 'linear10', fixed (0.01, 10));
end

function s = scenario (id, model, config)
  s = config; s.id = id; s.model = model;
end

function c = fixed (h, stop)
  c = struct ('solver', 'ode4', 'fixed_step', h, 'reltol', [], 'abstol', [], 'zero_crossings', 'off', ...
              'start_time', 0, 'stop_time', stop, 'output_times', []);
end

function c = variable (times, reltol, abstol, zero_crossings)
  % Octave Blocks' default maxstep is Inf, Simulink's 'auto' is span/50; the
  % Simulink default is kept (it bounds steps more tightly, never less).
  c = struct ('solver', 'ode45', 'fixed_step', [], 'reltol', reltol, 'abstol', abstol, ...
              'zero_crossings', zero_crossings, 'start_time', times(1), 'stop_time', times(end), ...
              'output_times', times);
end

function r = run_case (s, runs)
  r = rmfield (s, 'id');
  r.ok = false; r.error = ''; r.simulink_solver = ''; r.warnings = {};
  r.first_seconds = NaN; r.seconds = []; r.median_seconds = NaN;
  r.fast_restart_first_seconds = NaN; r.fast_restart_seconds = []; r.fast_restart_median_seconds = NaN;
  r.t = []; r.y = [];
  name = ['ob_bench_' s.id];
  try
    if bdIsLoaded (name), close_system (name, 0); end
    new_system (name);
    cleanup = onCleanup (@() close_system (name, 0));
    build_model (name, s);
    set_param (name, 'SaveFormat', 'Array', 'SaveOutput', 'on', 'OutputSaveName', 'yout', ...
               'SaveTime', 'on', 'TimeSaveName', 'tout', 'SaveState', 'off', 'LimitDataPoints', 'off', ...
               'SignalLogging', 'off', 'ReturnWorkspaceOutputs', 'on', ...
               'StartTime', num (s.start_time), 'StopTime', num (s.stop_time));
    if strcmp (s.solver, 'ode4')
      set_param (name, 'SolverType', 'Fixed-step', 'Solver', 'ode4', 'FixedStep', num (s.fixed_step));
    else
      set_param (name, 'SolverType', 'Variable-step', 'Solver', 'ode45', ...
                 'RelTol', num (s.reltol), 'AbsTol', num (s.abstol), 'MaxStep', 'auto', ...
                 'OutputOption', 'SpecifiedOutputTimes', 'OutputTimes', mat2str (s.output_times, 17));
      if strcmp (s.zero_crossings, 'on')
        set_param (name, 'ZeroCrossControl', 'UseLocalSettings');
      else
        set_param (name, 'ZeroCrossControl', 'DisableAll');
      end
    end
    tic; out = sim (name); r.first_seconds = toc;
    r.seconds = zeros (1, runs);
    for k = 1:runs
      tic; out = sim (name); r.seconds(k) = toc;
    end
    r.median_seconds = median (r.seconds);
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
    try
      set_param (name, 'FastRestart', 'on');
      tic; restarted = sim (name); r.fast_restart_first_seconds = toc;
      r.fast_restart_seconds = zeros (1, runs);
      for k = 1:runs
        tic; restarted = sim (name); r.fast_restart_seconds(k) = toc;
      end
      r.fast_restart_median_seconds = median (r.fast_restart_seconds);
      r.fast_restart_max_difference = max (abs (restarted.get ('yout') - r.y), [], 'all');
      set_param (name, 'FastRestart', 'off');
    catch err
      r.error = ['Fast Restart: ' err.message];
    end
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
  switch s.model
    case 'oscillator'
      % x' = v, v' = -x, x(0) = 1 (ob_oscillator).
      add_block ('simulink/Continuous/Integrator', [m '/Position'], 'InitialCondition', '1');
      add_block ('simulink/Continuous/Integrator', [m '/Velocity'], 'InitialCondition', '0');
      add_block ('simulink/Math Operations/Gain', [m '/Negate'], 'Gain', '-1');
      add_line (m, 'Velocity/1', 'Position/1'); add_line (m, 'Position/1', 'Negate/1');
      add_line (m, 'Negate/1', 'Velocity/1');
      add_outport (m, 1, 'Position/1');
    case 'dde'
      % x' = -x(t - 1), x = 1 for t <= 0.
      add_block ('simulink/Continuous/Integrator', [m '/x'], 'InitialCondition', '1');
      add_block ('simulink/Continuous/Transport Delay', [m '/Delay'], 'DelayTime', '1', 'InitialOutput', '1');
      add_block ('simulink/Math Operations/Gain', [m '/Gain'], 'Gain', '-1');
      add_line (m, 'x/1', 'Delay/1'); add_line (m, 'Delay/1', 'Gain/1'); add_line (m, 'Gain/1', 'x/1');
      add_outport (m, 1, 'x/1');
    case 'mackey'
      % x' = 0.2 z / (1 + z^10) - 0.1 x, z = x(t - 17), x0 = 0.5.
      add_block ('simulink/Continuous/Integrator', [m '/x'], 'InitialCondition', '0.5');
      add_block ('simulink/Continuous/Transport Delay', [m '/Delay'], 'DelayTime', '17', 'InitialOutput', '0.5');
      add_block ('simulink/User-Defined Functions/Fcn', [m '/Production'], 'Expr', '0.2*u/(1+u^10)');
      add_block ('simulink/Math Operations/Gain', [m '/Decay'], 'Gain', '-0.1');
      add_block ('simulink/Math Operations/Sum', [m '/Sum'], 'Inputs', '++');
      add_line (m, 'x/1', 'Delay/1'); add_line (m, 'Delay/1', 'Production/1');
      add_line (m, 'x/1', 'Decay/1'); add_line (m, 'Production/1', 'Sum/1');
      add_line (m, 'Decay/1', 'Sum/2'); add_line (m, 'Sum/1', 'x/1');
      add_outport (m, 1, 'x/1');
    case 'control'
      % ob_control_example: the Switch passes the clamp while t >= 2.
      add_block ('simulink/Sources/Clock', [m '/Time']);
      add_block ('simulink/Discontinuities/Saturation', [m '/Clamp'], 'LowerLimit', '0', 'UpperLimit', '3');
      add_block ('simulink/Discontinuities/Dead Zone', [m '/Dead zone'], 'LowerValue', '1', 'UpperValue', '2');
      add_block ('simulink/Sources/Constant', [m '/False value'], 'Value', '-1');
      add_block ('simulink/Signal Routing/Switch', [m '/Switch'], 'Criteria', 'u2 >= Threshold', 'Threshold', '2');
      add_line (m, 'Time/1', 'Clamp/1'); add_line (m, 'Time/1', 'Dead zone/1');
      add_line (m, 'Clamp/1', 'Switch/1'); add_line (m, 'Time/1', 'Switch/2');
      add_line (m, 'False value/1', 'Switch/3');
      add_outport (m, 1, 'Switch/1'); add_outport (m, 2, 'Dead zone/1');
    case 'conditional'
      % ob_conditional_example on a 0.01 s clock: Enabled Unit Delay of the
      % time, initial output -1 (held), enable held after its last sample.
      add_block ('simulink/Sources/Clock', [m '/Time']);
      add_block ('simulink/Sources/From Workspace', [m '/Enable'], ...
                 'VariableName', mat2str ([(0:6)' [0;1;1;0;0;1;1]]), 'Interpolate', 'off', ...
                 'OutputAfterFinalValue', 'Holding final value', 'SampleTime', num (s.fixed_step));
      sub = [m '/Child'];
      add_block ('simulink/Ports & Subsystems/Enabled Subsystem', sub);
      delete_line (sub, 'In1/1', 'Out1/1');
      add_block ('simulink/Discrete/Unit Delay', [sub '/Delay'], 'InitialCondition', '0', ...
                 'SampleTime', num (s.fixed_step));
      add_line (sub, 'In1/1', 'Delay/1'); add_line (sub, 'Delay/1', 'Out1/1');
      set_param ([sub '/Out1'], 'InitialOutput', '-1', 'OutputWhenDisabled', 'held');
      add_line (m, 'Time/1', 'Child/1'); add_line (m, 'Enable/1', 'Child/Enable');
      add_outport (m, 1, 'Child/1');
    case 'linear10'
      % Step at t = 1 into x' = A x + B u, y = C x (n = 10).
      n = 10;
      A = -eye (n) + diag (0.5 * ones (n-1, 1), 1);
      add_block ('simulink/Sources/Step', [m '/Step'], 'Time', '1', 'Before', '0', 'After', '1', 'SampleTime', '0');
      add_block ('simulink/Continuous/State-Space', [m '/Plant'], 'A', mat2str (A), 'B', mat2str (ones (n, 1)), ...
                 'C', mat2str (ones (1, n)), 'D', '0', 'InitialCondition', mat2str (zeros (n, 1)));
      add_line (m, 'Step/1', 'Plant/1');
      add_outport (m, 1, 'Plant/1');
    otherwise
      error ('reference_ob_simulink_benchmarks: unknown model %s', s.model);
  end
end

function add_outport (m, port, source)
  name = sprintf ('Y%d', port);
  add_block ('simulink/Sinks/Out1', [m '/' name]);
  add_line (m, source, [name '/1']);
end
