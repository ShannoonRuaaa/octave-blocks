function cleanup = ob_test_setup ()
  root = fileparts(fileparts(mfilename('fullpath')));
  original = path ();
  scratch = fullfile(root,'tests','.artifacts','scratch');
  % Parallel stages share this folder, so another process may create it
  % between the check and mkdir; only fail if it still does not exist.
  if (!exist(scratch,'dir'))
    [ok, message] = mkdir (scratch);
    if (!ok && !exist (scratch, 'dir'))
      error ('ob_test_setup: cannot create %s: %s', scratch, message);
    endif
  endif
  variables = {'TMPDIR','TMP','TEMP'};
  previous = cellfun(@getenv,variables,'uniformoutput',false);
  for key = variables, setenv(key{1},scratch); endfor
  addpath (root);
  addpath (fullfile(root,'inst'));
  addpath (fullfile(root,'inst','examples'));
  addpath (fullfile(root,'tests','benchmarks'));
  addpath (fullfile(root,'inst','private'));
  cleanup = onCleanup (@() restore_environment(original,variables,previous));
endfunction

function restore_environment (original, variables, previous)
  path (original);
  for k = 1:numel(variables), setenv(variables{k},previous{k}); endfor
endfunction
