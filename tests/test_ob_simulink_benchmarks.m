function test_ob_simulink_benchmarks (directory = '', time_octave = true, accelerated = true)
  test_path_cleanup = ob_test_setup ();
  % Compare the nine shared benchmark cases of benchmarks/ob_benchmark_models
  % with the Simulink 26.2 outputs and warm wall times written by
  % reference_ob_simulink_benchmarks (simulink-benchmark-reference.json).
  % MATLAB is not needed at test time.
  %
  % The outputs show that both simulators do equivalent work.  Each case is
  % asserted within a tolerance that matches its method: identical classical
  % RK4 steps agree to rounding, adaptive solvers to their tolerances.  Cases
  % whose outputs differ for a diagnosed reason are listed in pending_table
  % (tag 'pending'): reported, not asserted.  With time_octave, every Octave
  % run is timed once and its ratio to Simulink's median warm sim() time is
  % printed; ratios are not asserted because machine load is not controlled.
  %
  % With accelerated (default true), every case that ob_accelerate supports
  % (all but control_zc_ode45) also runs compiled, in a temporary cache: its
  % outputs must equal the interpreted run (scaled error <= 1e-12) and meet
  % the same Simulink tolerance or pending diagnosis, and a warm compiled
  % call is timed against Simulink's warm sim().  Without a working
  % compiler (octave_blocks:accelerate_unavailable) the compiled column
  % reads 'no compiler' and the interpreted comparison still runs.
  here = fileparts (mfilename ('fullpath'));
  if (isempty (directory)), directory = ob_test_reference (); endif
  ref = jsondecode (fileread (fullfile (directory, 'simulink-benchmark-reference.json')));
  % The benchmark folder (models and the Mackey-Glass Function) stays on the
  % path while the cases run.
  folder = fullfile (here, 'benchmarks');
  added = isempty (strfind (path (), folder));
  if (added), addpath (folder); endif
  cache = tempname ();
  previous = getenv ('OB_ACCELERATOR_CACHE');
  setenv ('OB_ACCELERATOR_CACHE', cache);
  unwind_protect
    [table, failures] = run_cases (ref, time_octave, accelerated);
  unwind_protect_cleanup
    if (added), rmpath (folder); endif
    setenv ('OB_ACCELERATOR_CACHE', previous);
    if (any (strcmpi (strrep (strsplit (path (), pathsep ()), '\', '/'), strrep (cache, '\', '/'))))
      rmpath (cache);
    endif
    if (exist (cache, 'dir'))
      % Loaded MEX files cannot be deleted on Windows; clear them first.
      clear -f ob_accel_*;
      confirm = confirm_recursive_rmdir (false);
      rmdir (cache, 's');
      confirm_recursive_rmdir (confirm);
    endif
  end_unwind_protect
  report (ref, table, failures);
endfunction

function [table, failures] = run_cases (ref, time_octave, accelerated)
  cases = ob_benchmark_models ();
  pending = pending_table ();
  tolerance = struct ('oscillator_rk4', 1e-12, 'oscillator_ode45', 1e-6, 'dde_rk4', 1e-12, ...
                      'dde_ode45', 1e-6, 'mackey_rk4', 1e-12, 'mackey_ode45', 1e-6, ...
                      'control_zc_ode45', 1e-12, 'conditional_rk4', 1e-12, 'linear10_rk4', 1e-12);
  failures = {}; table = {};
  for k = 1:numel (cases)
    b = cases(k);
    if (! isfield (ref.cases, b.name))
      failures{end+1} = sprintf ('%s: no Simulink record', b.name);
      continue;
    endif
    c = ref.cases.(b.name);
    if (! c.ok)
      failures{end+1} = sprintf ('%s: the Simulink run failed: %s', b.name, c.error);
      continue;
    endif
    % The recorded settings must be those of the shared benchmark case.
    t = c.t(:)';
    if (numel (t) != numel (b.t) || max (abs (t - b.t)) > 1e-9)
      failures{end+1} = sprintf ('%s: Simulink output times differ from the benchmark case', b.name);
      continue;
    endif
    solver = 'rk4';
    if (strcmp (c.solver, 'ode45')), solver = 'ode45'; endif
    if (! strcmp (solver, b.options.solver))
      failures{end+1} = sprintf ('%s: Simulink solver %s, benchmark %s', b.name, c.solver, b.options.solver);
      continue;
    endif
    started = tic;
    result = ob_run (b.model, b.t, b.options);
    seconds = toc (started);
    scopes = find (strcmp ({b.model.blocks.type}, 'Scope'));
    ob = cell2mat (cellfun (@(v) double (v(:)'), result.values(:, scopes), 'UniformOutput', false));
    sl = c.y;
    if (rows (sl) != numel (t)), sl = sl.'; endif
    if (! isequal (size (sl), size (ob)))
      failures{end+1} = sprintf ('%s: Simulink output %s, Octave %s', b.name, mat2str (size (sl)), mat2str (size (ob)));
      continue;
    endif
    value = max (abs (sl(:) - ob(:)));
    entry = find (strcmp (b.name, {pending.id}));
    if (! isempty (entry))
      status = 'pending';
      printf ('pending %-18s max error %-10.3g %s: %s\n', b.name, value, pending(entry).category, ...
              pending(entry).diagnosis);
      if (value <= tolerance.(b.name))
        printf ('        %s now agrees: remove it from pending_table\n', b.name);
      endif
      [verified, message] = verify (b.name, t(:), sl, ob);
      printf ('        %s\n', message);
      if (! verified)
        failures{end+1} = sprintf ('%s: diagnosis not confirmed: %s', b.name, message);
      endif
    elseif (value <= tolerance.(b.name))
      status = 'agrees';
    else
      status = 'FAILS';
      failures{end+1} = sprintf ('%s: max error %.3g (tolerance %.3g)', b.name, value, tolerance.(b.name));
    endif
    if (! time_octave), seconds = NaN; endif
    [compiled, compiled_status, failures] = accelerated_case (b, result, sl, scopes, status, ...
                                                              tolerance.(b.name), accelerated, ...
                                                              time_octave, failures);
    table(end+1, :) = {b.name, value, status, c.first_seconds, c.median_seconds, ...
                       c.fast_restart_median_seconds, seconds, seconds / c.median_seconds, ...
                       seconds / c.fast_restart_median_seconds, compiled_status, compiled, ...
                       compiled / c.median_seconds};
  endfor
endfunction

function report (ref, table, failures)
  printf ('\nSimulink %s, %s, %d timed runs per mode (medians, seconds)\n', ref.simulink_version, ...
          ref.computer, ref.runs);
  printf ('%-18s %10s %8s %9s %9s %9s %9s %8s %8s  %-11s %9s %8s\n', 'case', 'max error', 'status', 'SL first', ...
          'SL warm', 'SL fast', 'Octave', 'ratio', 'fast', 'compiled', 'C call', 'ratio');
  for k = 1:rows (table)
    printf ('%-18s %10.3g %8s %9.4f %9.4f %9.4f %9.2f %8.0f %8.0f  %-11s %9.4f %8.2f\n', table{k, :});
  endfor
  printf (['compiled: the ob_accelerate result (agrees/pending as for Octave; interpreted: ' ...
           'outside the C subset; no compiler; capacity: delay history too long); C call: ' ...
           'warm ob_accelerate call (s); ratio: C call / SL warm\n']);
  if (! isempty (failures))
    error ('test_ob_simulink_benchmarks: %d failures\n  %s', numel (failures), strjoin (failures, "\n  "));
  endif
endfunction

function [seconds, status, failures] = accelerated_case (b, result, sl, scopes, interpreted_status, ...
                                                         tolerance, enabled, time_octave, failures)
  % Run one case through ob_accelerate (first call compiles, a second warm
  % call is timed).  The compiled outputs must equal the interpreted ones
  % and therefore meet the same Simulink check.
  seconds = NaN; status = 'not run';
  if (! enabled), return; endif
  options = b.options; options.accelerate = true;
  try
    compiled = ob_accelerate (b.model, b.t, options);
  catch err
    % The errors on which accelerate='auto' falls back: outside the C
    % subset, no working compiler (this comparison needs none), or delay
    % histories beyond the compiled capacity.
    switch (err.identifier)
      case 'octave_blocks:accelerate_unsupported', status = 'interpreted';
      case 'octave_blocks:accelerate_unavailable', status = 'no compiler';
      case 'octave_blocks:accelerate_capacity', status = 'capacity';
      otherwise, rethrow (err);
    endswitch
    return;
  end_try_catch
  if (time_octave)
    started = tic;
    compiled = ob_accelerate (b.model, b.t, options);
    seconds = toc (started);
  endif
  actual = cell2mat (cellfun (@(v) double (v(:)'), compiled.values(:, scopes), 'UniformOutput', false));
  expected = cell2mat (cellfun (@(v) double (v(:)'), result.values(:, scopes), 'UniformOutput', false));
  difference = max (abs (actual(:) - expected(:)) ./ max (1, abs (expected(:))));
  if (difference > 1e-12)
    failures{end+1} = sprintf ('%s: compiled and interpreted outputs differ by %.3g', b.name, difference);
    status = 'DIFFERS';
    return;
  endif
  value = max (abs (sl(:) - actual(:)));
  if (strcmp (interpreted_status, 'pending')), status = 'pending';
  elseif (value <= tolerance), status = 'agrees';
  else
    status = 'FAILS';
    failures{end+1} = sprintf ('%s: compiled max error %.3g (tolerance %.3g)', b.name, value, tolerance);
  endif
endfunction

function table = pending_table ()
  % Output differences with a diagnosis, tagged 'pending' for the next round.
  % verify () checks each diagnosis against an exact solution or a window
  % in which the two must still agree.
  table = struct ('id', {}, 'category', {}, 'diagnosis', {});
  delay = ['Simulink''s Transport Delay interpolates its history linearly between stored steps; ' ...
           'Octave Blocks uses cubic Hermite interpolation (ADVANCED_EXTENSIONS.md); Octave is ' ...
           'closer to the exact method-of-steps solution'];
  table(end+1) = struct ('id', 'dde_rk4', 'category', 'documented-difference', 'diagnosis', delay);
  table(end+1) = struct ('id', 'dde_ode45', 'category', 'documented-difference', 'diagnosis', delay);
  mackey = ['identical until the delayed history is first read back (t = 17); afterwards the linear ' ...
            'and cubic history interpolations differ and the chaotic Mackey-Glass dynamics (tau = 17) ' ...
            'amplify the difference'];
  table(end+1) = struct ('id', 'mackey_rk4', 'category', 'documented-difference', 'diagnosis', mackey);
  table(end+1) = struct ('id', 'mackey_ode45', 'category', 'documented-difference', 'diagnosis', mackey);
  table(end+1) = struct ('id', 'linear10_rk4', 'category', 'documented-difference', 'diagnosis', ...
                         ['Step at t = 1 on the grid: Simulink ode4''s last stage of the step ending at ' ...
                          't = 1 already sees the new Step value, adding h/6 to each of the 10 states ' ...
                          '(0.0167 in the output); Octave uses the left limit there and matches the exact ' ...
                          'step response (as int_s6_levelhold_ode4 in test_ob_simulink_delay_integrator)']);
endfunction

function [ok, message] = verify (name, t, sl, ob)
  switch (name)
    case {'dde_rk4', 'dde_ode45'}
      % x' = -x(t - 1), x = 1 for t <= 0: x = 1 - t on [0, 1], continued by
      % the method of steps.
      exact = unit_dde ([-1 1], t);
      ob_error = max (abs (ob - exact)); sl_error = max (abs (sl - exact));
      % Measured on the 2026-11-21 baseline: Octave 2.1e-8 (rk4) and 2.2e-7
      % (ode45), Simulink 1.0e-5 and 1.0e-3.
      bound = struct ('dde_rk4', 5e-8, 'dde_ode45', 5e-7).(name);
      ok = ob_error < bound && ob_error < sl_error / 100;
      message = sprintf ('error against the exact solution: Octave %.3g (bound %.3g), Simulink %.3g', ...
                         ob_error, bound, sl_error);
    case {'mackey_rk4', 'mackey_ode45'}
      early = t <= 17;
      bound = struct ('mackey_rk4', 1e-12, 'mackey_ode45', 1e-6).(name);
      early_error = max (abs (sl(early) - ob(early)));
      late = find (abs (sl - ob) > 1e-6, 1);
      ok = early_error <= bound;
      if (isempty (late)), first = NaN; else first = t(late); endif
      message = sprintf ('agreement to %.3g for t <= 17 (bound %.3g); first difference above 1e-6 at t = %g', ...
                         early_error, bound, first);
    case 'linear10_rk4'
      n = 10;
      A = -eye (n) + diag (0.5 * ones (n-1, 1), 1);
      exact = zeros (size (t));
      for k = find (t > 1)'
        exact(k) = ones (1, n) * (A \ ((expm (A * (t(k) - 1)) - eye (n)) * ones (n, 1)));
      endfor
      ob_error = max (abs (ob - exact)); sl_error = max (abs (sl - exact));
      ok = ob_error < 1e-8 && abs (sl_error - 10 * 0.01 / 6) < 1e-3;
      message = sprintf ('error against the exact step response: Octave %.3g, Simulink %.3g (10 h/6 = %.4g)', ...
                         ob_error, sl_error, 10 * 0.01 / 6);
    otherwise
      ok = false; message = 'no diagnosis check';
  endswitch
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
