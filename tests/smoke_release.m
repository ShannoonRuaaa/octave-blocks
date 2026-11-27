function report = smoke_release (tarball, output_directory = '')
  ## -*- texinfo -*-
  ## @deftypefn {} {@var{report} =} smoke_release (@var{tarball}, @var{output_directory})
  ## Verify an installed release in an isolated package registry and prefix.
  ## Run from a fresh Octave process with only tests/ added to the path.
  ## GCC and mkoctfile must be on PATH.  Artifacts and a JSON status report
  ## remain in the optional output directory (default: tests/.artifacts/).
  ## OB_SKIP_ACCELERATOR skips MEX checks explicitly; it does not test fallback.
  ## This focused smoke check is not the full release gate.
  ## @end deftypefn

  if (nargin < 1 || ! ischar (tarball) || exist (tarball, 'file') != 2)
    error ('smoke_release:MissingTarball', 'supply an existing package tarball');
  endif
  if (! isempty (which ('ob_run')) || ! isempty (which ('new_system')))
    error ('smoke_release:FreshSessionRequired', ...
           'start a fresh Octave process; add tests/ without running ob_setup or pkg load');
  endif
  tarball = canonicalize_file_name (tarball);
  if (isempty (output_directory))
    artifacts = fullfile (fileparts (mfilename ('fullpath')), '.artifacts');
    if (! exist (artifacts, 'dir')), mkdir (artifacts); endif
    output_directory = tempname (artifacts);
  elseif (exist (output_directory, 'dir'))
    error ('smoke_release:ExistingDirectory', 'choose a new output directory');
  endif
  mkdir (output_directory);
  output_directory = canonicalize_file_name (output_directory);
  report = struct ('octave', OCTAVE_VERSION, 'platform', computer (), ...
                   'tarball_sha256', hash ('sha256', fileread (tarball)), ...
                   'installed', false, 'runtime', false, 'model_format', false, ...
                   'command_api', false, 'generated_c', false, 'accelerator', 'pending', ...
                   'unloaded', false, 'uninstalled', false, ...
                   'registry_restored', false, 'complete', false);
  previous_path = path ();
  previous_directory = pwd ();
  [previous_prefix, previous_arch] = pkg ('prefix');
  previous_local = pkg ('local_list');
  previous_global = pkg ('global_list');
  previous_cache = getenv ('OB_ACCELERATOR_CACHE');
  isolated_install = false;
  unwind_protect
    % pkg temporarily changes directory while unpacking.  Relative path
    % entries would then be dropped, so use absolute entries until cleanup.
    entries = strsplit (previous_path, pathsep ());
    entries = cellfun (@make_absolute_filename, entries, 'uniformoutput', false);
    path (strjoin (entries, pathsep ()));
    % Prefix alone is insufficient: installation and uninstall also mutate
    % the registry.  Isolate both lists before any package operation.
    pkg ('local_list', fullfile (output_directory, 'local-packages.list'));
    pkg ('global_list', fullfile (output_directory, 'global-packages.list'));
    pkg ('prefix', fullfile (output_directory, 'pkg'), fullfile (output_directory, 'arch'));
    setenv ('OB_ACCELERATOR_CACHE', fullfile (output_directory, 'cache'));
    pkg ('install', '-local', tarball);
    isolated_install = true;
    pkg ('load', 'octave-blocks');
    report.installed = true;
    assert (isempty (which ('ob_is_combined_mode')) && isempty (which ('ob_is_resettable_mode')));
    assert (! isempty (strfind (which ('ob_example'), [filesep 'examples' filesep])));

    times = 0:0.1:2;
    oscillator = ob_oscillator ();
    plain = ob_run (oscillator, times);
    adaptive = ob_run (oscillator, times, struct ('solver', 'ode45', 'reltol', 1e-8, 'abstol', 1e-10));
    reference = ob_scope_data (plain, 4);
    assert (max (abs (reference - cos (times(:)))) < 1e-5);
    assert (max (abs (ob_scope_data (adaptive, 4) - cos (times(:)))) < 1e-6);
    ob_run (ob_combined_control_example (), 0:0.25:1);
    report.runtime = true;

    model_file = fullfile (output_directory, 'roundtrip.mat');
    ob_save_model (model_file, oscillator, [0 2 0.1]);
    [restored, config, options, version] = ob_load_model (model_file);
    assert (version == 1 && isequal (config, [0 2 0.1]));
    assert (ob_scope_data (ob_run (restored, times, options), 4), reference, 1e-12);
    report.model_format = true;

    ob_simulink_setup ();
    name = 'ob_release_smoke';
    new_system (name);
    add_block ('simulink/Sources/Constant', [name '/u'], 'Value', '1');
    add_block ('simulink/Math Operations/Gain', [name '/Gain'], 'Gain', '3');
    add_block ('simulink/Sinks/Out1', [name '/y']);
    add_line (name, 'u/1', 'Gain/1'); add_line (name, 'Gain/1', 'y/1');
    set_param (name, 'Solver', 'ode4', 'FixedStep', '0.1', 'StopTime', '1', 'SaveFormat', 'Dataset');
    output = sim (name);
    assert (all (output.yout.getElement (1).Values.Data(:) == 3));
    save_system (name, fullfile (output_directory, [name '.mat']));
    assert (load (fullfile (output_directory, [name '.mat'])).format_version == 1);
    bdclose (name);
    report.command_api = true;

    source = fullfile (output_directory, 'oscillator.c');
    executable = fullfile (output_directory, 'oscillator');
    if (ispc ()), executable = [executable '.exe']; endif
    csv = fullfile (output_directory, 'oscillator.csv');
    exported = ob_codegen (oscillator, source, [0 2 0.1]);
    compiler = getenv ('CC');
    if (isempty (compiler))
      compiler = file_in_path (getenv ('PATH'), 'gcc');
      if (ispc ()), compiler = file_in_path (getenv ('PATH'), 'gcc.exe'); endif
    endif
    if (isempty (compiler)), error ('smoke_release:CompilerRequired', 'put GCC on PATH or set CC to its executable'); endif
    report.compiler = compiler;
    run_command (sprintf ('%s -std=c99 -O2 -Wall -Wextra -Werror -DOB_STANDALONE %s -lm -o %s', ...
                         shell_arg (compiler), shell_arg (source), shell_arg (executable)));
    run_command (sprintf ('%s > %s', shell_arg (executable), shell_arg (csv)));
    actual = dlmread (csv, ',', 1, 0);
    expected = plain.t;
    for block = 1:numel (plain.compiled_model.blocks)
      width = prod (exported.shapes{block});
      if (width == 0), continue; endif
      values = zeros (numel (times), width);
      for sample = 1:numel (times)
        values(sample, :) = plain.flat_values{sample, block}(:)';
      endfor
      expected = [expected values];
    endfor
    assert (size (actual), size (expected));
    assert (max (abs (actual(:) - expected(:))) < 1e-11);
    report.generated_c = true;

    if (isempty (getenv ('OB_SKIP_ACCELERATOR')))
      [fast, first] = ob_accelerate (oscillator, times);
      [again, cached] = ob_accelerate (oscillator, times);
      assert (ob_scope_data (fast, 4), reference, 1e-11);
      assert (ob_scope_data (again, 4), reference, 1e-11);
      assert (cached.cache_hit && strcmp (first.mex, cached.mex));
      changed = oscillator;
      changed.blocks(3).value = -4;
      [different, edited] = ob_accelerate (changed, times);
      expected_edit = ob_run (changed, times);
      assert (! strcmp (first.mex, edited.mex));
      assert (ob_scope_data (different, 4), ob_scope_data (expected_edit, 4), 1e-11);
      report.accelerator = 'passed';
    else
      report.accelerator = 'skipped (OB_SKIP_ACCELERATOR)';
      disp ('Accelerator checks skipped explicitly; fallback was not tested');
    endif
    pkg ('unload', 'octave-blocks');
    assert (isempty (which ('ob_run')) && isempty (which ('ob_example')) && isempty (which ('new_system')));
    report.unloaded = true;
    pkg ('uninstall', '-local', 'octave-blocks');
    isolated_install = false;
    assert (isempty (pkg ('list')));
    report.uninstalled = true;
    report.complete = true;
  unwind_protect_cleanup
    if (isolated_install)
      try
        if (! isempty (which ('ob_simulink'))), ob_simulink ('bdclose', 'all'); endif
        pkg ('unload', 'octave-blocks');
        pkg ('uninstall', '-local', 'octave-blocks');
      catch cleanup_error
        warning ('smoke_release:CleanupFailed', '%s', cleanup_error.message);
      end_try_catch
    endif
    % Setting a missing registry path with pkg creates a file.  Reset its
    % defaults first so restoring a previously absent default never writes
    % into the user's normal registry.  Custom registry paths already exist.
    % pkg mlocks itself; unlock it explicitly before resetting its defaults.
    munlock ('pkg');
    clear pkg;
    if (! strcmp (pkg ('local_list'), previous_local))
      if (exist (previous_local, 'file'))
        pkg ('local_list', previous_local);
      else
        warning ('smoke_release:RegistryNotRestored', 'previous custom local registry is absent');
      endif
    endif
    if (! strcmp (pkg ('global_list'), previous_global))
      if (exist (previous_global, 'file'))
        pkg ('global_list', previous_global);
      else
        warning ('smoke_release:RegistryNotRestored', 'previous custom global registry is absent');
      endif
    endif
    [default_prefix, default_arch] = pkg ('prefix');
    if (! strcmp (default_prefix, previous_prefix) || ! strcmp (default_arch, previous_arch))
      pkg ('prefix', previous_prefix, previous_arch);
    endif
    [restored_prefix, restored_arch] = pkg ('prefix');
    report.registry_restored = strcmp (pkg ('local_list'), previous_local) ...
                               && strcmp (pkg ('global_list'), previous_global) ...
                               && strcmp (restored_prefix, previous_prefix) ...
                               && strcmp (restored_arch, previous_arch);
    report.complete = report.complete && report.registry_restored;
    setenv ('OB_ACCELERATOR_CACHE', previous_cache);
    cd (previous_directory);
    path (previous_path);
    fid = fopen (fullfile (output_directory, 'smoke-report.json'), 'w');
    if (fid >= 0), fputs (fid, jsonencode (report)); fclose (fid); endif
    fprintf ('Smoke artifacts: %s\n', output_directory);
  end_unwind_protect
  if (! report.complete)
    error ('smoke_release:StateNotRestored', 'package registry or prefix was not restored; inspect the smoke report');
  endif
  fprintf ('Release smoke passed (accelerator: %s); this is not full release validation.\n', report.accelerator);
endfunction

function run_command (command)
  [status, output] = system (command);
  if (status != 0), error ('smoke_release:CommandFailed', '%s\n%s', command, output); endif
endfunction

function quoted = shell_arg (value)
  if (ispc ())
    if (! isempty (regexp (value, '["\r\n%]', 'once')))
      error ('smoke_release:UnsupportedPath', 'Windows command paths must not contain quotes, newlines or percent signs');
    endif
    quoted = ['"' value '"'];
  else
    quoted = ["'" strrep(value, "'", "'\"'\"'") "'"];
  endif
endfunction
