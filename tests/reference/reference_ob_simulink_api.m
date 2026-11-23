function reference_ob_simulink_api (file)
  % Record live Simulink behaviour for the Octave Blocks command API.  Run in
  % MATLAB with Simulink (one session, models are never saved):
  %   reference_ob_simulink_api ('simulink-api-reference.json')
  % The record holds, for every library path the API supports (plus probes
  % of paths Simulink lacks): BlockType, MaskType, Ports, dialog parameter
  % names and default values; the same for built-in/<BlockType> paths;
  % parameter, sim-output and error probes; and the outputs of the
  % test_ob_simulink_api scenarios, including (0.3.0) the new library blocks
  % driven through the API and the SaveFormat 'Dataset' layout, element
  % access, warning and error text.  test_ob_simulink_api_reference compares
  % Octave Blocks with it.  Adapted from the sl_api_parity.m and
  % sl_followup.m parity harnesses (2026-11-21).
  if exist ('OCTAVE_VERSION', 'builtin')
    error ('reference_ob_simulink_api: run this producer in MATLAB with Simulink');
  end
  if nargin < 1, file = 'simulink-api-reference.json'; end
  if exist ('load_system', 'file') == 0
    error ('reference_ob_simulink_api:SimulinkMissing', 'A local Simulink engine is required.');
  end
  bdclose ('all');
  load_system ('simulink');
  details = ver ('simulink');
  record = struct ('producer', 'reference_ob_simulink_api.m', 'matlab_version', version, ...
                   'simulink_version', [details(1).Version ' ' details(1).Release], ...
                   'note', 'Recorded by the producer in one MATLAB session.');
  record.blocks = audit_blocks ();
  record.builtin = audit_builtin ();
  record.probes = probes ();
  record.scenarios = scenarios ();
  fid = fopen (file, 'w');
  if fid < 0, error ('reference_ob_simulink_api: cannot write %s', file); end
  fwrite (fid, jsonencode (record, 'ConvertInfAndNaN', true));
  fclose (fid);
  bdclose ('all');
end

%% ------------------------------------------------------------ library audit

function list = block_paths ()
  % {path, inside}: control port blocks are added inside a subsystem.
  list = {'simulink/Sources/Constant', false; 'simulink/Sources/Clock', false; ...
          'simulink/Sources/Step', false; 'simulink/Sources/Sine Wave', false; 'built-in/Sin', false; ...
          'simulink/Sources/Ramp', false; 'simulink/Sources/Ground', false; ...
          'simulink/Math Operations/Gain', false; 'built-in/Gain', false; ...
          'simulink/Math Operations/Sum', false; 'built-in/Sum', false; ...
          'simulink/Math Operations/Add', false; 'simulink/Math Operations/Subtract', false; ...
          'simulink/Math Operations/Product', false; 'simulink/Math Operations/Divide', false; ...
          'simulink/Math Operations/Abs', false; 'simulink/Math Operations/Sqrt', false; ...
          'simulink/Math Operations/Math Function', false; ...
          'simulink/Math Operations/Trigonometric Function', false; ...
          'simulink/User-Defined Functions/MATLAB Fcn', false; ...
          'simulink/User-Defined Functions/Interpreted MATLAB Function', false; ...
          'simulink/User-Defined Functions/Fcn', false; 'simulink/Discrete/Unit Delay', false; ...
          'simulink/Discrete/Discrete-Time Integrator', false; 'simulink/Continuous/Integrator', false; ...
          'simulink/Continuous/Transport Delay', false; 'simulink/Discontinuities/Saturation', false; ...
          'simulink/Discontinuities/Dead Zone', false; 'simulink/Signal Routing/Switch', false; ...
          'simulink/Signal Attributes/Rate Transition', false; 'simulink/Sinks/Scope', false; ...
          'simulink/Sinks/Display', false; 'simulink/Sinks/Terminator', false; ...
          'simulink/Sinks/To Workspace', false; 'simulink/Sources/In1', false; ...
          'simulink/Ports & Subsystems/In1', false; 'built-in/Inport', false; ...
          'simulink/Sinks/Out1', false; 'built-in/Outport', false; ...
          'simulink/Ports & Subsystems/Subsystem', false; ...
          'simulink/Ports & Subsystems/Enabled Subsystem', false; ...
          'simulink/Ports & Subsystems/Triggered Subsystem', false; ...
          'simulink/Ports & Subsystems/Enabled and Triggered Subsystem', false; ...
          'simulink/Ports & Subsystems/Resettable Subsystem', false; ...
          'simulink/Ports & Subsystems/Enable', true; 'simulink/Ports & Subsystems/Trigger', true; ...
          'simulink/Ports & Subsystems/Reset', true; ...
          'simulink/Ports & Subsystems/Resettable Subsystem/Reset', true; ...
          'simulink/Continuous/Transfer Fcn', false; 'simulink/Continuous/State-Space', false; ...
          'simulink/Continuous/Zero-Pole', false; 'simulink/Discrete/Discrete Transfer Fcn', false; ...
          'simulink/Discrete/Discrete State-Space', false; 'simulink/Continuous/PID Controller', false; ...
          'simulink/Discrete/Discrete PID Controller', false; ...
          'simulink/Lookup Tables/1-D Lookup Table', false; 'simulink/Lookup Tables/Lookup Table', false; ...
          'simulink/Discontinuities/Rate Limiter', false; 'simulink/Discontinuities/Relay', false; ...
          'simulink/Commonly Used Blocks/Constant', false; ... % paths added after the first audit
          'simulink/Commonly Used Blocks/Discrete-Time Integrator', false; ...
          'simulink/Commonly Used Blocks/Gain', false; 'simulink/Commonly Used Blocks/Ground', false; ...
          'simulink/Commonly Used Blocks/In1', false; 'simulink/Commonly Used Blocks/Integrator', false; ...
          'simulink/Commonly Used Blocks/Out1', false; 'simulink/Commonly Used Blocks/Product', false; ...
          'simulink/Commonly Used Blocks/Saturation', false; 'simulink/Commonly Used Blocks/Scope', false; ...
          'simulink/Commonly Used Blocks/Subsystem', false; 'simulink/Commonly Used Blocks/Sum', false; ...
          'simulink/Commonly Used Blocks/Switch', false; 'simulink/Commonly Used Blocks/Terminator', false; ...
          'simulink/Continuous/Integrator Limited', false; 'simulink/Ports & Subsystems/Out1', false; ...
          'built-in/Switch', false; 'built-in/SubSystem', false; 'built-in/EnablePort', true; ...
          'simulink/Discontinuities/Backlash', false; 'simulink/Discontinuities/Quantizer', false; ... % 0.3.0 builders
          'simulink/Math Operations/MinMax', false; 'simulink/Discontinuities/Saturation Dynamic', false; ...
          'simulink/Math Operations/Sign', false; 'simulink/Discontinuities/Dead Zone Dynamic', false; ...
          'simulink/Discontinuities/Coulomb & Viscous Friction', false; ...
          'simulink/Logic and Bit Operations/Relational Operator', false; ...
          'simulink/Commonly Used Blocks/Relational Operator', false; ...
          'simulink/Logic and Bit Operations/Logical Operator', false; ...
          'simulink/Commonly Used Blocks/Logical Operator', false; ...
          'simulink/Signal Routing/Multiport Switch', false; 'simulink/Sources/Pulse Generator', false; ...
          'simulink/Sources/Chirp Signal', false; 'simulink/Signal Routing/Mux', false; ...
          'simulink/Commonly Used Blocks/Mux', false; 'simulink/Signal Routing/Demux', false; ...
          'simulink/Commonly Used Blocks/Demux', false; 'simulink/Continuous/Integrator, Second-Order', false};
end

function A = audit_blocks ()
  list = block_paths ();
  A = {};
  for k = 1:size (list, 1)
    e = audit_entry (list{k, 1}, list{k, 2});
    A{end+1} = e; %#ok<AGROW>
    fprintf ('audit %2d %-60s ok=%d %s\n', k, e.path, e.ok, e.BlockType);
  end
end

function B = audit_builtin ()
  % Same record as audit_blocks, so the BlockType defaults (which can
  % differ from the library blocks') are compared too.
  types = {'Saturate', 'DeadZone', 'UnitDelay', 'DiscreteIntegrator', 'TransportDelay', 'TransferFcn', ...
           'StateSpace', 'ZeroPole', 'DiscreteTransferFcn', 'DiscreteStateSpace', 'Math', 'Trigonometry', ...
           'MATLABFcn', 'ToWorkspace', 'RateTransition', 'Lookup_n-D', 'Lookup', 'RateLimiter', 'SubSystem', ...
           'EnablePort', 'TriggerPort', 'ResetPort', 'Display', 'Terminator', 'Switch', 'Relay', 'Step', ...
           'Integrator', 'Fcn', 'Abs', 'Sqrt', 'Product', 'Constant', 'Clock', 'Scope', ...
           'Sin', 'Ground', 'Gain', 'Sum', 'Inport', 'Outport', 'Ramp', ...
           'Backlash', 'Quantizer', 'MinMax', 'Signum', 'RelationalOperator', 'Logic', ...  % 0.3.0 builders
           'MultiPortSwitch', 'DiscretePulseGenerator', 'Mux', 'Demux', 'SecondOrderIntegrator'};
  B = {};
  for k = 1:numel (types)
    inside = any (strcmp (types{k}, {'EnablePort', 'TriggerPort', 'ResetPort'}));
    e = audit_entry (['built-in/' types{k}], inside);
    B{end+1} = e; %#ok<AGROW>
    fprintf ('built-in %2d %-40s ok=%d %s\n', k, e.path, e.ok, e.BlockType);
  end
end

function e = audit_entry (path, inside)
  % BlockType, MaskType, Ports and every dialog parameter's default value.
  e = struct ('path', path, 'inside', inside, 'ok', false, 'message', '', 'BlockType', '', ...
              'MaskType', '', 'Ports', [], 'dialog_names', {{}}, 'dialog_values', {{}});
  [system, destination] = fresh_system (inside);
  try
    h = add_block (path, destination);
    e.ok = true;
    e.BlockType = get_param (h, 'BlockType'); e.MaskType = get_param (h, 'MaskType');
    e.Ports = get_param (h, 'Ports');
    dp = get_param (h, 'DialogParameters');
    if isstruct (dp)
      names = fieldnames (dp);
      values = cell (1, numel (names));
      for j = 1:numel (names)
        try, values{j} = enc (get_param (h, names{j})); catch, values{j} = '<err>'; end
      end
      e.dialog_names = names(:)'; e.dialog_values = values;
    end
  catch err
    e.message = err.message;
  end
  close_system (system, 0);
end

function [system, destination] = fresh_system (inside)
  system = 'aud';
  if bdIsLoaded (system), close_system (system, 0); end
  new_system (system);
  destination = 'aud/B';
  if inside
    add_block ('simulink/Ports & Subsystems/Subsystem', 'aud/S'); destination = 'aud/S/B';
  end
end

%% ------------------------------------------------------------ probes

function P = probes ()
  P = struct ();
  new_system ('st');
  P.step_initialvalue = attempt (@() add_block ('simulink/Sources/Step', 'st/S1', 'InitialValue', '2', 'FinalValue', '3'));
  add_block ('simulink/Sources/Step', 'st/S2', 'Before', '2', 'After', '3');
  P.step_get_before = get_param ('st/S2', 'Before');
  P.step_get_initialvalue = get_param ('st/S2', 'InitialValue');
  close_system ('st', 0);
  build_switch ();
  P.switch_criteria = get_param ('sw/Sw', 'Criteria');
  set_param ('sw', 'SaveFormat', 'Array');
  out = sim ('sw', 'StopTime', '1', 'Solver', 'ode4', 'FixedStep', '0.5');
  P.switch_y = out.yout(:)';
  h = add_block ('built-in/Switch', 'sw/Sw2');
  P.builtin_switch_criteria = get_param (h, 'Criteria');
  close_system ('sw', 0);
  new_system ('rr');
  P.ratelimiter_sampletime = attempt (@() add_block ('simulink/Discontinuities/Rate Limiter', 'rr/L', 'SampleTime', '0.1'));
  P.relay_sampletime = attempt (@() add_block ('simulink/Discontinuities/Relay', 'rr/R', 'SampleTime', '0.1'));
  P.dpid_inherited = attempt (@() add_block ('simulink/Discrete/Discrete PID Controller', 'rr/P', 'SampleTime', '-1'));
  close_system ('rr', 0);
  variants = {'', '1'};
  names = {'dtf_default', 'dtf_explicit1'};
  for v = 1:2
    new_system ('dtf');
    add_block ('simulink/Sources/Step', 'dtf/Step');
    add_block ('simulink/Discrete/Discrete Transfer Fcn', 'dtf/T');
    if ~isempty (variants{v}), set_param ('dtf/T', 'SampleTime', variants{v}); end
    add_block ('simulink/Sinks/Out1', 'dtf/Out1');
    add_line ('dtf', 'Step/1', 'T/1'); add_line ('dtf', 'T/1', 'Out1/1');
    set_param ('dtf', 'SaveFormat', 'Array');
    out = sim ('dtf', 'StopTime', '3', 'Solver', 'ode4', 'FixedStep', '0.1');
    P.(names{v}) = struct ('t', out.tout(:)', 'y', out.yout(:)');
    close_system ('dtf', 0);
  end
  build_tf ();
  P.sim_saveformat_array = attempt (@() sim ('tf', 'SaveFormat', 'Array'));
  P.legacy_rwo_on_namevalue = attempt (@() legacy_sim ('tf', 'StopTime', '3', 'FixedStep', '0.1'));
  P.legacy_rwo_on_timespan = attempt (@() legacy_sim ('tf', [0 3]));
  set_param ('tf', 'ReturnWorkspaceOutputs', 'off');
  [t, x, y] = sim ('tf', [0 3]);
  P.legacy_rwo_off_timespan = struct ('ok', true, 'message', '', 't_size', size (t), 'x_size', size (x), ...
                                      'y_size', size (y));
  P.legacy_rwo_off_namevalue = attempt (@() legacy_sim ('tf', 'StopTime', '3', 'FixedStep', '0.1'));
  o = sim ('tf');
  P.single_output_rwo_off_class = class (o);
  close_system ('tf', 0);
end

%% ------------------------------------------------------------ scenarios

function C = scenarios ()
  C = struct ();
  new_system ('ops');
  for p = {'StartTime', 'StopTime', 'Solver', 'FixedStep', 'RelTol', 'AbsTol', 'MaxStep', ...
           'ZeroCrossControl', 'Name', 'FileName', 'Type'}
    C.model_defaults.(p{1}) = enc (get_param ('ops', p{1}));
  end
  close_system ('ops', 0);

  build_api ();
  C.model_settings = struct ('ReturnWorkspaceOutputs', get_param ('api', 'ReturnWorkspaceOutputs'), ...
      'SaveFormat', get_param ('api', 'SaveFormat'), 'SaveOutput', get_param ('api', 'SaveOutput'), ...
      'SignalLogging', get_param ('api', 'SignalLogging'), 'OutputOption', get_param ('api', 'OutputOption'), ...
      'Refine', get_param ('api', 'Refine'), 'SolverType', get_param ('api', 'SolverType'));
  out = sim ('api');                                     % verbatim, for who
  who_api = out.who;
  out = sim ('api', 'OutputOption', 'SpecifiedOutputTimes', 'OutputTimes', '[0:0.05:2]');
  si = out.SimulationMetadata.ModelInfo.SolverInfo; fn = fieldnames (si); info = struct ();
  for k = 1:numel (fn), info.(fn{k}) = enc (si.(fn{k})); end
  C.api = struct ('t', out.tout(:)', 'y', row (yout_values (out)), 'solver', si.Solver, ...
                  'solverinfo', info, 'who', {who_api(:)'});
  close_system ('api', 0);

  build_ops ();
  out = sim ('ops', [0 1]);
  sl = out.sumlog;
  ops = struct ('tout_len', numel (out.tout), 'array_yout_size', [], 'array_yout_end', [], ...
                'sumlog_end', reshape (sl.Data(end, :), 1, []), 'ports', get_param ('ops/Sum', 'Ports'), ...
                'blocktype', get_param ('ops/Sum', 'BlockType'), 'inputs', get_param ('ops/Sum', 'Inputs'), ...
                'who', {who_list(out)}, 'solver', out.SimulationMetadata.ModelInfo.SolverInfo.Solver);
  set_param ('ops', 'SaveFormat', 'Array');
  out = sim ('ops', 'StartTime', '0', 'StopTime', '1');
  ops.array_yout_size = size (out.yout); ops.array_yout_end = out.yout(end, :);
  C.ops = ops;
  close_system ('ops', 0);

  build_tf ();
  OT = {'OutputOption', 'SpecifiedOutputTimes', 'OutputTimes', '[0:0.1:3]'};
  run = @() sim ('tf', 'StopTime', '3', 'Solver', 'ode45', 'RelTol', '1e-10', 'AbsTol', '1e-12', 'FixedStep', '0.1', OT{:});
  out = run (); tf = struct ('t', out.tout(:)', 'y1', row (yout_values (out)));
  assignin ('base', 'ob_api_gain', 6); set_param ('tf/Plant', 'Numerator', 'ob_api_gain');
  out = run (); tf.y2 = row (yout_values (out));
  assignin ('base', 'ob_api_gain', 2);
  out = run (); tf.y3 = row (yout_values (out));
  C.tf = tf;
  C.persist = struct ('dirty', get_param ('tf', 'Dirty'), 'close', attempt (@() close_system ('tf')), ...
                      'unique_name', '', 'dup', attempt (@() add_block ('simulink/Math Operations/Gain', 'tf/Plant')));
  h = add_block ('simulink/Math Operations/Gain', 'tf/Plant', 'MakeNameUnique', 'on');
  C.persist.unique_name = get_param (h, 'Name');
  close_system ('tf', 0);
  build_tf ();
  out = sim ('tf', 0:0.25:3);
  C.outtimes = struct ('t', out.tout(:)', 'y', row (yout_values (out)));
  close_system ('tf', 0);

  new_system ('lim');
  add_block ('simulink/Sources/Constant', 'lim/One');
  add_block ('simulink/Continuous/Integrator', 'lim/Int', 'LimitOutput', 'on', ...
             'UpperSaturationLimit', '0.75', 'LowerSaturationLimit', '0');
  add_block ('simulink/Sinks/Out1', 'lim/Out1');
  add_line ('lim', 'One/1', 'Int/1'); add_line ('lim', 'Int/1', 'Out1/1');
  out = sim ('lim', 'StopTime', '2', 'Solver', 'ode4', 'FixedStep', '0.25');
  lim = struct ('t', out.tout(:)', 'y1', row (yout_values (out)), ...
                'solver', out.SimulationMetadata.ModelInfo.SolverInfo.Solver);
  set_param ('lim/Int', 'ExternalReset', 'rising');
  lim.ports_rising = get_param ('lim/Int', 'Ports');
  add_block ('simulink/Sources/Step', 'lim/Reset', 'Time', '1', 'Before', '-1', 'After', '1');
  add_line ('lim', 'Reset/1', 'Int/2');
  out = sim ('lim', 'StopTime', '2', 'Solver', 'ode4', 'FixedStep', '0.25');
  lim.t2 = out.tout(:)'; lim.y2 = row (yout_values (out));
  set_param ('lim/Int', 'ExternalReset', 'none');
  lim.levelhold = attempt (@() set_param ('lim/Int', 'ExternalReset', 'level hold'));
  set_param ('lim/Int', 'ExternalReset', 'level');
  attempt (@() add_line ('lim', 'Reset/1', 'Int/2'));   % the old line may survive unconnected
  out = sim ('lim', 'StopTime', '2', 'Solver', 'ode4', 'FixedStep', '0.25');
  lim.y_level = row (yout_values (out));
  C.lim = lim;
  close_system ('lim', 0);

  new_system ('dly');
  add_block ('simulink/Sources/Clock', 'dly/Clock');
  add_block ('simulink/Continuous/Transport Delay', 'dly/Delay', 'DelayTime', '0.3', 'InitialOutput', '-1');
  add_block ('simulink/Sinks/Out1', 'dly/Out1');
  add_line ('dly', 'Clock/1', 'Delay/1'); add_line ('dly', 'Delay/1', 'Out1/1');
  out = sim ('dly', 'StopTime', '1', 'Solver', 'ode4', 'FixedStep', '0.1');
  C.dly = struct ('t', out.tout(:)', 'y', row (yout_values (out)), ...
                  'solver', out.SimulationMetadata.ModelInfo.SolverInfo.Solver);
  % No continuous states: the reported solver is the discrete one.
  out = sim ('dly', 'StopTime', '1', 'Solver', 'ode45');
  C.dly.solver_ode45 = out.SimulationMetadata.ModelInfo.SolverInfo.Solver;
  close_system ('dly', 0);

  build_cond ();
  out = sim ('cond', 'StopTime', '1.5', 'Solver', 'ode4', 'FixedStep', '0.1');
  cond = struct ('t', out.tout(:)', 'y', row (yout_values (out)), 'find_all', {find_system('cond')'}, ...
                 'find_depth1', {find_system('cond', 'SearchDepth', 1)'}, ...
                 'enable_blocktype', get_param ('cond/Sub/Enable', 'BlockType'), ...
                 'enable_ports', get_param ('cond/Sub/Enable', 'Ports'), ...
                 'sub_ports_enabled', get_param ('cond/Sub', 'Ports'));
  add_block ('simulink/Ports & Subsystems/Trigger', 'cond/Sub/Trigger', 'TriggerType', 'falling');
  add_line ('cond', 'On/1', 'Sub/Trigger');
  cond.sub_ports_enabled_triggered = get_param ('cond/Sub', 'Ports');
  delete_block ('cond/Sub/Enable');
  cond.sub_ports_after_delete = get_param ('cond/Sub', 'Ports');
  out = sim ('cond', 'StopTime', '1.5', 'Solver', 'ode4', 'FixedStep', '0.1');
  cond.y_after_delete = row (yout_values (out));
  C.cond = cond;
  close_system ('cond', 0);

  build_ports ();
  out = sim ('ports', [0 1]);
  y = yout_values (out);
  ports = struct ('y', y(end), 'in2_port_before', get_param ('ports/Sub/In2', 'Port'));
  delete_block ('ports/Sub/In1');
  ports.in2_port_after = get_param ('ports/Sub/In2', 'Port');
  ports.sub_ports_after = get_param ('ports/Sub', 'Ports');
  out = sim ('ports', [0 1]);
  y = yout_values (out); ports.y_after = y(end);
  C.ports = ports;
  close_system ('ports', 0);
  new_system ('ps');
  add_block ('simulink/Ports & Subsystems/Subsystem', 'ps/Sub');
  add_block ('simulink/Sources/In1', 'ps/Sub/In2');
  set_param ('ps/Sub/In2', 'Port', '1');
  C.portswap = struct ('in1_port', get_param ('ps/Sub/In1', 'Port'), 'in2_port', get_param ('ps/Sub/In2', 'Port'));
  close_system ('ps', 0);

  build_pid ();
  out = sim ('pid', 'StopTime', '12', 'Solver', 'ode4', 'FixedStep', '0.02');
  C.pid = struct ('t', out.tout(:)', 'y', row (yout_values (out)));
  close_system ('pid', 0);

  build_mix ();
  out = sim ('mix', 'StopTime', '1', 'Solver', 'ode4', 'FixedStep', '0.1');
  [y, info] = yout_values (out);
  mix = struct ('t', out.tout(:)', 'y1', row (y{1}), 'y2', row (y{2}), 'y3', row (y{3}), ...
                'time_len', info.time_len, 'expr_renamed', '', ...
                'ramp_params', {fieldnames(get_param ('mix/Ramp', 'DialogParameters'))'});
  set_param ('mix/Exp', 'Name', 'Exponential');
  mix.expr_renamed = get_param ('mix/Exponential', 'Expr');
  C.mix = mix;
  close_system ('mix', 0);

  build_mix ();
  E = struct ();
  E.signal_builder = attempt (@() add_block ('simulink/Sources/Signal Builder', 'mix/S'));
  if E.signal_builder.ok, delete_block ('mix/S'); end
  E.sat_gain = attempt (@() set_param ('mix/Sat', 'Gain', '3'));
  solver = get_param ('mix', 'Solver');
  E.solver_ode113 = attempt (@() set_param ('mix', 'Solver', 'ode113'));
  E.solver_after = get_param ('mix', 'Solver');
  set_param ('mix', 'Solver', solver);
  E.sampletime_offset = attempt (@() set_param ('mix/Z', 'SampleTime', '[0.2 0.5]'));
  E.sampletime_after = get_param ('mix/Z', 'SampleTime');
  E.dup_line = attempt (@() add_line ('mix', 'Ramp/1', 'Out1/1'));
  E.sim_missing = attempt (@() sim ('missing'));
  E.load_slx = attempt (@() load_system ('model.slx'));
  E.sum_plus_times = attempt (@() add_block ('simulink/Math Operations/Sum', 'mix/S', 'Inputs', '+*'));
  E.block_S_exists_after = ~isempty (find_system ('mix', 'SearchDepth', 1, 'Name', 'S'));
  if E.block_S_exists_after, delete_block ('mix/S'); end
  E.new_system_duplicate = attempt (@() new_system ('mix'));
  E.delete_line_missing = attempt (@() delete_line ('mix', 'Ramp/1', 'Out2/1'));
  E.get_param_bad = attempt (@() get_param ('mix/Sat', 'NoSuchParam'));
  E.set_param_numeric_stoptime = attempt (@() set_param ('mix', 'StopTime', 2));
  C.errors = E;
  set_param ('mix', 'StopTime', '1', 'Solver', 'ode4');
  out = sim ('mix');
  C.autostep = struct ('t', out.tout(:)', 'step', diff (out.tout(1:2)), 'n', numel (out.tout));
  close_system ('mix', 0);

  new_system ('loop');
  add_block ('simulink/Sources/Step', 'loop/Ref');
  add_block ('simulink/Math Operations/Subtract', 'loop/Err');
  add_block ('simulink/Continuous/PID Controller', 'loop/PID', 'P', '2', 'I', '1');
  add_block ('simulink/Continuous/Transfer Fcn', 'loop/Plant', 'Denominator', '[1 3 2]');
  add_block ('simulink/Sinks/Out1', 'loop/y');
  add_line ('loop', 'Ref/1', 'Err/1'); add_line ('loop', 'Plant/1', 'Err/2');
  add_line ('loop', 'Err/1', 'PID/1'); add_line ('loop', 'PID/1', 'Plant/1');
  add_line ('loop', 'Plant/1', 'y/1');
  out = sim ('loop', 'StopTime', '10', 'RelTol', '1e-10', 'AbsTol', '1e-12', ...
             'OutputOption', 'SpecifiedOutputTimes', 'OutputTimes', '[0:0.2:10]');
  C.loop = struct ('t', out.tout(:)', 'y', row (yout_values (out)), ...
                   'solver', out.SimulationMetadata.ModelInfo.SolverInfo.Solver);
  close_system ('loop', 0);

  new_system ('gv');
  add_block ('simulink/Sources/Constant', 'gv/C', 'Value', '[1 2]');
  add_block ('simulink/Math Operations/Gain', 'gv/K', 'Gain', '[2 3]');
  add_block ('simulink/Sinks/Out1', 'gv/Out1');
  add_line ('gv', 'C/1', 'K/1'); add_line ('gv', 'K/1', 'Out1/1');
  out = sim ('gv', 'StopTime', '1', 'Solver', 'ode4', 'FixedStep', '0.5');
  y = yout_values (out);
  C.gainvec = struct ('multiplication', get_param ('gv/K', 'Multiplication'), 'y', y(end, :));
  close_system ('gv', 0);

  new_system ('re');
  R = struct ();
  R.add_enable_root = attempt (@() add_block ('simulink/Ports & Subsystems/Enable', 're/Enable'));
  add_block ('simulink/Ports & Subsystems/Subsystem', 're/Sub');
  add_block ('simulink/Ports & Subsystems/Enable', 're/Sub/Enable');
  R.add_second_enable = attempt (@() add_block ('simulink/Ports & Subsystems/Enable', 're/Sub/Enable2'));
  R.add_reset_with_enable = attempt (@() add_block ('simulink/Ports & Subsystems/Reset', 're/Sub/Reset'));
  R.addline_reset_missing = attempt (@() add_line ('re', 'Sub/1', 'Sub/Reset'));
  C.rootenable = R;
  close_system ('re', 0);

  new_system ('lut');
  add_block ('simulink/Sources/Clock', 'lut/Clock');
  add_block ('simulink/Math Operations/Gain', 'lut/K', 'Gain', '2');
  add_block ('simulink/Lookup Tables/1-D Lookup Table', 'lut/LUT');
  add_block ('simulink/Sinks/Out1', 'lut/Out1');
  add_line ('lut', 'Clock/1', 'K/1'); add_line ('lut', 'K/1', 'LUT/1'); add_line ('lut', 'LUT/1', 'Out1/1');
  out = sim ('lut', 'StopTime', '5', 'Solver', 'ode4', 'FixedStep', '0.25');
  C.lutdefault = struct ('t', out.tout(:)', 'y', row (yout_values (out)), ...
                         'extrap', get_param ('lut/LUT', 'ExtrapMethod'), 'interp', get_param ('lut/LUT', 'InterpMethod'));
  close_system ('lut', 0);

  new_system ('dti');
  add_block ('simulink/Sources/Constant', 'dti/C');
  add_block ('simulink/Discrete/Discrete-Time Integrator', 'dti/DTI');
  add_block ('simulink/Sinks/Out1', 'dti/Out1');
  add_line ('dti', 'C/1', 'DTI/1'); add_line ('dti', 'DTI/1', 'Out1/1');
  out = sim ('dti', 'StopTime', '3', 'Solver', 'ode4', 'FixedStep', '0.25');
  C.dtidefault = struct ('t', out.tout(:)', 'y', row (yout_values (out)), 'sampletime', get_param ('dti/DTI', 'SampleTime'));
  close_system ('dti', 0);

  new_system ('rl');
  add_block ('simulink/Sources/Step', 'rl/Step');
  add_block ('simulink/Discontinuities/Rate Limiter', 'rl/RL');
  add_block ('simulink/Sinks/Out1', 'rl/Out1');
  add_line ('rl', 'Step/1', 'RL/1'); add_line ('rl', 'RL/1', 'Out1/1');
  out = sim ('rl', 'StopTime', '3', 'Solver', 'ode4', 'FixedStep', '0.05');
  C.ratelimiter = struct ('t', out.tout(:)', 'y', row (yout_values (out)));
  close_system ('rl', 0);

  new_system ('trg');
  add_block ('simulink/Sources/Clock', 'trg/Clock');
  add_block ('simulink/Sources/Sine Wave', 'trg/Sine', 'Frequency', '2*pi', 'Phase', '-0.3');
  add_block ('simulink/Ports & Subsystems/Triggered Subsystem', 'trg/Sub');
  add_block ('simulink/Sinks/Out1', 'trg/Out1');
  add_line ('trg', 'Clock/1', 'Sub/1'); add_line ('trg', 'Sine/1', 'Sub/Trigger'); add_line ('trg', 'Sub/1', 'Out1/1');
  found = find_system ('trg');
  out = sim ('trg', 'StopTime', '3', 'Solver', 'ode4', 'FixedStep', '0.05');
  C.trig = struct ('t', out.tout(:)', 'y', row (yout_values (out)), 'find_all', {found(:)'});
  close_system ('trg', 0);

  new_system ('tw');
  add_block ('simulink/Sources/Clock', 'tw/Clock');
  add_block ('simulink/Sinks/To Workspace', 'tw/Log');
  add_line ('tw', 'Clock/1', 'Log/1');
  tw = struct ('default_saveformat', get_param ('tw/Log', 'SaveFormat'));
  set_param ('tw/Log', 'SaveFormat', 'Structure With Time');
  out = sim ('tw', 'StopTime', '1', 'Solver', 'ode4', 'FixedStep', '0.5');
  tw.fields = fieldnames (out.simout)'; tw.signals_fields = fieldnames (out.simout.signals)';
  tw.values = out.simout.signals.values(:)'; tw.time = out.simout.time(:)';
  tw.blockName = out.simout.blockName; tw.who = who_list (out);
  C.towsformat = tw;
  close_system ('tw', 0);

  new_system ('term');
  add_block ('simulink/Sources/Clock', 'term/Clock');
  add_block ('simulink/Sinks/Terminator', 'term/T');
  add_block ('simulink/Sinks/Display', 'term/D');
  add_block ('simulink/Sinks/Scope', 'term/Sc');
  add_line ('term', 'Clock/1', 'T/1'); add_line ('term', 'Clock/1', 'D/1'); add_line ('term', 'Clock/1', 'Sc/1');
  out = sim ('term', 'StopTime', '1', 'Solver', 'ode4', 'FixedStep', '0.5');
  found = find_system ('term', 'BlockType', 'Terminator');
  C.terminator = struct ('who', {who_list(out)}, 'bt_T', get_param ('term/T', 'BlockType'), ...
                         'bt_D', get_param ('term/D', 'BlockType'), 'find_terminator', {found(:)'});
  close_system ('term', 0);

  % 0.3.0: the new library blocks through the command API, and Dataset
  % logging (yout, signal logging, Scope logging).
  C.newnonlinear = new_nonlinear ();
  C.newrouting = new_routing ();
  C.dataset = dataset_probe ();
  C.followup = followup_probe ();
end

function F = followup_probe ()
  % 0.3.0 review follow-ups: the sample-based Pulse Generator's discrete
  % rate as seen by an inherited Unit Delay (default solver settings, and
  % ode4 at 0.2 s with the Unit Delay at 1 s), a Mux with a count fed a
  % row vector, the sample-based PulseWidth limits, and how set_param
  % stores enumerated values typed in another case.
  F = struct ();
  m = 'prt';
  new_system (m);
  add_block ('built-in/DiscretePulseGenerator', [m '/P']);
  add_block ('simulink/Discrete/Unit Delay', [m '/UD']);
  add_block ('simulink/Sinks/Out1', [m '/y1']); add_block ('simulink/Sinks/Out1', [m '/y2']);
  add_line (m, 'P/1', 'y1/1'); add_line (m, 'P/1', 'UD/1'); add_line (m, 'UD/1', 'y2/1');
  F.ud_sampletime = get_param ([m '/UD'], 'SampleTime');
  set_param (m, 'SaveFormat', 'Array', 'StopTime', '10');
  out = sim (m);
  F.pulse_auto = struct ('t', out.tout(:)', 'y', out.yout);
  set_param ([m '/UD'], 'SampleTime', '1');
  set_param (m, 'StopTime', '4', 'Solver', 'ode4', 'FixedStep', '0.2');
  out = sim (m);
  F.pulse_fixed = struct ('t', out.tout(:)', 'y', out.yout);
  set_param (m, 'StopTime', '4', 'Solver', 'ode4', 'FixedStep', '1');
  for c = {{'equal', '2', '2'}, {'zero', '2', '0'}, {'over', '2', '3'}}
    % set_param itself may refuse the value.
    r = attempt (@() set_param ([m '/P'], 'Period', c{1}{2}, 'PulseWidth', c{1}{3}));
    r.stage = 'set_param'; r.y = [];
    if r.ok
      r = attempt (@() sim (m)); r.stage = 'sim'; r.y = [];
      if r.ok, out = sim (m); r.y = out.yout(:, 1)'; end
    end
    F.(['width_' c{1}{1}]) = r;
    set_param ([m '/P'], 'Period', '2', 'PulseWidth', '1');
  end
  close_system (m, 0);

  m = 'mxr';
  new_system (m);
  add_block ('simulink/Sources/Constant', [m '/A'], 'Value', '[1 2]');
  add_block ('simulink/Sources/Constant', [m '/B'], 'Value', '3');
  add_block ('simulink/Signal Routing/Mux', [m '/M']);
  add_block ('simulink/Sinks/Out1', [m '/y']);
  add_line (m, 'A/1', 'M/1'); add_line (m, 'B/1', 'M/2'); add_line (m, 'M/1', 'y/1');
  set_param (m, 'SaveFormat', 'Array', 'StopTime', '1');
  out = sim (m);
  F.mux_row = struct ('y', out.yout(end, :));
  close_system (m, 0);

  % {library path, parameter, value typed}: get_param afterwards, or the error.
  cases = {'simulink/Math Operations/MinMax', 'Function', 'MAX'; ...
           'simulink/Logic and Bit Operations/Logical Operator', 'Operator', 'nxor'; ...
           'simulink/Logic and Bit Operations/Relational Operator', 'Operator', 'isinf'; ...
           'simulink/Sources/Pulse Generator', 'PulseType', 'time based'; ...
           'simulink/Sources/Pulse Generator', 'TimeSource', 'use simulation time'; ...
           'simulink/Signal Routing/Multiport Switch', 'DataPortOrder', 'zero-based contiguous'; ...
           'simulink/Signal Routing/Multiport Switch', 'DataPortForDefault', 'additional data port'; ...
           'simulink/Signal Routing/Multiport Switch', 'DiagnosticForDefault', 'warning'; ...
           'simulink/Math Operations/Sign', 'ZeroCross', 'OFF'; ...
           'simulink/Signal Routing/Mux', 'DisplayOption', 'NONE'; ...
           'simulink/Continuous/Integrator, Second-Order', 'LimitX', 'Off'; ...
           'simulink/Continuous/Integrator, Second-Order', 'ICSourceX', 'Internal'};
  F.enum = struct ('path', {}, 'param', {}, 'typed', {}, 'ok', {}, 'value', {}, 'message', {});
  m = 'enm';
  new_system (m);
  for k = 1:size (cases, 1)
    block = sprintf ('%s/B%d', m, k);
    add_block (cases{k, 1}, block);
    e = struct ('path', cases{k, 1}, 'param', cases{k, 2}, 'typed', cases{k, 3}, 'ok', true, ...
                'value', '', 'message', '');
    try
      set_param (block, cases{k, 2}, cases{k, 3});
      e.value = get_param (block, cases{k, 2});
    catch err
      e.ok = false; e.message = err.message;
    end
    F.enum(end+1) = e;
  end
  close_system (m, 0);
end

function N = new_nonlinear ()
  % Every 0.3.0 nonlinear library block at its defaults (plus MinMax 'max',
  % Relational '>', Logical NXOR3 and NOT) driven by a Sine; ode4, 0.05 s.
  m = 'nlb';
  new_system (m);
  add_block ('simulink/Sources/Sine Wave', [m '/Sine'], 'Amplitude', '2');
  add_block ('simulink/Sources/Constant', [m '/Half'], 'Value', '0.5');
  add_block ('simulink/Sources/Constant', [m '/Up'], 'Value', '1');
  add_block ('simulink/Sources/Constant', [m '/Lo'], 'Value', '-0.5');
  add_block ('simulink/Discontinuities/Backlash', [m '/Backlash']);
  add_block ('simulink/Discontinuities/Quantizer', [m '/Quantizer']);
  add_block ('simulink/Math Operations/MinMax', [m '/Max'], 'Function', 'max', 'Inputs', '2');
  add_block ('simulink/Math Operations/Sign', [m '/Sign']);
  add_block ('simulink/Discontinuities/Saturation Dynamic', [m '/SatDyn']);
  add_block ('simulink/Discontinuities/Dead Zone Dynamic', [m '/DZDyn']);
  add_block ('simulink/Discontinuities/Coulomb & Viscous Friction', [m '/Friction']);
  add_block ('simulink/Math Operations/MinMax', [m '/MinAll']);
  add_block ('simulink/Logic and Bit Operations/Relational Operator', [m '/Rel'], 'Operator', '>');
  add_block ('simulink/Logic and Bit Operations/Logical Operator', [m '/Logic'], 'Operator', 'NXOR', 'Inputs', '3');
  add_block ('simulink/Commonly Used Blocks/Logical Operator', [m '/Not'], 'Operator', 'NOT');
  outputs = {'Backlash', 'Quantizer', 'Max', 'Sign', 'SatDyn', 'DZDyn', 'Friction', 'MinAll', 'Rel', 'Logic', 'Not'};
  for k = 1:numel (outputs)
    add_block ('simulink/Sinks/Out1', sprintf ('%s/y%d', m, k));
    add_line (m, [outputs{k} '/1'], sprintf ('y%d/1', k));
  end
  lines = {'Sine/1', 'Backlash/1'; 'Sine/1', 'Quantizer/1'; 'Sine/1', 'Max/1'; 'Half/1', 'Max/2'; ...
           'Sine/1', 'Sign/1'; 'Up/1', 'SatDyn/1'; 'Sine/1', 'SatDyn/2'; 'Lo/1', 'SatDyn/3'; ...
           'Up/1', 'DZDyn/1'; 'Sine/1', 'DZDyn/2'; 'Lo/1', 'DZDyn/3'; 'Sine/1', 'Friction/1'; ...
           'Friction/1', 'MinAll/1'; 'Sine/1', 'Rel/1'; 'Half/1', 'Rel/2'; 'Sine/1', 'Logic/1'; ...
           'Quantizer/1', 'Logic/2'; 'Sign/1', 'Logic/3'; 'Rel/1', 'Not/1'};
  for k = 1:size (lines, 1), add_line (m, lines{k, 1}, lines{k, 2}); end
  set_param (m, 'SaveFormat', 'Dataset', 'StopTime', '4', 'Solver', 'ode4', 'FixedStep', '0.05');
  out = sim (m);
  N = struct ('t', out.tout(:)', 'y', {per_element(out.yout)}, 'outputs', {outputs}, ...
              'ports_logic', get_param ([m '/Logic'], 'Ports'), 'ports_not', get_param ([m '/Not'], 'Ports'), ...
              'ports_minall', get_param ([m '/MinAll'], 'Ports'));
  close_system (m, 0);
end

function R = new_routing ()
  % Pulse Generator, Chirp Signal, Mux (count and widths), Demux, Multiport
  % Switch and Integrator, Second-Order; ode4, 0.05 s.
  m = 'rtb';
  new_system (m);
  add_block ('simulink/Sources/Pulse Generator', [m '/Pulse'], 'Amplitude', '2', 'Period', '1', ...
             'PulseWidth', '50', 'PhaseDelay', '0.25');
  add_block ('simulink/Sources/Chirp Signal', [m '/Chirp'], 'f1', '0.1', 'T', '5', 'f2', '1');
  add_block ('simulink/Sources/Sine Wave', [m '/Sine']);
  add_block ('simulink/Sources/Clock', [m '/Clock']);
  add_block ('simulink/Signal Routing/Mux', [m '/Mux']);
  add_block ('simulink/Signal Routing/Demux', [m '/Demux']);
  add_block ('simulink/Commonly Used Blocks/Mux', [m '/Mux3'], 'Inputs', '[2 1]');
  add_block ('simulink/Sources/Step', [m '/Ctl'], 'Time', '1', 'Before', '1', 'After', '3');
  for k = 1:3
    add_block ('simulink/Sources/Constant', sprintf ('%s/D%d', m, k), 'Value', num2str (10 * k));
  end
  add_block ('simulink/Signal Routing/Multiport Switch', [m '/Switch']);
  add_block ('simulink/Sources/Constant', [m '/One'], 'Value', '1');
  add_block ('simulink/Continuous/Integrator, Second-Order', [m '/SOI'], 'ICX', '1');
  % built-in/DiscretePulseGenerator defaults to a sample-based pulse (1 s samples).
  add_block ('built-in/DiscretePulseGenerator', [m '/PulseS']);
  for k = 1:9, add_block ('simulink/Sinks/Out1', sprintf ('%s/y%d', m, k)); end
  lines = {'Pulse/1', 'y1/1'; 'Chirp/1', 'y2/1'; 'Sine/1', 'Mux/1'; 'Clock/1', 'Mux/2'; 'Mux/1', 'Demux/1'; ...
           'Demux/1', 'y3/1'; 'Demux/2', 'y4/1'; 'Mux/1', 'Mux3/1'; 'Pulse/1', 'Mux3/2'; 'Mux3/1', 'y5/1'; ...
           'Ctl/1', 'Switch/1'; 'D1/1', 'Switch/2'; 'D2/1', 'Switch/3'; 'D3/1', 'Switch/4'; 'Switch/1', 'y6/1'; ...
           'One/1', 'SOI/1'; 'SOI/1', 'y7/1'; 'SOI/2', 'y8/1'; 'PulseS/1', 'y9/1'};
  for k = 1:size (lines, 1), add_line (m, lines{k, 1}, lines{k, 2}); end
  set_param (m, 'SaveFormat', 'Dataset', 'StopTime', '3', 'Solver', 'ode4', 'FixedStep', '0.05');
  out = sim (m);
  [y, times] = per_element (out.yout);
  R = struct ('t', out.tout(:)', 'y', {y}, 'times', {times}, ...
              'ports_switch', get_param ([m '/Switch'], 'Ports'), 'ports_soi', get_param ([m '/SOI'], 'Ports'), ...
              'ports_mux3', get_param ([m '/Mux3'], 'Ports'), 'ports_demux', get_param ([m '/Demux'], 'Ports'));
  close_system (m, 0);
end

function D = dataset_probe ()
  % SaveFormat 'Dataset': yout for scalar, vector and matrix root Outports
  % (and one inside a subsystem path), signal logging (logsout) and Scope
  % logging, element access by index and name, duplicates and misses.
  m = 'ds';
  new_system (m);
  add_block ('simulink/Sources/Sine Wave', [m '/Sine']);
  add_block ('simulink/Sources/Constant', [m '/Vec'], 'Value', '[1 2]');
  add_block ('simulink/Sources/Constant', [m '/Mat'], 'Value', '[1 2;3 4]');
  add_block ('simulink/Sources/Constant', [m '/Col'], 'Value', '[5;6]');
  add_block ('simulink/Sinks/Out1', [m '/Out1']);
  add_block ('simulink/Sinks/Out1', [m '/Vout']);
  add_block ('simulink/Sinks/Out1', [m '/Mout']);
  add_block ('simulink/Sinks/Out1', [m '/Cout']);
  add_block ('simulink/Sinks/Scope', [m '/Sc']);
  add_block ('simulink/Ports & Subsystems/Subsystem', [m '/Sub']);
  add_block ('simulink/Sinks/Scope', [m '/Sub/Inner']);
  add_line ([m '/Sub'], 'In1/1', 'Inner/1');
  add_line (m, 'Sine/1', 'Out1/1'); add_line (m, 'Vec/1', 'Vout/1'); add_line (m, 'Mat/1', 'Mout/1');
  add_line (m, 'Col/1', 'Cout/1'); add_line (m, 'Sine/1', 'Sc/1'); add_line (m, 'Vec/1', 'Sub/1');
  set_param (m, 'SaveFormat', 'Dataset', 'StopTime', '1', 'Solver', 'ode4', 'FixedStep', '0.25');
  D = struct ();
  D.model_saveformat = get_param (m, 'SaveFormat');
  D.signallogging = get_param (m, 'SignalLogging');
  D.signalloggingname = get_param (m, 'SignalLoggingName');
  out = sim (m);
  D.plain = struct ('who', {who_list(out)}, 'yout', describe_dataset (out.yout));
  % Access probes on yout.
  yo = out.yout;
  D.access = struct ();
  D.access.getElement_index = probe_value (@() yo.getElement (2));
  D.access.getElement_missing = probe_value (@() yo.getElement ('no_such_signal'));
  D.access.getElement_out_of_range = probe_value (@() yo.getElement (99));
  D.access.getElement_vout = probe_value (@() yo.getElement ('Vout'));
  D.access.get_index_name = probe_value (@() yo.get (1));
  D.access.numElements_dot = probe_value (@() yo.numElements);
  D.access.brace_name = probe_value (@() yo{1});
  % Signal logging on the Sine line (unnamed, then named), the Vec line
  % (named the same, a duplicate) and inside the subsystem.
  ph = get_param ([m '/Sine'], 'PortHandles');
  set_param (ph.Outport(1), 'DataLogging', 'on');
  out = sim (m);
  D.logged_unnamed = struct ('who', {who_list(out)}, 'logsout', describe_dataset (out.logsout));
  set_param (ph.Outport(1), 'Name', 'sig');
  pv = get_param ([m '/Vec'], 'PortHandles');
  set_param (pv.Outport(1), 'DataLogging', 'on', 'Name', 'sig');
  out = sim (m);
  D.logged_named = struct ('who', {who_list(out)}, 'logsout', describe_dataset (out.logsout), ...
                           'yout', describe_dataset (out.yout));
  D.access.duplicate = probe_value (@() out.logsout.getElement ('sig'));
  set_param (pv.Outport(1), 'DataLogging', 'off', 'Name', '');
  set_param (ph.Outport(1), 'DataLogging', 'off', 'Name', '');
  % Scope logging into a Dataset variable.
  set_param ([m '/Sc'], 'DataLogging', 'on', 'DataLoggingVariableName', 'ScopeData', ...
             'DataLoggingSaveFormat', 'Dataset');
  out = sim (m);
  D.scope = struct ('who', {who_list(out)}, 'scopedata', describe_dataset (out.ScopeData));
  % Array format: the same model with matrix outputs.
  D.array_matrix = attempt (@() sim (m, 'SaveFormat', 'Array'));
  close_system (m, 0);
end

function d = describe_dataset (ds)
  d = struct ('class', class (ds), 'Name', '', 'numElements', [], 'names', {{}}, 'names_size', [], ...
              'elements', {{}});
  if ~isa (ds, 'Simulink.SimulationData.Dataset'), return; end
  d.Name = ds.Name; d.numElements = numElements (ds);
  names = getElementNames (ds);
  d.names = names(:)'; d.names_size = size (names);
  for k = 1:numElements (ds)
    d.elements{end+1} = describe_element (getElement (ds, k));
  end
end

function e = describe_element (s)
  e = struct ('class', class (s), 'properties', {properties(s)'});
  for p = {'Name', 'PropagatedName', 'PortType', 'PortIndex'}
    if isprop (s, p{1}), e.(p{1}) = s.(p{1}); end
  end
  if isprop (s, 'BlockPath')
    e.BlockPath = s.BlockPath.getBlock (1); e.BlockPathLength = s.BlockPath.getLength ();
    e.BlockPath_class = class (s.BlockPath);
  end
  if isprop (s, 'Values')
    v = s.Values;
    e.values_class = class (v); e.values_name = v.Name; e.time = v.Time(:)';
    e.data_size = size (v.Data); e.data = double (v.Data(:)'); e.is_time_first = v.IsTimeFirst;
    e.length = v.Length;
  end
end

function r = probe_value (f)
  % Outcome and the class/size (and Name, or element count) of the result.
  r = struct ('ok', true, 'message', '', 'class', '', 'size', [], 'Name', '', 'numElements', []);
  try
    v = f ();
    r.class = class (v); r.size = size (v);
    if isa (v, 'Simulink.SimulationData.Dataset'), r.numElements = numElements (v);
    elseif isobject (v) && isprop (v, 'Name'), r.Name = v.Name; end
  catch err
    r.ok = false; r.message = err.message;
  end
end

function [y, times] = per_element (yo)
  % One numeric matrix per Dataset element (rows are samples) and its times.
  y = {}; times = {};
  for k = 1:numElements (yo)
    s = getElement (yo, k); v = s.Values;
    d = double (v.Data); n = numel (v.Time);
    if size (d, 1) ~= n || ndims (d) > 2, d = reshape (d, [], n).'; end
    y{end+1} = d; times{end+1} = v.Time(:)'; %#ok<AGROW>
  end
end

%% ------------------------------------------------------------ models

function build_api ()
  new_system ('api');
  add_block ('simulink/Sources/Sine Wave', 'api/Sine', 'Amplitude', '2', 'Frequency', '3', 'Bias', '0.5');
  add_block ('simulink/Continuous/Integrator', 'api/Int');
  add_block ('simulink/Sinks/Out1', 'api/Out1');
  add_line ('api', 'Sine/1', 'Int/1'); add_line ('api', 'Int/1', 'Out1/1');
  set_param ('api', 'StopTime', '2', 'Solver', 'ode45', 'RelTol', '1e-9', 'AbsTol', '1e-12', 'FixedStep', '0.05');
end

function build_ops ()
  new_system ('ops');
  for k = 1:3
    add_block ('simulink/Sources/Constant', sprintf ('ops/C%d', k), 'Value', mat2str (k * [1 2]));
  end
  add_block ('simulink/Math Operations/Sum', 'ops/Sum', 'Inputs', '+-+');
  add_block ('simulink/Math Operations/Product', 'ops/Prod', 'Inputs', '**/');
  add_block ('simulink/Math Operations/Gain', 'ops/K', 'Gain', '-2');
  add_block ('simulink/Sinks/To Workspace', 'ops/Log', 'VariableName', 'sumlog');
  add_block ('simulink/Sinks/Out1', 'ops/Out1');
  for k = 1:3
    add_line ('ops', sprintf ('C%d/1', k), sprintf ('Sum/%d', k));
    add_line ('ops', sprintf ('C%d/1', k), sprintf ('Prod/%d', k));
  end
  add_line ('ops', 'Sum/1', 'K/1'); add_line ('ops', 'K/1', 'Log/1'); add_line ('ops', 'Prod/1', 'Out1/1');
end

function build_tf ()
  new_system ('tf');
  add_block ('simulink/Sources/Step', 'tf/Step', 'Time', '0.5');
  add_block ('simulink/Continuous/Transfer Fcn', 'tf/Plant', 'Denominator', '[1 2]', 'Numerator', '[4]');
  add_block ('simulink/Sinks/Out1', 'tf/y');
  add_line ('tf', 'Step/1', 'Plant/1'); add_line ('tf', 'Plant/1', 'y/1');
end

function build_cond ()
  new_system ('cond');
  add_block ('simulink/Sources/Clock', 'cond/Clock');
  add_block ('simulink/Sources/Step', 'cond/On', 'Time', '0.45');
  add_block ('simulink/Sources/Step', 'cond/Off', 'Time', '1.05', 'After', '-1');
  add_block ('simulink/Math Operations/Add', 'cond/Gate');
  add_block ('simulink/Ports & Subsystems/Enabled Subsystem', 'cond/Sub');
  add_block ('simulink/Math Operations/Gain', 'cond/Sub/Double', 'Gain', '2');
  delete_line ('cond/Sub', 'In1/1', 'Out1/1');
  add_line ('cond/Sub', 'In1/1', 'Double/1'); add_line ('cond/Sub', 'Double/1', 'Out1/1');
  add_block ('simulink/Sinks/Out1', 'cond/Out1');
  add_line ('cond', 'On/1', 'Gate/1'); add_line ('cond', 'Off/1', 'Gate/2');
  add_line ('cond', 'Clock/1', 'Sub/1'); add_line ('cond', 'Gate/1', 'Sub/Enable');
  add_line ('cond', 'Sub/1', 'Out1/1');
end

function build_ports ()
  new_system ('ports');
  add_block ('simulink/Ports & Subsystems/Subsystem', 'ports/Sub');
  add_block ('simulink/Sources/In1', 'ports/Sub/In2');
  add_block ('simulink/Math Operations/Add', 'ports/Sub/Add');
  delete_line ('ports/Sub', 'In1/1', 'Out1/1');
  add_line ('ports/Sub', 'In1/1', 'Add/1'); add_line ('ports/Sub', 'In2/1', 'Add/2');
  add_line ('ports/Sub', 'Add/1', 'Out1/1');
  add_block ('simulink/Sources/Constant', 'ports/A', 'Value', '1');
  add_block ('simulink/Sources/Constant', 'ports/B', 'Value', '10');
  add_line ('ports', 'A/1', 'Sub/1'); add_line ('ports', 'B/1', 'Sub/2');
  add_block ('simulink/Sinks/Out1', 'ports/Out1'); add_line ('ports', 'Sub/1', 'Out1/1');
end

function build_pid ()
  new_system ('pid');
  add_block ('simulink/Sources/Step', 'pid/Ref');
  add_block ('simulink/Math Operations/Subtract', 'pid/Err');
  add_block ('simulink/Continuous/PID Controller', 'pid/PID', 'P', '2', 'I', '1', 'D', '0.1', 'N', '50');
  add_block ('simulink/Continuous/State-Space', 'pid/Plant', 'A', '[0 1; -2 -3]', 'B', '[0; 1]', ...
             'C', '[1 0]', 'D', '0', 'InitialCondition', '0');
  add_block ('simulink/Sinks/Out1', 'pid/y');
  add_line ('pid', 'Ref/1', 'Err/1'); add_line ('pid', 'Plant/1', 'Err/2');
  add_line ('pid', 'Err/1', 'PID/1'); add_line ('pid', 'PID/1', 'Plant/1'); add_line ('pid', 'Plant/1', 'y/1');
end

function build_mix ()
  new_system ('mix');
  add_block ('simulink/Sources/Ramp', 'mix/Ramp', 'Slope', '2', 'Start', '0.5', 'InitialOutput', '1');
  add_block ('simulink/Discontinuities/Saturation', 'mix/Sat', 'UpperLimit', '2', 'LowerLimit', '0');
  add_block ('simulink/User-Defined Functions/Fcn', 'mix/Exp', 'Expr', 'exp(u)');
  add_block ('simulink/Discrete/Unit Delay', 'mix/Z', 'SampleTime', '0.2', 'InitialCondition', '5');
  add_block ('simulink/Sinks/Out1', 'mix/Out1'); add_block ('simulink/Sinks/Out1', 'mix/Out2');
  add_block ('simulink/Sinks/Out1', 'mix/Out3');
  add_line ('mix', 'Ramp/1', 'Sat/1'); add_line ('mix', 'Sat/1', 'Out1/1');
  add_line ('mix', 'Sat/1', 'Exp/1'); add_line ('mix', 'Exp/1', 'Out2/1');
  add_line ('mix', 'Ramp/1', 'Z/1'); add_line ('mix', 'Z/1', 'Out3/1');
end

function build_switch ()
  new_system ('sw');
  add_block ('simulink/Sources/Constant', 'sw/U1', 'Value', '1');
  add_block ('simulink/Sources/Constant', 'sw/U2', 'Value', '0');
  add_block ('simulink/Sources/Constant', 'sw/U3', 'Value', '3');
  add_block ('simulink/Signal Routing/Switch', 'sw/Sw');
  add_block ('simulink/Sinks/Out1', 'sw/Out1');
  add_line ('sw', 'U1/1', 'Sw/1'); add_line ('sw', 'U2/1', 'Sw/2'); add_line ('sw', 'U3/1', 'Sw/3');
  add_line ('sw', 'Sw/1', 'Out1/1');
end

%% ------------------------------------------------------------ helpers

function legacy_sim (varargin)
  [t, x, y] = sim (varargin{:}); %#ok<ASGLU>
end

function r = attempt (f)
  r = struct ('ok', true, 'message', '');
  try
    f ();
  catch err
    r.ok = false; r.message = err.message;
  end
end

function s = enc (v)
  if ischar (v), s = v;
  elseif isstring (v), s = char (strjoin (v, ' '));
  elseif isnumeric (v) || islogical (v), s = mat2str (v);
  elseif iscell (v), s = sprintf ('{cell %s}', mat2str (size (v)));
  else, s = ['<' class(v) '>'];
  end
end

function v = row (value)
  if iscell (value), v = value; else, v = value(:)'; end
end

function [y, info] = yout_values (out)
  % Dataset yout as a matrix (one column per element), or a cell when the
  % elements are logged at different rates.
  yo = out.yout;
  info = struct ('time_len', []);
  if isa (yo, 'Simulink.SimulationData.Dataset')
    cols = {};
    for k = 1:numElements (yo)
      val = yo{k}.Values;
      info.time_len(end+1) = numel (val.Time);
      d = val.Data; sz = size (d);
      if numel (val.Time) ~= sz(1)
        d = reshape (d, [], numel (val.Time)).';
      else
        d = reshape (d, sz(1), []);
      end
      cols{end+1} = double (d); %#ok<AGROW>
    end
    try
      y = [cols{:}];
    catch
      y = cols;
    end
  else
    y = double (yo);
  end
end

function w = who_list (out)
  % SimulationOutput.who is a method, so out.who(:) would pass ':' to it.
  w = out.who;
  w = w(:)';
end
