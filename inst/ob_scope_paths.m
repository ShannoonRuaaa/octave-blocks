function paths = ob_scope_paths (model, prefix = [])
  ## -*- texinfo -*-
  ## @deftypefn {} {@var{paths} =} ob_scope_paths (@var{model}, @var{prefix})
  ## Return a cell row of paths to every Scope in a model hierarchy.
  ## Each path is a row of block indices from the root to a Scope.  The
  ## optional @var{prefix}, normally empty, is prepended to every path.
  ## Scopes are visited in block order, descending into each Subsystem.
  ##
  ## @example
  ## paths = ob_scope_paths (ob_oscillator ());
  ## @end example
  ## @seealso{ob_scope_data, ob_signal_values}
  ## @end deftypefn

  paths = {};
  for id = 1:numel (model.blocks)
    if (strcmp (model.blocks(id).type, 'Scope'))
      paths{end + 1} = [prefix id];
    elseif (strcmp (model.blocks(id).type, 'Subsystem'))
      paths = [paths ob_scope_paths(model.blocks(id).value, [prefix id])];
    endif
  endfor
endfunction
