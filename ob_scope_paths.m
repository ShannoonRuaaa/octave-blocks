function paths = ob_scope_paths (model, prefix = [])
  paths = {};
  for id = 1:numel (model.blocks)
    if (strcmp (model.blocks(id).type, 'Scope'))
      paths{end + 1} = [prefix id];
    elseif (strcmp (model.blocks(id).type, 'Subsystem'))
      paths = [paths ob_scope_paths(model.blocks(id).value, [prefix id])];
    endif
  endfor
endfunction
