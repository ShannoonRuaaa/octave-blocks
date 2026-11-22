function root = ob_setup (option = '')
  % OB_SETUP Configure a source checkout; installed packages use pkg load.
  %   ob_setup() adds the installed API and examples, without test internals.
  %   ob_setup('tests') also adds developer tests, benchmarks and tools.
  root = fileparts(mfilename('fullpath'));
  if (!ischar(option) || !any(strcmp(option,{'','tests'})))
    error ('ob_setup: use ob_setup() or ob_setup(''tests'')');
  endif
  addpath (fullfile(root,'inst'));
  addpath (fullfile(root,'inst','examples'));
  if (strcmp(option,'tests'))
    addpath (fullfile(root,'tests'));
    addpath (fullfile(root,'tests','benchmarks'));
    addpath (fullfile(root,'tools'));
  endif
endfunction
