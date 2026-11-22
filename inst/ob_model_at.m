function diagram = ob_model_at (model, path = [])
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
