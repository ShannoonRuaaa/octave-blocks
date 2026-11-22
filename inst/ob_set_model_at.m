function model = ob_set_model_at (model, path, diagram)
  if (isempty (path))
    model = diagram;
  else
    path = path(:)';
    ob_model_at (model, path); % validate before indexing
    id = path(1);
    model.blocks(id).value = ob_set_model_at (model.blocks(id).value, path(2:end), diagram);
  endif
endfunction
