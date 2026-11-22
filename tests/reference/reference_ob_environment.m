function reference_ob_environment (file)
  % Record whether a usable Simulink engine is present, independently of
  % Octave.  Run in MATLAB:  reference_ob_environment ('matlab-environment.json')
  % A positive license test alone is not evidence of an engine, so this also
  % builds and simulates a small unsaved model and checks its result.
  if exist ('OCTAVE_VERSION', 'builtin')
    error ('reference_ob_environment: run this producer in MATLAB');
  end
  record = struct ('matlab_version', version, 'producer', 'reference_ob_environment.m', ...
                   'simulink_installed', false, 'simulink_version', '', ...
                   'simulink_license_test', license ('test', 'Simulink'), ...
                   'simulink_license_checkout', false, ...
                   'load_system_available', exist ('load_system', 'file') ~= 0, ...
                   'simulation_ok', false, 'simulation_max_error', NaN, 'simulation_message', '');
  details = ver ('simulink');
  if ~isempty (details)
    record.simulink_installed = true;
    record.simulink_version = details(1).Version;
  end
  record.simulink_license_checkout = logical (license ('checkout', 'Simulink'));
  if record.simulink_installed && record.load_system_available
    [~, suffix] = fileparts (tempname); name = ['ob_env_' suffix];
    try
      new_system (name);
      cleanup = onCleanup (@() close_system (name, 0));
      add_block ('simulink/Sources/Sine Wave', [name '/Sine']);
      add_block ('simulink/Continuous/Integrator', [name '/Int']);
      add_block ('simulink/Sinks/Out1', [name '/Out1']);
      add_line (name, 'Sine/1', 'Int/1'); add_line (name, 'Int/1', 'Out1/1');
      set_param (name, 'StopTime', '2*pi', 'Solver', 'ode45', 'RelTol', '1e-9', ...
                 'AbsTol', '1e-12', 'SaveFormat', 'Array', 'ReturnWorkspaceOutputs', 'on');
      out = sim (name);
      t = out.tout; y = out.yout;
      record.simulation_max_error = max (abs (y(:) - (1 - cos (t(:)))));
      record.simulation_ok = record.simulation_max_error < 1e-6;
    catch err
      record.simulation_message = err.message;
    end
  end
  fid = fopen (file, 'w');
  if fid < 0, error ('reference_ob_environment: cannot write %s', file); end
  fprintf (fid, '%s', jsonencode (record));
  fclose (fid);
end
