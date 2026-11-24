function ob_save_model (file, model, config, options = struct ())
  ## -*- texinfo -*-
  ## @deftypefn {} {} ob_save_model (@var{file}, @var{model}, @var{config}, @var{options})
  ## Save a model struct, configuration and solver options in a MAT file.
  ## @var{config} is @code{[start stop step]}.  The optional @var{options}
  ## struct uses the same solver settings as @code{ob_run}.  Validate all
  ## inputs and write a temporary file beside the destination before
  ## replacing it.  New files include @code{format_version = 1}.  This
  ## function has no return value.  Replacement uses @code{movefile}; this
  ## does not promise crash durability or atomicity on every filesystem.
  ##
  ## @example
  ## ob_save_model ("model.mat", ob_oscillator (), [0 10 0.1]);
  ## @end example
  ## @seealso{ob_load_model, ob_run}
  ## @end deftypefn

  if (! ischar (file) || rows (file) != 1 || isempty (file))
    error ('ob_save_model:InvalidPath', 'ob_save_model: file path must be a nonempty character row');
  endif
  ob_validate_model (model);
  config = ob_validate_config (config);
  options = ob_solver_options (options);
  format_version = 1;
  % Write beside the destination, then replace it only after a successful save.
  folder = fileparts (file);
  if (isempty (folder)), folder = pwd (); endif
  temporary = [tempname(folder) ".mat"];
  unwind_protect
    save ("-mat7-binary", temporary, "format_version", "model", "config", "options");
    [ok, message] = movefile (temporary, file, "f");
    if (! ok), error ('ob_save_model:WriteFailed', 'ob_save_model: %s', message); endif
  unwind_protect_cleanup
    if (exist (temporary, "file")), unlink (temporary); endif
  end_unwind_protect
endfunction
