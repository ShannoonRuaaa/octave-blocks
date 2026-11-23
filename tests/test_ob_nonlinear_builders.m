function test_ob_nonlinear_builders ()
  test_path_cleanup = ob_test_setup ();
  % Regression suite for the nonlinear subsystem builders: ob_backlash,
  % ob_quantizer, ob_minmax, ob_saturation_dynamic, ob_sign,
  % ob_dead_zone_dynamic, ob_coulomb_viscous_friction,
  % ob_relational_operator and ob_logical_operator.
  %   1. analytic values on constant inputs (half-way quotients, crossed
  %      limits, ties, every operator for 2 and 3 inputs, scalar expansion)
  %   2. invalid arguments raise 'ob_<name>:' errors
  %   3. defaults equal the recorded Simulink library defaults
  %   4. recorded Simulink 26.2 traces (reference_ob_nonlinear_builders.m,
  %      simulink-nonlinear-builders-reference.json; MATLAB is not needed
  %      at test time), fixed-step ode4 and variable-step ode45 with zero
  %      crossings
  %   5. zero-crossing guards: present for the comparison blocks, absent
  %      for Quantizer and Logical Operator, and exact event-located
  %      integrals
  %   6. per builder: strict C99 export compiled with gcc and compared with
  %      ob_run, and an ob_accelerate run compared with ob_run
  check_analytic ();
  check_invalid ();
  ref = jsondecode (fileread (ob_test_reference ('simulink-nonlinear-builders-reference.json')));
  check_defaults (ref.defaults);
  check_reference (ref);
  check_zero_crossings ();
  check_compiled (ref);
  disp ('Octave Blocks nonlinear builder tests passed');
endfunction

%% ------------------------------------------------------------- analytic

function check_analytic ()
  % Sign: element-wise, exact zero, matrix input.
  assert (evaluate (ob_sign (), {[-2 0 3; 1e-300 -1e-300 0]}), [-1 0 1; 1 -1 0]);
  assert (evaluate (ob_sign (), {-0.5}), -1);
  assert (! signbit (evaluate (ob_sign (), {-0})));                  % Simulink: +0
  assert (! signbit (evaluate (ob_coulomb_viscous_friction (1, 1), {-0})));

  % Comparisons never overflow (ob_builder_difference): the values Simulink
  % 26.2 gives for the reviewer's cases, and exact signs at the extremes.
  assert (evaluate (ob_minmax ('max', 2), {1e308, -1e308}), 1e308);
  assert (evaluate (ob_minmax ('min', 3), {realmax, -realmax, 0}), -realmax);
  assert (evaluate (ob_saturation_dynamic (), {1e308, -1e308, -1e308}), -1e308);
  assert (evaluate (ob_saturation_dynamic (), {realmax, -1e308, -realmax}), -1e308);
  assert (evaluate (ob_saturation_dynamic (), {1e308, [1.5e308 -1e308], -realmax}), [1e308 -1e308]);
  assert (evaluate (ob_dead_zone_dynamic (), {1e308, -1e308, -1}), -1e308 + 1);
  y = evaluate (ob_dead_zone_dynamic (), {realmax, -1e308, -realmax});    % inside: +0
  assert (y == 0 && ! signbit (y));
  assert (evaluate (ob_relational_operator ('>'), {1e308, -1e308}), 1);
  assert (evaluate (ob_relational_operator ('<'), {1e308, -1e308}), 0);
  assert (evaluate (ob_relational_operator ('=='), {realmax, realmax}), 1);
  assert (evaluate (ob_relational_operator ('~='), {realmax, -realmax}), 1);
  % Subnormals one step apart compare exactly (halving alone would merge
  % 0 with 4.9e-324 and 3 with 4 steps).
  tiny = pow2 (-1074);
  ops = {'>', '>=', '<', '<=', '==', '~='};
  for k = 1:numel (ops)
    y = evaluate (ob_relational_operator (ops{k}), {[tiny 0 3*tiny 4*tiny -tiny], [0 tiny 4*tiny 4*tiny 0]});
    expected = double (feval ({'gt', 'ge', 'lt', 'le', 'eq', 'ne'}{k}, [1 0 3 4 -1], [0 1 4 4 0]));
    assert (isequal (y, expected), ['subnormal ' ops{k}]);
  endfor
  assert (evaluate (ob_minmax ('max', 2), {3 * tiny, 4 * tiny}), 4 * tiny);
  assert (evaluate (ob_minmax ('min', 2), {tiny, 0}), 0);
  assert (evaluate (ob_saturation_dynamic (), {tiny, 4 * tiny, 0}), tiny);
  assert (evaluate (ob_dead_zone_dynamic (), {3 * tiny, 4 * tiny, -tiny}), tiny);

  % Quantizer: q*round(u/q) by true division (Simulink), halves away from 0.
  assert (evaluate (ob_quantizer (0.1), {[0.15 0.35 -0.25 1.05 -0.45]}), ...
          0.1 * round ([0.15 0.35 -0.25 1.05 -0.45] ./ 0.1));
  assert (isequal (evaluate (ob_quantizer (0.1), {[0.15 0.35]}), [0.1 0.1*3]));   % not 0.2, 0.4
  assert (evaluate (ob_quantizer (), {[0.74 0.76 -0.25]}), [0.5 1 -0.5]);
  assert (evaluate (ob_quantizer ([0.5 0.3]), {1}), [1 0.3 * round(1 / 0.3)]);
  assert (evaluate (ob_quantizer (0.5, 0.25), {0.3}), 0.5);

  % Backlash: first sample from y0 (the held and inherited forms agree).
  assert (evaluate (ob_backlash (1, 0), {1.25}), 0.75, 1e-15);
  assert (evaluate (ob_backlash (1, 0, 0.25), {1.25}), 0.75, 1e-15);
  assert (evaluate (ob_backlash (1, 2), {1.75}), 2);
  assert (evaluate (ob_backlash (0.5, [0 1]), {[1 -1]}), [0.75 -0.75]);
  assert (evaluate (ob_backlash (0, 0), {1.25}), 1.25);

  % MinMax: ties, scalar expansion, n = 4.
  assert (evaluate (ob_minmax ('max', 3), {1, [0 2 3], 2.5}), [2.5 2.5 3]);
  assert (evaluate (ob_minmax ('min', 2), {[1 -1], 0}), [0 -1]);
  assert (evaluate (ob_minmax ('MIN', 4), {3, -2, [5 -7], 1}), [-2 -7]);
  assert (evaluate (ob_minmax ('max', 2), {4, 4}), 4);
  assert (evaluate (ob_minmax (), {[1 2; 3 4], [4 3; 2 1]}), [1 2; 2 1]);

  % Saturation Dynamic, including Simulink's priority for lo > up.
  sat = @(up, u, lo) (u > up) .* up + (u <= up) .* ((u < lo) .* lo + (u >= lo) .* u);
  u = [-3 -1 0 0.5 0.7 2];
  assert (evaluate (ob_saturation_dynamic (), {0.5, u, -1}), sat (0.5, u, -1));
  assert (evaluate (ob_saturation_dynamic (), {0, u, 1}), sat (0, u, 1));      % crossed limits
  assert (evaluate (ob_saturation_dynamic (), {[1 0.5 2], 1.5, -1}), [1 0.5 1.5]);

  % Dead Zone Dynamic, including Simulink's priority for lo > up.
  dz = @(up, u, lo) (u >= up) .* (u - up) + (u < up) .* ((u > lo) .* 0 + (u <= lo) .* (u - lo));
  assert (evaluate (ob_dead_zone_dynamic (), {0.5, u, -1}), dz (0.5, u, -1));
  assert (evaluate (ob_dead_zone_dynamic (), {0, u, 1}), dz (0, u, 1));       % crossed bounds
  assert (evaluate (ob_dead_zone_dynamic (), {[1 0.5 2], 1.5, -1}), [0.5 1 0]);
  assert (! any (signbit (evaluate (ob_dead_zone_dynamic (), {1, [0 -0.5], -1}))));

  % Coulomb & Viscous Friction: y = gain.*u + offset.*sign(u).
  assert (evaluate (ob_coulomb_viscous_friction (), {2}), 2 + [1 3 2 0]);
  assert (evaluate (ob_coulomb_viscous_friction (), {0}), [0 0 0 0]);
  assert (evaluate (ob_coulomb_viscous_friction (2, 3), {[-1 0 0.5]}), [-5 0 3.5]);
  assert (evaluate (ob_coulomb_viscous_friction ([1 2], [3 0.5]), {[1 -2]}), [4 -3]);
  assert (evaluate (ob_coulomb_viscous_friction (-1, 1), {2}), 1);       % negative offset allowed
  % Equal-length vectors pair element-wise whatever their orientation
  % (Simulink 1-D parameters), never as an outer combination.
  assert (evaluate (ob_coulomb_viscous_friction ([1 2], [3; 4]), {1}), [4 6]);

  % Relational Operator: all six operators, equal / less / greater cases.
  a = [1 2 3]; b = 2;
  ops = {'==', '~=', '!=', '<', '<=', '>=', '>'};
  expected = {a == b, a != b, a != b, a < b, a <= b, a >= b, a > b};
  for k = 1:numel (ops)
    y = evaluate (ob_relational_operator (ops{k}), {a, b});
    assert (isequal (y, double (expected{k})), ops{k});
    assert (! any (signbit (y)));
  endfor
  assert (evaluate (ob_relational_operator (), {[3 5], 4}), [1 0]);        % default '<='
  assert (evaluate (ob_relational_operator ('>'), {0.5, [0 1; 2 -1]}), [1 0; 0 1]);

  % Logical Operator: every operator for 2 and 3 inputs over all truth
  % combinations (nonzero = true), NOT, and scalar expansion.
  for n = 2:3
    combos = dec2bin (0:2^n-1) - '0';            % rows: one combination each
    values = cell (1, n);
    for k = 1:n, values{k} = combos(:, k)' .* (k - 2.5); endfor   % nonzero levels -1.5, -0.5, 0.5
    count = sum (combos, 2)';
    truth = struct ('AND', count == n, 'OR', count > 0, 'NAND', count < n, 'NOR', count == 0, ...
                    'XOR', mod (count, 2) == 1, 'NXOR', mod (count, 2) == 0);
    for op = fieldnames (truth)'
      y = evaluate (ob_logical_operator (op{1}, n), values);
      assert (isequal (y, double (truth.(op{1}))), sprintf ('%s with %d inputs', op{1}, n));
    endfor
  endfor
  assert (evaluate (ob_logical_operator ('not'), {[0 2 -1]}), [1 0 0]);
  assert (evaluate (ob_logical_operator ('NOT', 1), {0}), 1);
  assert (evaluate (ob_logical_operator (), {[0 2 -1], 1}), [0 1 1]);
  assert (evaluate (ob_logical_operator ('xor', 4), {1, 1, [1 0], 0}), [1 0]);
  % Every Sum in the rewrite has exactly two inputs (Gemini's draft wired three).
  model = ob_logical_operator ('OR', 5);
  sums = find (strcmp ({model.blocks.type}, 'Sum'));
  for id = sums, assert (nnz (model.edges(:, 3) == id), 2); endfor
endfunction

%% -------------------------------------------------------- invalid input

function check_invalid ()
  assert_error (@() ob_sign (1), 'ob_sign: function called with too many inputs');
  assert_error (@() ob_backlash (-1), 'ob_backlash: width must be nonnegative');
  assert_error (@() ob_backlash ('a'), 'ob_backlash: width must be of class');
  assert_error (@() ob_backlash ([1 2]), 'ob_backlash: width must be scalar');
  assert_error (@() ob_backlash (1i), 'ob_backlash: width must be real');
  assert_error (@() ob_backlash (1, Inf), 'ob_backlash: initial_output must be finite');
  assert_error (@() ob_backlash (1, []), 'ob_backlash: initial_output must be nonempty');
  assert_error (@() ob_backlash (1, 0, 0.25, 0.25), 'ob_backlash: Ts must be');
  assert_error (@() ob_backlash (1, 0, -2), 'ob_backlash: Ts must be');
  assert_error (@() ob_backlash (1, 0, 0, 0.1), 'ob_backlash: Ts must be');
  assert_error (@() ob_backlash (1, 0, 0, 0, 0), 'ob_backlash: function called with too many inputs');
  assert_error (@() ob_quantizer ('a'), 'ob_quantizer: interval must be of class');
  assert_error (@() ob_quantizer (0), 'ob_quantizer: interval must be positive');
  assert_error (@() ob_quantizer (Inf), 'ob_quantizer: interval must be finite');
  assert_error (@() ob_quantizer (0.5, [1 2]), 'ob_quantizer: Ts must be scalar');
  assert_error (@() ob_quantizer (0.5, 0.1, 0.2), 'ob_quantizer: Ts must be');
  assert_error (@() ob_minmax (3), 'ob_minmax: func must be');
  assert_error (@() ob_minmax ('mean'), 'ob_minmax: func must be');
  assert_error (@() ob_minmax ('max', 1), 'ob_minmax: inputs = 1');
  assert_error (@() ob_minmax ('max', 2.5), 'ob_minmax: inputs must be integer');
  assert_error (@() ob_minmax ('max', '3'), 'ob_minmax: inputs must be of class');
  assert_error (@() ob_saturation_dynamic (1), 'ob_saturation_dynamic: function called with too many inputs');
  assert_error (@() ob_dead_zone_dynamic (1), 'ob_dead_zone_dynamic: function called with too many inputs');
  assert_error (@() ob_coulomb_viscous_friction ('a'), 'ob_coulomb_viscous_friction: offset must be of class');
  assert_error (@() ob_coulomb_viscous_friction (1, NaN), 'ob_coulomb_viscous_friction: gain must be finite');
  assert_error (@() ob_coulomb_viscous_friction ([1 2], [1 2 3]), 'ob_coulomb_viscous_friction: offset and gain sizes');
  assert_error (@() ob_coulomb_viscous_friction ([1 2 3], [1; 2]), 'ob_coulomb_viscous_friction: offset and gain sizes must match');
  assert_error (@() ob_coulomb_viscous_friction (ones (2), [1 2]), 'got 2x2 and 1x2');
  assert_error (@() ob_coulomb_viscous_friction (1, 1, 1), 'ob_coulomb_viscous_friction: function called with too many inputs');
  assert_error (@() ob_relational_operator (5), 'ob_relational_operator: op must be');
  assert_error (@() ob_relational_operator ('=>'), 'ob_relational_operator: op must be');
  assert_error (@() ob_relational_operator ('isNaN'), 'ob_relational_operator: one-input operator');
  assert_error (@() ob_logical_operator (5), 'ob_logical_operator: op must be');
  assert_error (@() ob_logical_operator ('IMPLIES'), 'ob_logical_operator: op must be');
  assert_error (@() ob_logical_operator ('AND', 1), 'ob_logical_operator: AND needs inputs >= 2');
  assert_error (@() ob_logical_operator ('NOT', 2), 'ob_logical_operator: NOT takes exactly 1 input');
  assert_error (@() ob_logical_operator ('OR', 0), 'ob_logical_operator: inputs must be positive');
  % Shape errors surface when the model runs: a scalar Backlash state or a
  % scalar held Quantizer interval with a vector signal (documented; the
  % expanded parameters work), and non-broadcastable MinMax inputs.
  assert_error (@() evaluate (ob_backlash (), {[1 2]}), 'match its state shape');
  assert_error (@() evaluate (ob_quantizer (0.5, 0.25), {[1 2]}), 'match its state shape');
  assert (evaluate (ob_backlash (1, [0 0]), {[1 2]}), [0.5 1.5]);
  assert (evaluate (ob_quantizer ([0.5 0.5], 0.25), {[1.2 2]}), [1 2]);
  assert_error (@() evaluate (ob_minmax ('max', 2), {[1 2], [1 2 3]}), 'nonconformant');
endfunction

%% ------------------------------------------------------------- defaults

function check_defaults (defaults)
  % Each builder's defaults equal the library defaults Simulink reports.
  assert (defaults.backlash.BlockType, 'Backlash');
  assert (isequal (ob_backlash (), dut (defaults.backlash, struct (), 1)));
  assert (isequal (ob_quantizer (), dut (defaults.quantizer, struct (), 1)));
  assert (isequal (ob_sign (), dut (defaults.sign, struct (), 1)));
  assert (isequal (ob_saturation_dynamic (), dut (defaults.saturation_dynamic, struct (), 3)));
  assert (isequal (ob_dead_zone_dynamic (), dut (defaults.dead_zone_dynamic, struct (), 3)));
  assert (isequal (ob_coulomb_viscous_friction (), dut (defaults.coulomb_viscous_friction, struct (), 1)));
  assert (defaults.coulomb_viscous_friction.parameters.offset, '[1 3 2 0]');
  assert (isequal (ob_relational_operator (), dut (defaults.relational_operator, struct (), 2)));
  assert (isequal (ob_relational_operator (), dut (defaults.relational_operator_common, struct (), 2)));
  assert (isequal (ob_logical_operator (), dut (defaults.logical_operator, struct (), 2)));
  assert (isequal (ob_logical_operator (), dut (defaults.logical_operator_common, struct (), 2)));
  % Simulink's MinMax default is Inputs = 1 (element reduction), which is
  % documented as unsupported; the builder keeps Function = 'min'.
  assert (defaults.minmax.parameters.Inputs, '1');
  assert_error (@() dut (defaults.minmax, struct (), 1), 'ob_minmax: inputs = 1');
  assert (isequal (ob_minmax (), dut (defaults.minmax, struct ('Inputs', '2'), 2)));
endfunction

%% ------------------------------------------------------------ reference

function check_reference (ref)
  ids = fieldnames (ref.cases);
  worst = 0; compared = 0;
  for k = 1:numel (ids)
    id = ids{k}; c = ref.cases.(id);
    if (! c.ok), error ('%s: the Simulink reference run failed: %s', id, c.error); endif
    kind = block_kind (c.block);
    sub = dut (ref.defaults.(kind), c.parameters, numel (c.sources));
    t = c.t(:)';
    model = harness (sub, c.sources, c.integrate);
    if (strcmp (c.solver, 'ode4'))
      options = struct ('solver', 'rk4');
      tolerance = 1e-12;
    else
      options = struct ('solver', 'ode45', 'reltol', 1e-10, 'abstol', 1e-12, 'zero_crossings', true);
      tolerance = 1e-7;
    endif
    result = ob_run (model, t, options);
    y = ob_scope_data (result, numel (model.blocks));
    sl = c.y;
    if (isvector (sl) && numel (t) > 1), sl = sl(:); endif
    assert (isequal (size (y), size (sl)), sprintf ('%s: output shape', id));
    err = max (abs (y(:) - sl(:)) ./ max (1, abs (sl(:))));
    assert (err <= tolerance, sprintf ('%s: max scaled error %.3g against Simulink', id, err));
    worst = max (worst, err * (tolerance == 1e-12)); compared += 1;
  endfor
  printf ('  %d Simulink 26.2 cases agree (worst fixed-step scaled error %.3g)\n', compared, worst);
endfunction

%% ------------------------------------------------------- zero crossings

function check_zero_crossings ()
  t = 0:0.1:10;
  zc = struct ('solver', 'rk4', 'zero_crossings', true);
  S = @(a, p) struct ('kind', 'sine', 'amplitude', a, 'phase', p, 'bias', 0);
  R = @(a, p) struct ('kind', 'roundsine', 'amplitude', a, 'phase', p, 'bias', 0);
  % Integral of sign(sin t) over [0, 10] is 4*pi - 10 once the sign
  % changes are located; without guards RK4 integrates across them.
  m = harness (ob_sign (), S(1, 0), true); last = numel (m.blocks);
  r = ob_run (m, t, zc);
  assert (ob_scope_data (r, last)(end), 4 * pi - 10, 1e-9);
  assert (numel (r.events) > 0);
  plain = ob_run (m, t, struct ('solver', 'rk4'));
  assert (abs (ob_scope_data (plain, last)(end) - (4 * pi - 10)) > 1e-3);
  r = ob_run (harness (ob_coulomb_viscous_friction (2, 3), S(1, 0), true), t, zc);
  assert (ob_scope_data (r, last)(end), 3 * (1 - cos (10)) + 2 * (4 * pi - 10), 1e-5);
  % Guards: comparison builders register events, Quantizer and Logical
  % Operator (no ZeroCross in Simulink) do not.
  guarded = {ob_minmax('max', 2), {S(1, 0), S(1, pi/2)}; ob_relational_operator('>'), {S(1, 0), S(1, pi/2)}; ...
             ob_saturation_dynamic(), {S(0.5, 0), S(2, 0), S(-1, 0)}; ...
             ob_dead_zone_dynamic(), {S(0.5, 0), S(2, 0), S(-1, 0)}; ob_backlash(), {S(2, 0)}};
  for k = 1:rows (guarded)
    r = ob_run (harness (guarded{k, 1}, [guarded{k, 2}{:}], false), t, zc);
    assert (numel (r.events) > 0, sprintf ('guarded case %d registers no events', k));
  endfor
  r = ob_run (harness (ob_quantizer (0.5), S(2, 0), false), t, zc);
  assert (numel (r.events), 0);
  % Discrete Backlash (Ts > 0) has no guards either (Simulink applies no
  % zero-crossing detection to a sampled Backlash), and its values equal
  % those of a run without zero crossings.
  m = harness (ob_backlash (1, 0, 0.25), S(2, 0), true);
  r = ob_run (m, 0:0.05:10, zc);
  assert (numel (r.events), 0);
  plain = ob_run (m, 0:0.05:10, struct ('solver', 'rk4'));
  assert (isequal (ob_scope_data (r, numel (m.blocks) - 1), ob_scope_data (plain, numel (m.blocks) - 1)));
  assert (! any (strcmp ({ob_backlash(1, 0, 0.25).blocks.type}, 'Dead Zone')));
  r = ob_run (harness (ob_logical_operator ('XOR', 2), [R(0.6, 0), R(0.6, pi/2)], false), t, zc);
  assert (numel (r.events), 0);
endfunction

%% -------------------------------------------------- C export, accelerate

function check_compiled (ref)
  % One harness per builder, run with zero crossings off (flat exporter)
  % and, for the guarded builders, on (typed exporter).
  root = fullfile (fileparts (mfilename ('fullpath')), '.artifacts', 'nonlinear-builders');
  if (! exist (root, 'dir')), mkdir (root); endif
  gcc = compiler ();
  cases = {'backlash', 'backlash_ts_offset', 'quantizer_half', 'quantizer_ts', 'minmax_expand', ...
           'satdyn_vec', 'sign_vec', 'dzdyn_inv', 'cvf_default', 'relop_vec', 'logic_nxor3', 'logic_vec'};
  guarded = {'backlash', 'minmax_expand', 'satdyn_vec', 'sign_vec', 'dzdyn_inv', 'cvf_default', 'relop_vec'};
  compiled = 0; accelerated = 0;
  for k = 1:numel (cases)
    c = ref.cases.(cases{k});
    sub = dut (ref.defaults.(block_kind (c.block)), c.parameters, numel (c.sources));
    model = harness (sub, c.sources, zeros (1, columns (c.y)));   % integrate the DUT output
    config = [0 4 c.t(2) - c.t(1)];
    for zc = [false true]
      if (zc && ! any (strcmp (cases{k}, guarded))), continue; endif
      options = struct ('solver', 'rk4', 'zero_crossings', zc);
      name = sprintf ('%s_zc%d', cases{k}, zc);
      t = ob_time_grid (config(1), config(2), config(3));
      expected = ob_run (model, t, options);
      if (! isempty (gcc))
        compare_c (gcc, root, name, model, config, options, expected);
        compiled += 1;
      endif
      [fast, info] = ob_accelerate (model, t, options);
      if (zc), assert (info.exporter, 'typed'); else assert (info.exporter, 'flat'); endif
      for id = [numel(model.blocks) - 1, numel(model.blocks)]    % DUT output and its integral
        a = ob_scope_data (fast, id); b = ob_scope_data (expected, id);
        assert (max (abs (a(:) - b(:)) ./ max (1, abs (b(:)))) <= 1e-12, [name ' accelerate']);
      endfor
      accelerated += 1;
    endfor
  endfor
  if (isempty (gcc))
    warning ('test_ob_nonlinear_builders: gcc not found; C export compile checks skipped');
  endif
  printf ('  %d C exports compiled and matched; %d accelerated runs matched\n', compiled, accelerated);
endfunction

function compare_c (gcc, root, name, model, config, options, result)
  source = fullfile (root, [name '.c']); binary = fullfile (root, [name '.exe']);
  info = ob_codegen (model, source, config, options);
  expected = result.t(:);
  for block = 1:numel (result.compiled_model.blocks)
    count = prod (info.shapes{block});
    if (count == 0), continue; endif
    traces = zeros (numel (result.t), count);
    for sample = 1:numel (result.t)
      traces(sample, :) = result.flat_values{sample, block}(:)';
    endfor
    expected = [expected traces];
  endfor
  [status, output] = system (sprintf ('"%s" -std=c99 -O2 -Wall -Wextra -Werror -DOB_STANDALONE "%s" -lm -o "%s"', ...
                                      gcc, source, binary));
  assert (status == 0, sprintf ('%s: gcc failed: %s', name, output));
  previous = getenv ('PATH');
  setenv ('PATH', [fileparts(gcc) pathsep previous]);
  [status, output] = system (sprintf ('"%s"', binary));
  setenv ('PATH', previous);
  assert (status == 0, sprintf ('%s: executable failed', name));
  lines = strsplit (strtrim (output), "\n");
  actual = str2num (strjoin (lines(2:end), ';'));
  assert (isequal (size (actual), size (expected)), [name ': C output shape']);
  err = max (abs (actual(:) - expected(:)) ./ max (1, abs (expected(:))));
  assert (err < 1e-11, sprintf ('%s: C/Octave mismatch %.3g', name, err));
endfunction

function gcc = compiler ()
  gcc = '';
  candidates = {fullfile(OCTAVE_HOME, 'bin', 'gcc.exe'), fullfile(OCTAVE_HOME, 'bin', 'gcc')};
  for k = 1:numel (candidates)
    if (exist (candidates{k}, 'file')), gcc = candidates{k}; return; endif
  endfor
  found = file_in_path (getenv ('PATH'), 'gcc');
  if (! isempty (found)), gcc = found; endif
endfunction

%% -------------------------------------------------------------- helpers

function kind = block_kind (path)
  kinds = struct ('Backlash', 'backlash', 'Quantizer', 'quantizer', 'MinMax', 'minmax', ...
                  'Saturation_Dynamic', 'saturation_dynamic', 'Sign', 'sign', ...
                  'Dead_Zone_Dynamic', 'dead_zone_dynamic', 'Coulomb___Viscous_Friction', 'coulomb_viscous_friction', ...
                  'Relational_Operator', 'relational_operator', 'Logical_Operator', 'logical_operator');
  name = regexprep (path((find (path == '/', 1, 'last') + 1):end), '[^A-Za-z]', '_');
  kind = kinds.(name);
endfunction

function sub = dut (defaults, parameters, ports)
  % The builder call for a Simulink block: the recorded library defaults
  % overlaid with the case's parameters (the mapping recommended for
  % ob_simulink's add_block).
  p = defaults.parameters;
  if (isstruct (parameters))
    for f = fieldnames (parameters)'
      p.(f{1}) = parameters.(f{1});
    endfor
  endif
  E = @(name) str2num (p.(name));
  switch (defaults.BlockType)
    case 'Backlash'
      [Ts, offset] = rate (E('SampleTime'));
      sub = ob_backlash (E('BacklashWidth'), E('InitialOutput'), Ts, offset);
    case 'Quantizer'
      [Ts, offset] = rate (E('SampleTime'));
      sub = ob_quantizer (E('QuantizationInterval'), Ts, offset);
    case 'MinMax'
      sub = ob_minmax (p.Function, E('Inputs'));
    case 'Signum'
      sub = ob_sign ();
    case 'RelationalOperator'
      sub = ob_relational_operator (p.Operator);
    case 'Logic'
      if (strcmp (p.Operator, 'NOT')), sub = ob_logical_operator ('NOT');
      else sub = ob_logical_operator (p.Operator, E('Inputs')); endif
    otherwise
      switch (defaults.MaskType)
        case 'Saturation Dynamic', sub = ob_saturation_dynamic ();
        case 'Dead Zone Dynamic', sub = ob_dead_zone_dynamic ();
        case 'Coulombic and Viscous Friction', sub = ob_coulomb_viscous_friction (E('offset'), E('gain'));
        otherwise, error ('no builder for %s', defaults.path);
      endswitch
  endswitch
  types = {sub.blocks.type};
  assert (sum (strcmp (types, 'Inport')), ports);
endfunction

function [Ts, offset] = rate (value)
  Ts = value(1); offset = 0;
  if (numel (value) > 1), offset = value(2); endif
endfunction

function model = harness (sub, sources, integrate)
  % Time -> sources -> DUT -> Scope (last block).  INTEGRATE true (or an
  % initial state of the DUT output shape) adds DUT -> Integrator -> Scope,
  % the DUT scope then being next to last.
  % Sources: 'sine' amplitude*sin(t + phase) + bias, 'roundsine' rounds
  % it, 'const' outputs amplitude (row vectors as in the Simulink producer).
  blocks = struct ('type', {}, 'value', {}, 'name', {}, 'x', {}, 'y', {});
  edges = zeros (0, 4);
  blocks(1) = leaf ('Time', [], 't');
  inputs = zeros (1, numel (sources));
  for k = 1:numel (sources)
    s = sources(k);
    amplitude = s.amplitude(:)';
    if (strcmp (s.kind, 'const'))
      blocks(end+1) = leaf ('Constant', amplitude, sprintf ('c%d', k)); inputs(k) = numel (blocks);
      continue;
    endif
    blocks(end+1) = leaf ('Constant', s.phase, sprintf ('phase%d', k)); phase = numel (blocks);
    blocks(end+1) = leaf ('Sum', [], sprintf ('arg%d', k)); arg = numel (blocks);
    edges(end+1:end+2, :) = [1 1 arg 1; phase 1 arg 2];
    blocks(end+1) = leaf ('Function', [], 'sin'); edges(end+1, :) = [arg 1 numel(blocks) 1];
    blocks(end+1) = leaf ('Gain', amplitude, sprintf ('amp%d', k)); edges(end+1, :) = [numel(blocks)-1 1 numel(blocks) 1];
    blocks(end+1) = leaf ('Constant', s.bias, sprintf ('bias%d', k));
    blocks(end+1) = leaf ('Sum', [], sprintf ('in%d', k));
    edges(end+1:end+2, :) = [numel(blocks)-2 1 numel(blocks) 1; numel(blocks)-1 1 numel(blocks) 2];
    if (strcmp (s.kind, 'roundsine'))
      blocks(end+1) = leaf ('Function', [], 'round'); edges(end+1, :) = [numel(blocks)-1 1 numel(blocks) 1];
    endif
    inputs(k) = numel (blocks);
  endfor
  blocks(end+1) = leaf ('Subsystem', sub, 'DUT'); d = numel (blocks);
  for k = 1:numel (inputs), edges(end+1, :) = [inputs(k) 1 d k]; endfor
  if (! isequal (integrate, false))
    initial = 0; if (! islogical (integrate)), initial = integrate; endif
    blocks(end+1) = leaf ('Integrator', initial, 'int'); edges(end+1, :) = [d 1 numel(blocks) 1];
    blocks(end+1) = leaf ('Scope', [], 'y'); edges(end+1, :) = [d 1 numel(blocks) 1];
    blocks(end+1) = leaf ('Scope', [], 'iy'); edges(end+1, :) = [numel(blocks)-2 1 numel(blocks) 1];
  else
    blocks(end+1) = leaf ('Scope', [], 'y'); edges(end+1, :) = [d 1 numel(blocks) 1];
  endif
  model = struct ('blocks', blocks, 'edges', edges);
endfunction

function b = leaf (type, value, name)
  b = struct ('type', type, 'value', value, 'name', name, 'x', 0.5, 'y', 0.5);
endfunction

function y = evaluate (sub, values)
  % First output sample of SUB driven by Constant inputs.
  n = numel (values);
  blocks = struct ('type', {}, 'value', {}, 'name', {}, 'x', {}, 'y', {});
  edges = zeros (0, 4);
  for k = 1:n
    blocks(k) = leaf ('Constant', values{k}, sprintf ('c%d', k));
    edges(end+1, :) = [k 1 n+1 k];
  endfor
  blocks(n+1) = leaf ('Subsystem', sub, 'DUT');
  blocks(n+2) = leaf ('Scope', [], 'y');
  edges(end+1, :) = [n+1 1 n+2 1];
  result = ob_run (struct ('blocks', blocks, 'edges', edges), [0 1]);
  samples = ob_signal_values (result, n+2, 1);
  y = samples{1};
endfunction

function assert_error (callback, fragment)
  try
    callback ();
  catch err
    assert (! isempty (strfind (err.message, fragment)), ...
            sprintf ('expected "%s", got "%s"', fragment, err.message));
    return;
  end_try_catch
  error ('expected an error containing "%s"', fragment);
endfunction
