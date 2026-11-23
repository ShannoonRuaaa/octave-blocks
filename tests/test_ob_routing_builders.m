function test_ob_routing_builders (reference_file)
  test_path_cleanup = ob_test_setup ();
% TEST_OB_ROUTING_BUILDERS  Verify the routing, source and filter builders.
%   Covers ob_multiport_switch, ob_pulse_generator, ob_chirp, ob_mux,
%   ob_demux, ob_rate_transition, ob_second_order_integrator and
%   ob_first_order_filter with analytic expectations, invalid-input checks,
%   live Simulink traces recorded by
%   reference/reference_ob_routing_builders.m, a strict C99 ob_codegen
%   compile-and-compare case and an accelerated run per builder.
  if (nargin < 1)
    reference_file = ob_test_reference ('simulink-routing-builders-reference.json');
  endif
  ref = jsondecode (fileread (reference_file));
  C = ref.cases;
  checks = 0;
  compiled = {};

  % ---------------------------------------------------------- Multiport Switch
  lib = library (ref, 'simulink/Signal Routing/Multiport Switch');
  expect (str2double (lib.Inputs) == 3 && strcmp (lib.DataPortOrder, 'One-based contiguous') ...
          && strcmp (lib.DataPortForDefault, 'Last data port'), 'Multiport Switch library defaults changed');
  default_switch = ob_multiport_switch ();
  expect (sum (strcmp ({default_switch.blocks.type}, 'Inport')) == 4, 'default Multiport Switch has 3 data ports');
  for id = {'mps_onebased_none', 'mps_onebased_inrange', 'mps_zerobased_none', 'mps_additional_none', ...
            'mps_vector_none', 'mps_two_ports_warning', 'mps_vector_control'}
    c = C.(id{1});
    expect (c.ok, '%s: reference run failed', id{1});
    model = mps_model (c.parameters);
    compare_reference (id{1}, model, c, 0);
    checks += 1;
  endfor
  % Documented difference: Simulink's default DiagnosticForDefault 'Error'
  % stops the run; the builder routes the default (last) port instead.
  c = C.mps_onebased_error;
  expect (! c.ok && ! isempty (strfind (c.error, 'is not in between')), 'mps_onebased_error: Simulink should reject');
  t = 0:0.125:4.5;
  y = run_trace (mps_model (c.parameters), t);
  expect (all (y(t < 1) == 30) && all (y(t >= 4) == 30), 'mps_onebased_error: below-range control routes the last port');
  % Analytic: fractional control truncates toward zero, out of range and
  % negative control route the default port.
  ctrl = [1 1.5 1.99 2 2.7 3 3.9 4 -3 0.5 0];
  want = [10 10 10 20 20 30 30 30 30 30 30];
  expect (isequal (switch_values (ctrl, 3, 'one-based', 'last', [10 20 30]), want), 'one-based truncation');
  ctrl = [-1.5 -1 -0.5 0 0.99 1 2.5 3 7];
  want = [30 30 10 10 10 20 30 30 30];
  expect (isequal (switch_values (ctrl, 3, true, 'last', [10 20 30]), want), 'zero-based truncation');
  ctrl = [0.9 1 2.2 3.99 4 -2];
  want = [99 10 20 30 99 99];
  expect (isequal (switch_values (ctrl, 3, 'One-based contiguous', 'Additional data port', [10 20 30 99]), want), ...
          'additional default port');
  expect (isequal (switch_values ([1 2 1.5], 2, false, 'last', [-1 1]), [-1 1 -1]), 'two data ports');
  % Zero crossings place the switching instants exactly: the integral of
  % the output for control = t over [0, 4.5] is 30 + 10 + 20 + 1.5*30.
  zc = mps_model (struct ('Inputs', '3', 'DataPortOrder', 'One-based contiguous', ...
                          'DataPortForDefault', 'Last data port', 'ControlOffset', '0.05', ...
                          'Data', {{'10', '20', '30'}}));
  zc = integrate_output (zc);
  r = ob_run (zc, [0 4.5], struct ('solver', 'ode45', 'zero_crossings', true, 'reltol', 1e-9, 'abstol', 1e-12));
  got = ob_scope_data (r, numel (zc.blocks));
  expect (abs (got(end) - (30*0.95 + 10 + 20 + 30*1.55)) < 1e-6, 'Multiport Switch zero-crossing integral %.12g', got(end));
  y = run_trace (mps_model (C.mps_vector_none.parameters), [0 1.25 2]);
  expect (isequal (y, [5 6; 1 2; 3 4]), 'vector data');
  assert_error (@() run_trace (mps_nan_model (), [0 1]), 'finite');
  assert_error (@() ob_multiport_switch (1), 'ob_multiport_switch:');
  assert_error (@() ob_multiport_switch ('a'), 'ob_multiport_switch:');
  assert_error (@() ob_multiport_switch (Inf), 'ob_multiport_switch:');
  assert_error (@() ob_multiport_switch (2.5), 'ob_multiport_switch:');
  assert_error (@() ob_multiport_switch (3, 'Specify indices'), 'Specify indices');
  assert_error (@() ob_multiport_switch (3, 'yes'), 'ob_multiport_switch:');
  assert_error (@() ob_multiport_switch (3, [1 0]), 'ob_multiport_switch:');
  % Numbers are not order flags (1 would read as one-based); logicals are.
  assert_error (@() ob_multiport_switch (3, 1), 'logical scalar');
  assert_error (@() ob_multiport_switch (3, 0), 'logical scalar');
  expect (strcmp (ob_multiport_switch (3, true).blocks(2).name, 'data 0') ...
          && strcmp (ob_multiport_switch (3, false).blocks(2).name, 'data 1'), 'logical data_port_order');
  % Vector control selects element-wise, zero-based and out of range too.
  model = mps_model (struct ('Inputs', '3', 'DataPortOrder', 'Zero-based contiguous', 'Control', '[0;2.5;-3;7]', ...
                             'Data', {{'[10;11;12;13]', '[20;21;22;23]', '[30;31;32;33]'}}));
  expect (isequal (run_trace (model, [0 1])(1, :), [10 31 32 33]), 'zero-based vector control');
  assert_error (@() ob_multiport_switch (3, 1, 'first'), 'ob_multiport_switch:');
  assert_error (@() ob_multiport_switch (3, 1, 'last', 4), 'called with too many inputs');
  checks += 6;
  compiled{end+1} = {'mps_rk4', mps_model(C.mps_additional_none.parameters), [0 5 0.125], struct()};
  compiled{end+1} = {'mps_zc', zc, [0 4.5 0.25], struct('zero_crossings', true)};
  compiled{end+1} = {'mps_vector_control', model, [0 1 0.5], struct()};

  % ---------------------------------------------------------- Pulse Generator
  lib = library (ref, 'simulink/Sources/Pulse Generator');
  expect (strcmp (lib.PulseType, 'Time based') && str2double (lib.Period) == 10 ...
          && str2double (lib.PulseWidth) == 5 && str2double (lib.Amplitude) == 1 ...
          && str2double (lib.PhaseDelay) == 0, 'Pulse Generator library defaults changed');
  for id = {'pg_defaults', 'pg_a5_t2_w50_d1', 'pg_t01_w50', 'pg_t03_w33_d01', 'pg_late_t01_w50', ...
            'pg_vector_amplitude', 'pg_negative_delay'}
    c = C.(id{1});
    expect (c.ok, '%s: reference run failed', id{1});
    compare_reference (id{1}, source_model (pulse (c.parameters)), c, 0);
    checks += 1;
  endfor
  c = C.pg_integral_ode45;
  model = integrate_output (source_model (pulse (c.parameters)));
  r = ob_run (model, c.t, struct ('solver', 'ode45', 'zero_crossings', true, 'reltol', 1e-9, 'abstol', 1e-12));
  got = ob_scope_data (r, numel (model.blocks));
  want = reference_outputs (c){1};
  expect (max (abs (got - want)) < 1e-6, 'pg_integral_ode45: zero-crossing integral differs by %.3g', max (abs (got - want)));
  for id = {'pg_width_0', 'pg_width_100'}
    expect (! C.(id{1}).ok, '%s: Simulink should reject the pulse width', id{1});
  endfor
  assert_error (@() ob_pulse_generator (1, 2, 0), 'ob_pulse_generator:');
  assert_error (@() ob_pulse_generator (1, 2, 100), 'ob_pulse_generator:');
  % Documented difference: Simulink refuses a fixed step that does not
  % divide the pulse timing; the builder samples the pulse at the steps.
  c = C.pg_step_not_divisor;
  expect (! c.ok && ! isempty (strfind (c.error, 'integer multiple of the fixed step size')), ...
          'pg_step_not_divisor: Simulink should reject the step');
  y = run_trace (source_model (pulse (c.parameters)), 0:0.3:3, struct ('solver', 'rk4'));
  expect (isequal (y', [1 1 0 0 1 0 0 1 1 0 1]), 'pulse sampled at a non-dividing fixed step');
  % Edges on a decimal grid over a long run: T = 0.1, 50 %, t = k*0.05.
  t = (0:1000) * 0.05;
  y = run_trace (source_model (ob_pulse_generator (1, 0.1, 50)), t);
  expect (isequal (y', double (mod (0:1000, 2) == 0)), 'pulse edges on a decimal grid');
  t = 0:0.1:3;
  y = run_trace (source_model (ob_pulse_generator (2, 0.3, 100/3, 0.1)), t);
  k = round ((t - 0.1) / 0.3 * 3);
  expect (isequal (y', 2 * double (t >= 0.1 - 1e-12 & mod (k, 3) == 0)), 'pulse T = 0.3');
  assert_error (@() ob_pulse_generator ('a'), 'ob_pulse_generator:');
  assert_error (@() ob_pulse_generator (1, 0), 'ob_pulse_generator:');
  assert_error (@() ob_pulse_generator (1, -1), 'ob_pulse_generator:');
  assert_error (@() ob_pulse_generator (1, 1, 50, Inf), 'ob_pulse_generator:');
  assert_error (@() ob_pulse_generator (1, [1 2]), 'ob_pulse_generator:');
  assert_error (@() ob_pulse_generator (1, 1, 50, 0, 1), 'called with too many inputs');
  checks += 4;
  compiled{end+1} = {'pulse_zc', model, [0 10 0.1], struct('zero_crossings', true)};
  compiled{end+1} = {'pulse_vector', source_model(pulse(C.pg_vector_amplitude.parameters)), [0 4 0.05], struct()};

  % ---------------------------------------------------------- Chirp Signal
  lib = library (ref, 'simulink/Sources/Chirp Signal');
  expect (str2double (lib.f1) == 0.1 && str2double (lib.T) == 100 && str2double (lib.f2) == 1, ...
          'Chirp Signal library defaults changed');
  for id = {'chirp_defaults', 'chirp_custom', 'chirp_vector'}
    c = C.(id{1});
    expect (c.ok, '%s: reference run failed', id{1});
    compare_reference (id{1}, source_model (chirp (c.parameters)), c, 1e-12);
    checks += 1;
  endfor
  t = (0:0.05:30)';
  y = run_trace (source_model (ob_chirp (0.5, 2, 1.5)), t);
  expect (max (abs (y - sin (2*pi*(0.5*t + 0.25*t.^2)))) < 1e-12, 'chirp analytic');
  y = run_trace (source_model (ob_chirp ([0.1; 0.2], 4, 1)), t);
  want = [sin(2*pi*(0.1*t + 0.9/8*t.^2)) sin(2*pi*(0.2*t + 0.8/8*t.^2))];
  expect (max (abs (y(:) - want(:))) < 1e-12, 'chirp vector parameters');
  assert_error (@() ob_chirp (0.1, 0), 'ob_chirp:');
  assert_error (@() ob_chirp (0.1, -1), 'ob_chirp:');
  assert_error (@() ob_chirp ('a'), 'ob_chirp:');
  assert_error (@() ob_chirp ([1 2], 1, [1 2 3]), 'same length');
  assert_error (@() ob_chirp (0.1, 1, NaN), 'ob_chirp:');
  assert_error (@() ob_chirp (0.1, 100, 1, 2), 'called with too many inputs');
  checks += 3;
  compiled{end+1} = {'chirp', source_model(chirp(C.chirp_vector.parameters)), [0 6 0.05], struct()};

  % ---------------------------------------------------------- Mux / Demux
  for name = {'simulink/Signal Routing/Mux', 'simulink/Commonly Used Blocks/Mux'}
    expect (str2double (library (ref, name{1}).Inputs) == 2, 'Mux library default changed');
  endfor
  for name = {'simulink/Signal Routing/Demux', 'simulink/Commonly Used Blocks/Demux'}
    expect (str2double (library (ref, name{1}).Outputs) == 2, 'Demux library default changed');
  endfor
  mux_args = struct ('mux_three_scalars', {{3}}, 'mux_widths', {{[2 1]}}, ...
                     'mux_count_vector_input', {{2, [2 1]}}, 'mux_five', {{5}});
  for id = fieldnames (mux_args)'
    c = C.(id{1});
    expect (c.ok, '%s: reference run failed', id{1});
    compare_reference (id{1}, routed_model (c.parameters.Sources, ob_mux (mux_args.(id{1}){:}), 1), c, 1e-12);
    checks += 1;
  endfor
  demux_args = struct ('demux_three', {{3}}, 'demux_four_into_two', {{2, 4}}, 'demux_three_into_two', {{2, 3}}, ...
                       'demux_five_into_three', {{3, 5}}, 'demux_widths', {{[1 3]}});
  for id = fieldnames (demux_args)'
    c = C.(id{1});
    expect (c.ok, '%s: reference run failed', id{1});
    dut = ob_demux (demux_args.(id{1}){:});
    compare_reference (id{1}, routed_model ({c.parameters.Source}, dut, numel (reference_outputs (c))), c, 1e-12);
    checks += 1;
  endfor
  c = C.mux_demux_roundtrip;
  roundtrip = routed_model (c.parameters.Sources, chain_subsystems (ob_mux (3), ob_demux (3)), 3);
  compare_reference ('mux_demux_roundtrip', roundtrip, c, 1e-12);
  y = run_trace (routed_model ({'[1;2]', '3', 'gain:[4;5;6]'}, ob_mux ([2 1 3]), 1), [0 1]);
  expect (isequal (y, [1 2 3 0 0 0; 1 2 3 4 5 6]), 'mux widths [2 1 3]');
  model = routed_model ({'gain:[1;2;3;4;5;6;7]'}, ob_demux ([3 4]), 2);
  r = ob_run (model, [0 2]);
  expect (isequal (ob_scope_data (r, 4), [0 0 0; 2 4 6]) && isequal (ob_scope_data (r, 5), [0 0 0 0; 8 10 12 14]), ...
          'demux widths [3 4]');
  big = routed_model (arrayfun (@(k) num2str (k), 1:7, 'uniformoutput', false), ob_mux (7), 1);
  expect (isequal (run_trace (big, [0 1])(end, :), 1:7), 'mux of 7 inputs');
  assert_error (@() run_trace (routed_model ({'[1;2]', '3'}, ob_mux (2), 1), [0 1]), 'nonconformant');
  % Documented difference: Simulink accepts row-vector inputs (recorded);
  % the builders need columns and fail with the Gain dimension error.
  c = C.mux_row_input;
  expect (c.ok && isequal (reference_outputs (c){1}(1, :), [1 2 3]), 'mux_row_input: Simulink accepts a row');
  assert_error (@() run_trace (routed_model (c.parameters.Sources, ob_mux (2, [2 1]), 1), [0 1]), 'nonconformant');
  c = C.demux_row_input;
  expect (c.ok && isequal (reference_outputs (c){1}(1), 1), 'demux_row_input: Simulink accepts a row');
  assert_error (@() run_trace (routed_model ({c.parameters.Source}, ob_demux (3), 3), [0 1]), 'nonconformant');
  assert_error (@() ob_mux (0), 'ob_mux:');
  assert_error (@() ob_mux ('a'), 'ob_mux:');
  assert_error (@() ob_mux (2.5), 'ob_mux:');
  assert_error (@() ob_mux (2, [1 1 1]), 'one entry per input');
  assert_error (@() ob_mux ([2 1], [2 1]), 'not both');
  assert_error (@() ob_mux ([2 -1]), 'ob_mux:');
  assert_error (@() ob_demux (0), 'ob_demux:');
  assert_error (@() ob_demux (3, 2), 'at least the number of outputs');
  assert_error (@() ob_demux ([1 3], 5), 'must equal sum');
  assert_error (@() ob_demux (2, 'a'), 'ob_demux:');
  checks += 5;
  compiled{end+1} = {'mux_demux', routed_model({'clock', 'sin', 'gain:[2;3]'}, ...
                                                chain_subsystems(ob_mux([1 1 2]), ob_demux([3 1])), 2), ...
                     [0 2 0.1], struct('zero_crossings', true)};

  % ---------------------------------------------------------- Rate Transition
  lib = library (ref, 'simulink/Signal Attributes/Rate Transition');
  expect (strcmp (lib.Integrity, 'on') && strcmp (lib.Deterministic, 'on') ...
          && str2double (lib.InitialCondition) == 0, 'Rate Transition library defaults changed');
  ids = fieldnames (C)';
  ids = ids(strncmp (ids, 'rt_', 3));
  for id = ids
    c = C.(id{1});
    p = c.parameters;
    if (! c.ok)
      % Simulink rejects deterministic transfer with offsets or with
      % periods that are not integer multiples, and so does the builder.
      expect (! isempty (strfind (c.error, 'Ensure deterministic data transfer')), '%s: unexpected Simulink error', id{1});
      assert_error (@() rate_model (p), 'deterministic = false');
    elseif (str2num (p.OutPortSampleTime)(1) == 0)
      % Documented difference: discrete to continuous is rejected.
      assert_error (@() rate_model (p), 'not supported');
    else
      compare_reference (id{1}, rate_model (p), c, 1e-12);
    endif
    checks += 1;
  endfor
  % Analytic: slow (0.75) to fast (0.25), deterministic and integrity-only.
  slow = rate_model (struct ('InRate', '0.75', 'OutPortSampleTime', '0.25', 'InitialCondition', '5', ...
                             'Integrity', 'on', 'Deterministic', 'on', 'Source', 'clock'));
  t = 0:0.25:3;
  expect (isequal (run_trace (slow, t)', [5 5 5 0 0 0 0.75 0.75 0.75 1.5 1.5 1.5 2.25]), 'deterministic 0.75 -> 0.25');
  slow = rate_model (struct ('InRate', '0.75', 'OutPortSampleTime', '0.25', 'InitialCondition', '5', ...
                             'Integrity', 'on', 'Deterministic', 'off', 'Source', 'clock'));
  expect (isequal (run_trace (slow, t)', [5 0 0 0 0.75 0.75 0.75 1.5 1.5 1.5 2.25 2.25 2.25]), ...
          'integrity-only 0.75 -> 0.25');
  % Integrity off ignores the deterministic flag: the current slow sample
  % is visible on a simultaneous hit, with no extra slow-period delay.
  unprotected = struct ('InRate', '0.75', 'OutPortSampleTime', '0.25', 'InitialCondition', '5', ...
                        'Integrity', 'off', 'Deterministic', 'on', 'Source', 'clock');
  want_unprotected = [0 0 0 0.75 0.75 0.75 1.5 1.5 1.5 2.25 2.25 2.25 3];
  expect (isequal (run_trace (rate_model (unprotected), t)', want_unprotected), ...
          'integrity off uses the current sample');
  unprotected.Deterministic = 'off';
  expect (isequal (run_trace (rate_model (unprotected), t)', want_unprotected), ...
          'deterministic flag has no effect without integrity');
  % Analytic: output hits before the input's first hit show IC with
  % Integrity on (fast [0.25 0.2] to slow [0.5 0.1]) and 0 with it off.
  late = struct ('InRate', '[0.25 0.2]', 'OutPortSampleTime', '[0.5 0.1]', 'InitialCondition', '-9', ...
                 'Integrity', 'on', 'Deterministic', 'off', 'Source', 'clock');
  t = 0:0.05:1.2;
  want = [0 0 -9*ones(1, 10) 0.45*ones(1, 10) 0.95 0.95 0.95];
  expect (max (abs (run_trace (rate_model (late), t)' - want)) < 1e-12, 'late input with integrity');
  late.Integrity = 'off';
  want(want == -9) = 0;
  expect (max (abs (run_trace (rate_model (late), t)' - want)) < 1e-12, 'late input without integrity');
  expect (numel (ob_rate_transition ([0.25 0.2], [0.5 0.1], -9, false).blocks) == 4, ...
          'late input adds an input-rate sample');
  expect (numel (ob_rate_transition ([0.25 0.1], [0.5 0.2], -9, false).blocks) == 3, ...
          'no input-rate sample when the input hits first');
  % SIZE expands a scalar IC (Simulink's expansion to the signal width).
  model = ob_rate_transition (0.5, 0.25, -9, true, true, 2);
  expect (isequal (model.blocks(2).value, [-9; -9]), 'signal_size expands IC');
  expect (isequal (ob_rate_transition (0.5, 0.25, 1, false, true, [2 3]).blocks(2).value, ones (2, 3)), ...
          'signal_size [rows cols]');
  assert_error (@() ob_rate_transition (0.5, 0.25, [1; 2], true, true, 3), 'signal_size is 3x1');
  assert_error (@() ob_rate_transition (0.5, 0.25, 0, true, true, 0), 'ob_rate_transition:');
  assert_error (@() ob_rate_transition (0.5, 0.25, 0, true, true, [1 2 3]), 'width n or');
  assert_error (@() ob_rate_transition (0.5, 0.25, 0, true, true, 1.5), 'ob_rate_transition:');
  model = ob_rate_transition (1, 0.25, 0, false);
  expect (numel (model.blocks) == 4, 'integrity-only transfer on a common base needs no output hold');
  expect (strcmp (ob_rate_transition (0, 0.5).blocks(2).type, 'Rate Transition'), 'continuous input is a hold');
  assert_error (@() ob_rate_transition (0.5, 0), 'not supported');
  assert_error (@() ob_rate_transition (0.5, -1), 'inherited');
  assert_error (@() ob_rate_transition (-1, 0.5), 'inherited');
  assert_error (@() ob_rate_transition (0.5, [0.25 0.3]), 'offset');
  assert_error (@() ob_rate_transition (0.5, 0.25, 'x'), 'ob_rate_transition:');
  assert_error (@() ob_rate_transition (0.5, 0.25, 0, 'yes'), 'logical scalar');
  assert_error (@() ob_rate_transition (0.5, 0.25, 0, true, [1 1]), 'logical scalar');
  assert_error (@() ob_rate_transition (0.5), 'supply input_rate');
  assert_error (@() ob_rate_transition (pi, 0.25, 0, false), 'common base period');
  % Integrity off ignores Deterministic, offsets included (recorded).
  ob_rate_transition ([0.5 0.1], [0.25 0.05], 0, true, false);
  checks += 3;
  compiled{end+1} = {'rate_det', rate_model(C.rt_vector_s2f_det.parameters), [0 2 0.25], struct()};
  compiled{end+1} = {'rate_integrity', rate_model(C.rt_offset_nondet.parameters), [0 2 0.05], struct()};
  compiled{end+1} = {'rate_hold', integrate_output(rate_model(C.rt_c2d_nondet.parameters)), [0 3 0.1], struct()};
  compiled{end+1} = {'rate_late_ic', rate_model(C.rt_scalar_ic_vector_late.parameters), [0 1 0.05], struct()};
  compiled{end+1} = {'rate_unprotected_s2f', rate_model(unprotected), [0 3 0.25], struct()};
  compiled{end+1} = {'rate_unprotected_f2s', rate_model(C.rt_f2s_nointegrity.parameters), [0 2 0.05], struct()};

  % ---------------------------------------------------------- Integrator, Second-Order
  lib = library (ref, 'simulink/Continuous/Integrator, Second-Order');
  expect (strcmp (lib.ShowOutput, 'both') && str2double (lib.ICX) == 0 && str2double (lib.ICDXDT) == 0 ...
          && strcmp (lib.ExternalReset, 'none') && strcmp (lib.LimitX, 'off'), ...
          'Integrator, Second-Order library defaults changed');
  for id = {'soi_constant', 'soi_sin', 'soi_vector', 'soi_defaults', 'soi_scalar_ic_vector', 'soi_defaults_vector'}
    c = C.(id{1});
    p = c.parameters;
    args = {};
    if (isfield (p, 'ICX')), args = {str2num(p.ICX), str2num(p.ICDXDT)}; endif
    if (isfield (p, 'Width'))
      % Simulink expands scalar ICs to the input width; SIZE does it here.
      args(end+1:2) = {0};
      args{3} = str2double (p.Width);
    endif
    model = routed_model ({p.Source}, ob_second_order_integrator (args{:}), 2);
    compare_reference (id{1}, model, c, 1e-12);
    checks += 1;
  endfor
  t = 0:0.25:3;
  r = ob_run (routed_model ({'2'}, ob_second_order_integrator (1, 0), 2), t, struct ('solver', 'rk4'));
  expect (max (abs (ob_scope_data (r, 3) - (1 + t'.^2))) < 1e-12 && max (abs (ob_scope_data (r, 4) - 2*t')) < 1e-12, ...
          'second-order integrator analytic');
  model = ob_second_order_integrator ([1 2; 3 4], 0);
  expect (isequal (model.blocks(2).value, zeros (2)), 'scalar dxdt0 expands');
  assert_error (@() ob_second_order_integrator ([1 2], [1 2 3]), 'same shape');
  assert_error (@() ob_second_order_integrator ('a'), 'ob_second_order_integrator:');
  assert_error (@() ob_second_order_integrator (Inf), 'ob_second_order_integrator:');
  assert_error (@() ob_second_order_integrator (0, 0, 0), 'ob_second_order_integrator:');
  assert_error (@() ob_second_order_integrator (0, 0, [1 2 3]), 'width n or');
  assert_error (@() ob_second_order_integrator ([1; 2], 0, 3), 'to match signal_size');
  assert_error (@() ob_second_order_integrator (0, 0, 2, 1), 'called with too many inputs');
  model = ob_second_order_integrator (0, 0, [2 2]);
  expect (isequal (model.blocks(2).value, zeros (2)) && isequal (model.blocks(3).value, zeros (2)), ...
          'signal_size expands the defaults');
  % Without SIZE a vector input fails with the engine's state-shape error.
  assert_error (@() run_trace (routed_model ({'[1;-1]'}, ob_second_order_integrator (), 2), [0 1]), 'shape');
  checks += 3;
  compiled{end+1} = {'second_order', routed_model({'gain:[1;-1]'}, ob_second_order_integrator([1; 2], 0.5), 2), ...
                     [0 5 0.1], struct()};
  compiled{end+1} = {'second_order_ode45', routed_model({'sin'}, ob_second_order_integrator(0.5, -1), 2), ...
                     [0 5 0.1], struct('solver', 'ode45')};
  compiled{end+1} = {'second_order_size', routed_model({'gain:[1;-2]'}, ob_second_order_integrator(1, 0, 2), 2), ...
                     [0 2 0.25], struct()};

  % ---------------------------------------------------------- First-order filter
  for id = {'tf_lowpass', 'tf_highpass', 'tf_leadlag', 'dss_lowpass_zoh', 'dss_leadlag_tustin', 'dss_highpass_zoh'}
    c = C.(id{1});
    compare_reference (id{1}, routed_model ({'sin'}, filter_model (c.parameters), 1), c, 1e-9);
    checks += 1;
  endfor
  t = (0:0.1:3)';
  step = struct ('type', 'Step', 'value', [0 0 1]);
  opts = struct ('solver', 'ode45', 'reltol', 1e-10, 'abstol', 1e-12);
  y = run_trace (routed_model ({step}, ob_first_order_filter ('lowpass', 0.5, 2), 1), t, opts);
  expect (max (abs (y - 2*(1 - exp (-2*t)))) < 1e-7, 'lowpass step');
  y = run_trace (routed_model ({step}, ob_first_order_filter ('highpass', 0.5, 2), 1), t, opts);
  expect (max (abs (y - 2*exp (-2*t))) < 1e-7, 'highpass step');
  y = run_trace (routed_model ({step}, ob_first_order_filter ('leadlag', [0.2 0.5], 1), 1), t, opts);
  expect (max (abs (y - (1 - 0.6*exp (-2*t)))) < 1e-7, 'leadlag step');
  y = run_trace (routed_model ({step}, ob_first_order_filter ('lowpass', 0.5, 2, 0.1), 1), t);
  expect (max (abs (y - 2*(1 - exp (-2*t)))) < 1e-12, 'zoh lowpass step (exact at the samples)');
  for method = {'zoh', 'tustin'}
    y = run_trace (routed_model ({'3'}, ob_first_order_filter ('leadlag', [0.2 0.5], 2, 0.1, method{1}, 3), 1), t);
    expect (max (abs (y - 6)) < 1e-12, '%s: x0 = u0 starts in steady state', method{1});
  endfor
  y = run_trace (routed_model ({'3'}, ob_first_order_filter ('highpass', 0.5, 1, 0, 'zoh', 3), 1), t, opts);
  expect (max (abs (y)) < 1e-9, 'continuous x0 = u0 steady state');
  model = ob_first_order_filter ('lowpass', 0.5, 1, 0.2, 'zoh', 0, 0.1);
  expect (isequal (model.sample_times(model.sample_times(:, 1) > 0, :)(1, :), [0.2 0.1]), 'discrete offset');
  assert_error (@() ob_first_order_filter (1, 0.5), 'kind must be');
  assert_error (@() ob_first_order_filter ('bandpass', 0.5), 'kind must be');
  assert_error (@() ob_first_order_filter ('lowpass', -1), 'ob_first_order_filter:');
  assert_error (@() ob_first_order_filter ('lowpass', [1 2]), 'ob_first_order_filter:');
  assert_error (@() ob_first_order_filter ('leadlag', [1 0]), 'tp > 0');
  assert_error (@() ob_first_order_filter ('lowpass', 1, 1, 0.1, 'euler'), 'method must be');
  assert_error (@() ob_first_order_filter ('lowpass', 1, 1, 0.1, 'zoh', 'a'), 'ob_first_order_filter:');
  assert_error (@() ob_first_order_filter ('lowpass', 1, 1, 0, 'zoh', 0, 0.1), 'positive Ts');
  assert_error (@() ob_first_order_filter ('lowpass', 1, 1, 0.1, 'zoh', 0, 0.1), 'offset must');
  checks += 6;
  compiled{end+1} = {'filter_continuous', routed_model({'sin'}, ob_first_order_filter('leadlag', [0.2 0.5], 1.5), 1), ...
                     [0 5 0.1], struct()};
  compiled{end+1} = {'filter_tustin', routed_model({'sin'}, ob_first_order_filter('highpass', 0.5, 1, 0.2, 'tustin', 1), 1), ...
                     [0 3 0.1], struct()};

  % ---------------------------------------------------------- C export and acceleration
  directory = fullfile (fileparts (mfilename ('fullpath')), '.artifacts', 'routing-builders');
  if (! exist (directory, 'dir')), mkdir (directory); endif
  gcc = find_gcc ();
  for k = 1:numel (compiled)
    [name, model, config, options] = compiled{k}{:};
    if (isempty (gcc))
      fprintf ('  %s: gcc not found, C export compile skipped\n', name);
    else
      c_compare (gcc, directory, name, model, config, options);
    endif
    if (isempty (getenv ('OB_SKIP_ACCELERATOR')))
      accelerated_compare (name, model, ob_time_grid (config(1), config(2), config(3)), options);
      fprintf ('  %-20s C export and accelerated run match ob_run\n', name);
      checks += 2;
    else
      fprintf ('  %-20s C export matches ob_run (accelerator skipped)\n', name);
      checks += 1;
    endif
  endfor
  fprintf ('routing builders: %d checks passed (%d C export cases)\n', checks, numel (compiled));
endfunction

% ============================================================ model builders

function model = mps_model (p)
  % Time + ControlOffset -> control; Constant data -> data ports.
  data = p.Data;
  if (! iscell (data)), data = num2cell (data); endif
  order = 'One-based contiguous';
  if (isfield (p, 'DataPortOrder')), order = p.DataPortOrder; endif
  default = 'Last data port';
  if (isfield (p, 'DataPortForDefault')), default = p.DataPortForDefault; endif
  dut = ob_multiport_switch (str2double (p.Inputs), order, default);
  m = ob_builder_block ();
  if (isfield (p, 'Control'))
    % A constant (possibly vector) control.
    [m, ctrl] = ob_builder_block (m, 'Constant', str2num (p.Control), 'control', 0.2, 0.8);
  else
    [m, t] = ob_builder_block (m, 'Time', [], 't', 0.05, 0.9);
    [m, c] = ob_builder_block (m, 'Constant', str2double (p.ControlOffset), 'offset', 0.05, 0.75);
    [m, ctrl] = ob_builder_block (m, 'Sum', [], 'control', 0.2, 0.8, [t c]);
  endif
  ids = ctrl;
  for k = 1:numel (data)
    value = data{k};
    if (ischar (value)), value = str2num (value); endif
    [m, ids(end+1)] = ob_builder_block (m, 'Constant', value, sprintf ('d%d', k), 0.2, 0.6 - 0.1 * k);
  endfor
  [m, d] = ob_builder_block (m, 'Subsystem', dut, 'Multiport Switch', 0.5, 0.5, ids);
  m = ob_builder_block (m, 'Scope', [], 'y', 0.9, 0.5, d);
  model = rmfield (m, 'execution');
endfunction

function model = mps_nan_model ()
  m = ob_builder_block ();
  [m, c] = ob_builder_block (m, 'Constant', NaN, 'nan', 0.1, 0.8);
  [m, a] = ob_builder_block (m, 'Constant', 1, 'a', 0.1, 0.5);
  [m, b] = ob_builder_block (m, 'Constant', 2, 'b', 0.1, 0.2);
  [m, d] = ob_builder_block (m, 'Subsystem', ob_multiport_switch (2), 'Multiport Switch', 0.5, 0.5, [c a b]);
  m = ob_builder_block (m, 'Scope', [], 'y', 0.9, 0.5, d);
  model = rmfield (m, 'execution');
endfunction

function values = switch_values (ctrl, n, order, default, data)
  % Evaluate the switch for constant controls.
  values = zeros (size (ctrl));
  for k = 1:numel (ctrl)
    dut = ob_multiport_switch (n, order, default);
    m = ob_builder_block ();
    [m, c] = ob_builder_block (m, 'Constant', ctrl(k), 'control', 0.1, 0.9);
    ids = c;
    for j = 1:numel (data)
      [m, ids(end+1)] = ob_builder_block (m, 'Constant', data(j), sprintf ('d%d', j), 0.1, 0.8 - 0.1 * j);
    endfor
    [m, d] = ob_builder_block (m, 'Subsystem', dut, 'Multiport Switch', 0.5, 0.5, ids);
    m = ob_builder_block (m, 'Scope', [], 'y', 0.9, 0.5, d);
    values(k) = run_trace (rmfield (m, 'execution'), [0 1])(1);
  endfor
endfunction

function dut = pulse (p)
  args = {};
  names = {'Amplitude', 'Period', 'PulseWidth', 'PhaseDelay'};
  for k = 1:numel (names)
    if (! isfield (p, names{k})), break; endif
    args{end+1} = str2num (p.(names{k}));
  endfor
  dut = ob_pulse_generator (args{:});
endfunction

function dut = chirp (p)
  args = {};
  names = {'f1', 'T', 'f2'};
  for k = 1:numel (names)
    if (! isfield (p, names{k})), break; endif
    args{end+1} = str2num (p.(names{k}));
  endfor
  dut = ob_chirp (args{:});
endfunction

function dut = filter_model (p)
  if (isfield (p, 'Ts'))
    dut = ob_first_order_filter (p.kind, str2num (p.tau), str2double (p.gain), str2double (p.Ts), p.method);
  else
    dut = ob_first_order_filter (p.kind, str2num (p.tau), str2double (p.gain));
  endif
endfunction

function model = rate_model (p)
  % Time -> [native Rate Transition hold at InRate, the Zero-Order Hold of
  % the producer] -> ob_rate_transition -> Scope.
  % A Width field gives the signal size for a scalar IC (Simulink infers it).
  in_rate = str2num (p.InRate);
  ic = str2num (p.InitialCondition);
  width = [];
  if (isfield (p, 'Width'))
    width = str2double (p.Width);
    ic = repmat (ic, width, 1);   % the upstream hold's shape
  endif
  dut = ob_rate_transition (in_rate, str2num (p.OutPortSampleTime), str2num (p.InitialCondition), ...
                            strcmp (p.Deterministic, 'on'), strcmp (p.Integrity, 'on'), width);
  m = ob_builder_block ();
  [m, s] = add_source (m, p.Source, 1);
  rates = zeros (numel (m.blocks), 2);
  if (in_rate(1) > 0)
    [m, s] = ob_builder_block (m, 'Rate Transition', zeros (size (ic)), 'Zero-Order Hold', 0.3, 0.5, s);
    rates(s, :) = [in_rate 0](1:2);
  endif
  [m, d] = ob_builder_block (m, 'Subsystem', dut, 'Rate Transition', 0.6, 0.5, s);
  m = ob_builder_block (m, 'Scope', [], 'y', 0.9, 0.5, d);
  rates(end+1:numel (m.blocks), :) = 0;
  m.sample_times = rates;
  model = rmfield (m, 'execution');
endfunction

function model = source_model (dut)
  m = ob_builder_block ();
  [m, d] = ob_builder_block (m, 'Subsystem', dut, 'DUT', 0.4, 0.5);
  m = ob_builder_block (m, 'Scope', [], 'y', 0.8, 0.5, d);
  model = rmfield (m, 'execution');
endfunction

function model = routed_model (sources, dut, outputs)
  % Source specs ('clock', 'sin', 'gain:[...]', a block struct or a
  % Constant value string) -> DUT -> one Scope per DUT output.
  m = ob_builder_block ();
  ids = [];
  for k = 1:numel (sources)
    [m, ids(end+1)] = add_source (m, sources{k}, k);
  endfor
  [m, d] = ob_builder_block (m, 'Subsystem', dut, 'DUT', 0.5, 0.5, ids);
  for k = 1:outputs
    [m, s] = ob_builder_block (m, 'Scope', [], sprintf ('y%d', k), 0.9, 0.9 - 0.1 * k);
    m.edges(end+1, :) = [d k s 1];
  endfor
  model = rmfield (m, 'execution');
endfunction

function [m, id] = add_source (m, spec, k)
  y = 0.9 - 0.12 * k;
  if (isstruct (spec))
    [m, id] = ob_builder_block (m, spec.type, spec.value, sprintf ('s%d', k), 0.1, y);
  elseif (strcmp (spec, 'clock'))
    [m, id] = ob_builder_block (m, 'Time', [], sprintf ('t%d', k), 0.1, y);
  elseif (strcmp (spec, 'sin'))
    [m, t] = ob_builder_block (m, 'Time', [], sprintf ('t%d', k), 0.05, y);
    [m, id] = ob_builder_block (m, 'Function', [], 'sin', 0.15, y, t);
  elseif (strncmp (spec, 'gain:', 5))
    [m, t] = ob_builder_block (m, 'Time', [], sprintf ('t%d', k), 0.05, y);
    [m, id] = ob_builder_block (m, 'Gain', str2num (spec(6:end)), sprintf ('g%d', k), 0.15, y, t);
  else
    [m, id] = ob_builder_block (m, 'Constant', str2num (spec), sprintf ('c%d', k), 0.1, y);
  endif
endfunction

function model = chain_subsystems (first, second)
  % first's single output feeds second; outputs are second's outputs.
  inputs = sum (strcmp ({first.blocks.type}, 'Inport'));
  outputs = sum (strcmp ({second.blocks.type}, 'Outport'));
  m = ob_builder_block ();
  ids = [];
  for k = 1:inputs
    [m, ids(end+1)] = ob_builder_block (m, 'Inport', k, sprintf ('u%d', k), 0.1, 0.9 - 0.1 * k);
  endfor
  [m, a] = ob_builder_block (m, 'Subsystem', first, 'first', 0.4, 0.5, ids);
  [m, b] = ob_builder_block (m, 'Subsystem', second, 'second', 0.6, 0.5, a);
  for k = 1:outputs
    [m, o] = ob_builder_block (m, 'Outport', k, sprintf ('y%d', k), 0.9, 0.9 - 0.1 * k);
    m.edges(end+1, :) = [b k o 1];
  endfor
  model = m;
endfunction

function model = integrate_output (model)
  % The last Scope becomes a continuous Integrator (initial state 0) that
  % feeds a new last Scope.
  scope = numel (model.blocks);
  node = model.blocks(scope);
  model.blocks(scope).type = 'Integrator';
  model.blocks(scope).value = 0;
  model.blocks(scope).name = 'integral';
  model.blocks(end+1) = node;
  model.edges(end+1, :) = [scope 1 numel(model.blocks) 1];
  if (isfield (model, 'sample_times'))
    model.sample_times(end+1, :) = 0;
  endif
endfunction

% ============================================================ comparisons

function y = run_trace (model, t, options = struct ())
  % Trace of the last Scope (all elements, one row per time).
  r = ob_run (model, t, options);
  y = ob_scope_data (r, numel (model.blocks));
endfunction

function compare_reference (id, model, c, tolerance)
  % Compare every Scope (in block order) with the recorded outports.
  want = reference_outputs (c);
  scopes = find (strcmp ({model.blocks.type}, 'Scope'));
  expect (numel (scopes) == numel (want), '%s: %d scopes for %d recorded outputs', id, numel (scopes), numel (want));
  options = struct ('solver', 'rk4');
  r = ob_run (model, c.t(:)', options);
  for k = 1:numel (scopes)
    got = ob_scope_data (r, scopes(k));
    expect (isequal (size (got), size (want{k})), '%s output %d: size %s, Simulink %s', id, k, ...
            mat2str (size (got)), mat2str (size (want{k})));
    err = max (abs (got(:) - want{k}(:)));
    expect (err <= tolerance, '%s output %d: max error %.3g > %.3g', id, k, err, tolerance);
  endfor
endfunction

function Y = reference_outputs (c)
  % Recorded outports as a cell of (time x elements) matrices.
  nt = numel (c.t);
  y = c.y;
  if (iscell (y))
    Y = cellfun (@(v) reshape (v, nt, []), y(:)', 'uniformoutput', false);
  elseif (ndims (y) == 3)
    Y = arrayfun (@(k) reshape (y(k, :, :), size (y, 2), size (y, 3)), 1:size (y, 1), 'uniformoutput', false);
  elseif (isvector (y) && numel (y) == nt)
    Y = {y(:)};
  else
    Y = arrayfun (@(k) y(k, :)', 1:rows (y), 'uniformoutput', false);
  endif
endfunction

function value = library (ref, path)
  index = find (strcmp ({ref.library.path}, path));
  expect (numel (index) == 1 && ref.library(index).ok, 'library block %s not recorded', path);
  value = ref.library(index).parameters;
endfunction

function c_compare (gcc, directory, name, model, config, options)
  % Export, compile as strict C99, run, compare the CSV with ob_run.
  source = fullfile (directory, [name '.c']);
  exe = fullfile (directory, [name '.exe']);
  csv = fullfile (directory, [name '.csv']);
  info = ob_codegen (model, source, config, options);
  shell (sprintf ('"%s" -std=c99 -O2 -Wall -Wextra -Werror -DOB_STANDALONE "%s" -lm -o "%s"', gcc, source, exe), ...
         [name ': compile']);
  shell (sprintf ('"%s" > "%s"', exe, csv), [name ': run']);
  actual = dlmread (csv, ',', 1, 0);
  result = ob_run (model, ob_time_grid (config(1), config(2), config(3)), options);
  expected = result.t;
  for block = 1:numel (result.compiled_model.blocks)
    count = prod (info.shapes{block});
    if (count == 0), continue; endif
    trace = zeros (numel (result.t), count);
    for s = 1:numel (result.t)
      trace(s, :) = result.flat_values{s, block}(:)';
    endfor
    expected = [expected trace];
  endfor
  expect (isequal (size (actual), size (expected)), '%s: C output size %s, ob_run %s', name, ...
          mat2str (size (actual)), mat2str (size (expected)));
  err = max (abs (actual(:) - expected(:)) ./ max (1, abs (expected(:))));
  tolerance = 1e-11;
  if (isfield (options, 'solver') && strcmp (options.solver, 'ode45')), tolerance = 1e-9; endif
  expect (err < tolerance, '%s: C/Octave scaled error %.3g', name, err);
endfunction

function shell (command, label)
  [status, output] = system (command);
  expect (status == 0, '%s failed: %s', label, output);
endfunction

function accelerated_compare (name, model, t, options)
  plain = ob_run (model, t, options);
  options.accelerate = true;
  fast = ob_run (model, t, options);
  tolerance = 1e-11;
  if (isfield (options, 'solver') && strcmp (options.solver, 'ode45')), tolerance = 1e-9; endif
  for scope = find (strcmp ({model.blocks.type}, 'Scope'))
    a = ob_scope_data (plain, scope); b = ob_scope_data (fast, scope);
    err = max (abs (a(:) - b(:)) ./ max (1, abs (a(:))));
    expect (err < tolerance, '%s: accelerated scope %d differs by %.3g', name, scope, err);
  endfor
endfunction

function gcc = find_gcc ()
  gcc = file_in_path (getenv ('PATH'), 'gcc.exe');
  if (isempty (gcc)), gcc = file_in_path (getenv ('PATH'), 'gcc'); endif
  if (isempty (gcc))
    candidate = fullfile (OCTAVE_HOME (), 'bin', 'gcc.exe');
    if (exist (candidate, 'file')), gcc = candidate; endif
  endif
endfunction

function expect (condition, varargin)
  if (! condition)
    error ('test_ob_routing_builders: %s', sprintf (varargin{:}));
  endif
endfunction

function assert_error (f, fragment)
  try
    f ();
  catch err
    expect (! isempty (strfind (err.message, fragment)), 'expected error containing "%s", got "%s"', ...
            fragment, err.message);
    return;
  end_try_catch
  error ('test_ob_routing_builders: expected an error containing "%s"', fragment);
endfunction
