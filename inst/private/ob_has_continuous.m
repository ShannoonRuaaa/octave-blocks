function yes = ob_has_continuous (model)
  yes = any (strcmp ({model.blocks.type}, 'Integrator'));
  if (yes), return; endif
  for id = reshape (find (strcmp ({model.blocks.type}, 'Subsystem')), 1, [])
    if (ob_has_continuous (model.blocks(id).value)), yes = true; return; endif
  endfor
endfunction
