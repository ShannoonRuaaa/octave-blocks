function ob_simulink_setup ()
  % OB_SIMULINK_SETUP Opt in to Simulink-named command wrappers.
  % These names intentionally take precedence over same-named functions.
  addpath (fullfile(fileparts(mfilename('fullpath')),'simulink'));
endfunction
