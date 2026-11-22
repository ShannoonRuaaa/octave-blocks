function yes = ob_has_inner_clocks (model)
  rates = ob_sample_times (model);
  yes = any (rates(:,1) > 0);
  if (yes), return; endif
  for id = reshape (find (strcmp ({model.blocks.type}, 'Subsystem')), 1, [])
    if (ob_has_inner_clocks (model.blocks(id).value)), yes = true; return; endif
  endfor
endfunction
