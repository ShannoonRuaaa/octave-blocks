function reference_ob_routing_builders (file)
  % Record live Simulink traces for the routing, source and filter builders
  % (ob_multiport_switch, ob_pulse_generator, ob_chirp, ob_mux, ob_demux,
  % ob_rate_transition, ob_second_order_integrator, ob_first_order_filter),
  % independently of Octave.  Run in MATLAB with Simulink:
  %   reference_ob_routing_builders ('simulink-routing-builders-reference.json')
  % Every model is built unsaved and closed again.  Each case stores its
  % Simulink block parameters as strings, so test_ob_routing_builders can
  % build the same model from the builders and check either agreement or a
  % documented difference.  Cases that Simulink rejects record ok = false
  % and the error message.  The library entry records the BlockType,
  % MaskType and dialog parameter defaults of every mapped library block.
  if exist ('OCTAVE_VERSION', 'builtin')
    error ('reference_ob_routing_builders: run this producer in MATLAB');
  end
  if nargin < 1, file = 'simulink-routing-builders-reference.json'; end
  load_system ('simulink');
  details = ver ('simulink');
  record = struct ('producer', 'reference_ob_routing_builders.m', ...
                   'matlab_version', version, ...
                   'simulink_version', [details(1).Version ' ' details(1).Release], ...
                   'note', 'Recorded by the producer in one MATLAB session; single-tasking.');
  record.library = library_defaults ();
  record.cases = struct ();
  scenarios = scenario_table ();
  for k = 1:numel (scenarios)
    s = scenarios{k};
    record.cases.(s.id) = run_case (s);
    c = record.cases.(s.id);
    fprintf ('%-28s ok=%d n=%d %s\n', s.id, c.ok, numel (c.t), c.error);
  end
  fid = fopen (file, 'w');
  if fid < 0, error ('reference_ob_routing_builders: cannot write %s', file); end
  fprintf (fid, '%s', jsonencode (record));
  fclose (fid);
end

function library = library_defaults ()
  paths = {'simulink/Signal Routing/Multiport Switch', 'simulink/Sources/Pulse Generator', ...
           'simulink/Sources/Chirp Signal', 'simulink/Signal Routing/Mux', 'simulink/Signal Routing/Demux', ...
           'simulink/Commonly Used Blocks/Mux', 'simulink/Commonly Used Blocks/Demux', ...
           'simulink/Signal Attributes/Rate Transition', 'simulink/Continuous/Integrator, Second-Order', ...
           'simulink/Continuous/Integrator, Second-Order Limited', 'simulink/Continuous/Transfer Fcn', ...
           'simulink/Discrete/Transfer Fcn First Order', 'simulink/Discrete/Transfer Fcn Lead or Lag', ...
           'simulink/Discrete/Transfer Fcn Real Zero', 'simulink/Discrete/Zero-Order Hold'};
  library = struct ('path', {}, 'ok', {}, 'BlockType', {}, 'MaskType', {}, 'parameters', {});
  for k = 1:numel (paths)
    entry = struct ('path', paths{k}, 'ok', false, 'BlockType', '', 'MaskType', '', 'parameters', struct ());
    try
      h = get_param (paths{k}, 'Handle');
      entry.ok = true;
      entry.BlockType = get_param (h, 'BlockType');
      entry.MaskType = get_param (h, 'MaskType');
      names = fieldnames (get_param (h, 'DialogParameters'));
      for j = 1:numel (names)
        value = get_param (h, names{j});
        if ischar (value), entry.parameters.(names{j}) = value; end
      end
    catch err
      entry.parameters = struct ('error', err.message);
    end
    library(end+1) = entry; %#ok<AGROW>
  end
end

function scenarios = scenario_table ()
  scenarios = {};
  % ---- Multiport Switch: control = Clock + ControlOffset, Constant data.
  mps = @(inputs, order, default, diag, offset, data) struct ('Inputs', inputs, 'DataPortOrder', order, ...
      'DataPortForDefault', default, 'DiagnosticForDefault', diag, 'ControlOffset', offset, 'Data', {data});
  one = 'One-based contiguous'; zero = 'Zero-based contiguous';
  scenarios{end+1} = scenario ('mps_onebased_none', 'mps', ...
      mps ('3', one, 'Last data port', 'None', '0', {'10', '20', '30'}), fixed (0.125, 0, 4.5));
  scenarios{end+1} = scenario ('mps_onebased_error', 'mps', ...
      mps ('3', one, 'Last data port', 'Error', '0', {'10', '20', '30'}), fixed (0.125, 0, 4.5));
  scenarios{end+1} = scenario ('mps_onebased_inrange', 'mps', ...
      mps ('3', one, 'Last data port', 'Error', '1', {'10', '20', '30'}), fixed (0.125, 0, 2.875));
  scenarios{end+1} = scenario ('mps_zerobased_none', 'mps', ...
      mps ('3', zero, 'Last data port', 'None', '-1', {'10', '20', '30'}), fixed (0.125, 0, 4.5));
  scenarios{end+1} = scenario ('mps_additional_none', 'mps', ...
      mps ('3', one, 'Additional data port', 'None', '-0.5', {'10', '20', '30', '99'}), fixed (0.125, 0, 5));
  scenarios{end+1} = scenario ('mps_vector_none', 'mps', ...
      mps ('3', one, 'Last data port', 'None', '0.5', {'[1;2]', '[3;4]', '[5;6]'}), fixed (0.25, 0, 4));
  scenarios{end+1} = scenario ('mps_two_ports_warning', 'mps', ...
      mps ('2', one, 'Last data port', 'Warning', '-1', {'-1', '1'}), fixed (0.0625, 0, 4));
  % A vector control selects element-wise (Control replaces Clock + offset).
  p = mps ('3', one, 'Last data port', 'None', '0', {'[10;11]', '[20;21]', '[30;31]'}); p.Control = '[1;3]';
  scenarios{end+1} = scenario ('mps_vector_control', 'mps', p, fixed (0.5, 0, 1));

  % ---- Pulse Generator (time based, simulation time).
  pg = @(a, p, w, d) struct ('Amplitude', a, 'Period', p, 'PulseWidth', w, 'PhaseDelay', d, 'Integrate', 'off');
  scenarios{end+1} = scenario ('pg_defaults', 'pg', struct ('Integrate', 'off'), fixed (0.25, 0, 30));
  scenarios{end+1} = scenario ('pg_a5_t2_w50_d1', 'pg', pg ('5', '2', '50', '1'), fixed (0.25, 0, 6));
  scenarios{end+1} = scenario ('pg_t01_w50', 'pg', pg ('1', '0.1', '50', '0'), fixed (0.05, 0, 1));
  scenarios{end+1} = scenario ('pg_t03_w33_d01', 'pg', pg ('1', '0.3', num2str (100/3, 17), '0.1'), fixed (0.1, 0, 3));
  scenarios{end+1} = scenario ('pg_late_t01_w50', 'pg', pg ('1', '0.1', '50', '0'), fixed (0.05, 99, 100));
  scenarios{end+1} = scenario ('pg_vector_amplitude', 'pg', pg ('[1 2]', '2', '25', '0'), fixed (0.25, 0, 4));
  scenarios{end+1} = scenario ('pg_negative_delay', 'pg', pg ('1', '2', '50', '-0.5'), fixed (0.25, 0, 4));
  scenarios{end+1} = scenario ('pg_width_0', 'pg', pg ('1', '2', '0', '0'), fixed (0.25, 0, 4));
  scenarios{end+1} = scenario ('pg_width_100', 'pg', pg ('1', '2', '100', '0'), fixed (0.25, 0, 4));
  p = pg ('1', '1', '50', '0.3'); p.Integrate = 'on';
  scenarios{end+1} = scenario ('pg_integral_ode45', 'pg', p, variable (1e-8, 1e-10, 0:0.5:10));
  % Simulink refuses a fixed step that does not divide the pulse timing.
  scenarios{end+1} = scenario ('pg_step_not_divisor', 'pg', pg ('1', '1', '50', '0'), fixed (0.3, 0, 3));

  % ---- Chirp Signal.
  scenarios{end+1} = scenario ('chirp_defaults', 'chirp', struct (), fixed (0.5, 0, 20));
  scenarios{end+1} = scenario ('chirp_custom', 'chirp', struct ('f1', '0.5', 'T', '2', 'f2', '1.5'), fixed (0.125, 0, 4));
  scenarios{end+1} = scenario ('chirp_vector', 'chirp', struct ('f1', '[0.1 0.5]', 'T', '5', 'f2', '[1 2]'), ...
      fixed (0.25, 0, 6));

  % ---- Mux / Demux.  Source specs: 'clock', 'sin', 'gain:[...]' (Clock
  % into a Gain) or a Constant value.
  scenarios{end+1} = scenario ('mux_three_scalars', 'mux', struct ('Inputs', '3', 'Sources', {{'clock', 'sin', '5'}}), ...
      fixed (0.25, 0, 2));
  scenarios{end+1} = scenario ('mux_widths', 'mux', struct ('Inputs', '[2 1]', 'Sources', {{'[1;2]', 'clock'}}), ...
      fixed (0.5, 0, 1));
  scenarios{end+1} = scenario ('mux_count_vector_input', 'mux', struct ('Inputs', '2', 'Sources', {{'[1;2]', '3'}}), ...
      fixed (0.5, 0, 1));
  scenarios{end+1} = scenario ('mux_five', 'mux', struct ('Inputs', '5', 'Sources', {{'1', '2', '3', '4', 'clock'}}), ...
      fixed (0.5, 0, 1));
  scenarios{end+1} = scenario ('demux_three', 'demux', struct ('Outputs', '3', 'Source', '[4;5;6]'), fixed (0.5, 0, 1));
  scenarios{end+1} = scenario ('demux_four_into_two', 'demux', struct ('Outputs', '2', 'Source', 'gain:[1;2;3;4]'), ...
      fixed (0.5, 0, 1));
  scenarios{end+1} = scenario ('demux_three_into_two', 'demux', struct ('Outputs', '2', 'Source', '[1;2;3]'), ...
      fixed (0.5, 0, 1));
  scenarios{end+1} = scenario ('demux_five_into_three', 'demux', struct ('Outputs', '3', 'Source', '[1;2;3;4;5]'), ...
      fixed (0.5, 0, 1));
  scenarios{end+1} = scenario ('demux_widths', 'demux', struct ('Outputs', '[1 3]', 'Source', 'gain:[1;2;3;4]'), ...
      fixed (0.5, 0, 1));
  scenarios{end+1} = scenario ('mux_demux_roundtrip', 'muxdemux', struct ('Inputs', '3', 'Outputs', '3', ...
      'Sources', {{'clock', 'sin', '5'}}), fixed (0.25, 0, 2));
  % Row-vector inputs: accepted by Simulink, a documented difference.
  scenarios{end+1} = scenario ('mux_row_input', 'mux', struct ('Inputs', '2', 'Sources', {{'[1 2]', '3'}}), ...
      fixed (0.5, 0, 1));
  scenarios{end+1} = scenario ('demux_row_input', 'demux', struct ('Outputs', '3', 'Source', '[1 2 3]'), ...
      fixed (0.5, 0, 1));

  % ---- Rate Transition: Clock -> [Zero-Order Hold at InRate] -> RT -> Out.
  rt = @(in, out, integrity, det) struct ('InRate', in, 'OutPortSampleTime', out, 'InitialCondition', '-9', ...
      'Integrity', integrity, 'Deterministic', det, 'Source', 'clock');
  modes = {'det', 'on', 'on'; 'nondet', 'on', 'off'; 'nointegrity', 'off', 'off'};
  rates = {'s2f', '0.5', '0.25', 0.25, 3; 's2f4', '1', '0.25', 0.25, 4; 'f2s', '0.25', '0.5', 0.25, 3; ...
           'c2d', '0', '0.5', 0.25, 3; 'equal', '0.5', '0.5', 0.25, 3};
  for r = 1:size (rates, 1)
    for m = 1:size (modes, 1)
      scenarios{end+1} = scenario (sprintf ('rt_%s_%s', rates{r, 1}, modes{m, 1}), 'rt', ...
          rt (rates{r, 2}, rates{r, 3}, modes{m, 2}, modes{m, 3}), fixed (rates{r, 4}, 0, rates{r, 5})); %#ok<AGROW>
    end
  end
  scenarios{end+1} = scenario ('rt_s2f_det_integrity_off', 'rt', rt ('0.5', '0.25', 'off', 'on'), fixed (0.25, 0, 3));
  for m = 1:size (modes, 1)
    scenarios{end+1} = scenario (['rt_offset_' modes{m, 1}], 'rt', ...
        rt ('[0.5 0.1]', '[0.25 0.05]', modes{m, 2}, modes{m, 3}), fixed (0.05, 0, 2)); %#ok<AGROW>
    scenarios{end+1} = scenario (['rt_noninteger_' modes{m, 1}], 'rt', ...
        rt ('0.5', '0.2', modes{m, 2}, modes{m, 3}), fixed (0.1, 0, 2)); %#ok<AGROW>
  end
  scenarios{end+1} = scenario ('rt_c2d_offset_det', 'rt', rt ('0', '[0.5 0.25]', 'on', 'on'), fixed (0.25, 0, 3));
  scenarios{end+1} = scenario ('rt_offset_det_integrity_off', 'rt', rt ('[0.5 0.1]', '[0.25 0.05]', 'off', 'on'), ...
      fixed (0.05, 0, 2));
  scenarios{end+1} = scenario ('rt_f2s_offset_nondet', 'rt', rt ('[0.25 0.1]', '[0.5 0.2]', 'on', 'off'), ...
      fixed (0.05, 0, 2));
  scenarios{end+1} = scenario ('rt_aligned_offset_nondet', 'rt', rt ('[0.5 0.25]', '0.25', 'on', 'off'), ...
      fixed (0.25, 0, 3));
  scenarios{end+1} = scenario ('rt_d2c_det', 'rt', rt ('0.5', '0', 'on', 'on'), fixed (0.25, 0, 2));
  p = rt ('0.5', '0.25', 'on', 'on'); p.Source = 'gain:[1;-2]'; p.InitialCondition = '[-9;-8]';
  scenarios{end+1} = scenario ('rt_vector_s2f_det', 'rt', p, fixed (0.25, 0, 2));
  p.Deterministic = 'off';
  scenarios{end+1} = scenario ('rt_vector_s2f_nondet', 'rt', p, fixed (0.25, 0, 2));
  % Output hits before the input's first hit (input offset larger than the
  % output offset): IC with Integrity on, 0 with it off.
  late = {'f2s_late', '[0.25 0.2]', '[0.5 0.1]', 0.05, 2; 'equal_late', '[0.5 0.25]', '0.5', 0.25, 2; ...
          'equal_both_late', '[0.5 0.3]', '[0.5 0.1]', 0.1, 2; 'noninteger_late', '[0.2 0.1]', '0.5', 0.1, 2; ...
          's2f_late', '[0.5 0.1]', '0.2', 0.1, 2};
  for r = 1:size (late, 1)
    for m = 2:3
      scenarios{end+1} = scenario (sprintf ('rt_%s_%s', late{r, 1}, modes{m, 1}), 'rt', ...
          rt (late{r, 2}, late{r, 3}, modes{m, 2}, modes{m, 3}), fixed (late{r, 4}, 0, late{r, 5})); %#ok<AGROW>
    end
  end
  % Scalar IC on a vector signal: Simulink expands it (Width tells the
  % Octave test the signal size; Simulink infers it).
  for m = 1:2
    p = rt ('0.5', '0.25', modes{m, 2}, modes{m, 3}); p.Source = 'gain:[1;-2]'; p.Width = '2';
    scenarios{end+1} = scenario (['rt_scalar_ic_vector_' modes{m, 1}], 'rt', p, fixed (0.25, 0, 1.5)); %#ok<AGROW>
  end
  p = rt ('[0.25 0.2]', '[0.5 0.1]', 'on', 'off'); p.Source = 'gain:[1;-2]'; p.Width = '2';
  scenarios{end+1} = scenario ('rt_scalar_ic_vector_late', 'rt', p, fixed (0.05, 0, 1));

  % ---- Integrator, Second-Order.
  scenarios{end+1} = scenario ('soi_constant', 'soi', struct ('Source', '2', 'ICX', '1', 'ICDXDT', '0'), ...
      fixed (0.5, 0, 2));
  scenarios{end+1} = scenario ('soi_sin', 'soi', struct ('Source', 'sin', 'ICX', '0.5', 'ICDXDT', '-1'), ...
      fixed (0.1, 0, 5));
  scenarios{end+1} = scenario ('soi_vector', 'soi', struct ('Source', '[1;-1]', 'ICX', '[1;2]', 'ICDXDT', '0.5'), ...
      fixed (0.25, 0, 2));
  scenarios{end+1} = scenario ('soi_defaults', 'soi', struct ('Source', 'sin'), fixed (0.25, 0, 2));
  % Scalar ICX/ICDXDT on a vector input expand to its width.
  scenarios{end+1} = scenario ('soi_scalar_ic_vector', 'soi', struct ('Source', '[1;-1]', 'ICX', '1', 'ICDXDT', '0', ...
      'Width', '2'), fixed (0.5, 0, 2));
  scenarios{end+1} = scenario ('soi_defaults_vector', 'soi', struct ('Source', 'gain:[1;-2]', 'Width', '2'), ...
      fixed (0.25, 0, 2));

  % ---- First-order filters: continuous Transfer Fcn and the discretized
  % Discrete State-Space realization, both driven by sin(t).
  tf = @(kind, tau, gain) struct ('kind', kind, 'tau', tau, 'gain', gain, 'Source', 'sin');
  scenarios{end+1} = scenario ('tf_lowpass', 'tf', tf ('lowpass', '0.5', '2'), fixed (0.1, 0, 5));
  scenarios{end+1} = scenario ('tf_highpass', 'tf', tf ('highpass', '0.5', '1'), fixed (0.1, 0, 5));
  scenarios{end+1} = scenario ('tf_leadlag', 'tf', tf ('leadlag', '[0.2 0.5]', '1.5'), fixed (0.1, 0, 5));
  p = tf ('lowpass', '0.5', '2'); p.Ts = '0.1'; p.method = 'zoh';
  scenarios{end+1} = scenario ('dss_lowpass_zoh', 'dss', p, fixed (0.1, 0, 3));
  p = tf ('leadlag', '[0.2 0.5]', '1.5'); p.Ts = '0.1'; p.method = 'tustin';
  scenarios{end+1} = scenario ('dss_leadlag_tustin', 'dss', p, fixed (0.1, 0, 3));
  p = tf ('highpass', '0.5', '1'); p.Ts = '0.2'; p.method = 'zoh';
  scenarios{end+1} = scenario ('dss_highpass_zoh', 'dss', p, fixed (0.1, 0, 3));
end

function s = scenario (id, model, parameters, solver)
  s = solver;
  s.id = id; s.model = model; s.parameters = parameters;
end

function s = fixed (step, start, stop)
  s = struct ('solver', 'ode4', 'fixed_step', step, 'reltol', [], 'abstol', [], ...
              'start_time', start, 'stop_time', stop, 'output_times', []);
end

function s = variable (reltol, abstol, times)
  s = struct ('solver', 'ode45', 'fixed_step', [], 'reltol', reltol, 'abstol', abstol, ...
              'start_time', times(1), 'stop_time', times(end), 'output_times', times);
end

function c = run_case (s)
  name = ['rob_' s.id];
  if bdIsLoaded (name), close_system (name, 0); end
  new_system (name);
  cleanup = onCleanup (@() close_system (name, 0));
  c = rmfield (s, 'id');
  c.ok = false; c.error = ''; c.warnings = {}; c.t = []; c.y = {}; c.matrices = struct ();
  try
    c.matrices = build (name, s.model, s.parameters);
    set_param (name, 'StartTime', num2str (s.start_time, 17), 'StopTime', num2str (s.stop_time, 17), ...
               'SaveOutput', 'on', 'SaveTime', 'on', 'SaveFormat', 'StructureWithTime', ...
               'ReturnWorkspaceOutputs', 'on', 'EnableMultiTasking', 'off');
    if strcmp (s.solver, 'ode4')
      set_param (name, 'SolverType', 'Fixed-step', 'Solver', 'ode4', 'FixedStep', num2str (s.fixed_step, 17));
    else
      set_param (name, 'SolverType', 'Variable-step', 'Solver', 'ode45', ...
                 'RelTol', num2str (s.reltol, 17), 'AbsTol', num2str (s.abstol, 17), ...
                 'OutputOption', 'SpecifiedOutputTimes', 'OutputTimes', mat2str (s.output_times, 17));
    end
    [~, ~] = lastwarn ('');
    out = sim (name);
    [message, ~] = lastwarn ();
    if ~isempty (message), c.warnings = {message}; end
    c.t = out.tout(:)';
    signals = out.yout.signals;
    for k = 1:numel (signals)
      v = signals(k).values;
      if ndims (v) == 3
        v = reshape (permute (v, [3 1 2]), size (v, 3), []);
      end
      c.y{k} = v;
    end
    c.ok = true;
  catch err
    c.error = err.message;
    for k = 1:numel (err.cause), c.error = [c.error ' | ' err.cause{k}.message]; end
  end
end

function matrices = build (m, kind, p)
  matrices = struct ();
  switch kind
    case 'mps'
      data = p.Data;
      if isfield (p, 'Control')
        add_block ('simulink/Sources/Constant', [m '/ctl'], 'Value', p.Control);
      else
        add_block ('simulink/Sources/Clock', [m '/clk']);
        add_block ('simulink/Sources/Constant', [m '/offset'], 'Value', p.ControlOffset);
        add_block ('simulink/Math Operations/Add', [m '/ctl']);
        add_line (m, 'clk/1', 'ctl/1'); add_line (m, 'offset/1', 'ctl/2');
      end
      add_block ('simulink/Signal Routing/Multiport Switch', [m '/sw'], 'Inputs', p.Inputs, ...
                 'DataPortOrder', p.DataPortOrder, 'DataPortForDefault', p.DataPortForDefault, ...
                 'DiagnosticForDefault', p.DiagnosticForDefault);
      add_line (m, 'ctl/1', 'sw/1');
      for k = 1:numel (data)
        add_block ('simulink/Sources/Constant', sprintf ('%s/d%d', m, k), 'Value', data{k});
        add_line (m, sprintf ('d%d/1', k), sprintf ('sw/%d', k + 1));
      end
      output (m, 'sw/1', 1);
    case 'pg'
      add_block ('simulink/Sources/Pulse Generator', [m '/p']);
      set_some (m, 'p', p, {'Amplitude', 'Period', 'PulseWidth', 'PhaseDelay'});
      if strcmp (p.Integrate, 'on')
        add_block ('simulink/Continuous/Integrator', [m '/I']);
        add_line (m, 'p/1', 'I/1'); output (m, 'I/1', 1);
      else
        output (m, 'p/1', 1);
      end
    case 'chirp'
      add_block ('simulink/Sources/Chirp Signal', [m '/c']);
      set_some (m, 'c', p, {'f1', 'T', 'f2'});
      output (m, 'c/1', 1);
    case {'mux', 'muxdemux'}
      add_block ('simulink/Signal Routing/Mux', [m '/mx'], 'Inputs', p.Inputs);
      for k = 1:numel (p.Sources)
        add_line (m, [source(m, sprintf ('s%d', k), p.Sources{k}) '/1'], sprintf ('mx/%d', k));
      end
      if strcmp (kind, 'mux')
        output (m, 'mx/1', 1);
      else
        add_block ('simulink/Signal Routing/Demux', [m '/dm'], 'Outputs', p.Outputs);
        add_line (m, 'mx/1', 'dm/1');
        for k = 1:str2double (p.Outputs), output (m, sprintf ('dm/%d', k), k); end
      end
    case 'demux'
      add_block ('simulink/Signal Routing/Demux', [m '/dm'], 'Outputs', p.Outputs);
      add_line (m, [source(m, 's', p.Source) '/1'], 'dm/1');
      count = str2num (p.Outputs); %#ok<ST2NM>
      if ~isscalar (count), count = numel (count); end
      for k = 1:count, output (m, sprintf ('dm/%d', k), k); end
    case 'rt'
      src = source (m, 's', p.Source);
      add_block ('simulink/Signal Attributes/Rate Transition', [m '/rt'], 'OutPortSampleTime', p.OutPortSampleTime, ...
                 'InitialCondition', p.InitialCondition, 'Integrity', p.Integrity, 'Deterministic', p.Deterministic);
      if ~strcmp (p.InRate, '0')
        add_block ('simulink/Discrete/Zero-Order Hold', [m '/z'], 'SampleTime', p.InRate);
        add_line (m, [src '/1'], 'z/1'); add_line (m, 'z/1', 'rt/1');
      else
        add_line (m, [src '/1'], 'rt/1');
      end
      output (m, 'rt/1', 1);
    case 'soi'
      src = source (m, 's', p.Source);
      add_block ('simulink/Continuous/Integrator, Second-Order', [m '/i2']);
      set_some (m, 'i2', p, {'ICX', 'ICDXDT'});
      add_line (m, [src '/1'], 'i2/1');
      output (m, 'i2/1', 1); output (m, 'i2/2', 2);
    case 'tf'
      [num, den] = first_order (p);
      src = source (m, 's', p.Source);
      add_block ('simulink/Continuous/Transfer Fcn', [m '/f'], 'Numerator', mat2str (num, 17), ...
                 'Denominator', mat2str (den, 17));
      add_line (m, [src '/1'], 'f/1'); output (m, 'f/1', 1);
      matrices = struct ('num', num, 'den', den);
    case 'dss'
      [~, ~, A, B, C, D] = first_order (p);
      [Ad, Bd, Cd, Dd] = discretize (A, B, C, D, str2double (p.Ts), p.method);
      src = source (m, 's', p.Source);
      add_block ('simulink/Discrete/Discrete State-Space', [m '/f'], 'A', mat2str (Ad, 17), 'B', mat2str (Bd, 17), ...
                 'C', mat2str (Cd, 17), 'D', mat2str (Dd, 17), 'SampleTime', p.Ts);
      add_line (m, [src '/1'], 'f/1'); output (m, 'f/1', 1);
      matrices = struct ('A', Ad, 'B', Bd, 'C', Cd, 'D', Dd);
    otherwise
      error ('reference_ob_routing_builders: unknown model %s', kind);
  end
end

function set_some (m, block, p, names)
  for k = 1:numel (names)
    if isfield (p, names{k}), set_param ([m '/' block], names{k}, p.(names{k})); end
  end
end

function name = source (m, name, spec)
  % 'clock', 'sin', 'gain:[...]' (Clock into a Gain) or a Constant value.
  if strcmp (spec, 'clock')
    add_block ('simulink/Sources/Clock', [m '/' name]);
  elseif strcmp (spec, 'sin')
    add_block ('simulink/Sources/Sine Wave', [m '/' name]);
  elseif strncmp (spec, 'gain:', 5)
    add_block ('simulink/Sources/Clock', [m '/' name '_clk']);
    add_block ('simulink/Math Operations/Gain', [m '/' name], 'Gain', spec(6:end));
    add_line (m, [name '_clk/1'], [name '/1']);
  else
    add_block ('simulink/Sources/Constant', [m '/' name], 'Value', spec);
  end
end

function output (m, port, k)
  add_block ('simulink/Sinks/Out1', sprintf ('%s/y%d', m, k), 'Port', num2str (k));
  add_line (m, port, sprintf ('y%d/1', k));
end

function [num, den, A, B, C, D] = first_order (p)
  % H(s) = g/(tau s + 1), g tau s/(tau s + 1) or g (tz s + 1)/(tp s + 1),
  % realized with the lag state x' = (u - x)/tp.
  tau = str2num (p.tau); g = str2double (p.gain); %#ok<ST2NM>
  switch p.kind
    case 'lowpass',  num = g; den = [tau 1]; tp = tau; D = 0; C = g;
    case 'highpass', num = [g * tau 0]; den = [tau 1]; tp = tau; D = g; C = -g;
    case 'leadlag',  num = g * [tau(1) 1]; den = [tau(2) 1]; tp = tau(2); D = g * tau(1) / tau(2); C = g - D;
  end
  A = -1 / tp; B = 1 / tp;
end

function [Ad, Bd, Cd, Dd] = discretize (A, B, C, D, Ts, method)
  n = size (A, 1);
  switch method
    case 'zoh'
      E = expm ([A B; zeros(size (B, 2), n + size (B, 2))] * Ts);
      Ad = E(1:n, 1:n); Bd = E(1:n, n+1:end); Cd = C; Dd = D;
    case 'tustin'
      I = eye (n); M = I - A * Ts / 2;
      Ad = M \ (I + A * Ts / 2); Bd = M \ B * Ts;
      Cd = C / M; Dd = D + C / M * B * Ts / 2;
  end
end
