function model = ob_prepare_runtime_model (model)
  % Prepare immutable graph/execution metadata after validation and flattening.
  % Rebuild rather than trusting a cache supplied by a caller or checkpoint.
  count = numel (model.blocks);
  if (! isfield (model, 'algebraic_loops'))
    [unused_order, edges, unused_stateful, model.algebraic_loops] = ...
        ob_execution_order (model, true);
  else
    canonical = sortrows (ob_edges (model), [3 4]);
    edges = canonical(:, [1 3]);
  endif
  sources = repmat ({zeros(1,0)}, 1, count);
  for edge = edges'
    sources{edge(2)}(end+1) = edge(1);
  endfor
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
  types = {model.blocks.type};
  conditional_mask = strcmp (types, 'Conditional Subsystem');
  integrator_mask = strcmp (types, 'Integrator');
  step_mask = strcmp (types, 'Step');
  primitive_mask = strcmp (types, 'Switch') | strcmp (types, 'Saturation') | strcmp (types, 'Dead Zone');
  conditional_ids = reshape (find (conditional_mask), 1, []);
  conditional = cell (1, count);
  for id = conditional_ids
    conditional{id} = ob_event_execution (model.blocks(id).value, struct ());
  endfor
  model.runtime_info = struct ('kind','octave-blocks-runtime-info-v1', ...
      'sources',{sources},'loop_at',loop_at,'conditional',{conditional}, ...
      'conditional_ids',conditional_ids, ...
      'integrator_ids',reshape(find(integrator_mask),1,[]), ...
      'step_ids',reshape(find(step_mask),1,[]), ...
      'zc_ids',reshape(find(primitive_mask | conditional_mask),1,[]), ...
      'continuous_path_ids',reshape(find(integrator_mask | conditional_mask),1,[]), ...
      'boundary_ids',reshape(find(step_mask | conditional_mask),1,[]));
endfunction
