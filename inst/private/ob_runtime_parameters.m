function params = ob_runtime_parameters (model, id)
  % Prepared parameters of a structured block, with a fallback for
  % checkpoints whose runtime cache predates them.
  if (isfield (model, 'runtime_info') && isfield (model.runtime_info, 'plan') ...
      && isscalar (model.runtime_info) && isfield (model.runtime_info, 'kind') ...
      && strcmp (model.runtime_info.kind, 'octave-blocks-runtime-info-v1'))
    % A same-version plan carries its own complete parameter cache.  Caches
    % of another kind take the validated lookup below even with a plan field.
    params = model.runtime_info.plan.parameters{id};
    if (isstruct (params)), return; endif
  elseif (isfield (model, 'runtime_info') && isstruct (model.runtime_info) ...
          && isscalar (model.runtime_info) && isfield (model.runtime_info, 'parameters'))
    cache = model.runtime_info.parameters;
    if (iscell (cache) && numel (cache) == numel (model.blocks) && isstruct (cache{id}))
      params = cache{id};
      return;
    endif
  endif
  params = ob_block_parameters (model.blocks(id));
endfunction
