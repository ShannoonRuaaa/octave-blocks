function verify_ob_codegen (directory)
  test_path_cleanup = ob_test_setup ();
  % Compare every standalone CSV with its Octave reference at the case's
  % scaled tolerance (manifest field 'tolerance': 1e-11 for RK4 exports,
  % 1e-9 for ode45 exports; manifests without it use 1e-11).
  cases = jsondecode (fileread (fullfile(directory, 'manifest.json')));
  worst = 0; compared = 0; adaptive = 0; adaptive_worst = 0;
  for k = 1:numel (cases)
    item = cases(k);
    if (! item.standalone), continue; endif
    tolerance = 1e-11;
    if (isfield (item, 'tolerance') && ! isempty (item.tolerance)), tolerance = item.tolerance; endif
    expected = dlmread (fullfile(directory, item.expected), ',');
    actual = dlmread (fullfile(directory, [item.name '.csv']), ',', 1, 0);
    assert (isequal (size(actual), size(expected)), ['CSV shape mismatch: ' item.name]);
    assert (all (isfinite(actual(:))), ['Nonfinite C output: ' item.name]);
    error = max (abs(actual(:)-expected(:)) ./ max(1,abs(expected(:))));
    assert (error < tolerance, sprintf('C/Octave mismatch for %s: %.17g (tolerance %g)', item.name, error, tolerance));
    worst = max (worst, error); compared += 1;
    if (tolerance > 1e-11), adaptive += 1; adaptive_worst = max (adaptive_worst, error); endif
  endfor
  fprintf ('Compared %d compiled models against Octave; worst scaled error %.3g\n', compared, worst);
  if (adaptive > 0)
    fprintf ('  of which %d ode45 models (tolerance 1e-9); worst scaled error %.3g\n', adaptive, adaptive_worst);
  endif
endfunction
