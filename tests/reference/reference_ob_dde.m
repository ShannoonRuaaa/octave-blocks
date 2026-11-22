function reference_ob_dde (file)
  % Generate MATLAB dde23 references for Transport Delay feedback models,
  % independently of Octave.  Run in MATLAB:
  %   reference_ob_dde ('matlab-dde-reference.json')
  if exist ('OCTAVE_VERSION', 'builtin')
    error ('reference_ob_dde: run this producer in MATLAB');
  end
  options = ddeset ('RelTol', 1e-10, 'AbsTol', 1e-12);
  % x' = -x(t-1), x = 1 for t <= 0.
  linear_t = 0:0.1:6;
  tic; linear = dde23 (@(t, y, z) -z, 1, 1, [0 6], options); linear_seconds = toc;
  % Mackey-Glass: x' = 0.2 x(t-17) / (1 + x(t-17)^10) - 0.1 x, x = 0.5 for t <= 0.
  mackey_t = 0:1:300;
  tic;
  mackey = dde23 (@(t, y, z) 0.2*z/(1 + z^10) - 0.1*y, 17, 0.5, [0 300], options);
  mackey_seconds = toc;
  evidence = struct ('matlab_version', version, 'producer', 'reference_ob_dde.m', ...
      'reltol', 1e-10, 'abstol', 1e-12, ...
      'linear_t', linear_t, 'linear_y', deval (linear, linear_t), 'linear_seconds', linear_seconds, ...
      'mackey_t', mackey_t, 'mackey_y', deval (mackey, mackey_t), 'mackey_seconds', mackey_seconds);
  fid = fopen (file, 'w');
  fprintf (fid, '%s', jsonencode (evidence));
  fclose (fid);
end
