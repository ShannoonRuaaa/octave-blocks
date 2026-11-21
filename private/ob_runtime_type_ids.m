function ids = ob_runtime_type_ids (model, field, type)
  % Indexed block IDs from the runtime cache, or a scan of block types.
  if (isfield (model, 'runtime_info') && isstruct (model.runtime_info) ...
      && isscalar (model.runtime_info) && isfield (model.runtime_info, field))
    candidate = model.runtime_info.(field);
    if (isnumeric (candidate) && (isempty (candidate) || (rows (candidate) == 1 ...
        && all (candidate >= 1 & candidate <= numel (model.blocks) & candidate == fix (candidate)))))
      ids = reshape (candidate, 1, []);
      return;
    endif
  endif
  ids = reshape (find (strcmp ({model.blocks.type}, type)), 1, []);
endfunction
