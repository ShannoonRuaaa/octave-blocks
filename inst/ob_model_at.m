function diagram = ob_model_at (model, path = [])
  ## -*- texinfo -*-
  ## @deftypefn {} {@var{diagram} =} ob_model_at (@var{model}, @var{path})
  ## Return the subsystem diagram at a path of block indices.
  ## Each element of @var{path} identifies a Subsystem in the preceding
  ## diagram.  An empty or omitted path returns the root model.  Invalid
  ## subsystem paths raise an error.
  ##
  ## @example
  ## m = ob_subsystem_example ();
  ## root = ob_model_at (m, []);
  ## @end example
  ## @seealso{ob_set_model_at}
  ## @end deftypefn

  diagram = model;
  if (! isnumeric (path) || ! isreal (path) || (! isempty (path) && ! isvector (path)) ...
      || any (! isfinite (path(:))))
    error ("ob_model_at: path must contain subsystem block indices");
  endif
  for id = path(:)'
    if (! isscalar (id) || id < 1 || id != fix (id) || id > numel (diagram.blocks) ...
        || ! strcmp (diagram.blocks(id).type, "Subsystem"))
      error ("ob_model_at: path must identify subsystem blocks");
    endif
    diagram = diagram.blocks(id).value;
  endfor
endfunction
