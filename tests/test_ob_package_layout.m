function test_ob_package_layout ()
  test_path_cleanup = ob_test_setup ();
  % Keep installed function discovery and both catalogs synchronized.
  % Private implementation and developer tests must never become public APIs.
  root = fileparts (fileparts (mfilename ('fullpath')));
  functions = {};
  for folder = {'inst', 'inst/examples', 'inst/simulink'}
    files = dir (fullfile (root, folder{1}, '*.m'));
    for file = files'
      [unused, name] = fileparts (file.name);
      if (strcmp (name, 'Contents')), continue; endif
      assert (! any (strcmp (functions, name)), ...
              'test_ob_package_layout: duplicate installed function %s', name);
      functions{end+1} = name;
      source = fileread (fullfile (root, folder{1}, file.name));
      signature = regexp (source, '^function\s+(?:\[[^\]]*\]\s*=\s*|\w+\s*=\s*)?(\w+)\s*\(', 'tokens', 'once');
      assert (! isempty (signature) && strcmp (signature{1}, name), ...
              'test_ob_package_layout: filename/signature mismatch in %s', file.name);
      % Inspect help without running examples or opening the Qt editor.
      [text, format] = get_help_text (fullfile (root, folder{1}, file.name));
      assert (! any (strcmp (format, {'not found', 'not documented'})) && ! isempty (strtrim (text)), ...
              'test_ob_package_layout: missing help in %s', file.name);
    endfor
  endfor
  indexed = {};
  lines = strsplit (fileread (fullfile (root, 'INDEX')), '\n');
  for line = lines
    if (! isempty (regexp (line{1}, '^\s+\w', 'once')))
      indexed = [indexed strsplit(strtrim(line{1}))];
    endif
  endfor
  catalog = regexp (fileread (fullfile (root, 'inst', 'Contents.m')), ...
                    '(?m)^##   (\w+)\s+-', 'tokens');
  catalog = cellfun (@(entry) entry{1}, catalog, 'uniformoutput', false);
  assert (sort (indexed), sort (functions));
  assert (sort (catalog), sort (functions));
  for name = {'ob_is_combined_mode', 'ob_is_resettable_mode'}
    assert (exist (fullfile (root, 'inst', 'private', [name{1} '.m']), 'file') == 2);
    assert (! exist (fullfile (root, 'inst', [name{1} '.m']), 'file'));
  endfor
  printf ('Package layout passed (%d unique installed functions, matching INDEX/Contents and reachable help)\n', ...
          numel (functions));
endfunction
