function params = ob_runtime_parameters (model, id)
  % Prepared parameters of a structured block, with a fallback for
  % checkpoints whose runtime cache predates them.
  if (isfield (model, 'runtime_info') && isstruct (model.runtime_info) ...
      && isscalar (model.runtime_info) && isfield (model.runtime_info, 'parameters'))
    cache = model.runtime_info.parameters;
    if (iscell (cache) && numel (cache) == numel (model.blocks) && isstruct (cache{id}))
      params = cache{id};
      return;
    endif
  endif
  params = ob_block_parameters (model.blocks(id));
endfunction
