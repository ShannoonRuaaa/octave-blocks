function model = ob_set_model_at (model, path, diagram)
  ## -*- texinfo -*-
  ## @deftypefn {} {@var{model} =} ob_set_model_at (@var{model}, @var{path}, @var{diagram})
  ## Replace a subsystem diagram and return the updated model struct.
  ## @var{path} is a sequence of Subsystem block indices, as in
  ## @code{ob_model_at}.  An empty path replaces the root.  The path is
  ## validated before indexing; the replacement diagram is validated when
  ## the model is run, saved, or otherwise explicitly validated.
  ##
  ## @example
  ## m = ob_example ();
  ## m = ob_set_model_at (m, [], ob_oscillator ());
  ## @end example
  ## @seealso{ob_model_at}
  ## @end deftypefn

  if (isempty (path))
    model = diagram;
  else
    path = path(:)';
    ob_model_at (model, path); % validate before indexing
    id = path(1);
    model.blocks(id).value = ob_set_model_at (model.blocks(id).value, path(2:end), diagram);
  endif
endfunction
