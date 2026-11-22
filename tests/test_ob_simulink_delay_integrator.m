function test_ob_simulink_delay_integrator ()
  test_path_cleanup = ob_test_setup ();
  % Compare Transport Delay and Limited Integrator models with recorded
  % Simulink 26.2 traces.  MATLAB is not needed at test time; regenerate the
  % reference with reference_ob_simulink_delay_integrator.m.
  %
  % Each case either agrees with Simulink to a tight tolerance or shows one
  % documented difference (ADVANCED_EXTENSIONS.md, "Comparison with
  % Simulink"), asserted explicitly on both sides so that a behaviour change
  % in either direction fails here.
  ref = jsondecode (fileread (ob_test_reference ('simulink-delay-integrator-reference.json')));
  ids = fieldnames (ref.cases);
  agreed = 0; documented = 0;
  for k = 1:numel (ids)
    id = ids{k};
    c = ref.cases.(id);
    if (! c.ok), error ('%s: the Simulink reference run failed: %s', id, c.error); endif
    [t, sl, ob, first] = run_case (c);
    h = 0.1;
    switch (id)
      % --- Transport Delay -------------------------------------------------
      case {'delay_s1_ode4', 'delay_s1_ode45'}
        % At exactly t0 + T Simulink still outputs InitialOutput; Octave
        % outputs u(t0) (right-continuous).  Elsewhere identical.
        assert (ob, (t < 0.5) * 7 + (t >= 0.5) .* (t - 0.5), 1e-12);
        [s, o] = differ_only_at (id, t, sl, ob, 0.5, 1e-12);
        assert ([s o], [7 0], 1e-12);
      case 'delay_s2_ode4'
        % Simulink fixed step stores one sample per major step, so the
        % delayed step becomes a one-step ramp and its integral is offset by
        % h/2.  Octave keeps the step and is exact.
        assert (ob, max (0, t - 1.35), 1e-12);
        offset_after (id, t, sl, ob, 1.4, h / 2, 1.2);
      case 'delay_s2_ode45'
        assert (ob, max (0, t - 1.35), 1e-9);
        assert (sl, ob, 2e-7);
      case {'delay_s3_ode4_h01', 'delay_s11_ode4_h01'}
        % Simulink interpolates the history linearly (second order); Octave
        % uses cubic Hermite interpolation (third order).
        exact = ref.dde23.(id).y(:);
        assert (numel (exact), numel (t));
        bounds = struct ('delay_s3_ode4_h01', [3e-5 9e-4 1.2e-3], ...
                         'delay_s11_ode4_h01', [5e-6 3.5e-4 5e-4]).(id);
        assert (max (abs (ob - exact)) < bounds(1));
        sl_error = max (abs (sl - exact));
        assert (sl_error > bounds(2) && sl_error < bounds(3));
      case {'delay_s4_ode4', 'delay_s4b_ode4'}
        % A delay shorter than the fixed step: Simulink extrapolates (and
        % warns); Octave subdivides the step and stays exact.
        assert (any (! cellfun (@isempty, strfind (c.warnings, 'smaller than the step size'))));
        initial = str2num (c.parameters.InitialOutput);
        assert (ob, (t < 0.03) * initial + (t >= 0.03) .* (t - 0.03), 1e-12);
        [s, o] = differ_only_at (id, t, sl, ob, 0.1, 1e-12);
        assert ([s o], [0 0.07], 1e-12);
      case 'delay_s5_ode4'
        [s, o] = differ_only_at (id, t, sl, ob, 0.2, 1e-12);
        assert ([s; o], [5 6; 0 0], 1e-12);
      case 'delay_s5b_ode4'
        % A scalar initial output is broadcast from the very first sample.
        assert (size (first), [2 1]);
        assert (ob(1, :), [3 3]);
        [s, o] = differ_only_at (id, t, sl, ob, 0.2, 1e-12);
        assert ([s; o], [3 3; 0 0], 1e-12);
      case 'delay_s6_fixed05'
        % y = 1 - 0.5 y(t-1): Simulink reports the left limit of each jump
        % at the jump instant, so its trace is Octave's one sample late.
        assert (ob', [1 1 0.5 0.5 0.75 0.75 0.625], 1e-12);
        assert (sl', [1 1 1 0.5 0.5 0.75 0.75], 1e-12);
        assert (sl(2:end), ob(1:end-1), 1e-12);
      case 'delay_s6_fixed01'
        [s, o] = differ_only_at (id, t, sl, ob, [1 2 3], 1e-12);
        assert (s', [1 0.5 0.75], 1e-12);
        assert (o', [0.5 0.75 0.625], 1e-12);
      case 'delay_s7_ode4'
        exact = (t >= 0.25) .* sin (t - 0.25);
        assert (max (abs (ob - exact)) < 1e-4);
        % Linear interpolation of a sine: about h^2/8.
        assert (max (abs (sl - exact)), h^2 / 8, 1e-4);
      case 'delay_s8_ode4'
        [s, o] = differ_only_at (id, t, sl, ob, 1.5, 1e-12);
        assert ([s o], [7 1], 1e-12);
      case 'delay_s9_ode4'
        % InitialOutput 7 differs from u(t0) = 0.  Octave's RK4 end stage
        % sees the left limit 7 at t0 + T and the next step starts from 0,
        % so the integral is exact.  Simulink's k1 stage at t0 + T still sees
        % 7, which adds h/6 * 7.
        assert (ob, ramp_integral (t, 0.5, 7), 1e-12);
        offset_after (id, t, sl, ob, 0.6, h / 6 * 7, 0.5);
      case 'delay_s9_ode45'
        assert (ob, ramp_integral (t, 0.5, 7), 1e-9);
        assert (sl, ob, 5e-8);
      case 'delay_s9b_ode4'
        % Off the grid, Simulink does not split the step at t0 + T.
        assert (ob, ramp_integral (t, 0.35, 7), 1e-12);
        offset_after (id, t, sl, ob, 0.4, h / 6 * 7.05 + 2.1 - (2.45 + 0.05^2 / 2), 0.3);
      case 'delay_s10_ode4_h01'
        % x' = -x(t-1) with x(0) = 1 but InitialOutput 0.  Octave is exact
        % until the history kink at t = 1 (smoothed by the Hermite slopes)
        % is read back from t = 1.9 on; then its error stays below 1e-3.
        % Simulink keeps its h/6 offset from t0 + T (about 0.0167).
        early = t <= 1.85;
        exact = unit_dde ([0 1], t);
        assert (ob(early), exact(early), 1e-12);
        offset_after (id, t, sl, ob, 1.1, h / 6, 1.0, 1.1);
        late_errors (t, sl, ob, exact, [1e-3 0.01 0.02]);
      case 'delay_s12_ode4'
        % A scalar input is expanded to the vector initial output's shape.
        assert (size (first), [2 1]);
        [s, o] = differ_only_at (id, t, sl, ob, 0.2, 1e-12);
        assert ([s; o], [5 6; 0 0], 1e-12);
      case 'delay_s13_ode4'
        assert (size (first), [2 2]);
        assert (sl, ob, 1e-12);
      case 'delay_s14_ode4'
        % Vector state, scalar InitialOutput 1: only x2(0) = 2 differs from it.
        early = t <= 1.85;
        x1 = unit_dde ([-1 1], t); x2 = unit_dde ([-1 2], t);
        assert (ob(early, :), [x1(early) x2(early)], 1e-12);
        assert (sl(early, 1), ob(early, 1), 1e-12);
        offset_after (id, t, sl(:, 2), ob(:, 2), 1.1, h / 6, 1.0, 1.1);
        % Later, x1 (no kink) has the cubic vs. linear interpolation errors
        % of delay_s3; x2 those of delay_s10.
        late_errors (t, sl(:, 1), ob(:, 1), x1, [3e-5 5e-4 1.2e-3]);
        late_errors (t, sl(:, 2), ob(:, 2), x2, [1e-3 0.01 0.02]);
      % --- Limited Integrator ----------------------------------------------
      case {'int_s1_ramp_ode4_h025', 'int_r5_ramp_ode4_h01_up099', 'int_s7_icout_inward_ode4'}
        % Simulink ode4 gates each stage on its own state, so a step whose
        % last stage reaches a bound stops short of it; Octave's RK4 gates
        % on the step's initial state and lands on the bound.
        expected = struct ('int_s1_ramp_ode4_h025', [1 0.75+0.25/6*5 1], ...
                           'int_r5_ramp_ode4_h01_up099', [1 0.9+0.1/6*5 0.99], ...
                           'int_s7_icout_inward_ode4', [3 -0.9-0.1/6*5 -1]).(id);
        [s, o] = differ_only_at (id, t, sl, ob, expected(1), 1e-12);
        assert ([s o], expected(2:3), 1e-12);
      case 'int_s3_vec_ode4_h025'
        [s, o] = differ_only_at (id, t, sl, ob, [0.25 0.5], 1e-12);
        assert (s, [0.25 -0.25+0.25/6 0.5; 0.5-0.25/6 -0.25 1-0.25/6*2], 1e-12);
        assert (o, [0.25 -0.25 0.5; 0.5 -0.25 1], 1e-12);
      case {'int_s2_cos_ode4_h01', 'int_s4_rising_ode4', 'int_s4_falling_ode4', 'int_s4_either_ode4', ...
            'int_s5_rising_ode4', 'int_s6_level_ode4', 'int_s7_icout_reset_ode4', ...
            'int_s7_rpos0_level_ode4', 'int_r1_zero_rising_ode4', 'int_r1_zero_falling_ode4', ...
            'int_r2_satreset_rising_ode4', 'int_r4b_truepulse_rising_ode4', 'int_r5_ramp_ode4_h01_up1'}
        assert (sl, ob, 1e-12);
      case 'int_s6_levelshift_ode4'
        % 'level' also resets when the signal returns to zero, sampled at
        % the step after the gate closes at 2.05.
        assert (sl, ob, 1e-12);
        assert (ob(near (t, 2.1)), 0.25, 1e-12);
      case {'int_s1_ramp_ode45_sparse', 'int_s4_either_ode45_zcon', 'int_s6_levelhold_ode45_zcon', ...
            'int_r7_stepinput_ode45_zcon'}
        assert (sl, ob, 1e-9);
      case 'int_s6_levelshift_ode45_zcon'
        % Simulink locates the nonzero-to-zero reset at 2.05.  Octave's hold
        % ends there with the state at its initial value, so ode45 needs no
        % sampled reset and agrees (0.30 at 2.1, not 0.25 as with ode4).
        assert (sl, ob, 1e-9);
        assert (ob(near (t, 2.1)), 0.3, 1e-12);
      case 'int_s6_levelshift_ode45_zcoff'
        % Without zero crossings Simulink releases the hold within its step
        % tolerance after 2.05 (about 3.6e-6 late); Octave releases exactly
        % at 2.05.
        late = t >= 2.1 - 1e-9;
        assert (sl(! late), ob(! late), 1e-9);
        offset = sl(late) - ob(late);
        assert (max (offset) - min (offset) < 1e-9);
        assert (offset(1) < -1e-6 && offset(1) > -1e-5);
      case 'int_s5_rising_ode45_zcon'
        % Simulink locates each edge (0.55, 1.55, 2.55); Octave samples
        % resets at accepted hits, here 0.6, 1.6 and 2.6.
        offset_after (id, t, sl, ob, 0.6, 0.05, 0.5);
      case 'int_s6_levelhold_ode4'
        % Gate closes exactly at t = 2.  Simulink's k4 stage at t = 2 sees
        % the Step's new value; Octave's RK4 end stage uses the left limit.
        offset_after (id, t, sl, ob, 2.0, h / 6, 1.9);
      case 'int_r3_levelpulse_ode4'
        % Octave splits RK4 steps at Step times and holds for exactly 0.05;
        % Simulink ode4 samples the pulse in its stages: h/6 * (1+0+0+1).
        offset_after (id, t, sl, ob, 1.1, -h / 6, 1.0);
      case 'int_r7_stepinput_ode4'
        offset_after (id, t, sl, ob, 0.6, 0.5 + h / 6 * 16 - 0.7, 0.5);
      case {'int_r3_levelpulse_ode45_zcon', 'int_r4b_truepulse_rising_ode45_zcon'}
        % A reset pulse entirely between output samples: Simulink locates
        % it; Octave never samples it.
        offset_after (id, t, sl, ob, 1.1, -1.02, 1.0);
      otherwise
        error ('%s: no expectation for this reference case', id);
    endswitch
    if (isequal (sl, ob) || max (abs (sl(:) - ob(:))) <= 2e-7), agreed += 1;
    else documented += 1; endif
  endfor
  printf ('Simulink delay/integrator parity (%s): %d cases agree, %d documented differences\n', ...
          ref.simulink_version, agreed, documented);
endfunction

function [t, sl, ob, first] = run_case (c)
  % Build the Octave Blocks model for one reference case and run it on the
  % Simulink output times.
  [model, port] = build_model (c);
  t = c.t(:);
  if (strcmp (c.solver, 'ode4')), options = struct ('solver', 'rk4');
  else options = struct ('solver', 'ode45', 'reltol', c.reltol, 'abstol', c.abstol); endif
  result = ob_run (model, t', options);
  first = result.values{1, port};
  ob = cell2mat (cellfun (@(v) v(:)', result.values(:, port), 'UniformOutput', false));
  sl = c.y;
  if (rows (sl) != numel (t)), sl = sl'; endif
  assert (size (sl), size (ob));
endfunction

function [model, port] = build_model (c)
  B = @(type, value, name) struct ('type', type, 'value', value, 'name', name, 'x', 0, 'y', 0);
  p = c.parameters;
  E = @(text) str2num (text);
  if (isfield (p, 'DelayTime'))
    delay = B('Transport Delay', struct ('delay', E(p.DelayTime), 'initial', E(p.InitialOutput)), 'TD');
  endif
  switch (c.model)
    case 'clock_td'
      model.blocks = [B('Time', [], 'Clock') delay B('Scope', [], 'Out1')];
      model.edges = [1 2; 2 3]; port = 3;
    case 'clock_gain_td'
      model.blocks = [B('Time', [], 'Clock') B('Gain', E(p.Gain), 'G') delay B('Scope', [], 'Out1')];
      model.edges = [1 2; 2 3; 3 4]; port = 4;
    case 'clock_td_integrator'
      model.blocks = [B('Time', [], 'Clock') delay B('Integrator', E(p.InitialCondition), 'Int') ...
                      B('Scope', [], 'Out1')];
      model.edges = [1 2; 2 3; 3 4]; port = 4;
    case 'step_td_integrator'
      model.blocks = [B('Step', [E(p.Time) E(p.Before) E(p.After)], 'Step') delay ...
                      B('Integrator', E(p.InitialCondition), 'Int') B('Scope', [], 'Out1')];
      model.edges = [1 2; 2 3; 3 4]; port = 4;
    case 'dde'
      model.blocks = [B('Integrator', E(p.InitialCondition), 'x') delay B('Gain', E(p.Gain), 'G') ...
                      B('Scope', [], 'Out1')];
      model.edges = [1 2; 2 3; 3 1; 1 4]; port = 4;
    case 'feedback'
      model.blocks = [B('Constant', E(p.Value), 'One') B('Sum', [], 'Sum') delay ...
                      B('Gain', E(p.Gain), 'G') B('Scope', [], 'Out1')];
      model.edges = [1 1 2 1; 4 1 2 2; 2 1 3 1; 3 1 4 1; 2 1 5 1]; port = 5;
    case 'sine_td'
      model.blocks = [B('Time', [], 'Clock') B('Function', [], 'sin') delay B('Scope', [], 'Out1')];
      model.edges = [1 2; 2 3; 3 4]; port = 4;
    case 'integrator'
      [model, port] = build_integrator (p, B, E);
    otherwise
      error ('unknown reference model %s', c.model);
  endswitch
endfunction

function [model, port] = build_integrator (p, B, E)
  % Simulink Integrator with LimitOutput/ExternalReset as a Limited
  % Integrator; the reset signal is a sum of Step blocks, as in the producer.
  switch (p.Input)
    case 'cos'
      blocks = [B('Time', [], 'Clock') B('Function', [], 'cos')];
      edges = [1 1 2 1]; source = 2;
    case 'step'
      blocks = B('Step', E(p.InputValue), 'In'); edges = zeros (0, 4); source = 1;
    otherwise
      blocks = B('Constant', E(p.InputValue), 'In'); edges = zeros (0, 4); source = 1;
  endswitch
  lower = -Inf; upper = Inf;
  if (strcmp (p.LimitOutput, 'on'))
    lower = E(p.LowerSaturationLimit); upper = E(p.UpperSaturationLimit);
  endif
  blocks(end+1) = B('Limited Integrator', struct ('initial', E(p.InitialCondition), 'lower', lower, ...
                                                  'upper', upper, 'reset', p.ExternalReset), 'Int');
  int = numel (blocks);
  edges(end+1, :) = [source 1 int 1];
  blocks(end+1) = B('Scope', [], 'Out1'); port = numel (blocks);
  edges(end+1, :) = [int 1 port 1];
  if (! strcmp (p.ExternalReset, 'none'))
    steps = E(p.ResetSteps);
    ids = zeros (1, rows (steps));
    for j = 1:rows (steps)
      blocks(end+1) = B('Step', steps(j, :), sprintf ('S%d', j)); ids(j) = numel (blocks);
    endfor
    last = ids(1);
    for j = 2:rows (steps)
      blocks(end+1) = B('Sum', [], sprintf ('P%d', j)); sum_id = numel (blocks);
      edges(end+1, :) = [last 1 sum_id 1]; edges(end+1, :) = [ids(j) 1 sum_id 2];
      last = sum_id;
    endfor
    edges(end+1, :) = [last 1 int 2];
  endif
  model = struct ('blocks', blocks, 'edges', edges);
endfunction

function mask = near (t, times)
  mask = false (size (t));
  for time = times(:)'
    mask |= abs (t - time) < 1e-9;
  endfor
endfunction

function [s, o] = differ_only_at (id, t, sl, ob, times, tol)
  % Agreement to tol everywhere except at the listed times, where the two
  % must really differ.  Returns the Simulink and Octave rows there.
  at = near (t, times);
  assert (nnz (at), numel (times));
  if (any (any (abs (sl(! at, :) - ob(! at, :)) > tol)))
    error ('%s: Simulink and Octave differ outside t = %s', id, mat2str (times));
  endif
  s = sl(at, :); o = ob(at, :);
  if (any (max (abs (s - o), [], 2) <= 1e-6))
    error ('%s: the documented difference at t = %s has disappeared', id, mat2str (times));
  endif
endfunction

function offset_after (id, t, sl, ob, from, offset, agree_to, upto = Inf)
  % Agreement up to 'agree_to', then a constant offset sl - ob from 'from'
  % (up to 'upto', when later behaviour also diverges in other ways).
  early = t <= agree_to + 1e-9;
  late = t >= from - 1e-9 & t <= upto + 1e-9;
  assert (any (early) && any (late));
  if (any (abs (sl(early) - ob(early)) > 1e-9))
    error ('%s: Simulink and Octave differ before t = %g', id, from);
  endif
  if (any (abs (sl(late) - ob(late) - offset) > 1e-9))
    error ('%s: expected the documented offset %.6g from t = %g; got %s', id, offset, from, ...
           mat2str ((sl(late) - ob(late))', 6));
  endif
endfunction

function late_errors (t, sl, ob, exact, bounds)
  % After the t = 1 kink is read back (t > 1.85): Octave's error below
  % bounds(1), Simulink's within [bounds(2), bounds(3)].
  late = t > 1.85;
  ob_error = max (abs (ob(late) - exact(late)));
  sl_error = max (abs (sl(late) - exact(late)));
  if (ob_error >= bounds(1) || sl_error < bounds(2) || sl_error > bounds(3))
    error ('late DDE errors: Octave %.3g (bound %.3g), Simulink %.3g (expected %.3g to %.3g)', ...
           ob_error, bounds(1), sl_error, bounds(2), bounds(3));
  endif
endfunction

function x = unit_dde (first, t)
  % Method of steps for x' = -x(t - 1): 'first' is x on [0, 1] as a
  % polynomial in t (polyval order).  On [k, k+1], x is x(k) minus the
  % integral of the previous piece, in the local time t - k.
  x = zeros (size (t));
  q = first;
  for k = 0:ceil (max (t)) - 1
    in = t >= k - 1e-9 & t <= k + 1 + 1e-9;
    x(in) = polyval (q, t(in) - k);
    next = -polyint (q);
    next(end) += polyval (q, 1);
    q = next;
  endfor
endfunction

function y = ramp_integral (t, delay, initial)
  % Integral of a Transport Delay of the clock with a constant initial output.
  y = (t <= delay) .* initial .* t + (t > delay) .* (initial * delay + (t - delay).^2 / 2);
endfunction
