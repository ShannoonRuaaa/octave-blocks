function model = ob_prepare_runtime_model (model)
  % Prepare immutable graph/execution metadata after validation and flattening.
  % Rebuild rather than trusting a cache supplied by a caller or checkpoint.
  count = numel (model.blocks);
  canonical = sortrows (ob_edges (model), [3 4]);
  sources = repmat ({zeros(1,0)}, 1, count);
  for edge = canonical'
    sources{edge(3)}(end+1) = edge(1);
  endfor
  if (! isfield (model, 'algebraic_loops'))
    [unused_order, unused_edges, unused_stateful, model.algebraic_loops] = ...
        ob_execution_order (model, true);
  endif
  loops = model.algebraic_loops;
  if (! iscell (loops))
    error ('ob_prepare_runtime_model: algebraic_loops must be a cell array');
  endif
  loop_at = zeros (1, count);
  for group = 1:numel (loops)
    ids = loops{group};
    if (! isnumeric (ids) || ! isreal (ids) || ! isvector (ids) || isempty (ids) ...
        || any (! isfinite (ids)) || any (ids != fix (ids)) ...
        || any (ids < 1 | ids > count) || numel (unique(ids)) != numel (ids) ...
        || any (loop_at(ids) != 0))
      error ('ob_prepare_runtime_model: algebraic loop IDs must be disjoint valid block indices');
    endif
    loop_at(ids) = group;
  endfor
  conditional = cell (1, count);
  for id = reshape (find (strcmp ({model.blocks.type}, 'Conditional Subsystem')), 1, [])
    conditional{id} = ob_event_execution (model.blocks(id).value, struct ());
  endfor
  model.runtime_info = struct ('kind','octave-blocks-runtime-info-v1', ...
      'sources',{sources},'loop_at',loop_at,'conditional',{conditional});
endfunction
