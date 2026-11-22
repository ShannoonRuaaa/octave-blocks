function test_ob_simulink_api_reference (file)
  % Compare the Simulink-style command API with recorded Simulink R2026b
  % behaviour: every library path, its BlockType/MaskType, Ports, parameter
  % names and default values, built-in/<BlockType> paths, and scenario
  % outputs where the products agree.  The reference comes from
  % reference_ob_simulink_api.m (run in MATLAB with Simulink).  Each
  % documented difference (SIMULINK_API.md, "Differences from Simulink") is
  % listed below and checked to still be the documented Octave behaviour.
  here = fileparts (mfilename ('fullpath'));
  if (nargin < 1), file = ob_test_reference ('simulink-api-reference.json'); endif
  addpath (fullfile (fileparts (here), 'simulink'));
  ref = jsondecode (fileread (file));
  bdclose ('all');
  cleanup = onCleanup (@() bdclose ('all'));
  checks = 0;

  % ---- library blocks: path, BlockType, MaskType, Ports, names, defaults
  for k = 1:numel (ref.blocks)
    check_block (item (ref.blocks, k));
    checks += 1;
  endfor
  for k = 1:numel (ref.builtin)
    b = item (ref.builtin, k);
    if (isfield (b, 'dialog_names'))
      % Recorded by the producer: the BlockType defaults, which can differ
      % from the library blocks', get the full comparison.
      check_block (b);
      checks += 1;
      continue;
    endif
    % The interim record holds only the BlockType of these paths.
    [system, destination] = fresh_destination (b.path);
    if (b.ok)
      add_block (b.path, destination);
      expect (strcmp (get_param (destination, 'BlockType'), b.BlockType), ...
              '%s: BlockType %s, Simulink %s', b.path, get_param (destination, 'BlockType'), b.BlockType);
    else
      assert_error (@() add_block (b.path, destination), 'There is no block named');
    endif
    close_system (system, 0);
    checks += 1;
  endfor

  % ---- parameter probes
  P = ref.probes;
  new_system ('st');
  ok = attempt (@() add_block ('simulink/Sources/Step', 'st/S1', 'InitialValue', '2', 'FinalValue', '3'));
  expect (ok == P.step_initialvalue.ok, 'Step InitialValue/FinalValue acceptance differs');
  add_block ('simulink/Sources/Step', 'st/S2', 'Before', '2', 'After', '3');
  expect (strcmp (get_param ('st/S2', 'Before'), P.step_get_before) ...
          && strcmp (get_param ('st/S2', 'InitialValue'), P.step_get_initialvalue), 'Step aliases differ');
  check_error (@() add_block ('simulink/Discontinuities/Rate Limiter', 'st/L', 'SampleTime', '0.1'), ...
               P.ratelimiter_sampletime);
  check_error (@() add_block ('simulink/Discontinuities/Relay', 'st/R', 'SampleTime', '0.1'), P.relay_sampletime);
  % Documented difference: the discrete PID builder needs an explicit period.
  expect (P.dpid_inherited.ok, 'reference: Simulink accepted an inherited Discrete PID');
  assert_error (@() add_block ('simulink/Discrete/Discrete PID Controller', 'st/P', 'SampleTime', '-1'), ...
                'explicit SampleTime');
  close_system ('st', 0);
  build_switch ();
  expect (strcmp (get_param ('sw/Sw', 'Criteria'), P.switch_criteria), 'library Switch Criteria differs');
  out = sim ('sw', 'StopTime', '1', 'Solver', 'ode4', 'FixedStep', '0.5');
  compare ('switch default', out.yout, P.switch_y, 0);
  h = add_block ('built-in/Switch', 'sw/Sw2');
  expect (strcmp (get_param (h, 'Criteria'), P.builtin_switch_criteria), 'built-in/Switch Criteria differs');
  close_system ('sw', 0);
  build_dtf ('');
  out = sim ('dtf', 'StopTime', '3', 'Solver', 'ode4', 'FixedStep', '0.1');
  compare ('dtf default', out.yout, P.dtf_default.y, 1e-12);
  set_param ('dtf/T', 'SampleTime', '1');
  out = sim ('dtf', 'StopTime', '3', 'Solver', 'ode4', 'FixedStep', '0.1');
  compare ('dtf SampleTime 1', out.yout, P.dtf_explicit1.y, 1e-12);
  close_system ('dtf', 0);
  checks += 6;

  % ---- legacy sim outputs and SaveFormat
  build_tf ();
  expect (attempt (@() sim ('tf', 'SaveFormat', 'Array')) == P.sim_saveformat_array.ok, 'sim SaveFormat Array');
  check_error (@() legacy_sim ('tf', 'StopTime', '3', 'FixedStep', '0.1'), P.legacy_rwo_on_namevalue);
  check_error (@() legacy_sim ('tf', [0 3]), P.legacy_rwo_on_timespan);
  set_param ('tf', 'ReturnWorkspaceOutputs', 'off');
  [t, x, y] = sim ('tf', [0 3]);
  % Documented difference: x is empty and outputs follow the FixedStep grid.
  expect (P.legacy_rwo_off_timespan.ok && numel (t) == numel (y) && isempty (x), 'legacy [t, x, y]');
  check_error (@() legacy_sim ('tf', 'StopTime', '3', 'FixedStep', '0.1'), P.legacy_rwo_off_namevalue);
  expect (strcmp (class (sim ('tf')), P.single_output_rwo_off_class), 'single output with ReturnWorkspaceOutputs off');
  close_system ('tf', 0);
  checks += 1;

  % ---- scenarios recorded by sl_api_parity.m
  C = ref.scenarios;
  new_system ('ops');
  for name = fieldnames (C.model_defaults)'
    expect (strcmp (get_param ('ops', name{1}), C.model_defaults.(name{1})), 'model default %s differs', name{1});
  endfor
  expect (strcmp (get_param ('ops', 'ReturnWorkspaceOutputs'), C.model_settings.ReturnWorkspaceOutputs), ...
          'ReturnWorkspaceOutputs default differs');
  % Documented difference: Simulink's default SaveFormat Dataset is unavailable.
  expect (strcmp (C.model_settings.SaveFormat, 'Dataset') && strcmp (get_param ('ops', 'SaveFormat'), 'Array'), ...
          'SaveFormat default');
  close_system ('ops', 0);
  checks += 1;

  build_api ();
  out = sim ('api');
  compare ('api t', out.tout, C.api.t, 1e-12);
  compare ('api y', out.yout, C.api.y, 1e-9);
  info = out.SimulationMetadata.ModelInfo.SolverInfo;
  expect (strcmp (info.Solver, C.api.solver) && strcmp (info.Type, C.api.solverinfo.Type), 'api solver info');
  compare ('api MaxStepSize', info.MaxStepSize, str2double (C.api.solverinfo.MaxStepSize), 1e-15);
  expect (isequal (out.who, C.api.who(:)), 'api who');
  checks += 1;

  build_ops ();
  out = sim ('ops', [0 1]);
  expect (numel (out.tout) == C.ops.tout_len, 'ops tout length');
  compare ('ops Array size', size (out.yout), C.ops.array_yout_size, 0);
  compare ('ops Array end', out.yout(end, :), C.ops.array_yout_end, 1e-12);
  compare ('ops sumlog', out.sumlog.signals.values(end, :), C.ops.sumlog_end, 1e-12);
  compare ('ops Sum Ports', get_param ('ops/Sum', 'Ports'), C.ops.ports, 0);
  expect (strcmp (get_param ('ops/Sum', 'BlockType'), C.ops.blocktype) ...
          && strcmp (get_param ('ops/Sum', 'Inputs'), C.ops.inputs), 'ops Sum parameters');
  expect (isequal (out.who, C.ops.who(:)), 'ops who');
  expect (strcmp (out.SimulationMetadata.ModelInfo.SolverInfo.Solver, C.ops.solver), 'ops solver');
  checks += 1;

  build_tf ();
  outputs = {'y1', 'y2', 'y3'}; gains = {'', '6', '2'};
  for k = 1:3
    if (! isempty (gains{k}))
      assignin ('base', 'ob_api_gain', str2double (gains{k}));
      set_param ('tf/Plant', 'Numerator', 'ob_api_gain');
    endif
    out = sim ('tf', 'StopTime', '3', 'Solver', 'ode45', 'RelTol', '1e-10', 'AbsTol', '1e-12', 'FixedStep', '0.1');
    compare (['tf ' outputs{k}], out.yout, C.tf.(outputs{k}), 1e-9);
  endfor
  set_param ('tf/Plant', 'Numerator', '[4]');       % outtimes used the plain model
  out = sim ('tf', 0:0.25:3);
  compare ('outtimes t', out.tout, C.outtimes.t, 1e-12);
  compare ('outtimes y', out.yout, C.outtimes.y, 1e-6);
  % Persistence probes on the same model.
  expect (strcmp (get_param ('tf', 'Dirty'), C.persist.dirty), 'Dirty');
  check_error (@() add_block ('simulink/Math Operations/Gain', 'tf/Plant'), C.persist.dup);
  path = add_block ('simulink/Math Operations/Gain', 'tf/Plant', 'MakeNameUnique', 'on');
  expect (strcmp (path, ['tf/' C.persist.unique_name]), 'MakeNameUnique');
  check_error (@() close_system ('tf'), C.persist.close);
  close_system ('tf', 0);
  checks += 3;

  build_lim ();
  out = sim ('lim', 'StopTime', '2', 'Solver', 'ode4', 'FixedStep', '0.25');
  compare_limited ('lim y1', out, C.lim.t, C.lim.y1);
  expect (strcmp (out.SimulationMetadata.ModelInfo.SolverInfo.Solver, C.lim.solver), 'lim solver');
  set_param ('lim/Int', 'ExternalReset', 'rising');
  compare ('lim Ports', get_param ('lim/Int', 'Ports'), C.lim.ports_rising, 0);
  add_block ('simulink/Sources/Step', 'lim/Reset', 'Time', '1', 'Before', '-1', 'After', '1');
  add_line ('lim', 'Reset/1', 'Int/2');
  out = sim ('lim', 'StopTime', '2', 'Solver', 'ode4', 'FixedStep', '0.25');
  compare_limited ('lim y2', out, C.lim.t2, C.lim.y2);
  expect (attempt (@() set_param ('lim/Int', 'ExternalReset', 'level hold')) == C.lim.levelhold.ok, 'level hold');
  set_param ('lim/Int', 'ExternalReset', 'level');
  out = sim ('lim', 'StopTime', '2', 'Solver', 'ode4', 'FixedStep', '0.25');
  compare ('lim level', out.yout, C.lim.y_level, 1e-12);
  checks += 1;

  new_system ('dly');
  add_block ('simulink/Sources/Clock', 'dly/Clock');
  add_block ('simulink/Continuous/Transport Delay', 'dly/Delay', 'DelayTime', '0.3', 'InitialOutput', '-1');
  add_block ('simulink/Sinks/Out1', 'dly/Out1');
  add_line ('dly', 'Clock/1', 'Delay/1'); add_line ('dly', 'Delay/1', 'Out1/1');
  out = sim ('dly', 'StopTime', '1', 'Solver', 'ode4', 'FixedStep', '0.1');
  compare ('dly', out.yout, C.dly.y, 1e-12);
  % Without continuous states Simulink reports its discrete solvers.
  expect (strcmp (out.SimulationMetadata.ModelInfo.SolverInfo.Solver, C.dly.solver), 'dly solver');
  out = sim ('dly', 'StopTime', '1', 'Solver', 'ode45');
  expect (strcmp (out.SimulationMetadata.ModelInfo.SolverInfo.Solver, C.dly.solver_ode45), 'dly ode45 solver');
  checks += 2;

  build_cond ();
  out = sim ('cond', 'StopTime', '1.5', 'Solver', 'ode4', 'FixedStep', '0.1');
  compare ('cond', out.yout, C.cond.y, 1e-12);
  % The sets agree; Simulink's ordering differs (documented).
  expect (isequal (sort (find_system ('cond')), sort (C.cond.find_all(:))), 'cond find_system');
  expect (isequal (sort (find_system ('cond', 'SearchDepth', 1)), sort (C.cond.find_depth1(:))), 'cond SearchDepth 1');
  expect (strcmp (get_param ('cond/Sub/Enable', 'BlockType'), C.cond.enable_blocktype), 'Enable BlockType');
  compare ('Enable Ports', get_param ('cond/Sub/Enable', 'Ports'), C.cond.enable_ports, 0);
  compare ('enabled Ports', get_param ('cond/Sub', 'Ports'), C.cond.sub_ports_enabled, 0);
  add_block ('simulink/Ports & Subsystems/Trigger', 'cond/Sub/Trigger', 'TriggerType', 'falling');
  add_line ('cond', 'On/1', 'Sub/Trigger');
  compare ('enabled and triggered Ports', get_param ('cond/Sub', 'Ports'), C.cond.sub_ports_enabled_triggered, 0);
  delete_block ('cond/Sub/Enable');
  compare ('Ports after delete', get_param ('cond/Sub', 'Ports'), C.cond.sub_ports_after_delete, 0);
  out = sim ('cond', 'StopTime', '1.5', 'Solver', 'ode4', 'FixedStep', '0.1');
  compare ('cond after delete', out.yout, C.cond.y_after_delete, 1e-12);
  checks += 2;

  build_ports ();
  out = sim ('ports', [0 1]);
  compare ('ports', out.yout(end), C.ports.y, 1e-12);
  expect (strcmp (get_param ('ports/Sub/In2', 'Port'), C.ports.in2_port_before), 'In2 Port');
  delete_block ('ports/Sub/In1');
  expect (strcmp (get_param ('ports/Sub/In2', 'Port'), C.ports.in2_port_after), 'In2 Port after delete');
  compare ('ports Ports', get_param ('ports/Sub', 'Ports'), C.ports.sub_ports_after, 0);
  % Documented difference: Simulink grounds the now unconnected input
  % (y = 10); Octave Blocks deletes the line and requires every input.
  expect (C.ports.y_after == 10, 'reference ports y_after');
  assert_error (@() sim ('ports', [0 1]), 'inputs');
  new_system ('ps');
  add_block ('simulink/Ports & Subsystems/Subsystem', 'ps/Sub');
  add_block ('simulink/Sources/In1', 'ps/Sub/In2');
  set_param ('ps/Sub/In2', 'Port', '1');
  expect (strcmp (get_param ('ps/Sub/In1', 'Port'), C.portswap.in1_port) ...
          && strcmp (get_param ('ps/Sub/In2', 'Port'), C.portswap.in2_port), 'port renumbering');
  checks += 2;

  build_pid ();
  out = sim ('pid', 'StopTime', '12', 'Solver', 'ode4', 'FixedStep', '0.02');
  % Documented difference: Octave's RK4 splits at, and takes the left limit
  % of, the Step at t = 1, so the traces agree exactly only up to the step.
  % After it, the PID (with D/N filter) and State-Space loop must stay within
  % the recorded size of that difference (peak 1.72e-3).
  before = C.pid.t <= 1 + 1e-12;
  compare ('pid until the step', out.yout(before), C.pid.y(before), 1e-12);
  expect (max (abs (C.pid.y)) > 0.9, 'reference: the pid trace should respond to the step');
  compare ('pid whole trace', out.yout, C.pid.y, 2e-3);
  checks += 2;

  build_mix ();
  out = sim ('mix', 'StopTime', '1', 'Solver', 'ode4', 'FixedStep', '0.1');
  compare ('mix y1', out.yout(:, 1), C.mix.y1, 1e-12);
  compare ('mix y2', out.yout(:, 2), C.mix.y2, 1e-12);
  % Simulink logs the 0.2 s Unit Delay at its own rate.
  hits = abs (out.tout / 0.2 - round (out.tout / 0.2)) < 1e-9;
  compare ('mix y3', out.yout(hits, 3), C.mix.y3, 1e-12);
  expect (all (ismember (fieldnames (get_param ('mix/Ramp', 'DialogParameters')), C.mix.ramp_params)), 'Ramp names');
  set_param ('mix/Exp', 'Name', 'Exponential');
  expect (strcmp (get_param ('mix/Exponential', 'Expr'), C.mix.expr_renamed), 'renamed Fcn');
  % Errors: both products fail under the same conditions, except the
  % documented Signal Builder (D29) and numeric StopTime (D25) cases.
  E = C.errors;
  check_ok (@() add_block ('simulink/Sources/Signal Builder', 'mix/S'), ! E.signal_builder.ok, 'Signal Builder');
  check_ok (@() set_param ('mix/Sat', 'Gain', '3'), E.sat_gain.ok, 'Saturate Gain', E.sat_gain);
  solver = get_param ('mix', 'Solver');
  check_ok (@() set_param ('mix', 'Solver', 'ode113'), E.solver_ode113.ok, 'Solver ode113');
  expect (strcmp (get_param ('mix', 'Solver'), E.solver_after), 'Solver after ode113');
  set_param ('mix', 'Solver', solver);
  check_ok (@() set_param ('mix/Z', 'SampleTime', '[0.2 0.5]'), E.sampletime_offset.ok, 'SampleTime offset');
  expect (strcmp (get_param ('mix/Z', 'SampleTime'), E.sampletime_after), 'SampleTime after error');
  check_ok (@() add_line ('mix', 'Ramp/1', 'Out1/1'), E.dup_line.ok, 'duplicate line');
  check_ok (@() sim ('missing'), E.sim_missing.ok, 'sim missing');
  check_ok (@() load_system ('model.slx'), E.load_slx.ok, 'load .slx');
  check_ok (@() add_block ('simulink/Math Operations/Sum', 'mix/S', 'Inputs', '+*'), E.sum_plus_times.ok, 'Sum +*');
  expect (any (strcmp (find_system ('mix'), 'mix/S')) == E.block_S_exists_after, 'failed Sum left a block');
  check_ok (@() new_system ('mix'), E.new_system_duplicate.ok, 'duplicate new_system');
  check_ok (@() delete_line ('mix', 'Ramp/1', 'Out2/1'), E.delete_line_missing.ok, 'missing line');
  check_ok (@() get_param ('mix/Sat', 'NoSuchParam'), E.get_param_bad.ok, 'unknown parameter', E.get_param_bad);
  check_ok (@() set_param ('mix', 'StopTime', 2), ! E.set_param_numeric_stoptime.ok, 'numeric StopTime');
  set_param ('mix', 'StopTime', '10.0');
  % FixedStep 'auto' without continuous states: the fundamental sample time.
  set_param ('mix', 'Solver', 'ode4', 'StopTime', '1');
  out = sim ('mix');
  compare ('autostep', out.tout, C.autostep.t, 1e-12);
  checks += 4;

  new_system ('loop');
  add_block ('simulink/Sources/Step', 'loop/Ref');
  add_block ('simulink/Math Operations/Subtract', 'loop/Err');
  add_block ('simulink/Continuous/PID Controller', 'loop/PID', 'P', '2', 'I', '1');
  add_block ('simulink/Continuous/Transfer Fcn', 'loop/Plant', 'Denominator', '[1 3 2]');
  add_block ('simulink/Sinks/Out1', 'loop/y');
  add_line ('loop', 'Ref/1', 'Err/1'); add_line ('loop', 'Plant/1', 'Err/2');
  add_line ('loop', 'Err/1', 'PID/1'); add_line ('loop', 'PID/1', 'Plant/1');
  add_line ('loop', 'Plant/1', 'y/1');
  out = sim ('loop', 'StopTime', '10', 'RelTol', '1e-10', 'AbsTol', '1e-12', 'FixedStep', '0.2');
  compare ('loop', out.yout, C.loop.y, 1e-9);
  expect (strcmp (out.SimulationMetadata.ModelInfo.SolverInfo.Solver, C.loop.solver), 'loop solver');
  checks += 1;

  new_system ('gv');
  add_block ('simulink/Sources/Constant', 'gv/C', 'Value', '[1 2]');
  add_block ('simulink/Math Operations/Gain', 'gv/K', 'Gain', '[2 3]');
  add_block ('simulink/Sinks/Out1', 'gv/Out1');
  add_line ('gv', 'C/1', 'K/1'); add_line ('gv', 'K/1', 'Out1/1');
  expect (strcmp (get_param ('gv/K', 'Multiplication'), C.gainvec.multiplication), 'Gain Multiplication');
  out = sim ('gv', 'StopTime', '1', 'Solver', 'ode4', 'FixedStep', '0.5');
  compare ('gainvec', out.yout(end, :), C.gainvec.y, 1e-12);
  checks += 1;

  R = C.rootenable;
  new_system ('re');
  % Documented difference: an Enable block at the root (an enabled
  % referenced model in Simulink) is rejected.
  check_ok (@() add_block ('simulink/Ports & Subsystems/Enable', 're/Enable'), ! R.add_enable_root.ok, 'root Enable');
  add_block ('simulink/Ports & Subsystems/Subsystem', 're/Sub');
  add_block ('simulink/Ports & Subsystems/Enable', 're/Sub/Enable');
  check_ok (@() add_block ('simulink/Ports & Subsystems/Enable', 're/Sub/Enable2'), R.add_second_enable.ok, 'second Enable');
  check_ok (@() add_block ('simulink/Ports & Subsystems/Reset', 're/Sub/Reset'), R.add_reset_with_enable.ok, ...
            'Reset library path', R.add_reset_with_enable);
  check_ok (@() add_line ('re', 'Sub/1', 'Sub/Reset'), R.addline_reset_missing.ok, 'missing Reset port');
  checks += 1;

  new_system ('lut');
  add_block ('simulink/Sources/Clock', 'lut/Clock');
  add_block ('simulink/Math Operations/Gain', 'lut/K', 'Gain', '2');
  add_block ('simulink/Lookup Tables/1-D Lookup Table', 'lut/LUT');
  add_block ('simulink/Sinks/Out1', 'lut/Out1');
  add_line ('lut', 'Clock/1', 'K/1'); add_line ('lut', 'K/1', 'LUT/1'); add_line ('lut', 'LUT/1', 'Out1/1');
  out = sim ('lut', 'StopTime', '5', 'Solver', 'ode4', 'FixedStep', '0.25');
  compare ('lutdefault', out.yout, C.lutdefault.y, 1e-12);
  expect (strcmp (get_param ('lut/LUT', 'ExtrapMethod'), C.lutdefault.extrap) ...
          && strcmp (get_param ('lut/LUT', 'InterpMethod'), C.lutdefault.interp), 'Lookup methods');
  new_system ('dti');
  add_block ('simulink/Sources/Constant', 'dti/C');
  add_block ('simulink/Discrete/Discrete-Time Integrator', 'dti/DTI');
  add_block ('simulink/Sinks/Out1', 'dti/Out1');
  add_line ('dti', 'C/1', 'DTI/1'); add_line ('dti', 'DTI/1', 'Out1/1');
  out = sim ('dti', 'StopTime', '3', 'Solver', 'ode4', 'FixedStep', '0.25');
  compare ('dtidefault', out.yout, C.dtidefault.y, 1e-12);
  expect (strcmp (get_param ('dti/DTI', 'SampleTime'), C.dtidefault.sampletime), 'DTI SampleTime');
  checks += 2;

  new_system ('trg');
  add_block ('simulink/Sources/Clock', 'trg/Clock');
  add_block ('simulink/Sources/Sine Wave', 'trg/Sine', 'Frequency', '2*pi', 'Phase', '-0.3');
  add_block ('simulink/Ports & Subsystems/Triggered Subsystem', 'trg/Sub');
  add_block ('simulink/Sinks/Out1', 'trg/Out1');
  add_line ('trg', 'Clock/1', 'Sub/1'); add_line ('trg', 'Sine/1', 'Sub/Trigger'); add_line ('trg', 'Sub/1', 'Out1/1');
  expect (isequal (sort (find_system ('trg')), sort (C.trig.find_all(:))), 'trig find_system');
  out = sim ('trg', 'StopTime', '3', 'Solver', 'ode4', 'FixedStep', '0.05');
  compare ('trig', out.yout, C.trig.y, 1e-12);
  checks += 1;

  % InitialTriggerSignalState: default, value list and the spellings
  % set_param accepts, recorded by reference_ob_conditional_probes.m.
  probes = jsondecode (fileread (ob_test_reference ('simulink-conditional-probes-reference.json')));
  port = probes.trigger_port;
  expect (strcmp (get_param ('trg/Sub/Trigger', 'InitialTriggerSignalState'), port.default), ...
          'InitialTriggerSignalState default');
  for value = cellify (port.values)
    set_param ('trg/Sub/Trigger', 'InitialTriggerSignalState', value{1});
    expect (strcmp (get_param ('trg/Sub/Trigger', 'InitialTriggerSignalState'), value{1}), ...
            'InitialTriggerSignalState %s', value{1});
  endfor
  for k = 1:numel (port.attempts)
    a = item (port.attempts, k);
    set_param ('trg/Sub/Trigger', 'InitialTriggerSignalState', port.default);
    check_error (@() set_param ('trg/Sub/Trigger', 'InitialTriggerSignalState', a.value), ...
                 struct ('ok', a.accepted, 'message', a.message));
    if (a.accepted)
      expect (strcmp (get_param ('trg/Sub/Trigger', 'InitialTriggerSignalState'), a.result), ...
              'InitialTriggerSignalState ''%s'' reads ''%s'', Simulink ''%s''', a.value, ...
              get_param ('trg/Sub/Trigger', 'InitialTriggerSignalState'), a.result);
    endif
  endfor
  checks += 1;

  new_system ('tw');
  add_block ('simulink/Sources/Clock', 'tw/Clock');
  add_block ('simulink/Sinks/To Workspace', 'tw/Log');
  add_line ('tw', 'Clock/1', 'Log/1');
  % Documented difference: To Workspace defaults to 'Structure With Time'
  % because Simulink's Timeseries has no Octave equivalent.
  expect (strcmp (C.towsformat.default_saveformat, 'Timeseries') ...
          && strcmp (get_param ('tw/Log', 'SaveFormat'), 'Structure With Time'), 'To Workspace SaveFormat');
  set_param ('tw/Log', 'SaveFormat', 'Structure With Time');
  out = sim ('tw', 'StopTime', '1', 'Solver', 'ode4', 'FixedStep', '0.5');
  expect (isequal (sort (fieldnames (out.simout)), sort (C.towsformat.fields(:))), 'To Workspace fields');
  expect (isequal (sort (fieldnames (out.simout.signals)), sort (C.towsformat.signals_fields(:))), 'signals fields');
  compare ('To Workspace values', out.simout.signals.values, C.towsformat.values, 1e-12);
  compare ('To Workspace time', out.simout.time, C.towsformat.time, 1e-12);
  expect (strcmp (out.simout.blockName, C.towsformat.blockName), 'To Workspace blockName');
  expect (isequal (out.who, C.towsformat.who(:)), 'To Workspace who');
  checks += 1;

  new_system ('term');
  add_block ('simulink/Sources/Clock', 'term/Clock');
  add_block ('simulink/Sinks/Terminator', 'term/T');
  add_block ('simulink/Sinks/Display', 'term/D');
  add_block ('simulink/Sinks/Scope', 'term/Sc');
  add_line ('term', 'Clock/1', 'T/1'); add_line ('term', 'Clock/1', 'D/1'); add_line ('term', 'Clock/1', 'Sc/1');
  out = sim ('term', 'StopTime', '1', 'Solver', 'ode4', 'FixedStep', '0.5');
  % Documented difference: Scope logging into logsout is an Octave extension.
  expect (isequal (out.who(! strcmp (out.who, 'logsout')), C.terminator.who(:)), 'terminator who');
  expect (strcmp (get_param ('term/T', 'BlockType'), C.terminator.bt_T) ...
          && strcmp (get_param ('term/D', 'BlockType'), C.terminator.bt_D), 'sink BlockTypes');
  expect (isequal (find_system ('term', 'BlockType', 'Terminator'), C.terminator.find_terminator(:)), ...
          'find_system Terminator');
  checks += 1;

  % Outport OutputWhenDisabled/InitialOutput, Enable StatesWhenEnabling and
  % SimulationMode, recorded by reference_ob_conditional_outputs.m.
  A = jsondecode (fileread (ob_test_reference ('simulink-conditional-outputs-reference.json'))).api;
  new_system ('cop');
  add_block ('simulink/Ports & Subsystems/Enabled Subsystem', 'cop/E');
  add_block ('simulink/Ports & Subsystems/Triggered Subsystem', 'cop/T');
  add_block ('simulink/Ports & Subsystems/Enabled and Triggered Subsystem', 'cop/ET');
  add_block ('simulink/Sinks/Out1', 'cop/Root');
  expect (strcmp (get_param ('cop/E/Out1', 'OutputWhenDisabled'), A.outport_default_output.value) ...
          && strcmp (get_param ('cop/E/Out1', 'InitialOutput'), A.outport_default_initial.value) ...
          && strcmp (get_param ('cop/E/Enable', 'StatesWhenEnabling'), A.enable_default_states.value), ...
          'conditional Outport/Enable defaults');
  probes = {'outport_set_reset', 'cop/E/Out1', 'OutputWhenDisabled', 'reset'; ...
            'outport_set_capital_reset', 'cop/E/Out1', 'OutputWhenDisabled', 'Reset'; ...
            'outport_set_capital_held', 'cop/E/Out1', 'OutputWhenDisabled', 'HELD'; ...
            'outport_set_bogus', 'cop/E/Out1', 'OutputWhenDisabled', 'bogus'; ...
            'outport_set_initial_matrix', 'cop/E/Out1', 'InitialOutput', '[1 2;3 4]'; ...
            'outport_set_initial_undefined', 'cop/E/Out1', 'InitialOutput', 'ob_undefined_variable_xyz'; ...
            'outport_set_initial_empty', 'cop/E/Out1', 'InitialOutput', '[]'; ...
            'root_set_reset', 'cop/Root', 'OutputWhenDisabled', 'reset'; ...
            'triggered_set_reset', 'cop/T/Out1', 'OutputWhenDisabled', 'reset'; ...
            'combined_set_reset', 'cop/ET/Out1', 'OutputWhenDisabled', 'reset'; ...
            'enable_set_reset', 'cop/E/Enable', 'StatesWhenEnabling', 'reset'; ...
            'enable_set_capital_reset', 'cop/E/Enable', 'StatesWhenEnabling', 'Reset'};
  for k = 1:rows (probes)
    recorded = A.(probes{k, 1});
    check_error (@() set_param (probes{k, 2:4}), recorded);
    if (recorded.ok)
      expect (strcmp (get_param (probes{k, 2}, probes{k, 3}), recorded.value), '%s reads ''%s'', Simulink ''%s''', ...
              probes{k, 1}, get_param (probes{k, 2}, probes{k, 3}), recorded.value);
    endif
  endfor
  % Simulink names the EnablePort by its full path in this message; the
  % Octave Blocks message names the block.
  recorded = A.enable_set_bogus;
  [ok, message] = attempt (@() set_param ('cop/E/Enable', 'StatesWhenEnabling', 'bogus'));
  expect (! recorded.ok && ! ok && ! isempty (strfind (message, 'Invalid setting in EnablePort block')) ...
          && ! isempty (strfind (message, 'for parameter ''StatesWhenEnabling''')), 'StatesWhenEnabling error');
  % Documented difference: set_param accepts numeric values (stored as text).
  expect (! A.outport_set_initial_numeric.ok && attempt (@() set_param ('cop/E/Out1', 'InitialOutput', 3)), ...
          'numeric InitialOutput');
  expect (strcmp (get_param ('cop', 'SimulationMode'), A.simulation_mode_default.value), 'SimulationMode default');
  for mode = {'accelerator', 'rapid_accelerator', 'normal', 'capital_accelerator', ...
              'rapid_accelerator_words', 'rapid_accelerator_space', 'bogus'}
    recorded = A.(['simulation_mode_' mode{1}]);
    attempted = struct ('accelerator', 'accelerator', 'rapid_accelerator', 'rapid-accelerator', ...
                        'normal', 'normal', 'capital_accelerator', 'Accelerator', ...
                        'rapid_accelerator_words', 'Rapid Accelerator', ...
                        'rapid_accelerator_space', 'rapid accelerator', 'bogus', 'bogus').(mode{1});
    check_error (@() set_param ('cop', 'SimulationMode', attempted), recorded);
    if (recorded.ok)
      expect (strcmp (get_param ('cop', 'SimulationMode'), recorded.value), 'SimulationMode %s', attempted);
    endif
  endfor
  % Documented difference: SIL, PIL and external modes are rejected; every
  % accepted value is one of Simulink's.
  expect (A.simulation_mode_external.ok && ! attempt (@() set_param ('cop', 'SimulationMode', 'external')), ...
          'SimulationMode external');
  expect (all (ismember ({'normal', 'accelerator', 'rapid-accelerator'}, cellify (A.simulation_mode_enum.value))), ...
          'SimulationMode values');
  checks += 3;

  bdclose ('all');
  printf ('Simulink API reference (%s): %d checks passed\n', ref.simulink_version, checks);
endfunction

%% ---------------------------------------------------------------- library

function check_block (e)
  [system, destination] = fresh_destination (e.path, e.inside);
  if (! e.ok)
    assert_error (@() add_block (e.path, destination), 'There is no block named');
    close_system (system, 0);
    return;
  endif
  add_block (e.path, destination);
  ours = get_param (destination, 'BlockType');
  expect (strcmp (ours, e.BlockType), '%s: BlockType %s, Simulink %s', e.path, ours, e.BlockType);
  ours = get_param (destination, 'MaskType');
  expect (strcmp (ours, e.MaskType), '%s: MaskType ''%s'', Simulink ''%s''', e.path, ours, e.MaskType);
  if (strcmp (e.path, 'built-in/Lookup_n-D'))
    % Documented: the built-in default is a multi-dimensional table; only the
    % 1-D configuration is supported, so the port count must still differ.
    expect (! isequal (get_param (destination, 'Ports'), reshape (e.Ports, 1, [])), ...
            '%s: Ports now match Simulink; update the exception', e.path);
  else
    compare ([e.path ' Ports'], get_param (destination, 'Ports'), e.Ports, 0);
  endif
  names = cellify (e.dialog_names); values = cellify (e.dialog_values);
  params = get_param (destination, 'DialogParameters');
  for name = fieldnames (params)'
    reason = exception (e.BlockType, e.MaskType, e.path, name{1});
    if (strcmp (reason, 'extension')), continue; endif
    match = find (strcmp (names, name{1}), 1);
    expect (! isempty (match), '%s: %s is not a Simulink parameter name', e.path, name{1});
    ours = get_param (destination, name{1});
    if (! isempty (reason))
      % A documented default difference must still be a difference.
      expect (! strcmp (ours, values{match}), '%s: %s now matches Simulink; update the exception', e.path, name{1});
    else
      expect (strcmp (ours, values{match}), '%s: %s = ''%s'', Simulink ''%s''', e.path, name{1}, ours, values{match});
    endif
  endfor
  close_system (system, 0);
endfunction

function reason = exception (block_type, mask_type, path, name)
  % Documented differences from the Simulink R2026b defaults (see
  % SIMULINK_API.md): '' = none, 'extension' = Octave-only parameter,
  % otherwise the reason for a different default value.
  reason = '';
  if (strcmp (block_type, 'RateLimiter') && strcmp (name, 'OctaveSampleTime'))
    reason = 'extension';      % the sampled Rate Limiter's period
  elseif (strcmp (block_type, 'Fcn') && strcmp (name, 'Expr'))
    reason = 'Simulink''s default expression indexes u(2)';
  elseif (strcmp (block_type, 'ToWorkspace') && strcmp (name, 'SaveFormat') && ! strncmp (path, 'built-in/', 9))
    reason = 'Timeseries has no Octave equivalent';
  elseif (strcmp (path, 'built-in/Lookup_n-D') && any (strcmp (name, {'BreakpointsForDimension1', 'Table'})))
    reason = 'the built-in default is multi-dimensional; only 1-D tables are supported';
  elseif (strcmp (mask_type, 'PID 1dof') && ! isempty (strfind (path, 'Discrete PID')) && strcmp (name, 'SampleTime'))
    reason = 'the discrete PID builder needs an explicit period';
  endif
endfunction

function [system, destination] = fresh_destination (path, inside = [])
  % Control port blocks go inside a subsystem, as in the Simulink audit.
  if (isempty (inside))
    inside = any (cellfun (@(t) ! isempty (strfind (path, t)), {'EnablePort', 'TriggerPort', 'ResetPort'}));
  endif
  system = 'aud';
  if (bdIsLoaded (system)), close_system (system, 0); endif
  new_system (system);
  destination = 'aud/B';
  if (inside)
    add_block ('simulink/Ports & Subsystems/Subsystem', 'aud/S');
    destination = 'aud/S/B';
  endif
endfunction

%% ---------------------------------------------------------------- models

function build_api ()
  new_system ('api');
  add_block ('simulink/Sources/Sine Wave', 'api/Sine', 'Amplitude', '2', 'Frequency', '3', 'Bias', '0.5');
  add_block ('simulink/Continuous/Integrator', 'api/Int');
  add_block ('simulink/Sinks/Out1', 'api/Out1');
  add_line ('api', 'Sine/1', 'Int/1'); add_line ('api', 'Int/1', 'Out1/1');
  set_param ('api', 'StopTime', '2', 'Solver', 'ode45', 'RelTol', '1e-9', 'AbsTol', '1e-12', 'FixedStep', '0.05');
endfunction

function build_ops ()
  new_system ('ops');
  for k = 1:3
    add_block ('simulink/Sources/Constant', sprintf ('ops/C%d', k), 'Value', mat2str (k * [1 2]));
  endfor
  add_block ('simulink/Math Operations/Sum', 'ops/Sum', 'Inputs', '+-+');
  add_block ('simulink/Math Operations/Product', 'ops/Prod', 'Inputs', '**/');
  add_block ('simulink/Math Operations/Gain', 'ops/K', 'Gain', '-2');
  add_block ('simulink/Sinks/To Workspace', 'ops/Log', 'VariableName', 'sumlog');
  add_block ('simulink/Sinks/Out1', 'ops/Out1');
  for k = 1:3
    add_line ('ops', sprintf ('C%d/1', k), sprintf ('Sum/%d', k));
    add_line ('ops', sprintf ('C%d/1', k), sprintf ('Prod/%d', k));
  endfor
  add_line ('ops', 'Sum/1', 'K/1'); add_line ('ops', 'K/1', 'Log/1'); add_line ('ops', 'Prod/1', 'Out1/1');
endfunction

function build_tf ()
  new_system ('tf');
  add_block ('simulink/Sources/Step', 'tf/Step', 'Time', '0.5');
  add_block ('simulink/Continuous/Transfer Fcn', 'tf/Plant', 'Denominator', '[1 2]', 'Numerator', '[4]');
  add_block ('simulink/Sinks/Out1', 'tf/y');
  add_line ('tf', 'Step/1', 'Plant/1'); add_line ('tf', 'Plant/1', 'y/1');
endfunction

function build_lim ()
  new_system ('lim');
  add_block ('simulink/Sources/Constant', 'lim/One');
  add_block ('simulink/Continuous/Integrator', 'lim/Int', 'LimitOutput', 'on', ...
             'UpperSaturationLimit', '0.75', 'LowerSaturationLimit', '0');
  add_block ('simulink/Sinks/Out1', 'lim/Out1');
  add_line ('lim', 'One/1', 'Int/1'); add_line ('lim', 'Int/1', 'Out1/1');
endfunction

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
endfunction

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
endfunction

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
endfunction

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
endfunction

function build_switch ()
  new_system ('sw');
  add_block ('simulink/Sources/Constant', 'sw/U1', 'Value', '1');
  add_block ('simulink/Sources/Constant', 'sw/U2', 'Value', '0');
  add_block ('simulink/Sources/Constant', 'sw/U3', 'Value', '3');
  add_block ('simulink/Signal Routing/Switch', 'sw/Sw');
  add_block ('simulink/Sinks/Out1', 'sw/Out1');
  add_line ('sw', 'U1/1', 'Sw/1'); add_line ('sw', 'U2/1', 'Sw/2'); add_line ('sw', 'U3/1', 'Sw/3');
  add_line ('sw', 'Sw/1', 'Out1/1');
endfunction

function build_dtf (sample_time)
  new_system ('dtf');
  add_block ('simulink/Sources/Step', 'dtf/Step');
  add_block ('simulink/Discrete/Discrete Transfer Fcn', 'dtf/T');
  if (! isempty (sample_time)), set_param ('dtf/T', 'SampleTime', sample_time); endif
  add_block ('simulink/Sinks/Out1', 'dtf/Out1');
  add_line ('dtf', 'Step/1', 'T/1'); add_line ('dtf', 'T/1', 'Out1/1');
endfunction

%% ---------------------------------------------------------------- helpers

function compare_limited (label, out, t, y)
  % Documented difference: when an RK4 step reaches an Integrator limit,
  % Octave lands on it while Simulink ode4 gates each stage and arrives one
  % step later; elsewhere the traces agree.
  compare ([label ' t'], out.tout, t, 1e-12);
  y = y(:); reached = abs (out.yout - y) > 1e-12;
  expect (all (abs (out.yout(reached) - y(reached) - 0.25 / 6) < 1e-12), ...
          '%s differs from Simulink beyond the documented limit step', label);
endfunction

function compare (label, ours, theirs, tolerance)
  ours = double (ours(:)); theirs = double (theirs(:));
  expect (numel (ours) == numel (theirs), '%s: %d values, Simulink %d', label, numel (ours), numel (theirs));
  error_value = max ([0; abs(ours - theirs)]);
  expect (error_value <= tolerance, '%s: max |Octave - Simulink| = %.3g > %.3g', label, error_value, tolerance);
endfunction

function check_error (callback, recorded)
  % Same outcome as Simulink; an expected error must carry Simulink's text.
  [ok, message] = attempt (callback);
  expect (ok == recorded.ok, 'outcome differs from Simulink (%s)', recorded.message);
  if (! ok)
    expect (! isempty (strfind (message, recorded.message)), 'error "%s" lacks Simulink''s "%s"', ...
            message, recorded.message);
  endif
endfunction

function check_ok (callback, expected_ok, label, recorded = [])
  [ok, message] = attempt (callback);
  expect (ok == expected_ok, '%s: Octave ok=%d, expected %d (%s)', label, ok, expected_ok, message);
  if (! isempty (recorded) && ! ok)
    expect (! isempty (strfind (message, recorded.message)), '%s: error "%s" lacks Simulink''s "%s"', ...
            label, message, recorded.message);
  endif
endfunction

function [ok, message] = attempt (callback)
  ok = true; message = '';
  try
    callback ();
  catch err
    ok = false; message = err.message;
  end_try_catch
endfunction

function legacy_sim (varargin)
  [t, x, y] = sim (varargin{:});
endfunction

function value = item (list, k)
  if (iscell (list)), value = list{k}; else value = list(k); endif
endfunction

function c = cellify (value)
  if (iscell (value)), c = value(:)';
  elseif (isempty (value)), c = {};
  else c = {value}; endif
endfunction

function expect (condition, varargin)
  if (! condition), error (varargin{:}); endif
endfunction

function assert_error (callback, fragment)
  [ok, message] = attempt (callback);
  expect (! ok, 'expected an error containing "%s"', fragment);
  expect (! isempty (strfind (message, fragment)), 'expected error containing "%s"; got "%s"', fragment, message);
endfunction
