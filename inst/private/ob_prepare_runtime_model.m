function model = ob_prepare_runtime_model (model, order = [])
  % Prepare immutable graph/execution metadata after validation and flattening.
  % Rebuild rather than trusting a cache supplied by a caller or checkpoint.
  % ORDER, the context's execution order (ob_execution_order), adds the
  % evaluation program for that order to the plan (see ob_program_eval).
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
  plan = evaluation_plan (types, sources, loop_at, parameters, conditional_mask, ...
                          integrator_mask, limited_mask, delay_mask, step_mask, primitive_mask);
  if (! isempty (order))
    program = evaluation_program (plan, order);
    if (! isempty (program)), plan.program = program; endif
  endif
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
      'parameters',{parameters}, ...
      'plan',plan);
endfunction

function program = evaluation_program (plan, order)
  % Evaluation program for one execution order, used by ob_program_eval.
  % It exists only for models that ob_runtime_eval evaluates without
  % lifecycle or solver state: no algebraic loops and no Conditional
  % Subsystem, Conditional Output, Rate Transition or unknown blocks, with
  % the input counts its inline cases assume (others report their errors
  % through ob_runtime_eval's general loop).  The program splits ORDER:
  %  - held: state outputs (Integrator, Unit Delay, Discrete Integrator),
  %    copied from the states first, as ob_runtime_eval already does;
  %  - constants and times: input-free Constant and Time blocks, assigned
  %    before the other blocks, whose values they cannot depend on;
  %  - sinks: Scope/Inport/Outport blocks that no block reads, copied after
  %    all others from their single source;
  %  - slots: the remaining blocks, evaluated in ORDER with ops (their plan
  %    codes) and first/second/third/inputs (their sources).
  % Flags: preset (there are constants or times), copies (there are sinks)
  % and controls (a slot is a Saturation, Dead Zone or Switch).  The
  % grouped blocks cannot fail, so an error still comes from the same
  % block, in the same order, with the same message.  Field names avoid the
  % *_ids suffix that metadata tools strip.
  program = [];
  codes = plan.codes; sources = plan.sources;
  count = numel (codes);
  order = reshape (order, 1, []);
  if (plan.loops || any (ismember (codes, [0 15 16 17])) ...
      || ! isequal (sort (order), 1:count))
    return;
  endif
  arity = cellfun ('numel', sources);
  % Input counts the inline cases take for granted; -1 means at least one,
  % NaN any (blocks whose evaluation does not read their inputs).
  expected = [0 0 0 0 1 2 2 1 1 3 -1 1 -1 1 NaN NaN NaN NaN NaN NaN];
  for id = 1:count
    want = expected(codes(id));
    if ((want == -1 && arity(id) < 1) || (want >= 0 && arity(id) != want)), return; endif
  endfor
  read = false (1, count);
  read([sources{:}]) = true;
  coded = codes(order);
  held = coded == 18;
  constants = coded == 2;
  times = coded == 3;
  sinks = coded == 12 & ! read(order);
  rest = ! (held | constants | times | sinks);
  slots = order(rest);
  first = zeros (1, numel (slots)); second = first; third = first;
  for k = 1:numel (slots)
    s = sources{slots(k)};
    if (numel (s) >= 1), first(k) = s(1); endif
    if (numel (s) >= 2), second(k) = s(2); endif
    if (numel (s) >= 3), third(k) = s(3); endif
  endfor
  sink_blocks = order(sinks);
  sink_sources = zeros (1, numel (sink_blocks));
  for k = 1:numel (sink_blocks), sink_sources(k) = sources{sink_blocks(k)}; endfor
  program = struct ('kind', 'octave-blocks-runtime-program-v1', 'order', order, ...
      'count', count, 'held', order(held), 'constants', order(constants), ...
      'times', order(times), 'slots', slots, 'ops', codes(slots), ...
      'first', first, 'second', second, 'third', third, ...
      'inputs', {sources(slots)}, 'sinks', sink_blocks, 'sink_sources', sink_sources, ...
      'preset', any (constants | times), 'copies', ! isempty (sink_blocks), ...
      'controls', any (ismember (codes(slots), [8 9 10])));
endfunction

function plan = evaluation_plan (types, sources, loop_at, parameters, conditional_mask, ...
                                 integrator_mask, limited_mask, delay_mask, step_mask, primitive_mask)
  % Numeric dispatch codes and fixed index lists for the solver hot paths.
  % Hot paths trust this optional record only inside a runtime_info of kind
  % octave-blocks-runtime-info-v1 (it is rebuilt with the rest of the cache)
  % and fall back to the general string/validation paths without it, e.g. for
  % checkpoints saved before it existed or caches of another kind.
  % The plan is self-contained: its own copies of the category lists
  % (*_blocks), source map, loop map and block parameters keep it independent
  % of the other runtime_info fields, which tools may strip or checkpoints may
  % lack (Octave shares the copies until one side is modified).
  % Block values are deliberately not cached: they are read live.
  names = {'External Input','Constant','Time','Step','Gain','Sum','Product', ...
           'Saturation','Dead Zone','Switch','Function','Scope','Inport','Outport', ...
           'Multiple Function','Function Output','Conditional Subsystem', ...
           'Conditional Output','Rate Transition','Unit Delay','Discrete Integrator', ...
           'Integrator','Limited Integrator','Transport Delay'};
  % Codes follow ob_runtime_eval's dispatch; 0 is an unknown type.
  values = [1 2 3 4 5 6 7 8 9 10 11 12 12 12 13 14 15 16 17 18 18 18 19 20];
  [known, where] = ismember (types, names);
  codes = zeros (1, numel (types));
  codes(known) = values(where(known));
  resettable = zeros (1, 0);
  for id = reshape (find (limited_mask), 1, [])
    if (! strcmp (parameters{id}.reset, 'none')), resettable(end+1) = id; endif
  endfor
  % Models without these blocks or resets can use the engine's single-hit step.
  lite = ! any (conditional_mask) && isempty (resettable) ...
         && ! any (strcmp (types, 'Unit Delay') | strcmp (types, 'Discrete Integrator') ...
                   | strcmp (types, 'Rate Transition'));
  plan = struct ('kind', 'octave-blocks-runtime-plan-v1', 'codes', codes, 'lite', lite, ...
      'sources', {sources}, 'loop_at', loop_at, 'parameters', {parameters}, ...
      'loops', any (loop_at), 'conditional', any (conditional_mask), ...
      'conditional_mask', conditional_mask, ...
      'conditional_blocks', reshape (find (conditional_mask), 1, []), ...
      'integrator_blocks', reshape (find (integrator_mask), 1, []), ...
      'limited', any (limited_mask), ...
      'limited_blocks', reshape (find (limited_mask), 1, []), ...
      'resettable', resettable, ...
      'delay_blocks', reshape (find (delay_mask), 1, []), ...
      'step_blocks', reshape (find (step_mask), 1, []), ...
      'boundary_blocks', reshape (find (step_mask | conditional_mask), 1, []), ...
      'guard_blocks', reshape (find (primitive_mask | conditional_mask), 1, []));
endfunction
