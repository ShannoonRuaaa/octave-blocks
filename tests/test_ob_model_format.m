function test_ob_model_format ()
  test_path_cleanup = ob_test_setup ();
  % The schema guard must reject unknown formats before interpreting a model.
  directory = tempname ();
  mkdir (directory);
  unwind_protect
    model = ob_oscillator ();
    config = [0 1 0.1];
    options = struct ('solver', 'rk4');
    file = fullfile (directory, 'model.mat');
    ob_save_model (file, model, config, options);
    raw = load (file);
    assert (raw.format_version, 1);
    [restored, settings, solver, version] = ob_load_model (file);
    assert (restored, model);
    assert (settings, config);
    assert (strcmp (solver.solver, 'rk4') && version == 1);
    before = ob_run (model, 0:0.1:1);
    after = ob_run (restored, 0:0.1:1, solver);
    assert (ob_scope_data (before, 4), ob_scope_data (after, 4), 1e-12);

    % A failed validation must preserve an existing destination byte for byte.
    original = hash ('sha256', fileread (file));
    invalid = model; invalid.edges = [NaN 2];
    failed = false;
    try
      ob_save_model (file, invalid, config);
    catch
      failed = true;
    end_try_catch
    assert (failed && strcmp (original, hash ('sha256', fileread (file))));

    % Legacy files are read without modification; re-saving adds the version.
    save ('-mat7-binary', file, 'model');
    [restored, settings, solver, version] = ob_load_model (file);
    assert (restored, model);
    assert (settings, [0 10 0.1]);
    assert (strcmp (solver.solver, 'rk4') && version == 0);
    assert (! isfield (load (file), 'format_version'));
    ob_save_model (file, restored, settings, solver);
    assert (load (file).format_version, 1);

    save ('-mat7-binary', file, 'model', 'config', 'options');
    [restored, settings, solver, version] = ob_load_model (file);
    assert (settings, config);
    assert (version, 0);

    for bad = {[], 0, -1, 1.5, NaN, Inf, [1 1], '1', true, 1+i}
      format_version = bad{1};
      save ('-mat7-binary', file, 'format_version', 'model');
      expect_id (@() ob_load_model (file), 'ob_load_model:InvalidFormatVersion');
    endfor
    format_version = 99;
    % No model at all: a future format still takes precedence.
    save ('-mat7-binary', file, 'format_version');
    expect_id (@() ob_load_model (file), 'ob_load_model:UnsupportedFormatVersion');
    format_version = 1;
    save ('-mat7-binary', file, 'format_version');
    expect_id (@() ob_load_model (file), 'ob_load_model:MissingModel');
    expect_id (@() ob_load_model (fullfile (directory, 'absent.mat')), 'ob_load_model:FileNotFound');
    expect_id (@() ob_load_model ([]), 'ob_load_model:InvalidPath');
    expect_id (@() ob_save_model ([], model, config), 'ob_save_model:InvalidPath');
  unwind_protect_cleanup
    % DIRECTORY came from tempname after ob_test_setup selected tests/.artifacts.
    rmdir (directory, 's');
  end_unwind_protect
  disp ('Model format: roundtrip, legacy normalization, failed-save preservation and version guards passed');
endfunction

function expect_id (callback, identifier)
  actual = '';
  try
    callback ();
  catch err
    actual = err.identifier;
  end_try_catch
  assert (strcmp (actual, identifier), 'expected %s, got %s', identifier, actual);
endfunction
