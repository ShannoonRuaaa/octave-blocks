function ctx = ob_linearize_context (caller, model, x0, u0, t0)
  % Compile MODEL once at time T0 for ob_linearize and ob_findop.
  %
  % CALLER is the public function name used as the error prefix and
  % identifier ('ob_linearize' or 'ob_findop').  X0 and U0 may be empty (the
  % model's initial states, zero inputs - the linmod/trim defaults).  The
  % returned context holds the compiled runtime and index maps; points are
  % evaluated with ob_linearize_eval without recompiling.
  %
  % Supported states: continuous Integrator blocks, and Limited Integrator
  % blocks without a reset port while the operating point lies strictly
  % inside their limits (the block is then locally an Integrator).  Discrete,
  % delay and conditional states raise CALLER:unsupported instead of being
  % dropped silently.
  if (! isnumeric (t0) || ! isreal (t0) || ! isscalar (t0) || ! isfinite (t0))
    error ([caller ':time'], '%s: Time must be a finite real scalar', caller);
  endif
  t0 = double (t0);
  try
    ob_validate_model (model);
  catch err
    error ([caller ':model'], '%s: invalid model: %s', caller, err.message);
  end_try_catch

  % Root input ports, their shapes (from model.inputs when present, from a
  % cell U0 otherwise, else scalar) and the operating input values.
  types = {model.blocks.type};
  inport_ids = find (strcmp (types, 'Inport'));
  ports = zeros (1, numel (inport_ids));
  for k = 1:numel (inport_ids), ports(k) = double (model.blocks(inport_ids(k)).value); endfor
  m_ports = numel (ports);
  if (! isequal (sort (ports), 1:m_ports))
    error ([caller ':model'], '%s: root Inports must be numbered 1..%d', caller, m_ports);
  endif
  datasets = {};
  if (isfield (model, 'inputs') && iscell (model.inputs)), datasets = model.inputs; endif
  shapes = repmat ({[1 1]}, 1, m_ports);
  for p = 1:min (m_ports, numel (datasets))
    if (isstruct (datasets{p}) && isfield (datasets{p}, 'shape') && ! isempty (datasets{p}.shape))
      shapes{p} = double (datasets{p}.shape(:)');
    elseif (isstruct (datasets{p}) && isfield (datasets{p}, 'values'))
      shapes{p} = [1 columns(datasets{p}.values)];
    endif
  endfor
  if (iscell (u0))
    if (numel (u0) != m_ports)
      error ([caller ':input'], '%s: U0 cell must have one entry per root Inport (%d)', caller, m_ports);
    endif
    parts = cell (m_ports, 1);
    for p = 1:m_ports
      value = u0{p};
      check_values (caller, value, 'U0', ':input');
      if (p <= numel (datasets) && ! isempty (datasets{p}) && prod (shapes{p}) != numel (value))
        error ([caller ':input'], '%s: U0{%d} must have %d elements to match the Inport %d dataset', ...
               caller, p, prod (shapes{p}), p);
      endif
      if (! (p <= numel (datasets) && ! isempty (datasets{p}))), shapes{p} = size (value); endif
      parts{p} = double (value(:));
    endfor
    u_vec = vertcat (parts{:});
  else
    counts = cellfun (@prod, shapes);
    if (isempty (u0))
      u_vec = zeros (sum (counts), 1);
    else
      check_values (caller, u0, 'U0', ':input');
      u_vec = double (u0(:));
      if (numel (u_vec) != sum (counts))
        error ([caller ':input'], '%s: U0 has %d elements; the root Inports carry %d', ...
               caller, numel (u_vec), sum (counts));
      endif
    endif
  endif
  if (isempty (u_vec)), u_vec = zeros (0, 1); endif
  counts = cellfun (@prod, shapes);
  input_index = zeros (sum (counts), 2);
  row = 0;
  for p = 1:m_ports
    input_index(row + (1:counts(p)), :) = [repmat(p, counts(p), 1), (1:counts(p))'];
    row += counts(p);
  endfor

  work = model;
  work.inputs = input_signals (t0, u_vec, shapes);
  % One compile to find unsupported state, with the offending block's path.
  try
    [flat, unused, paths] = ob_compile_model (work);
  catch err
    error ([caller ':model'], '%s: %s', caller, err.message);
  end_try_catch
  flat_types = {flat.blocks.type};
  unsupported = {'Unit Delay', 'Discrete Integrator', 'Transport Delay', ...
                 'Rate Transition', 'Conditional Subsystem'};
  for id = 1:numel (flat_types)
    if (any (strcmp (flat_types{id}, unsupported)))
      path = paths{id}; path = path(path > 0);
      error ([caller ':unsupported'], ...
             '%s: block %s (%s) holds discrete, delay or conditional state; only continuous Integrator states can be linearized', ...
             caller, path_text (model, path), flat_types{id});
    endif
  endfor
  try
    rt = ob_runtime_init (work, t0, struct ('solver', 'rk4'));
  catch err
    error ([caller ':model'], '%s: %s', caller, err.message);
  end_try_catch

  % Continuous states in flat (hierarchical depth-first) order.
  state_ids = find (strcmp (rt.types, 'Integrator') | strcmp (rt.types, 'Limited Integrator'));
  n_blocks = numel (state_ids);
  state_shapes = cell (1, n_blocks); state_counts = zeros (1, n_blocks);
  routes = zeros (1, n_blocks); limits = cell (1, n_blocks);
  x_parts = cell (n_blocks, 1); state_names = {};
  state_index = zeros (0, 2);
  for k = 1:n_blocks
    id = state_ids(k);
    value = double (rt.states{id});
    state_shapes{k} = size (value); state_counts(k) = numel (value);
    x_parts{k} = value(:);
    sources = rt.edges(rt.edges(:, 2) == id, 1);   % sorted by target port
    routes(k) = sources(1);
    if (strcmp (rt.types{id}, 'Limited Integrator'))
      params = ob_runtime_parameters (rt.model, id);
      if (! strcmp (params.reset, 'none'))
        error ([caller ':unsupported'], ...
               '%s: Limited Integrator %s has a reset port; resets are not linearized', ...
               caller, path_text (model, rt.block_paths{id}));
      endif
      limits{k} = struct ('lower', params.lower, 'upper', params.upper);
    endif
    name = path_text (model, rt.block_paths{id});
    for e = 1:state_counts(k)
      if (state_counts(k) == 1), state_names{end + 1, 1} = name;
      else state_names{end + 1, 1} = sprintf ('%s(%d)', name, e); endif
    endfor
    state_index = [state_index; repmat(k, state_counts(k), 1), (1:state_counts(k))'];
  endfor
  x_model = vertcat (x_parts{:});
  if (isempty (x_model)), x_model = zeros (0, 1); endif
  if (isempty (x0))
    x_vec = x_model;
  else
    check_values (caller, x0, 'X0', ':state');
    x_vec = double (x0(:));
    if (numel (x_vec) != numel (x_model))
      error ([caller ':state'], '%s: X0 has %d elements; the model has %d continuous states', ...
             caller, numel (x_vec), numel (x_model));
    endif
  endif

  % Root Outports only (an inner subsystem Outport is not a model output),
  % ordered by port number as linmod orders Out1, Out2, ...
  out_ids = [];
  for id = find (strcmp (rt.types, 'Outport'))
    if (numel (rt.block_paths{id}) == 1), out_ids(end + 1) = id; endif
  endfor
  out_ports = arrayfun (@(id) double (rt.model.blocks(id).value), out_ids);
  [out_ports, order] = sort (out_ports);
  out_ids = out_ids(order);

  ctx = struct ('caller', caller, 'rt', rt, 't0', t0, ...
                'state_ids', state_ids, 'state_shapes', {state_shapes}, ...
                'state_counts', state_counts, 'routes', routes, 'limits', {limits}, ...
                'state_names', {state_names}, 'state_index', state_index, ...
                'state_paths', {rt.block_paths(state_ids)}, ...
                'x0', x_vec, 'u0', u_vec, 'input_shapes', {shapes}, ...
                'input_ports', 1:m_ports, 'input_index', input_index, ...
                'out_ids', out_ids, 'output_ports', out_ports, ...
                'output_paths', {rt.block_paths(out_ids)});
  % Output shapes and the output index map come from one nominal evaluation.
  [unused, y, y_parts] = ob_linearize_eval (ctx, x_vec, u_vec);
  output_index = zeros (0, 2);
  for k = 1:numel (out_ids)
    output_index = [output_index; repmat(out_ports(k), numel (y_parts{k}), 1), (1:numel (y_parts{k}))'];
  endfor
  ctx.output_index = output_index;
endfunction

function check_values (caller, value, name, suffix)
  if (! isnumeric (value) || ! isreal (value) || issparse (value) ...
      || any (! isfinite (value(:))) || (! isempty (value) && ndims (value) > 2))
    error ([caller suffix], '%s: %s must be a finite real numeric array', caller, name);
  endif
endfunction

function signals = input_signals (t0, u_vec, shapes)
  signals = cell (1, numel (shapes));
  offset = 0;
  for p = 1:numel (shapes)
    c = prod (shapes{p});
    signals{p} = ob_input_signal (t0, reshape (u_vec(offset + (1:c)), 1, c), shapes{p}, 'zoh');
    offset += c;
  endfor
endfunction

function text = path_text (model, path)
  % Slash-separated block names along a hierarchical path ('plant/x').
  names = {};
  diagram = model;
  for k = 1:numel (path)
    if (path(k) < 1 || path(k) > numel (diagram.blocks)), break; endif
    block = diagram.blocks(path(k));
    name = block.name;
    if (isempty (name)), name = sprintf ('block %d', path(k)); endif
    names{end + 1} = name;
    if (k < numel (path) && isstruct (block.value) && isfield (block.value, 'blocks'))
      diagram = block.value;
    endif
  endfor
  text = strjoin (names, '/');
endfunction
