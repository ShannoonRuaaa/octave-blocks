function test_ob_analysis (directory = '')
  % Regression suite for ob_linearize, ob_findop, ob_bode and ob_stepinfo:
  % analytic expectations, invalid input, Simulink linmod/trim results and
  % Simulink traces recorded by tests/reference/reference_ob_analysis.m, and
  % for each function a model built from its result that is exported to
  % strict C99 (compiled when gcc is available) and run accelerated.
  test_path_cleanup = ob_test_setup ();
  if (isempty (directory)), directory = ob_test_reference (); endif
  ref = jsondecode (fileread (fullfile (directory, 'simulink-analysis-reference.json')));
  scratch = tempname (); mkdir (scratch);
  cleanup_scratch = onCleanup (@() remove_folder (scratch));
  cases = 0;
  cases += linearize_analytic ();
  cases += linearize_reference (ref);
  cases += linearize_errors ();
  cases += findop_cases (ref);
  cases += bode_cases (ref);
  cases += stepinfo_cases (ref);
  cases += export_cases (scratch);
  printf ('Octave Blocks analysis tests passed (%d groups)\n', cases);
endfunction

% --- ob_linearize ----------------------------------------------------------

function count = linearize_analytic ()
  count = 0;
  % theta'' = u - sin(theta) - 0.2 theta': states [omega; theta] in block order.
  model = pendulum ();
  sys = ob_linearize (model);
  assert (isequal (sys.state_names, {'omega'; 'theta'}));
  assert_close (sys.A, [-0.2 -1; 1 0], 1e-9);
  assert_close (sys.B, [1; 0], 1e-9); assert_close (sys.C, [0 1], 1e-12);
  assert_close (sys.D, 0, 1e-12);
  assert_close (sys.x0, [0.1; 0], 0); assert_close (sys.u0, 0, 0);
  assert_close (sys.dx0, [-0.02; 0.1], 1e-15); assert_close (sys.y0, 0, 0);
  assert (isequal (sys.input_ports, 1) && isequal (sys.output_ports, 1));
  sys = ob_linearize (model, [0; pi]);                    % inverted: +cos(pi)
  assert_close (sys.A, [-0.2 1; 1 0], 1e-9);
  sys = ob_linearize (model, [-0.2; 0.3], 0.4, 'Time', 1.5, 'Perturbation', 1e-6);
  assert_close (sys.A, [-0.2 -cos(0.3); 1 0], 1e-9);
  assert_close (sys.dx0, [0.4 - sin(0.3) + 0.04; -0.2], 1e-15);
  assert (sys.t0 == 1.5);
  count += 1;

  % State space with feedthrough; vector root input and two Outports listed
  % out of port order; a subsystem's inner Outport is not a model output.
  A = [-1 2; 0 -3]; B = [1; 2]; C = [1 1]; D = 0.5;
  sys = ob_linearize (wrap (ob_state_space (A, B, C, D, [0.3; -0.2])));
  assert_close ([sys.A sys.B; sys.C sys.D], [A B; C D], 1e-9);
  assert_close (sys.y0, C * [0.3; -0.2], 1e-15);
  model = mimo ();
  sys = ob_linearize (model, [], {[0; 0], 0});
  assert_close (sys.A, diag ([-1 -2]), 1e-9);
  assert_close (sys.B, [1 0 0; 0 1 0], 1e-9);
  assert_close (sys.C, [1 1; 1 -1; 0 0], 1e-9);
  assert_close (sys.D, [0 0.5 0; 0 0 0; 0 0 2], 1e-9);
  assert (isequal (sys.input_index, [1 1; 1 2; 2 1]));
  assert (isequal (sys.output_index, [1 1; 1 2; 2 1]));
  assert (isequal (sys.output_ports, [1 2]));
  % Without datasets a flat U0 treats every port as scalar.
  assert_error (@() ob_linearize (model, [], [1; -1; 3]), 'ob_linearize:input', 'root Inports carry 2');
  model.inputs = {ob_input_signal(0, [5 6], [2 1]), ob_input_signal(0, 7)};
  sys = ob_linearize (model);                              % shapes from datasets, u0 = 0
  assert_close (sys.u0, zeros (3, 1), 0);
  sys = ob_linearize (inner_outport ());
  assert_close ([sys.A sys.B; sys.C sys.D], [0 1; 1 0.5], 1e-9);
  assert (isequal (sys.output_paths, {3}));
  count += 1;

  % Time-varying derivative at t0, Saturation inside/beyond its limit,
  % Limited Integrator inside its limits, models without inputs or outputs.
  ramp.blocks = struct ('type', {'Time', 'Integrator', 'Outport'}, 'value', {[], 0, 1}, ...
                        'name', {'t', 'x', 'y'}, 'x', {.1, .5, .9}, 'y', {.5, .5, .5});
  ramp.edges = [1 1 2 1; 2 1 3 1];
  sys = ob_linearize (ramp, [], [], 'Time', 2);
  assert_close (sys.dx0, 2, 0); assert_close (sys.A, 0, 0);
  assert (isempty (sys.B) && isequal (size (sys.B), [1 0]));
  sat = saturation ();
  assert_close (ob_linearize (sat, 0, 0.5).B, 1, 1e-9);
  assert_close (ob_linearize (sat, 0, 2).B, 0, 0);
  sys = ob_linearize (limited ());
  assert_close ([sys.A sys.B sys.C sys.D], [-1 1 1 0], 1e-9);
  sys = ob_linearize (pendulum_scope ());
  assert (isequal (size (sys.C), [0 2]) && isequal (size (sys.B), [2 0]));
  assert_close (sys.A, [-0.2 -1; 1 0], 1e-9);
  count += 1;
endfunction

function count = linearize_reference (ref)
  % Simulink linmod.  Simulink orders the pendulum states theta, omega.
  count = 0;
  L = ref.linmod;
  model = pendulum ();
  perm = [2 1];                                   % ours(perm) = Simulink order
  sys = ob_linearize (model);
  check_linmod (sys, L.pend_default, perm, {'theta', 'omega'}, 1e-8);
  sys = ob_linearize (model, vec (L.pend_inverted.x)(perm), L.pend_inverted.u);
  check_linmod (sys, L.pend_inverted, perm, {'theta', 'omega'}, 1e-8);
  sys = ob_linearize (model, vec (L.pend_input.x)(perm), L.pend_input.u);
  check_linmod (sys, L.pend_input, perm, {'theta', 'omega'}, 1e-8);
  sys = ob_linearize (wrap (ob_state_space ([-1 2; 0 -3], [1; 2], [1 1], 0.5, [0.3; -0.2])));
  check_linmod (sys, L.ss_feedthrough, [1 2], {}, 1e-9);
  sys = ob_linearize (mimo (), [], {[0; 0], 0});
  check_linmod (sys, L.mimo_vector, [1 2], {}, 1e-9);
  sys = ob_linearize (inner_outport ());
  check_linmod (sys, L.inner_outport, 1, {'plant/x'}, 1e-9);
  % Realizations differ (controllable vs observable form): compare invariants.
  sys = ob_linearize (wrap (ob_transfer_function (4, [1 2])));
  check_invariants (sys, L.tf_first_order, 1e-9);
  sys = ob_linearize (saturation (), 0, 0.5);
  check_linmod (sys, L.saturation_inside, 1, {'x'}, 1e-9);
  check_linmod (sys, L.saturation_inside_v5, 1, {'x'}, 1e-9);
  % Beyond the limit ob_linearize agrees with linmod's numerical 'v5' method
  % (B = 0).  linmod's default block-by-block method keeps the Saturation's
  % unity gain there (recorded B = 1): a documented difference.
  sys = ob_linearize (saturation (), 0, 2);
  check_linmod (sys, L.saturation_beyond_v5, 1, {'x'}, 0);
  assert (L.saturation_beyond.B == 1 && sys.B == 0);
  sys = ob_linearize (limited ());
  check_linmod (sys, L.limited_integrator, 1, {'x'}, 1e-9);
  % 'Method','v5' reproduces linmod(...,'v5') on nonlinear points too: a
  % forward difference with h = del*(1 + 1e-3*|v|), so x' = -x^2 gives
  % -2x - h and x' = u^2 gives 2u + h, and the right-hand slope at a kink.
  % The default central differences give the exact -2x (= linmod default).
  for item = {{'square_x1_v5', 1, 1e-5}, {'square_x100_v5', 100, 1e-5}, {'square_x1_v5_del2', 1, 1e-2}}
    [name, x, del] = item{1}{:};
    sys = ob_linearize (square (), x, [], 'Method', 'v5', 'Perturbation', del);
    check_linmod (sys, L.(name), 1, {'x'}, 1e-8);
    assert_close (sys.A, -2 * x - del * (1 + 1e-3 * x), 1e-8 * (1 + 2 * x));   % rounding
  endfor
  sys = ob_linearize (square (), 1);
  check_linmod (sys, L.square_x1, 1, {'x'}, 1e-9);
  assert (abs (L.square_x1_v5.A - sys.A) > 1e-5);         % the methods differ by ~del
  sys = ob_linearize (input_square (), 0, 100, 'Method', 'v5', 'Perturbation', 1e-2);
  check_linmod (sys, L.input_square_u100_v5, 1, {'x'}, 1e-8);
  assert_close (ob_linearize (input_square (), 0, 100, 'Perturbation', 1e-2).B, 200, 1e-8);
  sys = ob_linearize (saturation (), 0, 1, 'Method', 'v5');
  check_linmod (sys, L.saturation_upper_v5, 1, {'x'}, 1e-12);
  sys = ob_linearize (saturation (), 0, -1, 'Method', 'v5');
  check_linmod (sys, L.saturation_lower_v5, 1, {'x'}, 1e-12);
  assert_close (ob_linearize (saturation (), 0, 1).B, 0.5, 1e-12);   % central: mean slope
  sys = ob_linearize (saturation (), 0, 2, 'Method', 'v5');
  check_linmod (sys, L.saturation_beyond_v5, 1, {'x'}, 0);
  sys = ob_linearize (pendulum (), [], [], 'Method', 'V5');
  check_linmod (sys, L.pend_default, perm, {'theta', 'omega'}, 1e-5);
  count += 1;
endfunction

function count = linearize_errors ()
  count = 0;
  model = pendulum ();
  assert_error (@() ob_linearize (model, [1 2 3]), 'ob_linearize:state', 'X0 has 3 elements');
  assert_error (@() ob_linearize (model, [NaN; 0]), 'ob_linearize:state', 'finite real');
  assert_error (@() ob_linearize (model, [], [1 2]), 'ob_linearize:input', 'U0 has 2 elements');
  assert_error (@() ob_linearize (model, [], 1i), 'ob_linearize:input', 'finite real');
  assert_error (@() ob_linearize (model, [], {1, 2}), 'ob_linearize:input', 'one entry per root Inport');
  assert_error (@() ob_linearize (model, 'Time', NaN), '', 'Time');
  assert_error (@() ob_linearize (model, 'Perturbation', 0), '', 'Perturbation');
  assert_error (@() ob_linearize (model, 'Tme', 1), 'ob_linearize:arguments', 'unknown option');
  assert_error (@() ob_linearize (model, 'Time'), 'ob_linearize:arguments', 'name-value');
  assert_error (@() ob_linearize (model, 'Method', 'forward'), 'ob_linearize:arguments', 'Method must be');
  assert_error (@() ob_linearize (model, 'Method', 5), 'ob_linearize:arguments', 'Method must be');
  assert_error (@() ob_linearize (struct ('blocks', 1)), 'ob_linearize:model', 'invalid model');
  assert_error (@() ob_linearize ([]), 'ob_linearize:model', 'invalid model');
  assert_error (@() ob_linearize (), '', 'supply a model');
  inputs = mimo (); inputs.inputs = {ob_input_signal(0, [5 6], [2 1]), ob_input_signal(0, 7)};
  assert_error (@() ob_linearize (inputs, [], {1, 0}), 'ob_linearize:input', 'U0{1} must have 2 elements');
  % Discrete, delay and conditional states are rejected, never dropped.
  for item = {{'Unit Delay', 0}, {'Discrete Integrator', 0}, {'Transport Delay', [0.1 0]}}
    m.blocks = struct ('type', {'Inport', 'Integrator', item{1}{1}, 'Outport'}, ...
                       'value', {1, 0, item{1}{2}, 1}, 'name', {'u', 'x', 'z', 'y'}, ...
                       'x', {.1, .4, .7, .9}, 'y', {.5, .5, .5, .5});
    m.edges = [1 1 2 1; 2 1 3 1; 3 1 4 1];
    m.sample_times = zeros (4, 2);
    if (! strcmp (item{1}{1}, 'Transport Delay')), m.sample_times(3, :) = [0.1 0]; endif
    assert_error (@() ob_linearize (m), 'ob_linearize:unsupported', ['block z (' item{1}{1} ')']);
  endfor
  assert_error (@() ob_linearize (ob_conditional_example ()), 'ob_linearize:unsupported', 'Conditional Subsystem');
  lim = limited (); lim.blocks(3).value.initial = 10;
  assert_error (@() ob_linearize (lim), 'ob_linearize:unsupported', 'strictly inside its limits');
  assert_error (@() ob_linearize (limited (), 10.5), 'ob_linearize:unsupported', 'strictly inside');
  lim = limited (); lim.blocks(3).value.reset = 'rising';
  lim.blocks(end + 1) = struct ('type', 'Constant', 'value', 0, 'name', 'r', 'x', .4, 'y', .9);
  lim.edges(end + 1, :) = [6 1 3 2];
  assert_error (@() ob_linearize (lim), 'ob_linearize:unsupported', 'reset port');
  count += 1;
endfunction

% --- ob_findop -------------------------------------------------------------

function count = findop_cases (ref)
  count = 0;
  T = ref.trim;
  model = pendulum ();
  % Hold u = 0.5 (trim(sys,x0,u0,[],[],1,[])): theta = asin(0.5) = pi/6.
  [op, sys] = ob_findop (model, [0; 0.5], 0.5, [], [], 1, []);
  assert (op.converged && op.residual < 1e-12);
  assert_close (op.x, [0; pi/6], 1e-12); assert_close (op.u, 0.5, 0);
  assert_close (op.x([2 1]), vec (T.pend_fixed_u.x), 1e-7);   % trim's own accuracy ~7e-9
  assert_close (op.y, T.pend_fixed_u.y, 1e-7);
  assert_close (sys.A, [-0.2 -cos(pi/6); 1 0], 1e-9);
  assert (isequal (op.state_names, {'omega'; 'theta'}));
  % Target y = pi/4 with u free (trim(sys,x0,u0,y0,[],[],1)).
  op = ob_findop (model, [0; 0.5], 0, pi/4, [], [], 1);
  assert (op.converged);
  assert_close (op.u, sin (pi/4), 1e-12); assert_close (op.u, T.pend_target_y.u, 1e-9);
  assert_close (op.x([2 1]), vec (T.pend_target_y.x), 1e-9);
  % Hold a state instead: theta = pi/3 fixed, omega and u free.
  op = ob_findop (model, [0.3; pi/3], 0, [], 2, [], []);
  assert (op.converged); assert_close (op.u, sin (pi/3), 1e-12);
  assert_close (op.x, [0; pi/3], 1e-12);
  % First-order 4/(s+2) with y = 3: u = 1.5 (state values depend on realization).
  op = ob_findop (wrap (ob_transfer_function (4, [1 2])), [], 0, 3, [], [], 1);
  assert (op.converged);
  assert_close ([op.u op.y], [T.tf_target_y.u T.tf_target_y.y], 1e-12);
  % Autonomous pendulum from [0; 3] converges to the inverted equilibrium.
  op = ob_findop (pendulum_scope (), [0; 3]);
  assert (op.converged); assert_close (op.x, [0; pi], 1e-12);
  % No equilibrium: x' = 1 never settles; reported, not hidden.
  m.blocks = struct ('type', {'Constant', 'Integrator', 'Outport'}, 'value', {1, 0, 1}, ...
                     'name', {'c', 'x', 'y'}, 'x', {.1, .5, .9}, 'y', {.5, .5, .5});
  m.edges = [1 1 2 1; 2 1 3 1];
  op = ob_findop (m);
  assert (! op.converged && op.residual == 1);
  % Everything fixed: a plain evaluation.
  op = ob_findop (model, [0; pi/6], 0.5, [], 1:2, 1, []);
  assert (op.converged && op.output.iterations == 0);
  op = ob_findop (model, [0; 0.5], 0.5, [], [], 1, [], 'AbsTol', 1e-3, 'RelTol', 0, 'MaxIter', 50);
  assert (op.converged);
  assert_error (@() ob_findop (model, [], 0, [], [], [], 1), 'ob_findop:output', 'IY requires');
  assert_error (@() ob_findop (model, [], 0, [1 2], [], [], 1), '', 'Y0');
  assert_error (@() ob_findop (model, [], 0, [], 3), '', 'IX');
  assert_error (@() ob_findop (model, [], 0, [], [1 1]), 'ob_findop:index', 'must not repeat');
  assert_error (@() ob_findop (model, [], 0, [], [], 1.5), '', 'IU');
  assert_error (@() ob_findop (model, [1 2 3]), 'ob_findop:state', 'X0 has 3 elements');
  assert_error (@() ob_findop (model, 'MaxIter', 0), '', 'MaxIter');
  assert_error (@() ob_findop (model, 'AbsTol', -1), '', 'AbsTol');
  assert_error (@() ob_findop (model, 'Bogus', 1), 'ob_findop:arguments', 'unknown option');
  assert_error (@() ob_findop (ob_conditional_example ()), 'ob_findop:unsupported', 'Conditional');
  assert_error (@() ob_findop (model, 'Method', 'x'), 'ob_findop:arguments', 'Method must be');
  % Limited Integrator x' = -x + u (limits +-10) with u = 20 held: every x
  % past 10 has x' = 0.  OP.x is the limit, the value ob_run reaches; trim
  % stops past the limit (and moves the held input), a documented difference.
  lim = limited ();
  op = ob_findop (lim, 0, 20, [], [], 1, []);
  assert (op.converged && op.residual == 0);
  assert (op.x == 10 && op.u == 20 && op.y == 10 && op.dx == 0);
  assert (T.limited_beyond.x > 10 && T.limited_beyond.y == 10);
  run = ob_run (setfield (lim, 'inputs', {ob_input_signal(0, 20)}), 0:0.5:20);
  assert_close (run.values{end, 5}, 10, 1e-12);              % root Outport
  try
    [op, sys] = ob_findop (lim, 0, 20, [], [], 1, []);
    error ('expected ob_findop:unsupported for SYS on a limit');
  catch err
    assert (strcmp (err.identifier, 'ob_findop:unsupported'));
  end_try_catch
  [op, sys] = ob_findop (lim, 0, 5, [], [], 1, []);        % inside: as ob_linearize
  assert_close (op.x, 5, 1e-12); assert_close ([sys.A sys.B sys.C sys.D], [-1 1 1 0], 1e-9);
  sys5 = ob_linearize (lim, 5, 5, 'Method', 'v5');
  [op, sys] = ob_findop (lim, 0, 5, [], [], 1, [], 'Method', 'v5');
  assert_close ([sys.A sys.B], [sys5.A sys5.B], 0);
  assert_error (@() ob_findop (lim, 11, 20), 'ob_findop:state', 'outside its limits');
  count += 1;
endfunction

% --- ob_bode ---------------------------------------------------------------

function count = bode_cases (ref)
  count = 0;
  % 1/(s(s+1)(s+2)): Gm = 6 at sqrt(2), Pm at |H| = 1.
  [A, B, C, D] = companion (1, [1 3 2 0]);
  r = ob_bode (A, B, C, D);
  wcp = fzero (@(w) w^2 * (w^2 + 1) * (w^2 + 4) - 1, [0.1 1]);
  pm = 180 - 90 - atand (wcp) - atand (wcp / 2);
  assert_close ([r.Gm r.Wcg r.Pm r.Wcp], [6 sqrt(2) pm wcp], 1e-9);
  assert_close (squeeze (r.phase)', -90 - atand (r.w) - atand (r.w / 2), 1e-9);   % integrator branch
  assert (isequal (size (r.H), [1 1 numel(r.w)]) && all (diff (r.w) > 0));
  % Type-2 plant 10/(s^2(s+1)): negative phase margin, no phase crossover.
  [A, B, C, D] = companion (10, [1 1 0 0]);
  r = ob_bode (A, B, C, D, [0.01 1 100]);
  wcp = fzero (@(w) w^4 * (w^2 + 1) - 100, [1 3]);
  assert_close ([r.Pm r.Wcp], [-atand(wcp) wcp], 1e-9);
  assert (isinf (r.Gm) && isnan (r.Wcg));
  assert_close (squeeze (r.phase)', -180 - atand ([0.01 1 100]), 1e-9);
  % Lightly damped 4/(s^2+0.4s+4): no phase crossover (Gm = Inf).
  [A, B, C, D] = companion (4, [1 0.4 4]);
  r = ob_bode (A, B, C, D, [1 2 2.8 10]);
  assert (isinf (r.Gm) && isnan (r.Wcg));
  assert_close ([r.Pm r.Wcp], [180 - atan2d(0.4 * 2.8, 4 - 2.8^2), 2.8], 1e-9);
  assert_close (squeeze (r.phase)(2), -90, 1e-12);
  % First order 4/(s+2) at w = 2: |H| = sqrt(2), -45 degrees; the sys form.
  r = ob_bode (struct ('A', -2, 'B', 1, 'C', 4, 'D', 0), 2);
  assert_close ([r.mag r.phase r.mag_db], [sqrt(2) -45 20*log10(sqrt(2))], 1e-12);
  assert_close (r.H, 4 / (2i + 2), 1e-15);
  r = ob_bode (struct ('A', -2, 'B', 1, 'C', 4, 'D', 0));
  assert (isinf (r.Gm) && isnan (r.Wcg));
  assert_close ([r.Pm r.Wcp], [120 sqrt(12)], 1e-9);
  % Phase branches: 1/s^2 at -180, -1/(s+1) at +180, 1/(s-1) at -180,
  % the non-minimum-phase (1-s)/(s+1)^2 from 0 down to -270.
  r = ob_bode ([0 1; 0 0], [0; 1], [1 0], 0, [0.1 1 10]);
  assert_close (squeeze (r.phase)', [-180 -180 -180], 1e-9);
  assert (r.Pm == 0 && abs (r.Wcp - 1) < 1e-12);
  r = ob_bode (-1, 1, -1, 0, 1e-3);   assert_close (r.phase, 180 - atand (1e-3), 1e-9);
  r = ob_bode (1, 1, 1, 0, 1e-3);     assert_close (r.phase, -180 + atand (1e-3), 1e-9);
  [A, B, C, D] = companion ([-1 1], [1 2 1]);
  r = ob_bode (A, B, C, D, [1e-3 1e3]);
  assert_close (squeeze (r.phase)', [-3*atand(1e-3), -3*atand(1e3)], 1e-9);
  assert_close ([r.Gm r.Wcg], [2 sqrt(3)], 1e-9);
  % MIMO and static gain.
  r = ob_bode (diag ([-1 -2]), eye (2), [1 1; 1 -1], [0 0.5; 0 0], [0.5 5]);
  assert (isequal (size (r.H), [2 2 2]) && isnan (r.Gm) && isnan (r.Pm));
  assert_close (r.H(:, :, 1), [1 1; 1 -1] * diag (1 ./ (0.5i + [1 2])) + [0 0.5; 0 0], 1e-14);
  r = ob_bode (zeros (0), zeros (0, 1), zeros (1, 0), 3, 1);
  assert (r.H == 3 && r.phase == 0 && isinf (r.Gm) && isinf (r.Pm));
  % |H| = 1 everywhere (static gain 1, all-pass (s-1)/(s+1)): no gain
  % crossover per grid point, just none.
  r = ob_bode (zeros (0), zeros (0, 1), zeros (1, 0), 1);
  assert (isempty (r.margins.PhaseMargin) && isinf (r.Pm) && isnan (r.Wcp));
  r = ob_bode (-1, 1, -2, 1);
  assert (isempty (r.margins.PhaseMargin) && isinf (r.Pm) && isnan (r.Wcp));
  assert_close (squeeze (r.phase)', 180 - 2 * atand (r.w), 1e-9);   % -1 at w = 0: +180 branch
  % Undamped pole 1/(s^2+1): H is Inf at w = 1 (phase NaN) with no
  % singular-matrix warning; an uncontrollable undamped mode stays finite.
  lastwarn ('');
  r = ob_bode ([0 1; -1 0], [0; 1], [1 0], 0, [0.5 1 2]);
  assert (isempty (lastwarn ()), 'ob_bode warned: %s', lastwarn ());
  assert_close (squeeze (r.mag)([1 3])', [4/3 1/3], 1e-12);
  assert (isinf (r.H(2)) && isinf (r.mag(2)) && isinf (r.mag_db(2)) && isnan (r.phase(2)));
  assert_close (squeeze (r.phase)([1 3])', [0 -180], 1e-9);
  r = ob_bode ([0 1; -1 0], [0; 1], [1 0], 0);
  assert (isempty (lastwarn ()) && r.Pm == 0 && abs (r.Wcp - sqrt (2)) < 1e-9 && isinf (r.Gm));
  r = ob_bode (blkdiag ([0 1; -1 0], -1), [0 0; 1 0; 0 1], [1 0 0; 0 0 1], zeros (2), 1);
  assert (isinf (r.H(1, 1)) && all (isfinite (r.H([2 3 4]))));
  assert_close (r.H(2, 2), 1 / (1i + 1), 1e-9);
  % 100(s+1)^2/(s^3(s+10)) in a rotated basis, where eig splits the triple
  % pole at 0 by ~1e-5: no spurious low-frequency crossing, same margins
  % as the companion form, phase on the -270 degree branch.  At 1e-3 rad/s
  % the rotated 1i*w*I - A is nearly singular, so the phase there carries
  % ~1e-6 degree of BLAS/LAPACK-dependent solve rounding, and one-ulp
  % changes to the rotated A move it by up to ~3e-5 degree.
  [A, B, C, D] = companion (100 * [1 2 1], [1 10 0 0 0]);
  [Q, unused] = qr ([4 1 0 2; 1 3 1 0; 0 1 5 1; 2 0 1 6]);
  assert (max (abs (eig (Q * A * Q'))(abs (eig (Q * A * Q')) < 1)) > 1e-7);   % split
  base = ob_bode (A, B, C, D);
  w = [1e-3 0.1 1 10];
  r = ob_bode (Q * A * Q', Q * B, C * Q', D, w);
  assert_close (squeeze (r.phase)', -270 + 2 * atand (w) - atand (w / 10), 1e-4);
  assert (numel (r.margins.GainMargin) == 1 && numel (base.margins.GainMargin) == 1);
  assert_close ([r.Gm r.Wcg r.Pm r.Wcp], [base.Gm base.Wcg base.Pm base.Wcp], 1e-7);
  % Linearized pendulum: H = 1/(s^2+0.2s+1) from ob_linearize's struct.
  r = ob_bode (ob_linearize (pendulum ()), 0.7);
  assert_close (r.H, 1 / (1 - 0.49 + 0.14i), 1e-9);
  % Recorded Simulink sine response of 4/(s^2+0.4s+4) at 2.8 rad/s.
  tr = ref.traces.sine_resonant;
  [mag, phase] = sine_fit (vec (tr.t), vec (tr.y), tr.w, -0.2 + 1i * sqrt (3.96));
  r = ob_bode (companion_struct (4, [1 0.4 4]), tr.w);
  assert_close ([mag phase], [r.mag r.phase], 1e-7);
  assert_error (@() ob_bode ([1 2], 1, 1, 0), 'ob_bode:dimensions', 'square');
  assert_error (@() ob_bode (-1, [1; 1], 1, 0), 'ob_bode:dimensions', 'dimensions');
  assert_error (@() ob_bode (-1, 1, 1, NaN), 'ob_bode:matrix', 'finite');
  assert_error (@() ob_bode (-1, 1, 1, 0, [-1 1]), 'ob_bode:frequency', 'positive');
  assert_error (@() ob_bode (-1, 1, 1, 0, [1 Inf]), 'ob_bode:frequency', 'positive');
  assert_error (@() ob_bode (-1, 1, 1, 0, []), 'ob_bode:frequency', 'positive');
  assert_error (@() ob_bode (struct ('A', -1)), 'ob_bode:arguments', 'fields A, B, C and D');
  assert_error (@() ob_bode (-1, 1, 1), 'ob_bode:arguments', 'supply');
  count += 1;
endfunction

% --- ob_stepinfo -------------------------------------------------------------

function count = stepinfo_cases (ref)
  count = 0;
  % Recorded Simulink step of 4/(s^2+1.2s+4): zeta = 0.3, wn = 2.
  tr = ref.traces.step_underdamped;
  t = vec (tr.t); y = vec (tr.y);
  info = ob_stepinfo (y, t, 1);
  wd = sqrt (4 - 0.36);
  exact = @(s) 1 - exp (-0.6 * s) .* (cos (wd * s) + 0.6 / wd * sin (wd * s));
  rise = fzero (@(s) exact (s) - 0.9, [0.5 1.5]) - fzero (@(s) exact (s) - 0.1, [0.01 0.5]);
  settle = fzero (@(s) abs (exact (s) - 1) - 0.02, [5.5 6.5]);
  mp = 100 * exp (-0.3 * pi / sqrt (1 - 0.09));
  assert_close (info.Overshoot, mp, 2e-3);
  assert_close (info.PeakTime, pi / wd, 0.005 + 1e-12);
  assert_close (info.Peak, 1 + mp / 100, 2e-5);
  assert_close (info.RiseTime, rise, 1e-4);
  assert_close (info.SettlingTime, settle, 1e-3);
  assert_close (info.TransientTime, info.SettlingTime, 0);       % max error = |yfinal - yinit|
  risen = find (y >= 0.9, 1);                                     % SettlingMin/Max window
  assert_close ([info.SettlingMin info.SettlingMax], [min(y(risen:end)) max(y)], 0);
  assert_close (info.SettlingMin, exact (2 * pi / wd), 1e-4);    % first trough
  assert (info.Undershoot == 0 && info.SteadyState == 1);
  % The same step through ob_run (rk4, the ode4 method) gives the same data.
  result = ob_run (step_model (4, [1 1.2 4], 0), t');
  assert_close (ob_scope_data (result, 5), y, 1e-10);
  % Non-minimum phase (1-s)/(s+1)^2: undershoot 100*(2/sqrt(e) - 1).
  tr = ref.traces.step_nonminimum;
  info = ob_stepinfo (vec (tr.y), vec (tr.t), 1);
  assert_close (info.Undershoot, 100 * (2 * exp (-0.5) - 1), 1e-3);
  assert (info.Overshoot == 0);
  % Offset response 2 + 3(1 - e^-t): relative to yinit = 2 and to MATLAB's
  % default yinit = 0, where TransientTime and SettlingTime differ.
  tr = ref.traces.step_offset;
  t = vec (tr.t); y = vec (tr.y);
  info = ob_stepinfo (y, t, 5, 2);
  assert_close ([info.RiseTime info.SettlingTime info.TransientTime], [log(9) log(50) log(50)], 2e-4);
  assert_close (info.Peak, 3 * (1 - exp (-10)), 1e-6);
  info = ob_stepinfo (y, t, 5);
  assert_close ([info.RiseTime info.SettlingTime info.TransientTime], [log(6) log(30) log(50)], 2e-4);
  assert_close ([info.Peak info.PeakTime], [y(end) 10], 0);
  % yfinal defaults to the last sample; options as name-value or struct.
  a = ob_stepinfo (y, t, [], 2);
  assert_close (a.SteadyState, y(end), 0);
  a = ob_stepinfo (y, t, 5, 2, 'RiseTimeLimits', [0.05 0.95], 'SettlingTimeThreshold', 0.05);
  b = ob_stepinfo (y, t, 5, 2, struct ('RiseTimeLimits', [0.05 0.95], 'SettlingTimeThreshold', 0.05));
  assert (isequal (a, b));
  assert_close ([a.RiseTime a.SettlingTime], [log(19) log(20)], 3e-4);
  % Unsettled data, zero step, never reaching the upper rise limit, channels.
  s = (0:0.1:10)';
  info = ob_stepinfo (sin (s), s, 0, 0);
  assert (isnan (info.SettlingTime) && isnan (info.RiseTime) && isnan (info.Overshoot));
  assert (isnan (info.TransientTime));
  info = ob_stepinfo (0.5 * (1 - exp (-s)), s, 1);
  assert (isnan (info.SettlingTime) && isnan (info.RiseTime) && isnan (info.SettlingMin));
  info = ob_stepinfo ([1 - exp(-s), 2 * (1 - exp(-2 * s))], s);
  assert (isequal (size (info), [2 1]));
  assert_close ([info.SteadyState], [1 - exp(-10), 2 * (1 - exp(-20))], 1e-15);
  assert_close (info(2).RiseTime, log (9) / 2, 5e-3);
  assert_error (@() ob_stepinfo ([1 2 3], [0 2 1]), 'ob_stepinfo:time', 'strictly increasing');
  assert_error (@() ob_stepinfo ([1 2 NaN], [0 1 2]), 'ob_stepinfo:data', 'finite');
  assert_error (@() ob_stepinfo ([1 2], [0 1 2]), 'ob_stepinfo:data', 'one row per time');
  assert_error (@() ob_stepinfo (1, 0), 'ob_stepinfo:time', 'at least two');
  assert_error (@() ob_stepinfo ([0 1], [0 1], [1 2 3]), 'ob_stepinfo:value', 'YFINAL');
  assert_error (@() ob_stepinfo ([0 1], [0 1], 1, Inf), 'ob_stepinfo:value', 'YINIT');
  assert_error (@() ob_stepinfo ([0 1], [0 1], 'SettlingTimeThreshold', 0), 'ob_stepinfo:option', '(0, 1)');
  assert_error (@() ob_stepinfo ([0 1], [0 1], 'SettlingTimeThreshold', 1), 'ob_stepinfo:option', '(0, 1)');
  assert_error (@() ob_stepinfo ([0 1], [0 1], 'RiseTimeLimits', [0.9 0.1]), 'ob_stepinfo:option', 'lo <= hi');
  assert_error (@() ob_stepinfo ([0 1], [0 1], 'RiseTimeLimits', [0 2]), 'ob_stepinfo:option', 'lo <= hi');
  assert_error (@() ob_stepinfo ([0 1], [0 1], 'Bogus', 1), 'ob_stepinfo:arguments', 'unknown option');
  assert_error (@() ob_stepinfo ([0 1]), 'ob_stepinfo:arguments', 'supply');
  count += 1;
endfunction

% --- models built from each result: strict C99 export and accelerator ------

function count = export_cases (scratch)
  count = 0;
  grid = 0:0.01:5;
  % ob_linearize: nonlinear pendulum and its linearization side by side,
  % both driven by a small step; the small-signal outputs agree.
  sys = ob_linearize (pendulum (), [0; 0]);
  m = pendulum_source ([0 0 0.01], [0; 0]);
  m.blocks(10) = block ('Subsystem', ob_state_space (sys.A, sys.B, sys.C, sys.D, [0; 0]), 'linear');
  m.blocks(11) = block ('Scope', [], 'linear y');
  m.edges = [m.edges; 1 1 10 1; 10 1 11 1];
  [result, ~] = export_and_compare (m, grid, scratch, 'linearize');
  nonlinear = ob_scope_data (result, 9); linear = ob_scope_data (result, 11);
  assert (max (abs (nonlinear - linear)) < 1e-3 * max (abs (nonlinear)));
  % ob_findop: starting at the operating point the model stays there.
  op = ob_findop (pendulum (), [0; 0.5], 0.5, [], [], 1, []);
  m = pendulum_source ([0 0.5 0.5], op.x);
  result = export_and_compare (m, grid, scratch, 'findop');
  assert (max (abs (ob_scope_data (result, 9) - pi/6)) < 1e-12);
  % ob_bode: steady-state sine response of 4/(s^2+0.4s+4) at 2.8 rad/s.
  w = 2.8; long = 0:0.01:60;
  m.blocks = [block('Time', [], 't'), block('Gain', w, 'w'), block('Function', [], 'sin'), ...
              block('Subsystem', ob_transfer_function (4, [1 0.4 4]), 'plant'), block('Scope', [], 'y')];
  m.edges = [1 1 2 1; 2 1 3 1; 3 1 4 1; 4 1 5 1];
  result = export_and_compare (m, long, scratch, 'bode');
  keep = long >= 50 - 1e-9;
  [mag, phase] = sine_fit (long(keep)', ob_scope_data (result, 5)(keep), w, -0.2 + 1i * sqrt (3.96));
  r = ob_bode (companion_struct (4, [1 0.4 4]), w);
  assert_close ([mag phase], [r.mag r.phase], 1e-6);
  % ob_stepinfo on the exported and accelerated step response.
  m = step_model (4, [1 1.2 4], 0);
  long = 0:0.01:10;
  [result, csv] = export_and_compare (m, long, scratch, 'stepinfo');
  a = ob_stepinfo (ob_scope_data (result, 5), result.t, 1);
  if (! isempty (csv))
    b = ob_stepinfo (csv(:, end), csv(:, 1), 1);
    assert_close ([a.RiseTime a.SettlingTime a.Overshoot], [b.RiseTime b.SettlingTime b.Overshoot], 1e-9);
  endif
  assert_close (a.Overshoot, 100 * exp (-0.3 * pi / sqrt (0.91)), 2e-3);
  count += 1;
endfunction

function [result, csv] = export_and_compare (model, grid, scratch, name)
  % ob_run, ob_run accelerated, and the strict C99 export (compiled and run
  % when gcc is available) give the same flat values.
  result = ob_run (model, grid);
  fast = ob_run (model, grid, struct ('accelerate', true));
  for b = 1:columns (result.flat_values)
    for k = 1:numel (grid)
      assert_close (fast.flat_values{k, b}, result.flat_values{k, b}, 1e-12);
    endfor
  endfor
  source = fullfile (scratch, [name '.c']);
  info = ob_codegen (model, source, [grid(1) grid(end) grid(2) - grid(1)]);
  text = fileread (source);
  assert (! isempty (strfind (text, 'int main(void)')));
  csv = [];
  gcc = compiler ();
  if (isempty (gcc))
    printf ('  %s: gcc not found; C export written but not compiled\n', name);
    return;
  endif
  exe = fullfile (scratch, [name '.exe']); out = fullfile (scratch, [name '.csv']);
  [status, message] = system (sprintf ('"%s" -std=c99 -O2 -Wall -Wextra -Werror -DOB_STANDALONE "%s" -lm -o "%s"', ...
                                       gcc, source, exe));
  assert (status == 0, 'C compile failed for %s: %s', name, message);
  [status, message] = system (sprintf ('"%s" > "%s"', exe, out));
  assert (status == 0, 'C run failed for %s: %s', name, message);
  csv = dlmread (out, ',', 1, 0);
  expected = result.t(:);
  for b = 1:numel (result.compiled_model.blocks)
    count = prod (info.shapes{b});
    if (count == 0), continue; endif
    traces = zeros (numel (result.t), count);
    for k = 1:numel (result.t), traces(k, :) = result.flat_values{k, b}(:)'; endfor
    expected = [expected traces];
  endfor
  assert (isequal (size (csv), size (expected)), 'C output shape differs for %s', name);
  err = max (abs (csv(:) - expected(:)) ./ max (1, abs (expected(:))));
  assert (err < 1e-11, 'C/Octave mismatch for %s: %g', name, err);
  printf ('  %s: strict C99 export compiled, worst scaled error %.3g; accelerated run matches\n', name, err);
endfunction

function gcc = compiler ()
  % Off Windows, a gcc.exe on PATH (WSL appends the Windows PATH) builds
  % Windows executables this system cannot run: use the native gcc.
  gcc = '';
  if (ispc ()), gcc = file_in_path (getenv ('PATH'), 'gcc.exe'); endif
  if (isempty (gcc)), gcc = file_in_path (getenv ('PATH'), 'gcc'); endif
  if (isempty (gcc))
    candidate = fullfile (OCTAVE_HOME (), 'bin', 'gcc.exe');
    if (exist (candidate, 'file')), gcc = candidate; endif
  endif
endfunction

% --- comparison helpers ------------------------------------------------------

function check_linmod (sys, r, perm, names, tol)
  s = r.sizes;
  A = mat (r.A, s(1), s(2)); B = mat (r.B, s(3), s(4));
  C = mat (r.C, s(5), s(6)); D = mat (r.D, s(7), s(8));
  assert_close (sys.A(perm, perm), A, tol);
  assert_close (sys.B(perm, :), B, tol);
  assert_close (sys.C(:, perm), C, tol);
  assert_close (sys.D, D, tol);
  if (! isempty (names))
    assert (isequal (cellstr (r.states(:)')(:), names(:)));
    assert (isequal (sys.state_names(perm), names(:)));
  endif
endfunction

function check_invariants (sys, r, tol)
  % Realization-independent: poles, Markov parameters C A^k B, and D.
  s = r.sizes;
  A = mat (r.A, s(1), s(2)); B = mat (r.B, s(3), s(4));
  C = mat (r.C, s(5), s(6)); D = mat (r.D, s(7), s(8));
  assert_close (sort (eig (sys.A)), sort (eig (A)), tol);
  for k = 0:rows (A)
    assert_close (sys.C * sys.A^k * sys.B, C * A^k * B, tol * 10^k);
  endfor
  assert_close (sys.D, D, tol);
endfunction

function v = mat (v, r, c)
  if (isempty (v)), v = zeros (r, c);
  elseif (! isequal (size (v), [r c])), v = reshape (v, r, c); endif
endfunction

function v = vec (v)
  v = v(:);
endfunction

function [mag, phase] = sine_fit (t, y, w, pole)
  % Least-squares fit y = a sin(wt) + b cos(wt) plus the residual transient
  % of the complex POLE: gain and phase (degrees) relative to sin(wt).
  decay = exp (real (pole) * t);
  basis = [sin(w * t), cos(w * t), decay .* sin(imag (pole) * t), decay .* cos(imag (pole) * t)];
  coeff = basis \ y;
  mag = hypot (coeff(1), coeff(2));
  phase = atan2d (coeff(2), coeff(1));
endfunction

function [A, B, C, D] = companion (num, den)
  % Controllable canonical form of num/den (proper).
  n = numel (den) - 1; den = den / den(1);
  num = [zeros(1, n + 1 - numel (num)) num] / 1;
  A = [zeros(n - 1, 1) eye(n - 1); -fliplr(den(2:end))];
  B = [zeros(n - 1, 1); 1];
  D = num(1);
  C = fliplr (num(2:end) - D * den(2:end));
endfunction

function sys = companion_struct (num, den)
  [A, B, C, D] = companion (num, den);
  sys = struct ('A', A, 'B', B, 'C', C, 'D', D);
endfunction

% --- models ------------------------------------------------------------------

function b = block (type, value, name)
  b = struct ('type', type, 'value', value, 'name', name, 'x', 0.5, 'y', 0.5);
endfunction

function model = pendulum ()
  % theta'' = u - sin(theta) - 0.2 theta', y = theta; omega(0) = 0.1.
  model = pendulum_source ([], [0.1; 0]);
  model.blocks(1) = block ('Inport', 1, 'u');
  model.blocks(9) = block ('Outport', 1, 'y');
endfunction

function model = pendulum_source (step, initial)
  % The pendulum driven by a Step [time initial final], observed by a Scope.
  model.blocks = [block('Step', step, 'u'), block('Sum', [], 's1'), block('Sum', [], 's2'), ...
                  block('Integrator', initial(1), 'omega'), block('Integrator', initial(2), 'theta'), ...
                  block('Function', [], 'sin'), block('Gain', -1, 'neg'), block('Gain', -0.2, 'damp'), ...
                  block('Scope', [], 'y')];
  model.edges = [1 1 2 1; 7 1 2 2; 2 1 3 1; 8 1 3 2; 3 1 4 1; 4 1 5 1; 5 1 6 1; ...
                 6 1 7 1; 4 1 8 1; 5 1 9 1];
endfunction

function model = pendulum_scope ()
  model = pendulum_source ([0 0 0], [0.1; 0]);
  model.blocks(1) = block ('Constant', 0, 'u');
endfunction

function model = wrap (child)
  model.blocks = [block('Inport', 1, 'u'), block('Subsystem', child, 'plant'), block('Outport', 1, 'y')];
  model.edges = [1 1 2 1; 2 1 3 1];
endfunction

function model = mimo ()
  % Outport 'w' (port 2) is listed before 'y' (port 1).
  plant = ob_state_space (diag ([-1 -2]), eye (2), [1 1; 1 -1], [0 0.5; 0 0], [0; 0]);
  model.blocks = [block('Inport', 1, 'u'), block('Inport', 2, 'v'), block('Outport', 2, 'w'), ...
                  block('Subsystem', plant, 'SS'), block('Gain', 2, 'G'), block('Outport', 1, 'y')];
  model.edges = [1 1 4 1; 4 1 6 1; 2 1 5 1; 5 1 3 1];
endfunction

function model = inner_outport ()
  child.blocks = [block('Inport', 1, 'In1'), block('Integrator', 0, 'x'), block('Gain', 0.5, 'half'), ...
                  block('Sum', [], 'sum'), block('Outport', 1, 'Out1')];
  child.edges = [1 1 2 1; 1 1 3 1; 2 1 4 1; 3 1 4 2; 4 1 5 1];
  model = wrap (child);
endfunction

function model = saturation ()
  model.blocks = [block('Inport', 1, 'u'), block('Saturation', [-1 1], 'sat'), ...
                  block('Integrator', 0, 'x'), block('Outport', 1, 'y')];
  model.edges = [1 1 2 1; 2 1 3 1; 3 1 4 1];
endfunction

function model = square ()
  % x' = -x^2, y = x; x(0) = 1.
  model.blocks = [block('Integrator', 1, 'x'), block('Product', [], 'sq'), ...
                  block('Gain', -1, 'g'), block('Outport', 1, 'y')];
  model.edges = [1 1 2 1; 1 1 2 2; 2 1 3 1; 3 1 1 1; 1 1 4 1];
endfunction

function model = input_square ()
  % x' = u^2, y = x.
  model.blocks = [block('Inport', 1, 'u'), block('Product', [], 'sq'), ...
                  block('Integrator', 0, 'x'), block('Outport', 1, 'y')];
  model.edges = [1 1 2 1; 1 1 2 2; 2 1 3 1; 3 1 4 1];
endfunction

function model = limited ()
  % x' = -x + u with output limits +-10, x(0) = 0.2.
  model.blocks = [block('Inport', 1, 'u'), block('Sum', [], 'sum'), ...
                  block('Limited Integrator', struct ('initial', 0.2, 'lower', -10, 'upper', 10), 'x'), ...
                  block('Gain', -1, 'neg'), block('Outport', 1, 'y')];
  model.edges = [1 1 2 1; 4 1 2 2; 2 1 3 1; 3 1 4 1; 3 1 5 1];
endfunction

function model = step_model (num, den, offset)
  model.blocks = [block('Step', [0 0 1], 'step'), block('Subsystem', ob_transfer_function (num, den), 'tf'), ...
                  block('Constant', offset, 'c'), block('Sum', [], 'sum'), block('Scope', [], 'y')];
  model.edges = [1 1 2 1; 2 1 4 1; 3 1 4 2; 4 1 5 1];
endfunction

% --- assertions --------------------------------------------------------------

function assert_close (actual, expected, tol)
  assert (isequal (size (actual), size (expected)), 'size %s vs %s', ...
          mat2str (size (actual)), mat2str (size (expected)));
  err = max (abs (actual(:) - expected(:)));
  if (isempty (err)), return; endif
  assert (err <= tol, 'error %.3g exceeds %.3g: %s vs %s', err, tol, ...
          mat2str (actual, 12), mat2str (expected, 12));
endfunction

function assert_error (callback, identifier, fragment)
  try
    callback ();
  catch err
    assert (! isempty (strfind (err.message, fragment)), ...
            'expected error containing "%s", got "%s"', fragment, err.message);
    if (! isempty (identifier))
      assert (strcmp (err.identifier, identifier), 'expected identifier %s, got %s', ...
              identifier, err.identifier);
    endif
    return;
  end_try_catch
  error ('expected an error containing "%s"', fragment);
endfunction

function remove_folder (folder)
  if (exist (folder, 'dir'))
    confirm_recursive_rmdir (false, 'local');
    rmdir (folder, 's');
  endif
endfunction
