function [model, config, options] = ob_load_model (file)
  ## -*- texinfo -*-
  ## @deftypefn {} {[@var{model}, @var{config}, @var{options}] =} ob_load_model (@var{file})
  ## Load and validate an Octave Blocks MAT file.
  ## Return the model struct, @code{[start stop step]} configuration and
  ## normalized solver options.  Older files without configuration use
  ## @code{[0 10 0.1]}; missing options use the default solver settings.
  ##
  ## @example
  ## [m, config, options] = ob_load_model ("model.mat");
  ## @end example
  ## @seealso{ob_save_model, ob_run}
  ## @end deftypefn

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
