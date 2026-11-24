function test_ob_accelerate ()
  test_path_cleanup = ob_test_setup ();
  % Accelerated (compiled C, MEX) runs against interpreted ob_run: flat rk4
  % and ode45 models, typed (conditional, multiple-output, zero-crossing)
  % rk4 models and user .m Functions.  Uses a temporary cache directory and
  % a temporary folder of test Functions, and removes both afterwards.
  root = fileparts (fileparts (mfilename ('fullpath')));
  private_path = ob_test_private_path ();  % ob_accelerate_events is in inst/private
  addpath (fullfile (root, 'tests', 'benchmarks'));
  cache = tempname ();
  functions = tempname (); mkdir (functions);
  write_functions (functions);
  addpath (functions);
  previous = getenv ('OB_ACCELERATOR_CACHE');
  setenv ('OB_ACCELERATOR_CACHE', cache);
  cases = 0;
  unwind_protect
    % Options: validated accelerate values.
    assert (isequal (ob_solver_options ().accelerate, false));
    assert (isequal (ob_solver_options (struct ('accelerate', 1)).accelerate, true));
    assert (strcmp (ob_solver_options (struct ('accelerate', 'auto')).accelerate, 'auto'));
    assert_error (@() ob_solver_options (struct ('accelerate', 'yes')), 'accelerate must be');
    assert_error (@() ob_solver_options (struct ('accelerate', 2)), 'accelerate must be');
    cases += 1;

    % MEX tools must also work inside project directories containing spaces.
    spaced = fullfile(cache,'cache with spaces');
    before_directory = pwd();
    before_tmp = getenv('TMPDIR');
    unwind_protect
      setenv('OB_ACCELERATOR_CACHE',spaced);
      [spaced_result,unused] = ob_accelerate(ob_example(),[0 .1 .2]);
      assert(ob_scope_data(spaced_result,3),[0;.2;.4],1e-12);
      assert(strcmp(pwd(),before_directory));
      assert(strcmp(getenv('TMPDIR'),before_tmp));
    unwind_protect_cleanup
      setenv('OB_ACCELERATOR_CACHE',cache);
    end_unwind_protect
    cases += 1;

    % A default cache blocked by a file falls back; an explicit bad path fails.
    blocker = fullfile(functions,'cache-blocker');
    fid = fopen(blocker,'w'); assert(fid>=0); fclose(fid);
    variable = 'XDG_CACHE_HOME';
    if (ispc()), variable = 'LOCALAPPDATA'; endif
    old_base = getenv(variable);
    unwind_protect
      setenv('OB_ACCELERATOR_CACHE',blocker);
      assert_error(@() ob_accelerate(ob_example(),[0 1]),'OB_ACCELERATOR_CACHE is not writable');
      setenv('OB_ACCELERATOR_CACHE',''); setenv(variable,blocker);
      [unused,default_info] = ob_accelerate(ob_example(),[0 1]);
      assert(!isempty(strfind(default_info.cache,fullfile(tempdir(),'octave-blocks'))));
    unwind_protect_cleanup
      setenv(variable,old_base); setenv('OB_ACCELERATOR_CACHE',cache);
    end_unwind_protect
    cases += 1;

    % Shared benchmark cases: all but control_zc_ode45 (zero crossings with
    % ode45) are accelerated.  The Mackey-Glass grids are shortened here to
    % keep the interpreted reference quick; they still read the delayed
    % history (tau = 17) for many delays.
    worst = 0;
    benchmarks = ob_benchmark_models ();
    for item = benchmarks
      if (strcmp (item.name, 'control_zc_ode45')), continue; endif
      t = item.t;
      if (strncmp (item.name, 'mackey', 6)), t = t(t <= 60); endif
      worst = max (worst, compare (item.name, item.model, t, item.options));
      cases += 1;
    endfor

    % A broad sample of C gate models: hierarchy, inputs, clocks, linear
    % systems, matrix signals, controls, delays and limited integrators.
    for item = sample_models ()
      worst = max (worst, compare (item.name, item.model, item.t, item.options));
      cases += 1;
    endfor
    printf ('Accelerated results: worst scaled error %.3g\n', worst);

    % Event records from the C log (guard, time, direction, kind, search
    % step): guard fields from the inventory, and a continuous-control change
    % logged before a plateau departure of the same search step is listed
    % after it, as ob_run lists them.  A change that ends one step stays
    % before a departure that the next step finds at the same instant, and
    % other records keep their order.
    guards = struct ('path', {[4], [9]}, 'type', {'Saturation', 'Conditional Subsystem'}, ...
                     'channel', {1, 1}, 'side', {'lower', 'control'}, 'boundary', {0, 0});
    event_log = [2 0.5 1 1 1; 1 0.5 -1 2 1; 1 0.7 1 3 2; 2 0.9 -1 1 3; 1 1.1 1 2 4];
    records = ob_accelerate_events (event_log, guards);
    assert (isequal ([records.time], [0.5 0.5 0.7 0.9 1.1]));
    assert (isequal ([records.direction], [-1 1 1 -1 1]));
    assert (isequal ({records.side}, {'lower', 'control', 'lower', 'control', 'lower'}));
    assert (isequal (fieldnames (records), {'time'; 'path'; 'type'; 'channel'; 'side'; 'direction'; 'boundary'}));
    assert (isequal (records(2).path, 9) && strcmp (records(2).type, 'Conditional Subsystem'));
    records = ob_accelerate_events ([2 0.5 1 1 1; 1 0.5 -1 2 2; 1 0.5 1 3 2], guards);
    assert (isequal ([records.direction], [1 -1 1]) && isequal ({records.side}, {'control', 'lower', 'lower'}));
    records = ob_accelerate_events ([2 0.5 1 1 4; 1 0.5 -1 2 4; 2 0.5 -1 1 5; 1 0.5 1 2 5], guards);
    assert (isequal ([records.direction], [-1 1 1 -1]));
    % Crossings of one step are listed in time order: guard 2's departure
    % from zero at the search origin 0.2 (logged after guard 1's crossing
    % bisected just later) comes first.  Crossings at the same time keep the
    % log (guard) order.
    records = ob_accelerate_events ([2 0.2 1 3 1; 1 0.2000000000007276 1 3 2; 2 0.2 -1 3 2; ...
                                     2 0.7 1 3 3; 1 0.7 -1 3 3], guards);
    assert (isequal ([records.time], [0.2 0.2 0.2000000000007276 0.7 0.7]));
    assert (isequal ([records.direction], [1 -1 1 1 -1]));
    assert (isequal ({records.side}, {'control', 'control', 'lower', 'control', 'lower'}));
    assert (isempty (ob_accelerate_events (zeros (0, 5), guards)));
    cases += 1;

    % The cache: a second run reuses the compiled file; ob_run delegates.
    dde = benchmarks(strcmp ({benchmarks.name}, 'dde_rk4'));
    [first, info] = ob_accelerate (dde.model, dde.t, dde.options);
    assert (info.cache_hit && strncmp (info.mex, 'ob_accel_', 9));
    assert (strncmp (info.source, cache, numel (cache)) && exist (info.source, 'file'));
    assert (numel (info.delay_capacity) == 1 && info.delay_capacity >= 64);
    via_run = ob_run (dde.model, dde.t, struct ('solver', 'rk4', 'accelerate', true));
    assert (isequal (via_run.flat_values, first.flat_values));
    assert (via_run.solver_options.accelerate == true);
    files = dir (fullfile (cache, ['*.' mexext()]));
    cases += 1;

    % Outside the subset: rejected before anything is compiled.
    % ode15s has no C port; ode45 exists only on the flat path; the typed
    % exporter rejects user Functions and Transport Delays.
    inner = ob_conditional_example ();
    inner.blocks(3).value.blocks(2).type = 'Function';
    inner.blocks(3).value.blocks(2).name = 'ob_test_accel_double';
    inner.blocks(3).value.blocks(2).value = [];
    unsupported = {{dde.model, 0:0.1:1, struct('solver', 'ode15s'), 'solver ode15s'}, ...
                   {ob_control_example(), 0:0.1:1, struct('solver', 'ode45', 'zero_crossings', true), ...
                    'solver ode45 with conditional subsystems'}, ...
                   {ob_conditional_example(), 0:1:3, struct('solver', 'ode45'), 'typed C exporter uses rk4'}, ...
                   {inner, 0:1:3, struct(), 'ob_test_accel_double'}};
    for item = unsupported
      [model, t, options, fragment] = item{1}{:};
      try
        ob_accelerate (model, t, options);
        error ('test_ob_accelerate: expected a rejection');
      catch err
        assert (strcmp (err.identifier, 'octave_blocks:accelerate_unsupported'), err.message);
        assert (! isempty (strfind (err.message, fragment)), err.message);
      end_try_catch
      % 'auto' falls back to interpretation with identical results.
      options.accelerate = 'auto';
      fallback = ob_run (model, t, options);
      options.accelerate = false;
      reference = ob_run (model, t, options);
      % Conditional cores are child contexts that keep the solver options,
      % so compare the numeric signals.
      numeric = cellfun (@isnumeric, reference.flat_values);
      assert (isequal (fallback.flat_values(numeric), reference.flat_values(numeric)));
      assert_error (@() ob_run (model, t, setfield (options, 'accelerate', true)), 'outside the accelerated C subset');
    endfor
    assert (numel (dir (fullfile (cache, ['*.' mexext()]))) == numel (files));
    cases += numel (unsupported);

    % User Functions: an error inside the function is a runtime error in both
    % modes (ob_run fails the same way, with the same message); a result of
    % another class or shape than at t(1) cannot be held by the compiled
    % model, so it is unsupported and 'auto' falls back to ob_run.
    late = ob_example ();
    late.blocks(1).type = 'Time';
    late.blocks(2).type = 'Function'; late.blocks(2).name = 'ob_test_accel_fail'; late.blocks(2).value = [];
    assert_error (@() ob_run (late, 0:0.25:1), 'ob_test_accel_fail: input 0.75 is too large');
    for mode = {true, 'auto'}
      try
        ob_run (late, 0:0.25:1, struct ('accelerate', mode{1}));
        error ('test_ob_accelerate: expected a Function failure');
      catch err
        assert (strcmp (err.identifier, 'octave_blocks:accelerate_runtime'), err.message);
        assert (! isempty (strfind (err.message, ['t = 0.75 (sample 4): Function ''ob_test_accel_fail'' ' ...
                                                  'failed (OB_EXTERNAL_ERROR): ob_test_accel_fail: input ' ...
                                                  '0.75 is too large'])), err.message);
      end_try_catch
    endfor
    for name = {'ob_test_accel_grow', 'ob_test_accel_complex'}
      late.blocks(2).name = name{1};
      try
        ob_accelerate (late, 0:0.25:1);
        error ('test_ob_accelerate: expected a shape change');
      catch err
        assert (strcmp (err.identifier, 'octave_blocks:accelerate_unsupported'), err.message);
        assert (! isempty (strfind (err.message, 'the compiled model needs a real double 1x1 matrix (at t = 0.75, sample 4)')), err.message);
      end_try_catch
      fallback = ob_run (late, 0:0.25:1, struct ('accelerate', 'auto'));
      assert (isequal (fallback.flat_values, ob_run (late, 0:0.25:1).flat_values));
    endfor
    % A first value that is not a real double matrix is rejected before compiling.
    late.blocks(2).name = 'ob_test_accel_single';
    assert_error (@() ob_accelerate (late, 0:0.25:1), 'returned a single value at t = 0');
    % ob_run keeps a NaN or Inf Function result (the Scope shows it); the
    % compiled model needs finite signals, so this is unsupported too.
    late.blocks(2).name = 'ob_test_accel_nan';
    try
      ob_accelerate (late, 0:0.25:1);
      error ('test_ob_accelerate: expected a nonfinite result');
    catch err
      assert (strcmp (err.identifier, 'octave_blocks:accelerate_unsupported'), err.message);
      assert (! isempty (strfind (err.message, ['Function ''ob_test_accel_nan'' returned a nonfinite ' ...
                                                'value; the compiled model needs finite signals (at ' ...
                                                't = 0.75, sample 4)'])), err.message);
    end_try_catch
    reference = ob_run (late, 0:0.25:1);
    assert (isnan (reference.flat_values{end, 2}));
    assert (isequaln (ob_run (late, 0:0.25:1, struct ('accelerate', 'auto')).flat_values, reference.flat_values));
    cases += 5;

    % Builds remembered in this session follow edits of user Functions: a
    % new output shape regenerates the export once (instead of failing on
    % the remembered shape), and shadowing a C-mapped builtin by a user file
    % (or removing that file) changes the export key.
    edited = tempname (); mkdir (edited); addpath (edited);
    unwind_protect
      write_function (edited, 'ob_test_accel_edited', 'y = 2 * u;');
      late.blocks(2).name = 'ob_test_accel_edited';
      [first, info] = ob_accelerate (late, 0:0.25:1);
      assert (isequal (size (first.flat_values{end, 2}), [1 1]) && ! info.reused_export);
      pause (1.1);   % a new modification time, so that Octave reloads the file
      write_function (edited, 'ob_test_accel_edited', 'y = [u, 2 * u];');
      rehash (); clear ob_test_accel_edited;
      [second, info] = ob_accelerate (late, 0:0.25:1);
      assert (! info.reused_export && isequal (second.flat_values, ob_run (late, 0:0.25:1).flat_values));
      [unused, info] = ob_accelerate (late, 0:0.25:1);
      assert (info.reused_export);
      shadowed = ob_example ();
      shadowed.blocks(1).type = 'Time';
      shadowed.blocks(2).type = 'Function'; shadowed.blocks(2).name = 'tanh'; shadowed.blocks(2).value = [];
      [builtin, info] = ob_accelerate (shadowed, 0:0.25:1);
      assert (isempty (info.external_functions) && isequal (builtin.flat_values, ob_run (shadowed, 0:0.25:1).flat_values));
      quiet = warning ('off', 'Octave:shadowed-function');
      unwind_protect
        write_function (edited, 'tanh', 'y = 2 * u;');
        rehash ();
        [user, info] = ob_accelerate (shadowed, 0:0.25:1);
        assert (! info.reused_export && isequal (info.external_functions, {'tanh'}));
        assert (isequal (user.flat_values{end, 2}, 2) && isequal (user.flat_values, ob_run (shadowed, 0:0.25:1).flat_values));
      unwind_protect_cleanup
        delete (fullfile (edited, 'tanh.m'));
        rehash (); clear tanh;
        warning (quiet);
      end_unwind_protect
      [again, info] = ob_accelerate (shadowed, 0:0.25:1);
      assert (info.reused_export && isempty (info.external_functions) && isequal (again.flat_values, builtin.flat_values));
    unwind_protect_cleanup
      rmpath (edited);
      confirm = confirm_recursive_rmdir (false);
      rmdir (edited, 's');
      confirm_recursive_rmdir (confirm);
    end_unwind_protect
    cases += 2;

    % ode45 settings of another class than double: ob_run then uses Octave's
    % ode45 in that class, which the C port does not reproduce.
    single_tolerance = struct ('solver', 'ode45', 'reltol', single (1e-5));
    assert_error (@() ob_accelerate (ob_oscillator (), 0:0.25:3, single_tolerance), ...
                  'ode45 C export needs double reltol, abstol and maxstep');
    single_tolerance.accelerate = 'auto';
    fallback = ob_run (ob_oscillator (), 0:0.25:3, single_tolerance);
    single_tolerance.accelerate = false;
    assert (isequal (fallback.flat_values, ob_run (ob_oscillator (), 0:0.25:3, single_tolerance).flat_values));
    cases += 1;

    % Without a working compiler: accelerate_unavailable, on which 'auto'
    % falls back (test_ob_simulink_benchmarks then reports 'no compiler').
    broken = tempname (); mkdir (broken);
    write_function (broken, 'mkoctfile', 'error (''mkoctfile: no compiler in this test'');', 'varargout', 'varargin');
    quiet = warning ('off', 'Octave:shadowed-function');
    addpath (broken); rehash ();
    unwind_protect
      % A constant no other case uses: its source is not in the cache yet.
      fresh = ob_example ();
      fresh.blocks(1).type = 'Constant'; fresh.blocks(1).value = 0.918273645;
      fresh.blocks(2).type = 'Integrator'; fresh.blocks(2).value = 0;
      try
        ob_accelerate (fresh, 0:0.5:1);
        error ('test_ob_accelerate: expected a missing compiler');
      catch err
        assert (strcmp (err.identifier, 'octave_blocks:accelerate_unavailable'), err.message);
        assert (! isempty (strfind (err.message, 'no compiler in this test')), err.message);
      end_try_catch
      assert (isequal (ob_run (fresh, 0:0.5:1, struct ('accelerate', 'auto')).flat_values, ...
                       ob_run (fresh, 0:0.5:1).flat_values));
    unwind_protect_cleanup
      rmpath (broken); rehash ();
      warning (quiet);
      confirm = confirm_recursive_rmdir (false);
      rmdir (broken, 's');
      confirm_recursive_rmdir (confirm);
    end_unwind_protect
    cases += 1;

    % C runtime failures are errors, never silent fallbacks: generated code
    % rejects nonfinite signals (Octave would produce complex sqrt(-1)).
    domain = ob_example ();
    domain.blocks(1).type = 'Constant'; domain.blocks(1).value = -1;
    domain.blocks(2).type = 'Function'; domain.blocks(2).name = 'sqrt'; domain.blocks(2).value = [];
    for mode = {true, 'auto'}
      try
        ob_run (domain, 0:0.5:1, struct ('accelerate', mode{1}));
        error ('test_ob_accelerate: expected a C runtime failure');
      catch err
        assert (strcmp (err.identifier, 'octave_blocks:accelerate_runtime'), err.message);
        assert (! isempty (strfind (err.message, 'OB_NONFINITE')), err.message);
      end_try_catch
    endfor
    cases += 1;

    % Delayed jumps that multiply through two incommensurate delays outgrow
    % the capacity heuristic: without retries the history overflows (a
    % capacity error, on which 'auto' falls back); by default the model is
    % rebuilt with doubled capacities and equals the interpreted run, and the
    % enlarged build is reused afterwards.
    B = @(type, value, name) struct ('type', type, 'value', value, 'name', name, 'x', 0, 'y', 0);
    jumps.blocks = [B('Step', [0 0 1], 'Step') B('Sum', [], 'Sum1') B('Sum', [], 'Sum2') ...
                    B('Transport Delay', [1 0], 'D1') B('Transport Delay', [sqrt(2) 0], 'D2') ...
                    B('Gain', 0.6, 'G1') B('Gain', 0.4, 'G2') B('Scope', [], 'Scope')];
    jumps.edges = [1 1 2 1; 3 1 2 2; 6 1 3 1; 7 1 3 2; 2 1 4 1; 2 1 5 1; 4 1 6 1; 5 1 7 1; 2 1 8 1];
    try
      ob_accelerate (jumps, 0:1:25, struct (), 0);
      error ('test_ob_accelerate: expected a history overflow');
    catch err
      assert (strcmp (err.identifier, 'octave_blocks:accelerate_capacity'), err.message);
      assert (! isempty (strfind (err.message, 'OB_DELAY_OVERFLOW')), err.message);
      assert (! isempty (strfind (err.message, 'accelerate=''auto''')), err.message);
    end_try_catch
    worst = max (worst, compare ('delay_jump_feedback', jumps, 0:1:25, struct ('solver', 'rk4')));
    [unused, info] = ob_accelerate (jumps, 0:1:25);
    assert (info.reused_export && info.capacity_retries == 0, 'enlarged build not reused');
    assert (all (info.delay_capacity >= [128 128]), mat2str (info.delay_capacity));
    cases += 1;

    % More than 1e6 segments in one gap: the compiled model reports the same
    % error as ob_run (and 'auto' does not hide it).
    tiny.blocks = [B('Time', [], 'Time') B('Transport Delay', [1e-7 0], 'Delay') B('Scope', [], 'Scope')];
    tiny.edges = [1 2; 2 3];
    assert_error (@() ob_run (tiny, [0 1]), 'needs more than 1e6 segments per output interval');
    for mode = {true, 'auto'}
      try
        ob_run (tiny, [0 1], struct ('accelerate', mode{1}));
        error ('test_ob_accelerate: expected a segment-limit failure');
      catch err
        assert (strcmp (err.identifier, 'octave_blocks:accelerate_runtime'), err.message);
        assert (! isempty (strfind (err.message, ...
          'Transport Delay of 9.9999999999999995e-08 needs more than 1e6 segments per output interval')), err.message);
      end_try_catch
    endfor
    cases += 1;
    printf ('Accelerator: %d cases passed\n', cases);
  unwind_protect_cleanup
    setenv ('OB_ACCELERATOR_CACHE', previous);
    if (any (strcmp (strsplit (path (), pathsep ()), cache))), rmpath (cache); endif
    if (exist (cache, 'dir'))
      % Loaded MEX files cannot be deleted on Windows; clear them first.
      clear -f ob_accel_*;
      confirm = confirm_recursive_rmdir (false);
      [ok] = rmdir (cache, 's');
      confirm_recursive_rmdir (confirm);
    endif
    rmpath (functions);
    confirm = confirm_recursive_rmdir (false);
    rmdir (functions, 's');
    confirm_recursive_rmdir (confirm);
  end_unwind_protect
endfunction

function write_functions (folder)
  % User Functions without a C mapping, called through ob_external_call.
  files = struct ( ...
    'ob_test_accel_double', 'y = 2 * u;', ...
    'ob_test_accel_affine', 'y = a .* b + [1 2; 3 4];', ...
    'ob_test_accel_fail', ['if (u > 0.5), error (''ob_test_accel_fail: input %g is too large'', u); endif' ...
                           char(10) '  y = 2 * u;'], ...
    'ob_test_accel_grow', 'if (u > 0.5), y = [u u]; else y = u; endif', ...
    'ob_test_accel_complex', 'y = sqrt (0.5 - u);', ...
    'ob_test_accel_single', 'y = single (u);', ...
    'ob_test_accel_nan', 'y = u; if (u > 0.5), y = NaN; endif');
  for name = fieldnames (files)'
    inputs = 'u';
    if (strcmp (name{1}, 'ob_test_accel_affine')), inputs = 'a, b'; endif
    write_function (folder, name{1}, files.(name{1}), 'y', inputs);
  endfor
  rehash ();
endfunction

function write_function (folder, name, body, outputs = 'y', inputs = 'u')
  fid = fopen (fullfile (folder, [name '.m']), 'w');
  fprintf (fid, "function %s = %s (%s)\n  %s\nendfunction\n", outputs, name, inputs, body);
  fclose (fid);
endfunction

function worst = compare (name, model, t, options)
  interpreted = ob_run (model, t, options);
  options.accelerate = true;
  [accelerated, info] = ob_accelerate (model, t, options);
  assert (isequal (fieldnames (accelerated), fieldnames (interpreted)), [name ': result fields']);
  assert (isequal (accelerated.t, interpreted.t), [name ': t']);
  assert (isequal (size (accelerated.flat_values), size (interpreted.flat_values)), [name ': flat size']);
  assert (isequal (size (accelerated.values), size (interpreted.values)), [name ': values size']);
  worst = max (scaled_error (name, accelerated.flat_values, interpreted.flat_values), ...
               scaled_error (name, accelerated.values, interpreted.values));
  % Typed cores: a Multiple Function core is the cell of its outputs; an
  % accelerated Conditional Subsystem core holds the context's outputs.
  types = {interpreted.compiled_model.blocks.type};
  for id = find (strcmp (types, 'Multiple Function'))
    assert (isequal (accelerated.flat_values(:, id), interpreted.flat_values(:, id)), [name ': multiple-output core']);
  endfor
  for id = find (strcmp (types, 'Conditional Subsystem'))
    for sample = 1:numel (t)
      assert (isequal (fieldnames (accelerated.flat_values{sample, id}), {'outputs'}), [name ': core fields']);
      assert (isequal (accelerated.flat_values{sample, id}.outputs, interpreted.flat_values{sample, id}.outputs), ...
              [name ': conditional core outputs']);
    endfor
  endfor
  assert (worst <= 1e-12, sprintf ('%s: accelerated/interpreted mismatch %.3g', name, worst));
  assert (accelerated.integration_steps == interpreted.integration_steps, [name ': integration steps']);
  assert (isequal (accelerated.sample_hits, interpreted.sample_hits), [name ': sample hits']);
  for field = {'order', 'solver', 'signal_map', 'block_paths', 'compiled_model', 'inputs', 'sample_times', 'events'}
    assert (isequal (accelerated.(field{1}), interpreted.(field{1})), [name ': ' field{1}]);
  endfor
  printf ('  %-28s %-5s %-5s %6d samples  error %.3g  (%s)\n', name, ob_solver_options (options).solver, info.exporter, ...
          numel (t), worst, ifelse_text (info.cache_hit, 'cached', sprintf ('compiled in %.2f s', info.compile_time)));
endfunction

function worst = scaled_error (name, actual, expected)
  worst = 0;
  for k = 1:numel (expected)
    a = actual{k}; e = expected{k};
    if (isempty (e) && isempty (a)), continue; endif
    if (! isnumeric (e)), continue; endif   % typed cores: compared in compare ()
    assert (isa (a, 'double') && isequal (size (a), size (e)), [name ': value shape']);
    e = double (e);
    worst = max ([worst; abs(a(:) - e(:)) ./ max(1, abs(e(:)))]);
  endfor
endfunction

function text = ifelse_text (condition, yes, no)
  if (condition), text = yes; else text = no; endif
endfunction

function cases = sample_models ()
  % C gate models of every accelerated family: flat rk4 (hierarchy, inputs,
  % clocks, linear systems, matrix signals, controls, delays, limited
  % integrators), the same kinds with ode45, typed rk4 (conditional,
  % multiple-output, enabled continuous/multirate, zero crossings) and user
  % Functions (one and two inputs, matrix values, rk4 and ode45).
  B = @(type, value, name) struct ('type', type, 'value', value, 'name', name, 'x', 0, 'y', 0);
  cases = struct ('name', {}, 'model', {}, 't', {}, 'options', {});
  ode45 = struct ('solver', 'ode45');
  add ('example', ob_example (), 0:0.3:3);
  add ('subsystem', ob_subsystem_example (), 0:0.1:10);
  add ('input', ob_input_example (), 0:0.05:1.5);
  add ('multirate', ob_multirate_example (), 0:0.1:3);
  add ('linear_system', ob_linear_system_example (), 0:0.1:4);
  add ('controls', ob_control_example (), 0:0.05:5);
  add ('oscillator_irregular', ob_oscillator (), [0 0.1 0.25 0.7 1.3 2]);
  clocked = ob_example ();
  clocked.blocks(1).type = 'Constant'; clocked.blocks(1).value = 1;
  clocked.blocks(2).type = 'Discrete Integrator'; clocked.blocks(2).value = 0;
  clocked.sample_times = [0 0; 0.1 0.07; 0 0];
  add ('clock_decimal_origin', clocked, 1000:0.17:1002);
  % Unit Delays every 0.1 and 0.3: ticks 3*0.1 and 0.3 differ by an ulp and
  % are processed together at the earlier one.
  delays.blocks = [B('Constant', 1, 'One') B('Unit Delay', 0, 'Fast') B('Unit Delay', 0, 'Slow') ...
                   B('Scope', [], 'Fast scope') B('Scope', [], 'Slow scope')];
  delays.edges = [1 1 2 1; 1 1 3 1; 2 1 4 1; 3 1 5 1];
  delays.sample_times = [0 0; 0.1 0; 0.3 0; 0 0; 0 0];
  add ('clock_coincidence', delays, 0:1:2);
  matrix = ob_example ();
  matrix.blocks(1).type = 'Constant'; matrix.blocks(1).value = [1 2; 3 4];
  matrix.blocks(2).type = 'Integrator'; matrix.blocks(2).value = zeros (2);
  add ('matrix_integrator', matrix, 0:0.25:2);
  step.blocks = [B('Step', [0.35 0 1], 'Step') B('Transport Delay', [0.2 -1], 'Delay') ...
                 B('Integrator', 0, 'Integrator') B('Scope', [], 'Scope')];
  step.edges = [1 2; 2 3; 3 4];
  add ('delay_step', step, 0:0.1:1.5);
  delay.blocks = [B('Time', [], 'Time') B('Gain', [1 2; 3 4], 'Gain') B('Transport Delay', [0.2 3], 'Delay') ...
                  B('Integrator', zeros(2), 'Integrator') B('Scope', [], 'Scope')];
  delay.edges = [1 2; 2 3; 3 4; 4 5];
  add ('delay_matrix', delay, 0:0.1:1);
  wave = ob_input_signal ((0:0.5:3)', [-1; 1; -1; 1; -1; 1; -1], [1 1], 'zoh');
  reset.blocks = [B('Constant', 1, 'One') ...
                  B('Limited Integrator', struct ('initial', 0.25, 'lower', 0, 'upper', 0.9, 'reset', 'either'), 'Limited') ...
                  B('Inport', 1, 'Reset') B('Scope', [], 'Scope')];
  reset.edges = [1 1 2 1; 3 1 2 2; 2 1 4 1];
  reset.inputs = {wave};
  add ('limited_reset', reset, 0:0.1:3);
  gate.blocks = [B('Constant', 1, 'One') ...
                 B('Limited Integrator', struct ('initial', 0.25, 'reset', 'level'), 'Limited') ...
                 B('Step', [1.05 0 1], 'Open') B('Step', [2.05 0 -1], 'Close') ...
                 B('Scope', [], 'Scope') B('Sum', [], 'Gate')];
  gate.edges = [1 1 2 1; 3 1 6 1; 4 1 6 2; 6 1 2 2; 2 1 5 1];
  add ('limited_level', gate, 0:0.1:3);

  % ode45 (adaptive C integrator).  Step times and input knots split
  % segments; delays record accepted interior points; Limited Integrators
  % saturate per evaluation and 'level' resets only while nonzero.
  unaligned = ob_example ();
  unaligned.blocks(1).type = 'Step'; unaligned.blocks(1).value = [0.35 0 1];
  unaligned.blocks(2).type = 'Integrator'; unaligned.blocks(2).value = 0;
  add ('ode45_step', unaligned, 0:0.3:1.2, ode45);
  add ('ode45_oscillator', ob_oscillator (), 0:0.25:5, ode45);
  add ('ode45_input', ob_input_example (), 0:0.05:1.5, ode45);
  add ('ode45_multirate', ob_multirate_example (), 0:0.1:3, ode45);
  add ('ode45_linear_system', ob_linear_system_example (), 0:0.1:4, ...
       struct ('solver', 'ode45', 'reltol', 1e-9, 'abstol', 1e-11, 'maxstep', 0.05));
  add ('ode45_matrix_integrator', matrix, 0:0.25:2, ode45);
  add ('ode45_delay_step', step, 0:0.1:1.5, ode45);
  add ('ode45_limited_reset', reset, 0:0.1:3, ode45);
  add ('ode45_limited_level', gate, 0:0.1:3, ode45);

  % Typed exporter (rk4).
  add ('typed_conditional', ob_conditional_example (), 0:1:6);
  triggered = ob_conditional_example ();
  triggered.inputs = {ob_input_signal(0:9, [-1;0;1;0;0;1;-1;0;0;1])};
  triggered.blocks(3).value.execution.mode = 'either';
  add ('typed_trigger_either', triggered, 0:1:9);
  add ('typed_multioutput', ob_multioutput_example (), 0:1:3);
  add ('typed_enabled_continuous', ob_enabled_continuous_example (), 0:0.1:4);
  add ('typed_enabled_multirate', ob_enabled_multirate_example (), 0:0.1:3);
  add ('typed_combined', ob_combined_control_example (), 0:0.1:4);
  add ('typed_zero_crossing', ob_zero_crossing_example (), 0:0.5:3, ...
       struct ('solver', 'rk4', 'zero_crossings', true, 'maxstep', 0.1));
  add ('typed_controls_events', ob_control_example (), 0:0.05:5, struct ('zero_crossings', true));
  [continuous, settings] = ob_continuous_control_example ();
  add ('typed_continuous_control', continuous, 0:0.1:2, settings);
  add ('typed_combined_continuous', ob_combined_continuous_example (), 0:0.1:3, struct ('zero_crossings', true));
  % An inherited enabled body with sampled control also samples at its
  % inner clocks (0.125 and 0.25), between and at the output times.
  inherited = ob_enabled_multirate_example ();
  inherited.sample_times(3,:) = [0 0];
  add ('typed_inherited_inner_clocks', inherited, 0:0.1:1);
  add ('typed_inherited_inner_sparse', inherited, [0 1]);
  % Its 0.3 inner clock and a root Unit Delay every 0.1: the delay's tick
  % 3*0.1 = 0.30000000000000004 is processed with the inner tick at 0.3
  % (the earlier of two ticks within the clock tolerance), in both runs.
  coincident = inherited;
  coincident.blocks(3).value.sample_times(2:3,:) = [0.1 0; 0.3 0];
  coincident.blocks(6) = B('Unit Delay', 0, 'Root delay');
  coincident.blocks(7) = B('Scope', [], 'Delay scope');
  coincident.edges(end+1:end+2, :) = [1 1 6 1; 6 1 7 1];
  coincident.sample_times(6:7, :) = [0.1 0; 0 0];
  add ('typed_coincident_clocks', coincident, 0:0.5:1);
  % Zero crossings: at 0.5 a Saturation crossing moves Switch 5 off its zero
  % plateau and its output disables (or enables) a continuous-control body.
  % ob_run lists the departure before the control change of the same search
  % step (the C logs them the other way round).  In the second model the
  % enabled body's output also leaves Switch 13's zero plateau, which only
  % the next search step finds: that departure stays after the change.
  body.blocks = [B('Inport', 1, 'In') B('Integrator', 0, 'x') B('Outport', 1, 'Out')];
  body.edges = [1 1 2 1; 2 1 3 1];
  body.execution = struct ('mode', 'enabled', 'control', 'continuous', 'initial_outputs', {{-9}});
  plateau.blocks = [B('Constant', 1, 'High') B('Time', [], 'Time') B('Gain', -1, 'Negate') ...
                    B('Constant', -1, 'Low') B('Switch', 0, 'Switch') B('Integrator', 0, 'Integral') ...
                    B('Scope', [], 'Integral scope') B('Constant', -0.5, 'Offset') B('Sum', [], 'Sum') ...
                    B('Saturation', [0 100], 'Saturation') B('Subsystem', body, 'Body') B('Scope', [], 'Body scope')];
  plateau.edges = [1 1 5 1; 3 1 5 2; 4 1 5 3; 5 1 6 1; 6 1 7 1; 2 1 9 1; 8 1 9 2; 9 1 10 1; ...
                   10 1 3 1; 1 1 11 1; 5 1 11 2; 11 1 12 1];
  events = struct ('solver', 'rk4', 'zero_crossings', true);
  add ('typed_departure_and_change', plateau, [0 1], events);
  plateau.blocks(1).value = -1; plateau.blocks(4).value = 1;
  plateau.blocks(11).value.execution.initial_outputs = {0};
  plateau.blocks(13) = B('Switch', 0, 'Second switch'); plateau.blocks(14) = B('Scope', [], 'Second scope');
  plateau.edges(end+1:end+4, :) = [4 1 13 1; 11 1 13 2; 1 1 13 3; 13 1 14 1];
  add ('typed_change_then_departure', plateau, [0 1], events);
  % One search from the stop 0.2 finds block 9's departure from zero at 0.2
  % and block 5's crossing at 0.2000000000007276; the C counts them in guard
  % order and the records come back in ob_run's time order.
  add ('typed_staggered_departure', ob_staggered_enables_example (), 0:0.1:0.5, ...
       struct ('solver', 'rk4', 'zero_crossings', true, 'maxstep', 0.1));
  % An enabled body at [0.5 0.25] keeps its outputs across the root input
  % boundary at 1.1 (enable off) between its hits, also in event mode.
  add ('typed_offset_hold_events', ob_scalar_initial_example ('offset'), 0:0.25:2, ...
       struct ('solver', 'rk4', 'zero_crossings', true));

  % User Functions through ob_external_call.
  term.blocks = [B('Integrator', 0.5, 'x') B('Function', [], 'ob_bench_mackey_term') ...
                 B('Gain', -0.1, 'Decay') B('Sum', [], 'Sum') B('Scope', [], 'Scope')];
  term.edges = [1 1 2 1; 1 1 3 1; 2 1 4 1; 3 1 4 2; 4 1 1 1; 1 1 5 1];
  add ('external_scalar', term, 0:0.5:20);
  add ('external_scalar_ode45', term, 0:0.5:20, ode45);
  pair.blocks = [B('Time', [], 'T') B('Constant', [1 2; 3 4], 'C') B('Function', [], 'ob_test_accel_affine') ...
                 B('Integrator', zeros(2), 'I') B('Scope', [], 'S')];
  pair.edges = [1 1 3 1; 2 1 3 2; 3 1 4 1; 4 1 5 1];
  add ('external_matrix_pair', pair, 0:0.1:1);
  add ('external_matrix_pair_ode45', pair, 0:0.1:1, ode45);
  % A 30x30 signal needs more stack than Octave's main thread offers, so this
  % run keeps the simulation thread and posts each call to the main thread.
  large.blocks = [B('Constant', reshape (1:900, 30, 30) / 900, 'C') B('Function', [], 'ob_test_accel_double') ...
                  B('Integrator', zeros (30), 'I') B('Scope', [], 'S')];
  large.edges = [1 1 2 1; 2 1 3 1; 3 1 4 1];
  add ('external_worker_thread', large, 0:0.25:1);

  function add (name, model, t, options = struct ('solver', 'rk4'))
    cases(end+1) = struct ('name', name, 'model', model, 't', t, 'options', options);
  endfunction
endfunction

function assert_error (callback, fragment)
  caught = false;
  try
    callback ();
  catch err
    caught = ! isempty (strfind (err.message, fragment));
  end_try_catch
  assert (caught);
endfunction
