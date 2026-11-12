function verify_ob_codegen (directory)
  cases = jsondecode (fileread (fullfile(directory, 'manifest.json')));
  worst = 0; compared = 0;
  for k = 1:numel (cases)
    item = cases(k);
    if (! item.standalone), continue; endif
    expected = dlmread (fullfile(directory, item.expected), ',');
    actual = dlmread (fullfile(directory, [item.name '.csv']), ',', 1, 0);
    assert (isequal (size(actual), size(expected)), ['CSV shape mismatch: ' item.name]);
    assert (all (isfinite(actual(:))), ['Nonfinite C output: ' item.name]);
    error = max (abs(actual(:)-expected(:)) ./ max(1,abs(expected(:))));
    assert (error < 1e-11, sprintf('C/Octave mismatch for %s: %.17g', item.name, error));
    worst = max (worst, error); compared += 1;
  endfor
  fprintf ('Compared %d compiled models against Octave; worst scaled error %.3g\n', compared, worst);
endfunction
