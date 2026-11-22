function report = benchmark_ob_accelerator (repeats = 5, output = '')
  % Accelerated (compiled C) against interpreted ob_run on the shared set.
  %
  %   report = benchmark_ob_accelerator ()
  %   report = benchmark_ob_accelerator (repeats, 'accelerator.json')
  %
  % Run from the repository root.  For each case of ob_benchmark_models the
  % first accelerated call compiles into a fresh temporary cache, and its
  % export and mkoctfile times are reported separately.  Interpreted (A) and
  % accelerated (B) runs are then interleaved A B B A, so both see the same
  % machine load, and 'repeats' further accelerated calls give the median
  % warm time.  Cases outside the C subset are listed with the reason.
  % Simulink sim() times and outputs come from simulink-benchmark-reference.json
  % (reference_ob_simulink_benchmarks.m) when that file exists; the largest
  % absolute difference between the accelerated Scope outputs and
  % Simulink's is reported (test_ob_simulink_benchmarks asserts it per case
  % or explains it).  All cases but control_zc_ode45 (zero crossings with
  % ode45) are accelerated.
  root = fileparts (fileparts (mfilename ('fullpath')));
  addpath (root);
  reference = fullfile (root, 'simulink-benchmark-reference.json');
  if (exist (fullfile (root, 'ob_setup.m'), 'file'))
    % Reorganized tree: its ob_setup adds src and examples; the recordings
    % are in reference/.  A flat tree is the library folder itself.
    ob_setup ();
    reference = fullfile (root, 'tests', 'reference', 'simulink-benchmark-reference.json');
  endif
  addpath (fullfile (root, 'tests', 'benchmarks'));
  cases = ob_benchmark_models ();
  simulink = struct ();
  if (exist (reference, 'file'))
    simulink = jsondecode (fileread (reference));
  endif
  cache = tempname ();
  previous = getenv ('OB_ACCELERATOR_CACHE');
  setenv ('OB_ACCELERATOR_CACHE', cache);
  rows = struct ('name', {}, 'supported', {}, 'reason', {}, 'samples', {}, ...
                 'export_seconds', {}, 'compile_seconds', {}, 'interpreted_seconds', {}, ...
                 'accelerated_seconds', {}, 'simulation_seconds', {}, 'speedup', {}, ...
                 'max_scaled_error', {}, 'simulink_seconds', {}, 'simulink_fast_restart_seconds', {}, ...
                 'simulink_max_error', {}, 'exporter', {});
  unwind_protect
    for item = cases
      row = struct ('name', item.name, 'supported', false, 'reason', '', 'samples', numel (item.t), ...
                    'export_seconds', NaN, 'compile_seconds', NaN, 'interpreted_seconds', NaN, ...
                    'accelerated_seconds', NaN, 'simulation_seconds', NaN, 'speedup', NaN, ...
                    'max_scaled_error', NaN, 'simulink_seconds', NaN, 'simulink_fast_restart_seconds', NaN, ...
                    'simulink_max_error', NaN, 'exporter', '');
      if (isfield (simulink, 'cases') && isfield (simulink.cases, item.name))
        recorded = simulink.cases.(item.name);
        if (isfield (recorded, 'median_seconds')), row.simulink_seconds = recorded.median_seconds; endif
        if (isfield (recorded, 'fast_restart_median_seconds'))
          row.simulink_fast_restart_seconds = recorded.fast_restart_median_seconds;
        endif
      endif
      try
        [unused, first] = ob_accelerate (item.model, item.t, item.options);
      catch err
        if (! any (strcmp (err.identifier, {'octave_blocks:accelerate_unsupported', ...
                                            'octave_blocks:accelerate_unavailable', ...
                                            'octave_blocks:accelerate_capacity'})))
          rethrow (err);
        endif
        row.reason = strrep (err.message, 'ob_accelerate: ', '');
        rows(end+1) = row;
        continue;
      end_try_catch
      row.supported = true;
      row.export_seconds = first.generate_time;
      row.compile_seconds = first.compile_time;
      interpreted = zeros (1, 2); accelerated = zeros (1, 2 + repeats); simulation = accelerated;
      [interpreted(1), a] = timed_interpreted (item);
      [accelerated(1), b, simulation(1)] = timed_accelerated (item);
      [accelerated(2), b, simulation(2)] = timed_accelerated (item);
      interpreted(2) = timed_interpreted (item);
      for k = 1:repeats
        [accelerated(2+k), b, simulation(2+k)] = timed_accelerated (item);
      endfor
      row.interpreted_seconds = mean (interpreted);
      row.accelerated_seconds = median (accelerated);
      row.simulation_seconds = median (simulation);
      row.speedup = row.interpreted_seconds / row.accelerated_seconds;
      row.max_scaled_error = scaled_error (b.flat_values, a.flat_values);
      row.exporter = first.exporter;
      if (isfield (simulink, 'cases') && isfield (simulink.cases, item.name) && simulink.cases.(item.name).ok)
        row.simulink_max_error = simulink_error (item, b, simulink.cases.(item.name));
      endif
      rows(end+1) = row;
    endfor
  unwind_protect_cleanup
    setenv ('OB_ACCELERATOR_CACHE', previous);
    if (any (strcmpi (strrep (strsplit (path (), pathsep ()), '\', '/'), strrep (cache, '\', '/'))))
      rmpath (cache);
    endif
    clear -f ob_accel_*;
    if (exist (cache, 'dir'))
      confirm = confirm_recursive_rmdir (false);
      rmdir (cache, 's');
      confirm_recursive_rmdir (confirm);
    endif
  end_unwind_protect

  report = struct ('octave_version', OCTAVE_VERSION, 'computer', computer (), ...
                   'date', datestr (now (), 'yyyy-mm-dd HH:MM'), 'repeats', repeats, ...
                   'simulink_reference', exist (reference, 'file') == 2, 'cases', rows);
  printf ('\nAccelerated (compiled C) vs interpreted ob_run, Octave %s (%s)\n', OCTAVE_VERSION, computer ());
  printf ('%-17s %7s %8s %9s %11s %10s %9s %8s %9s %10s %10s %10s\n', 'case', 'samples', 'export', 'compile', ...
          'interpreted', 'accel.', 'C only', 'speedup', 'error', 'Simulink', 'fast rest.', 'vs SL');
  for row = rows
    if (! row.supported)
      printf ('%-17s %7d  not accelerated: %s\n', row.name, row.samples, row.reason);
      continue;
    endif
    printf ('%-17s %7d %7.3fs %8.3fs %10.3fs %9.4fs %8.4fs %7.0fx %9.2g %10s %10s %10.2g\n', row.name, row.samples, ...
            row.export_seconds, row.compile_seconds, row.interpreted_seconds, row.accelerated_seconds, ...
            row.simulation_seconds, row.speedup, row.max_scaled_error, seconds_text (row.simulink_seconds), ...
            seconds_text (row.simulink_fast_restart_seconds), row.simulink_max_error);
  endfor
  if (report.simulink_reference)
    printf (['Simulink: recorded median warm sim() in Normal mode and with Fast Restart; vs SL: largest\n' ...
             'absolute Scope difference from Simulink (dde/mackey/linear10 differences are diagnosed\n' ...
             'in test_ob_simulink_benchmarks).\n']);
  endif
  if (! report.simulink_reference)
    printf (['\nNo simulink-benchmark-reference.json yet.  ADVANCED_EXTENSIONS.md (Comparison with\n' ...
             'Simulink) records warm Simulink sim() times of 0.19-0.23 s for x'' = -x(t-1) and\n' ...
             '0.22-0.37 s for Mackey-Glass (Fast Restart 0.07-0.40 s).\n']);
  endif
  printf (['export: ob_codegen + hashing on the first call; compile: mkoctfile --mex; accel.: median\n' ...
           'warm ob_accelerate call (export reused, result assembled); C only: the compiled simulation.\n']);
  if (! isempty (output))
    fid = fopen (output, 'w');
    if (fid < 0), error ('benchmark_ob_accelerator: cannot write %s', output); endif
    fputs (fid, jsonencode (report));
    fclose (fid);
  endif
endfunction

function [seconds, result] = timed_interpreted (item)
  options = item.options; options.accelerate = false;
  clock = tic ();
  result = ob_run (item.model, item.t, options);
  seconds = toc (clock);
endfunction

function [seconds, result, simulation] = timed_accelerated (item)
  options = item.options; options.accelerate = true;
  clock = tic ();
  [result, info] = ob_accelerate (item.model, item.t, options);
  seconds = toc (clock);
  simulation = info.run_time;
endfunction

function worst = scaled_error (actual, expected)
  % Numeric channels; typed cores (child contexts, output cells) are
  % compared field by field in test_ob_accelerate.
  worst = 0;
  for k = 1:numel (expected)
    if (! isnumeric (expected{k})), continue; endif
    e = double (expected{k}); a = actual{k};
    worst = max ([worst; abs(a(:) - e(:)) ./ max(1, abs(e(:)))]);
  endfor
endfunction

function value = simulink_error (item, result, recorded)
  % Largest absolute Scope difference from the recorded Simulink outputs.
  value = NaN;
  scopes = find (strcmp ({item.model.blocks.type}, 'Scope'));
  ob = cell2mat (cellfun (@(v) double (v(:)'), result.values(:, scopes), 'UniformOutput', false));
  sl = recorded.y;
  if (rows (sl) != numel (item.t)), sl = sl.'; endif
  if (isequal (size (sl), size (ob))), value = max (abs (sl(:) - ob(:))); endif
endfunction

function text = seconds_text (value)
  if (isnan (value)), text = '-'; else text = sprintf ('%.4fs', value); endif
endfunction
