function reference_ob_nonlinear_builders (file)
  % Record live Simulink traces for the nonlinear subsystem builders
  % (ob_backlash, ob_quantizer, ob_minmax, ob_saturation_dynamic, ob_sign,
  % ob_dead_zone_dynamic, ob_coulomb_viscous_friction,
  % ob_relational_operator, ob_logical_operator), independently of Octave.
  % Run in MATLAB with Simulink:
  %   reference_ob_nonlinear_builders ('simulink-nonlinear-builders-reference.json')
  % Each case drives one library block from Sine Wave / Constant sources
  % (optionally rounded), converts the output to double and records it.
  % The block parameters and sources are stored as data, so
  % test_ob_nonlinear_builders can rebuild the same model in Octave Blocks.
  % Cases with 'integrate' feed the block into an Integrator and run a
  % variable-step solver with zero-crossing detection.  The library
  % defaults (BlockType, MaskType, dialog parameters and port counts) are
  % recorded too.  Every model is built unsaved and closed again.
  if exist ('OCTAVE_VERSION', 'builtin')
    error ('reference_ob_nonlinear_builders: run this producer in MATLAB');
  end
  if nargin < 1, file = 'simulink-nonlinear-builders-reference.json'; end
  load_system ('simulink');
  details = ver ('simulink');
  record = struct ('producer', 'reference_ob_nonlinear_builders.m', ...
                   'matlab_version', version, ...
                   'simulink_version', [details(1).Version ' ' details(1).Release], ...
                   'note', 'Recorded by the producer in one MATLAB session.');
  record.defaults = library_defaults ();
  record.cases = struct ();
  scenarios = scenario_table ();
  for k = 1:numel (scenarios)
    s = scenarios{k};
    record.cases.(s.id) = run_case (s);
    fprintf ('%-22s ok=%d n=%d %s\n', s.id, record.cases.(s.id).ok, ...
             numel (record.cases.(s.id).t), record.cases.(s.id).error);
  end
  fid = fopen (file, 'w');
  if fid < 0, error ('reference_ob_nonlinear_builders: cannot write %s', file); end
  fprintf (fid, '%s', jsonencode (record));
  fclose (fid);
end

function defaults = library_defaults ()
  blocks = struct ('backlash', 'simulink/Discontinuities/Backlash', ...
                   'quantizer', 'simulink/Discontinuities/Quantizer', ...
                   'minmax', 'simulink/Math Operations/MinMax', ...
                   'saturation_dynamic', 'simulink/Discontinuities/Saturation Dynamic', ...
                   'sign', 'simulink/Math Operations/Sign', ...
                   'dead_zone_dynamic', 'simulink/Discontinuities/Dead Zone Dynamic', ...
                   'coulomb_viscous_friction', 'simulink/Discontinuities/Coulomb & Viscous Friction', ...
                   'relational_operator', 'simulink/Logic and Bit Operations/Relational Operator', ...
                   'relational_operator_common', 'simulink/Commonly Used Blocks/Relational Operator', ...
                   'logical_operator', 'simulink/Logic and Bit Operations/Logical Operator', ...
                   'logical_operator_common', 'simulink/Commonly Used Blocks/Logical Operator');
  defaults = struct ();
  names = fieldnames (blocks);
  for k = 1:numel (names)
    path = blocks.(names{k});
    d = struct ('path', path, 'BlockType', get_param (path, 'BlockType'), ...
                'MaskType', get_param (path, 'MaskType'), 'parameters', struct ());
    dp = get_param (path, 'DialogParameters');
    if isstruct (dp)
      fields = fieldnames (dp);
      for j = 1:numel (fields)
        value = get_param (path, fields{j});
        if ~ischar (value), value = mat2str (value); end
        d.parameters.(fields{j}) = value;
      end
    end
    ph = get_param (path, 'PortHandles');
    d.inports = numel (ph.Inport); d.outports = numel (ph.Outport);
    defaults.(names{k}) = d;
  end
end

function scenarios = scenario_table ()
  % Library paths, parameters (Simulink strings) and sources for each case.
  BL = 'simulink/Discontinuities/Backlash'; QZ = 'simulink/Discontinuities/Quantizer';
  MM = 'simulink/Math Operations/MinMax'; SD = 'simulink/Discontinuities/Saturation Dynamic';
  SG = 'simulink/Math Operations/Sign'; DZ = 'simulink/Discontinuities/Dead Zone Dynamic';
  CV = 'simulink/Discontinuities/Coulomb & Viscous Friction';
  RO = 'simulink/Logic and Bit Operations/Relational Operator';
  LO = 'simulink/Logic and Bit Operations/Logical Operator';
  S = @(a, p) source ('sine', a, p, 0);
  K = @(v) source ('const', v, 0, 0);
  R = @(a, p) source ('roundsine', a, p, 0);
  P = @(varargin) struct (varargin{:});
  f = fixed (0.1, 10); f5 = fixed (0.05, 10);
  v = variable (0:0.5:10);
  scenarios = {
    scenario('backlash', BL, struct(), {S(2, 0)}, f)
    scenario('backlash_y0', BL, P('BacklashWidth', '1', 'InitialOutput', '1.7'), {S(2, 0)}, f)
    scenario('backlash_ts', BL, P('SampleTime', '0.25'), {S(2, 0)}, f5)
    scenario('backlash_ts_offset', BL, P('BacklashWidth', '0.8', 'SampleTime', '[0.25 0.1]'), {S(2, 0)}, f5)
    scenario('backlash_vec', BL, P('BacklashWidth', '0.5', 'InitialOutput', '[0 1]'), {S([2 1.5], 0)}, f)
    scenario('quantizer', QZ, struct(), {S(2, 0)}, f)
    scenario('quantizer_half', QZ, P('QuantizationInterval', '0.1'), {K([0.15 0.35 -0.25 1.05 -0.45])}, f)
    scenario('quantizer_ts', QZ, P('SampleTime', '0.25'), {S(2, 0)}, f5)
    scenario('quantizer_vec_interval', QZ, P('QuantizationInterval', '[0.5 0.3]'), {S([2 2], 0)}, f)
    scenario('minmax_max3', MM, P('Function', 'max', 'Inputs', '3'), {S(1, 0), S(1, pi/2), K(0.2)}, f)
    scenario('minmax_min2', MM, P('Function', 'min', 'Inputs', '2'), {S(1, 0), S(1, pi/2)}, f)
    scenario('minmax_expand', MM, P('Function', 'max', 'Inputs', '2'), {S(1, 0), K([0.5 -0.5 0])}, f)
    scenario('satdyn', SD, struct(), {K(0.5), S(2, 0), K(-1)}, f)
    scenario('satdyn_inv', SD, struct(), {K(0), S(2, 0), K(1)}, f)
    scenario('satdyn_vec', SD, struct(), {K([1 0.5 2]), S(2, 0), K(-1)}, f)
    scenario('sign', SG, struct(), {S(1, 0)}, f)
    scenario('sign_vec', SG, struct(), {S([1 -1 0], 0)}, f)
    scenario('dzdyn', DZ, struct(), {K(0.5), S(2, 0), K(-1)}, f)
    scenario('dzdyn_inv', DZ, struct(), {K(0), S(2, 0), K(1)}, f)
    scenario('dzdyn_vec', DZ, struct(), {K([1 0.5 2]), S(2, 0), K(-1)}, f)
    scenario('cvf', CV, P('offset', '2', 'gain', '3'), {S(1, 0)}, f)
    scenario('cvf_default', CV, struct(), {S(1, 0)}, f)
    scenario('cvf_vec', CV, P('offset', '[1 2]', 'gain', '[3 0.5]'), {S([1 2], 0)}, f)
    scenario('relop_default', RO, struct(), {S(1, 0), S(1, pi/2)}, f)
    scenario('relop_lt', RO, P('Operator', '<'), {S(1, 0), S(1, pi/2)}, f)
    scenario('relop_ge', RO, P('Operator', '>='), {S(1, 0), S(1, pi/2)}, f)
    scenario('relop_gt', RO, P('Operator', '>'), {S(1, 0), S(1, pi/2)}, f)
    scenario('relop_eq', RO, P('Operator', '=='), {R(0.6, 0), R(0.6, pi/2)}, f)
    scenario('relop_ne', RO, P('Operator', '~='), {R(0.6, 0), R(0.6, pi/2)}, f)
    scenario('relop_vec', RO, P('Operator', '>='), {S([1 2 3], 0), K(0.5)}, f)
    scenario('logic_and', LO, struct(), {R(0.6, 0), R(0.6, pi/2)}, f)
    scenario('logic_or3', LO, P('Operator', 'OR', 'Inputs', '3'), {R(0.6, 0), R(0.6, pi/2), K(0)}, f)
    scenario('logic_nand3', LO, P('Operator', 'NAND', 'Inputs', '3'), {R(0.6, 0), R(0.6, pi/2), K(2)}, f)
    scenario('logic_nor2', LO, P('Operator', 'NOR', 'Inputs', '2'), {R(0.6, 0), R(0.6, pi/2)}, f)
    scenario('logic_xor2', LO, P('Operator', 'XOR', 'Inputs', '2'), {R(0.6, 0), R(0.6, pi/2)}, f)
    scenario('logic_xor3', LO, P('Operator', 'XOR', 'Inputs', '3'), {R(0.6, 0), R(0.6, pi/2), K(1)}, f)
    scenario('logic_nxor2', LO, P('Operator', 'NXOR', 'Inputs', '2'), {R(0.6, 0), R(0.6, pi/2)}, f)
    scenario('logic_nxor3', LO, P('Operator', 'NXOR', 'Inputs', '3'), {R(0.6, 0), R(0.6, pi/2), K(-1)}, f)
    scenario('logic_not', LO, P('Operator', 'NOT'), {R(0.6, 0)}, f)
    scenario('logic_vec', LO, P('Operator', 'OR', 'Inputs', '2'), {R([0.6 1.2], 0), K(0)}, f)
    integrated(scenario('sign_int', SG, struct(), {S(1, 0)}, v))
    integrated(scenario('cvf_int', CV, P('offset', '2', 'gain', '3'), {S(1, 0)}, v))
    integrated(scenario('relop_gt_int', RO, P('Operator', '>'), {S(1, 0), S(1, pi/2)}, v))
    integrated(scenario('satdyn_int', SD, struct(), {K(0.5), S(2, 0), K(-1)}, v))
  };
end

function s = scenario (id, block, parameters, sources, config)
  s = config;
  s.id = id; s.block = block; s.parameters = parameters;
  s.sources = [sources{:}];
  s.integrate = false;
end

function s = integrated (s)
  s.integrate = true;
end

function src = source (kind, amplitude, phase, bias)
  % 'sine' and 'roundsine': amplitude*sin(t + phase) + bias (then rounded);
  % 'const': the value is in amplitude.
  src = struct ('kind', kind, 'amplitude', amplitude, 'phase', phase, 'bias', bias);
end

function c = fixed (h, stop)
  c = struct ('solver', 'ode4', 'fixed_step', h, 'stop_time', stop, 'output_times', [], ...
              'reltol', [], 'abstol', []);
end

function c = variable (times)
  c = struct ('solver', 'ode45', 'fixed_step', [], 'stop_time', times(end), 'output_times', times, ...
              'reltol', 1e-10, 'abstol', 1e-12);
end

function result = run_case (s)
  result = s;
  result.ok = false; result.error = ''; result.t = []; result.y = [];
  name = ['nlb_' s.id];
  try
    [t, y] = simulate (name, s);
    result.t = t; result.y = y; result.ok = true;
  catch err
    result.error = err.message;
    if bdIsLoaded (name), close_system (name, 0); end
  end
end

function [t, y] = simulate (name, s)
  new_system (name);
  cleanup = onCleanup (@() close_system (name, 0));
  set_param (name, 'Solver', s.solver, 'StopTime', num2str (s.stop_time), 'SaveOutput', 'on', ...
             'SaveFormat', 'Array', 'SaveTime', 'on', 'ReturnWorkspaceOutputs', 'on');
  if strcmp (s.solver, 'ode4')
    set_param (name, 'FixedStep', num2str (s.fixed_step));
  else
    set_param (name, 'OutputOption', 'SpecifiedOutputTimes', 'OutputTimes', mat2str (s.output_times), ...
               'RelTol', num2str (s.reltol), 'AbsTol', num2str (s.abstol), ...
               'ZeroCrossControl', 'EnableAll');
  end
  add_block (s.block, [name '/DUT']);
  fields = fieldnames (s.parameters);
  for k = 1:numel (fields)
    set_param ([name '/DUT'], fields{k}, s.parameters.(fields{k}));
  end
  for k = 1:numel (s.sources)
    src = s.sources(k); block = sprintf ('S%d', k);
    if strcmp (src.kind, 'const')
      add_block ('simulink/Sources/Constant', [name '/' block], 'Value', mat2str (src.amplitude, 17));
    else
      add_block ('simulink/Sources/Sine Wave', [name '/' block], 'Amplitude', mat2str (src.amplitude, 17), ...
                 'Phase', num2str (src.phase, 17), 'Bias', num2str (src.bias, 17));
      if strcmp (src.kind, 'roundsine')
        add_block ('simulink/Math Operations/Rounding Function', [name '/R' block], 'Operator', 'round');
        add_line (name, [block '/1'], ['R' block '/1']);
        block = ['R' block];
      end
    end
    add_line (name, [block '/1'], sprintf ('DUT/%d', k));
  end
  add_block ('simulink/Signal Attributes/Data Type Conversion', [name '/DTC'], 'OutDataTypeStr', 'double');
  add_line (name, 'DUT/1', 'DTC/1');
  last = 'DTC';
  if s.integrate
    add_block ('simulink/Continuous/Integrator', [name '/Int']);
    add_line (name, 'DTC/1', 'Int/1');
    last = 'Int';
  end
  add_block ('simulink/Sinks/Out1', [name '/Out1']);
  add_line (name, [last '/1'], 'Out1/1');
  out = sim (name);
  t = out.tout; y = double (out.yout);
end
