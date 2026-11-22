function ids = ob_runtime_type_ids (model, field, type)
  % Indexed block IDs from the runtime cache, or a scan of block types.
  if (isfield (model, 'runtime_info') && isfield (model.runtime_info, 'plan') ...
      && isscalar (model.runtime_info) && any (strcmp (field, {'delay_ids', 'limited_ids'})) ...
      && isfield (model.runtime_info, 'kind') ...
      && strcmp (model.runtime_info.kind, 'octave-blocks-runtime-info-v1'))
    % A same-version plan keeps its own trusted copy of these index lists.
    % Caches of another kind take the validated lookup below.
    ids = model.runtime_info.plan.(strrep (field, '_ids', '_blocks'));
    return;
  endif
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
