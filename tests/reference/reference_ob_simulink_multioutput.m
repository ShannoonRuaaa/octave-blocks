function reference_ob_simulink_multioutput (file)
  % Record live Simulink traces for subsystems and functions with several
  % outputs: a virtual subsystem with three Outports, Enabled and Triggered
  % subsystems with several Outports (per-port OutputWhenDisabled and
  % InitialOutput, vector outputs) and two- and three-output MATLAB code.
  % Run in MATLAB with Simulink:
  %   reference_ob_simulink_multioutput ('simulink-multioutput-reference.json')
  % Every model is built unsaved and closed again.  test_ob_simulink_extended
  % rebuilds each case in Octave Blocks from the recorded parameters.
  %
  % Multiple-output MATLAB code is recorded twice: as a MATLAB System block
  % simulated by interpreted execution (no C compiler involved) and as a
  % MATLAB Function block, which Simulink always compiles; the compiler it
  % used is recorded.  The System object classes are written to a temporary
  % folder that is removed again.
  if exist ('OCTAVE_VERSION', 'builtin')
    error ('reference_ob_simulink_multioutput: run this producer in MATLAB');
  end
  if nargin < 1, file = 'simulink-multioutput-reference.json'; end
  load_system ('simulink');
  details = ver ('simulink');
  record = struct ('producer', 'reference_ob_simulink_multioutput.m', ...
                   'matlab_version', version, ...
                   'simulink_version', [details(1).Version ' ' details(1).Release], ...
                   'note', 'Recorded by the producer in one MATLAB session.');
  record.c_compiler = '';
  try
    compiler = mex.getCompilerConfigurations ('C', 'Selected');
    if ~isempty (compiler), record.c_compiler = compiler(1).Name; end
  catch
  end
  folder = tempname;
  mkdir (folder);
  write_system_objects (folder);
  addpath (folder);
  restore = onCleanup (@() cleanup_folder (folder));
  record.cases = struct ();
  scenarios = scenario_table ();
  for k = 1:numel (scenarios)
    s = scenarios{k};
    record.cases.(s.id) = run_case (s);
    r = record.cases.(s.id);
    fprintf ('%-34s ok=%d n=%d %.2fs %s\n', s.id, r.ok, numel (r.t), r.seconds, r.error);
  end
  fid = fopen (file, 'w');
  if fid < 0, error ('reference_ob_simulink_multioutput: cannot write %s', file); end
  fprintf (fid, '%s', jsonencode (record));
  fclose (fid);
end

function cleanup_folder (folder)
  rmpath (folder);
  rmdir (folder, 's');
end

function scenarios = scenario_table ()
  % Model names match the builders below and in test_ob_simulink_extended.m.
  scenarios = {};
  scenarios{end+1} = scenario ('virtual_three_ode4', 'virtual_three', ...
      'Virtual subsystem: 2u, sin u and the integral of u; one output branched', ...
      struct ('gain', 2, 'initial_state', 1), fixed ('ode4', 0.1, 2), ...
      {'gain', 'sin', 'integral', 'gain_plus_integral', 'sin_squared'});
  % Enabled subsystem with three Outports.  'policy' is OutputWhenDisabled
  % per port; initial outputs differ per port.
  enable = struct ('times', 0:7, 'values', [0 1 1 0 0 1 1 0]);
  base = struct ('enable', enable, 'delay_initial', 0, 'gain', 10, 'euler_initial', 0, ...
                 'initial_outputs', [-1 5 -3], 'states', 'held');
  for policy = {{'held', 'held', 'held'}, {'reset', 'reset', 'reset'}, {'held', 'reset', 'held'}}
    p = base; p.outputs = policy{1};
    label = 'mixed';
    if all (strcmp (policy{1}, 'held')), label = 'held'; end
    if all (strcmp (policy{1}, 'reset')), label = 'reset'; end
    scenarios{end+1} = scenario (['enabled_three_' label], 'enabled_three', ...
        'Enabled: Unit Delay, Gain and Forward Euler outputs with per-port policies', ...
        p, discrete (1, 7), {'delay', 'gain', 'euler'});
  end
  p = base; p.outputs = {'held', 'reset', 'held'}; p.states = 'reset';
  scenarios{end+1} = scenario ('enabled_three_mixed_statereset', 'enabled_three', ...
      'Enabled: per-port policies with reset states', p, discrete (1, 7), {'delay', 'gain', 'euler'});
  trigger = struct ('times', 0:9, 'values', [-1 0 1 0 0 1 -1 0 0 1]);
  p = struct ('trigger', trigger, 'trigger_type', 'either', 'initial_trigger', 'zero', ...
              'delay_initial', 4, 'gain', 2, 'initial_outputs', [-1 -5 6]);
  scenarios{end+1} = scenario ('triggered_three_either', 'triggered_three', ...
      'Triggered: sample, Unit Delay and Gain outputs with per-port initial outputs', ...
      p, discrete (1, 9), {'sample', 'delay', 'gain'});
  p = struct ('enable', enable, 'gain', [1 2], 'delay_initial', [0 0], ...
              'initial_outputs', {{[7 8], -4}}, 'outputs', {{'held', 'held'}});
  scenarios{end+1} = scenario ('enabled_vector', 'enabled_vector', ...
      'Enabled: vector Unit Delay with vector initial output, vector pass-through with a scalar one', ...
      p, discrete (1, 7), {'delay_1', 'delay_2', 'pass_1', 'pass_2'});
  % u = t*[1 -1 0.5] + [0 1 0.2]: the maximum moves from element 2 to 1 at
  % t = 0.5, where elements 1 and 2 tie (first occurrence wins).
  p = struct ('gain', [1 -1 0.5], 'bias', [0 1 0.2], 'octave_function', 'max');
  for implementation = {'system', 'mfunction'}
    q = p; q.implementation = implementation{1};
    scenarios{end+1} = scenario (['function_max_' implementation{1}], 'function_vector', ...
        '[value, index] = max(u)', q, fixed ('ode4', 0.1, 1), {'value', 'index'});
  end
  % test_ob_multi_function: [u + 1, u.', sum(u)] for u = t*[1 2 3] + [0 -1 4].
  p = struct ('gain', [1 2 3], 'bias', [0 -1 4], 'octave_function', 'test_ob_multi_function');
  for implementation = {'system', 'mfunction'}
    q = p; q.implementation = implementation{1};
    scenarios{end+1} = scenario (['function_three_' implementation{1}], 'function_vector', ...
        '[u + 1, u.'', sum(u(:))]', q, fixed ('ode4', 0.1, 1), ...
        {'same_1', 'same_2', 'same_3', 'transposed_1', 'transposed_2', 'transposed_3', 'total'});
  end
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
  r = rmfield (s, 'id');
  r.ok = false; r.error = ''; r.simulink_solver = ''; r.warnings = {}; r.seconds = NaN;
  r.t = []; r.y = []; r.port_sizes = {};
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
               'StartTime', num (s.start_time), 'StopTime', num (s.stop_time), ...
               'SolverType', 'Fixed-step', 'Solver', s.solver, 'FixedStep', num (s.fixed_step));
    tic; out = sim (name); r.seconds = toc;
    r.t = out.get ('tout');
    % One row per sample; each root output contributes its elements in
    % column-major order (matrix signals are logged rows x cols x samples).
    logged = out.get ('yout');
    r.y = zeros (numel (r.t), 0);
    r.port_sizes = {};
    for k = 1:numel (logged.signals)
      values = logged.signals(k).values;
      r.port_sizes{end+1} = logged.signals(k).dimensions;
      if ndims (values) == 3
        sz = size (values);
        values = reshape (permute (values, [3 1 2]), sz(3), []);
      end
      r.y = [r.y values];
    end
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
    case 'virtual_three'
      add_block ('simulink/Sources/Clock', [m '/Time']);
      sub = [m '/Child'];
      add_block ('simulink/Ports & Subsystems/Subsystem', sub);
      delete_line (sub, 'In1/1', 'Out1/1');
      add_block ('simulink/Math Operations/Gain', [sub '/Gain'], 'Gain', num (p.gain));
      add_block ('simulink/Math Operations/Trigonometric Function', [sub '/Sine'], 'Operator', 'sin');
      add_block ('simulink/Continuous/Integrator', [sub '/State'], 'InitialCondition', num (p.initial_state));
      add_block ('simulink/Sinks/Out1', [sub '/Out2']); add_block ('simulink/Sinks/Out1', [sub '/Out3']);
      add_line (sub, 'In1/1', 'Gain/1'); add_line (sub, 'Gain/1', 'Out1/1');
      add_line (sub, 'In1/1', 'Sine/1'); add_line (sub, 'Sine/1', 'Out2/1');
      add_line (sub, 'In1/1', 'State/1'); add_line (sub, 'State/1', 'Out3/1');
      add_line (m, 'Time/1', 'Child/1');
      add_block ('simulink/Math Operations/Sum', [m '/Sum'], 'Inputs', '++');
      add_block ('simulink/Math Operations/Product', [m '/Square'], 'Inputs', '2');
      add_line (m, 'Child/1', 'Sum/1'); add_line (m, 'Child/3', 'Sum/2');
      add_line (m, 'Child/2', 'Square/1'); add_line (m, 'Child/2', 'Square/2');
      add_outport (m, 1, 'Child/1'); add_outport (m, 2, 'Child/2'); add_outport (m, 3, 'Child/3');
      add_outport (m, 4, 'Sum/1'); add_outport (m, 5, 'Square/1');
    case 'enabled_three'
      add_block ('simulink/Sources/Digital Clock', [m '/Data'], 'SampleTime', num (s.fixed_step));
      add_workspace (m, 'Enable', p.enable, s.fixed_step);
      sub = [m '/Child'];
      add_block ('simulink/Ports & Subsystems/Enabled Subsystem', sub);
      set_param ([sub '/Enable'], 'StatesWhenEnabling', p.states);
      delete_line (sub, 'In1/1', 'Out1/1');
      add_block ('simulink/Discrete/Unit Delay', [sub '/Delay'], 'InitialCondition', num (p.delay_initial), ...
                 'SampleTime', '-1');
      add_block ('simulink/Math Operations/Gain', [sub '/Gain'], 'Gain', num (p.gain));
      add_block ('simulink/Discrete/Discrete-Time Integrator', [sub '/Euler'], ...
                 'IntegratorMethod', 'Integration: Forward Euler', 'InitialCondition', num (p.euler_initial), ...
                 'SampleTime', '-1');
      add_block ('simulink/Sinks/Out1', [sub '/Out2']); add_block ('simulink/Sinks/Out1', [sub '/Out3']);
      add_line (sub, 'In1/1', 'Delay/1'); add_line (sub, 'Delay/1', 'Out1/1');
      add_line (sub, 'In1/1', 'Gain/1'); add_line (sub, 'Gain/1', 'Out2/1');
      add_line (sub, 'In1/1', 'Euler/1'); add_line (sub, 'Euler/1', 'Out3/1');
      for k = 1:3
        set_param (sprintf ('%s/Out%d', sub, k), 'InitialOutput', num (p.initial_outputs(k)), ...
                   'OutputWhenDisabled', p.outputs{k});
      end
      add_line (m, 'Data/1', 'Child/1'); add_line (m, 'Enable/1', 'Child/Enable');
      for k = 1:3, add_outport (m, k, sprintf ('Child/%d', k)); end
    case 'triggered_three'
      add_block ('simulink/Sources/Digital Clock', [m '/Data'], 'SampleTime', num (s.fixed_step));
      add_workspace (m, 'Trigger', p.trigger, s.fixed_step);
      sub = [m '/Child'];
      add_block ('simulink/Ports & Subsystems/Triggered Subsystem', sub);
      set_param ([sub '/Trigger'], 'TriggerType', p.trigger_type, 'InitialTriggerSignalState', p.initial_trigger);
      add_block ('simulink/Discrete/Unit Delay', [sub '/Delay'], 'InitialCondition', num (p.delay_initial), ...
                 'SampleTime', '-1');
      add_block ('simulink/Math Operations/Gain', [sub '/Gain'], 'Gain', num (p.gain));
      add_block ('simulink/Sinks/Out1', [sub '/Out2']); add_block ('simulink/Sinks/Out1', [sub '/Out3']);
      add_line (sub, 'In1/1', 'Delay/1'); add_line (sub, 'Delay/1', 'Out2/1');
      add_line (sub, 'In1/1', 'Gain/1'); add_line (sub, 'Gain/1', 'Out3/1');
      for k = 1:3
        set_param (sprintf ('%s/Out%d', sub, k), 'InitialOutput', num (p.initial_outputs(k)));
      end
      add_line (m, 'Data/1', 'Child/1'); add_line (m, 'Trigger/1', 'Child/Trigger');
      for k = 1:3, add_outport (m, k, sprintf ('Child/%d', k)); end
    case 'enabled_vector'
      add_block ('simulink/Sources/Digital Clock', [m '/Data'], 'SampleTime', num (s.fixed_step));
      add_block ('simulink/Math Operations/Gain', [m '/Spread'], 'Gain', num (p.gain));
      add_workspace (m, 'Enable', p.enable, s.fixed_step);
      sub = [m '/Child'];
      add_block ('simulink/Ports & Subsystems/Enabled Subsystem', sub);
      delete_line (sub, 'In1/1', 'Out1/1');
      add_block ('simulink/Discrete/Unit Delay', [sub '/Delay'], 'InitialCondition', num (p.delay_initial), ...
                 'SampleTime', '-1');
      add_block ('simulink/Sinks/Out1', [sub '/Out2']);
      add_line (sub, 'In1/1', 'Delay/1'); add_line (sub, 'Delay/1', 'Out1/1');
      add_line (sub, 'In1/1', 'Out2/1');
      for k = 1:2
        set_param (sprintf ('%s/Out%d', sub, k), 'InitialOutput', num (p.initial_outputs{k}), ...
                   'OutputWhenDisabled', p.outputs{k});
      end
      add_line (m, 'Data/1', 'Spread/1'); add_line (m, 'Spread/1', 'Child/1');
      add_line (m, 'Enable/1', 'Child/Enable');
      add_outport (m, 1, 'Child/1'); add_outport (m, 2, 'Child/2');
    case 'function_vector'
      add_block ('simulink/Sources/Clock', [m '/Time']);
      add_block ('simulink/Math Operations/Gain', [m '/Spread'], 'Gain', num (p.gain));
      add_block ('simulink/Sources/Constant', [m '/Bias'], 'Value', num (p.bias));
      add_block ('simulink/Math Operations/Sum', [m '/Input'], 'Inputs', '++');
      add_line (m, 'Time/1', 'Spread/1'); add_line (m, 'Spread/1', 'Input/1'); add_line (m, 'Bias/1', 'Input/2');
      block = [m '/Function'];
      if strcmp (p.octave_function, 'max')
        count = 2; class_name = 'ObRefMaxTwo';
        script = sprintf ('function [value, index] = f(u)\n[value, index] = max(u);\n');
      else
        count = 3; class_name = 'ObRefThreeOutputs';
        script = sprintf ('function [same, transposed, total] = f(u)\nsame = u + 1;\ntransposed = u.'';\ntotal = sum(u(:));\n');
      end
      if strcmp (p.implementation, 'system')
        add_block ('simulink/User-Defined Functions/MATLAB System', block);
        set_param (block, 'System', class_name);
        set_param (block, 'SimulateUsing', 'Interpreted execution');
      else
        add_block ('simulink/User-Defined Functions/MATLAB Function', block);
        config = get_param (block, 'MATLABFunctionConfiguration');
        config.FunctionScript = script;
      end
      add_line (m, 'Input/1', 'Function/1');
      for k = 1:count, add_outport (m, k, sprintf ('Function/%d', k)); end
    otherwise
      error ('reference_ob_simulink_multioutput: unknown model %s', s.model);
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
    error ('reference_ob_simulink_multioutput: outport %s is not port %d', name, port);
  end
  add_line (m, source, [name '/1']);
end

function write_system_objects (folder)
  % System objects for interpreted MATLAB System blocks.
  write_lines (fullfile (folder, 'ObRefMaxTwo.m'), { ...
    'classdef ObRefMaxTwo < matlab.System', ...
    '  % [value, index] = max(u), simulated by interpreted execution.', ...
    '  methods (Access = protected)', ...
    '    function [value, index] = stepImpl (~, u)', ...
    '      [value, index] = max (u);', ...
    '    end', ...
    '    function n = getNumOutputsImpl (~)', ...
    '      n = 2;', ...
    '    end', ...
    '    function [a, b] = getOutputSizeImpl (~)', ...
    '      a = [1 1]; b = [1 1];', ...
    '    end', ...
    '    function [a, b] = getOutputDataTypeImpl (~)', ...
    '      a = ''double''; b = ''double'';', ...
    '    end', ...
    '    function [a, b] = isOutputComplexImpl (~)', ...
    '      a = false; b = false;', ...
    '    end', ...
    '    function [a, b] = isOutputFixedSizeImpl (~)', ...
    '      a = true; b = true;', ...
    '    end', ...
    '  end', ...
    'end'});
  write_lines (fullfile (folder, 'ObRefThreeOutputs.m'), { ...
    'classdef ObRefThreeOutputs < matlab.System', ...
    '  % [u + 1, u.'', sum(u(:))], simulated by interpreted execution.', ...
    '  methods (Access = protected)', ...
    '    function [same, transposed, total] = stepImpl (~, u)', ...
    '      same = u + 1;', ...
    '      transposed = u.'';', ...
    '      total = sum (u(:));', ...
    '    end', ...
    '    function n = getNumOutputsImpl (~)', ...
    '      n = 3;', ...
    '    end', ...
    '    function [a, b, c] = getOutputSizeImpl (obj)', ...
    '      a = propagatedInputSize (obj, 1); b = fliplr (a); c = [1 1];', ...
    '    end', ...
    '    function [a, b, c] = getOutputDataTypeImpl (~)', ...
    '      a = ''double''; b = ''double''; c = ''double'';', ...
    '    end', ...
    '    function [a, b, c] = isOutputComplexImpl (~)', ...
    '      a = false; b = false; c = false;', ...
    '    end', ...
    '    function [a, b, c] = isOutputFixedSizeImpl (~)', ...
    '      a = true; b = true; c = true;', ...
    '    end', ...
    '  end', ...
    'end'});
end

function write_lines (file, lines)
  fid = fopen (file, 'w');
  if fid < 0, error ('reference_ob_simulink_multioutput: cannot write %s', file); end
  fprintf (fid, '%s\n', lines{:});
  fclose (fid);
end
