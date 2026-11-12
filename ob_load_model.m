function [model, config, options] = ob_load_model (file)
  loaded = load (file, "model", "config", "options");
  if (! isfield (loaded, "model"))
    error ("ob_load_model: the file has no Octave Blocks model");
  endif
  ob_validate_model (loaded.model);
  config = [0 10 0.1];
  if (isfield (loaded, "config")), config = loaded.config; endif
  config = ob_validate_config (config);
  options = struct ();
  if (isfield (loaded, "options")), options = loaded.options; endif
  options = ob_solver_options (options);
  model = loaded.model;
endfunction
