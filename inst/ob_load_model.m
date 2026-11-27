function [model, config, options, format_version] = ob_load_model (file)
  ## -*- texinfo -*-
  ## @deftypefn {} {[@var{model}, @var{config}, @var{options}, @var{format_version}] =} ob_load_model (@var{file})
  ## Load and validate an Octave Blocks MAT file.
  ## Return the model struct, @code{[start stop step]} configuration and
  ## normalized solver options.  Older files without configuration use
  ## @code{[0 10 0.1]}; missing options use the default solver settings.
  ## The optional fourth output is the file's schema version: 1 for current
  ## files, or 0 for legacy unversioned files.  Legacy files are normalized
  ## in memory and receive version 1 when saved again.  Invalid versions
  ## and versions newer than 1 are rejected before model validation.
  ##
  ## @example
  ## [m, config, options] = ob_load_model ("model.mat");
  ## @end example
  ## @seealso{ob_save_model, ob_run}
  ## @end deftypefn

  if (! ischar (file) || rows (file) != 1 || isempty (file))
    error ('ob_load_model:InvalidPath', 'ob_load_model: file path must be a nonempty character row');
  endif
  if (exist (file, 'file') != 2)
    error ('ob_load_model:FileNotFound', 'ob_load_model: file not found: %s', file);
  endif
  loaded = load (file, 'format_version', 'model', 'config', 'options');
  supported_version = 1;
  format_version = 0;
  if (isfield (loaded, 'format_version'))
    version = loaded.format_version;
    if (! isnumeric (version) || ! isreal (version) || ! isscalar (version) ...
        || ! isfinite (version) || version < 1 || version != fix (version))
      error ('ob_load_model:InvalidFormatVersion', ...
             'ob_load_model: format_version must be a positive integer');
    endif
    format_version = double (version);
    if (format_version > supported_version)
      error ('ob_load_model:UnsupportedFormatVersion', ...
             'ob_load_model: file uses format_version %g; this release supports up to %d', ...
             format_version, supported_version);
    endif
  endif
  if (! isfield (loaded, "model"))
    error ('ob_load_model:MissingModel', 'ob_load_model: the file has no Octave Blocks model');
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
