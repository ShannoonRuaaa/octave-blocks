function cleanup = ob_test_setup ()
  root = fileparts(fileparts(mfilename('fullpath')));
  original = path ();
  scratch = fullfile(root,'tests','.artifacts','scratch');
  if (!exist(scratch,'dir')), mkdir(scratch); endif
  variables = {'TMPDIR','TMP','TEMP'};
  previous = cellfun(@getenv,variables,'uniformoutput',false);
  for key = variables, setenv(key{1},scratch); endfor
  addpath (root);
  addpath (fullfile(root,'tests','benchmarks'));
  addpath (fullfile(root,'private'));
  cleanup = onCleanup (@() restore_environment(original,variables,previous));
endfunction

function restore_environment (original, variables, previous)
  path (original);
  for k = 1:numel(variables), setenv(variables{k},previous{k}); endfor
endfunction
