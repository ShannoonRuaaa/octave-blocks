function test_ob_api_contract ()
  test_path_cleanup = ob_test_setup ();
  root = fileparts (fileparts (mfilename ('fullpath')));
  % A complete inventory is useful before any 1.0 stability promise is made.
  documented = regexp (fileread (fullfile (root, 'doc', 'API.md')), ...
                       '(?m)^\| `(\w+)` \| (candidate|experimental) \|', 'tokens');
  names = cellfun (@(item) item{1}, documented, 'uniformoutput', false);
  installed = {};
  for folder = {'inst', 'inst/examples', 'inst/simulink'}
    files = dir (fullfile (root, folder{1}, '*.m'));
    for file = files'
      [unused, name] = fileparts (file.name);
      if (! strcmp (name, 'Contents')), installed{end+1} = name; endif
    endfor
  endfor
  assert (sort (names), sort (installed));
  for name = {'octave_blocks', 'ob_save_model', 'ob_load_model'}
    assert (! isempty (strtrim (help (name{1}))));
  endfor
  r = ob_run (ob_oscillator (), 0:0.1:1);
  fields = {'t', 'values', 'flat_values', 'order', 'solver', 'solver_options', ...
            'integration_steps', 'signal_map', 'block_paths', 'compiled_model', ...
            'inputs', 'sample_hits', 'sample_times', 'events'};
  assert (all (isfield (r, fields)));
  assert (size (ob_scope_data (r, 4)), [numel(r.t) 1]);

  if (! any (strcmp (available_graphics_toolkits (), 'qt')))
    identifier = '';
    try
      octave_blocks ();
    catch err
      identifier = err.identifier;
    end_try_catch
    assert (strcmp (identifier, 'octave_blocks:QtUnavailable'));
  else
    disp ('Qt is available; headless preflight rejection is not exercised in this session');
  endif
  % The optimized solver remains conditional on the version it reproduces.
  assert (ob_dormand_prince ('available'), strcmp (OCTAVE_VERSION, '11.3.0'));
  disp ('API inventory, reachable help, runtime result fields and Qt preflight passed');
endfunction
