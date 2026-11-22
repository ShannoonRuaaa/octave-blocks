function root = ob_setup (option = '')
  % OB_SETUP Configure a source checkout; installed packages use pkg load.
  %   ob_setup() adds the installed API and examples, without test internals.
  %   ob_setup('tests') also adds developer tests, benchmarks and tools.
  root = fileparts(mfilename('fullpath'));
  if (!ischar(option) || !any(strcmp(option,{'','tests','simulink','all'})))
    error ('ob_setup: use ob_setup(), tests, simulink or all');
  endif
  addpath (fullfile(root,'inst'));
  addpath (fullfile(root,'inst','examples'));
  if (any(strcmp(option,{'tests','all'})))
    addpath (fullfile(root,'tests'));
    addpath (fullfile(root,'tests','benchmarks'));
    addpath (fullfile(root,'tools'));
  endif
  if (any(strcmp(option,{'simulink','all'}))), ob_simulink_setup (); endif
endfunction
