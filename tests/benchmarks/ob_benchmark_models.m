function cases = ob_benchmark_models ()
  % Shared engine benchmark set: interpreted runs, accelerated runs and the
  % recorded Simulink timings all use exactly these models and settings.
  % Each case has name, model, t (output times) and options (ob_run options).
  % Needs inst/, inst/examples/ and tests/benchmarks/: ob_setup ('tests').
  B = @(type, value, name) struct ('type', type, 'value', value, 'name', name, 'x', 0, 'y', 0);
  cases = struct ('name', {}, 'model', {}, 't', {}, 'options', {});

  % Harmonic oscillator x'' = -x through two Integrators.
  oscillator = ob_oscillator ();
  cases(end+1) = entry ('oscillator_rk4', oscillator, 0:0.01:20, struct ('solver', 'rk4'));
  cases(end+1) = entry ('oscillator_ode45', oscillator, 0:0.1:20, ...
                        struct ('solver', 'ode45', 'reltol', 1e-8, 'abstol', 1e-10));

  % Delay differential equation x' = -x(t-1), x = 1 for t <= 0.
  dde.blocks = [B('Integrator', 1, 'x') B('Transport Delay', [1 1], 'Delay') ...
                B('Gain', -1, 'Gain') B('Scope', [], 'Scope')];
  dde.edges = [1 2; 2 3; 3 1; 1 4];
  cases(end+1) = entry ('dde_rk4', dde, 0:0.01:6, struct ('solver', 'rk4'));
  cases(end+1) = entry ('dde_ode45', dde, 0:0.1:6, ...
                        struct ('solver', 'ode45', 'reltol', 1e-10, 'abstol', 1e-12));

  % Mackey-Glass: x' = 0.2 z / (1 + z^10) - 0.1 x, z = x(t - 17), x0 = 0.5.
  mackey.blocks = [B('Integrator', 0.5, 'x') B('Transport Delay', [17 0.5], 'Delay') ...
                   B('Function', [], 'ob_bench_mackey_term') B('Gain', -0.1, 'Decay') ...
                   B('Sum', [], 'Sum') B('Scope', [], 'Scope')];
  mackey.edges = [1 1 2 1; 2 1 3 1; 1 1 4 1; 3 1 5 1; 4 1 5 2; 5 1 1 1; 1 1 6 1];
  cases(end+1) = entry ('mackey_rk4', mackey, 0:0.1:300, struct ('solver', 'rk4'));
  cases(end+1) = entry ('mackey_ode45', mackey, 0:1:300, ...
                        struct ('solver', 'ode45', 'reltol', 1e-6, 'abstol', 1e-8));

  % Nonlinear controls with zero-crossing localization.
  cases(end+1) = entry ('control_zc_ode45', ob_control_example (), 0:0.01:10, ...
                        struct ('solver', 'ode45', 'zero_crossings', true));

  % Enabled/triggered conditional subsystems.
  cases(end+1) = entry ('conditional_rk4', ob_conditional_example (), 0:0.01:10, struct ('solver', 'rk4'));

  % Tenth-order linear system driven by a step.
  n = 10;
  A = -eye (n) + diag (0.5 * ones (n-1, 1), 1);
  plant = ob_state_space (A, ones (n, 1), ones (1, n), 0, zeros (n, 1));
  linear.blocks = [B('Step', [1 0 1], 'Step') B('Subsystem', plant, 'Plant') B('Scope', [], 'Scope')];
  linear.edges = [1 2; 2 3];
  cases(end+1) = entry ('linear10_rk4', linear, 0:0.01:10, struct ('solver', 'rk4'));
endfunction

function c = entry (name, model, t, options)
  c = struct ('name', name, 'model', model, 't', t, 'options', options);
endfunction
