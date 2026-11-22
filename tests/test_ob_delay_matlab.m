function test_ob_delay_matlab ()
  % Compare Transport Delay feedback against recorded MATLAB dde23 solutions.
  % MATLAB is not needed at test time; regenerate with reference_ob_dde.m.
  reference = jsondecode (fileread (ob_test_reference ('matlab-dde-reference.json')));
  B = @(type, value, name) struct ('type', type, 'value', value, 'name', name, 'x', 0, 'y', 0);

  % x' = -x(t-1).  Cubic history interpolation keeps RK4 third order.
  model.blocks = [B('Integrator', 1, 'x') B('Transport Delay', [1 1], 'Delay') ...
                  B('Gain', -1, 'Gain') B('Scope', [], 'Scope')];
  model.edges = [1 2; 2 3; 3 1; 1 4];
  t = reference.linear_t(:)';
  expected = reference.linear_y(:);
  result = ob_run (model, t);
  assert (cell2mat (result.values(:, 4)), expected, 5e-5);
  result = ob_run (model, t, struct ('solver', 'ode45', 'reltol', 1e-10, 'abstol', 1e-12));
  assert (cell2mat (result.values(:, 4)), expected, 1e-6);

  % Mackey-Glass with a 17 s delay over 300 s.
  folder = fullfile (tempdir (), 'octave-blocks-delay-tests');
  if (! exist (folder, 'dir')), mkdir (folder); endif
  fid = fopen (fullfile (folder, 'ob_test_mackey_term.m'), 'w');
  fprintf (fid, 'function y = ob_test_mackey_term (z)\n  y = 0.2 * z ./ (1 + z.^10);\nendfunction\n');
  fclose (fid); addpath (folder); rehash ();
  model.blocks = [B('Integrator', 0.5, 'x') B('Transport Delay', [17 0.5], 'Delay') ...
                  B('Function', [], 'ob_test_mackey_term') B('Gain', -0.1, 'Decay') ...
                  B('Sum', [], 'Sum') B('Scope', [], 'Scope')];
  model.edges = [1 1 2 1; 2 1 3 1; 1 1 4 1; 3 1 5 1; 4 1 5 2; 5 1 1 1; 1 1 6 1];
  t = 0:0.5:300;
  result = ob_run (model, t);
  y = cell2mat (result.values(:, 6));
  assert (y(1:2:end), reference.mackey_y(:), 5e-5);
  printf ('Transport Delay matches MATLAB dde23 (%s)\n', reference.matlab_version);
endfunction
