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
  % Build the source-index map using accumarray + mat2cell (same approach as
  % ob_c_adjacency) instead of a scalar edge-append loop.
  sources = repmat ({zeros(1,0)}, 1, count);
  if (!isempty(edges))
    incoming = accumarray (edges(:,2), 1, [count 1]);
    if (issorted(edges(:,2)))
      perm = (1:rows(edges))';
    else
      [~, perm] = sortrows ([edges(:,2) (1:rows(edges))'], [1 2]);
    endif
    sources = reshape (mat2cell (edges(perm,1)', 1, incoming'), 1, []);
  endif
  loops = model.algebraic_loops;
  if (! iscell (loops))
    error ('ob_prepare_runtime_model: algebraic_loops must be a cell array');
  endif
  loop_at = zeros (1, count);
  if (!isempty(loops))
    % Validate all loop groups at once before writing, then build the per-block
    % map in one vectorized pass using repelem/indexing.
    lens    = cellfun (@numel, loops);
    ids_all = [loops{:}];
    if (! isnumeric (ids_all) || ! isreal (ids_all) || isempty (ids_all) ...
        || any (! isfinite (ids_all)) || any (ids_all != fix (ids_all)) ...
        || any (ids_all < 1 | ids_all > count) ...
        || numel (unique (ids_all)) != numel (ids_all) ...
        || any (lens == 0))
      error ('ob_prepare_runtime_model: algebraic loop IDs must be disjoint valid block indices');
    endif
    groups  = repelem (1:numel(loops), lens);
    loop_at(ids_all) = groups;
  endif
  types = {model.blocks.type};
  conditional_mask = strcmp (types, 'Conditional Subsystem');
  limited_mask = strcmp (types, 'Limited Integrator');
  delay_mask = strcmp (types, 'Transport Delay');
  integrator_mask = strcmp (types, 'Integrator') | limited_mask;
  step_mask = strcmp (types, 'Step');
  parameters = cell (1, count);
  for id = reshape (find (limited_mask | delay_mask), 1, [])
    parameters{id} = ob_block_parameters (model.blocks(id));
  endfor
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
      'boundary_ids',reshape(find(step_mask | conditional_mask),1,[]), ...
      'delay_ids',reshape(find(delay_mask),1,[]), ...
      'limited_ids',reshape(find(limited_mask),1,[]), ...
      'parameters',{parameters});
endfunction
