function test_ob_performance_graph ()
  % The reference below pins historical FIFO/SCC ordering independently of the
  % optimized traversal. Random graph cases include duplicate sources, delayed
  % dependency breaks, canonical port order and unsupported algebraic cycles.
  previous_rng = rng ();
  unwind_protect
    rng (23117, 'twister');
    choices = {'Gain','Sum','Integrator','Unit Delay','Discrete Integrator','Rate Transition'};
    for trial = 1:160
      n = mod (trial, 49);
      model.blocks = struct ('type', choices(randi(numel(choices),1,n)));
      count = randi (max(1,4*n))-1;
      if (n == 0), count = 0; endif
      model.edges = ones (count, 4);
      if (count)
        model.edges(:,[1 3]) = randi(n,count,2);
        ports = zeros (1,n);
        for edge = 1:count
          target = model.edges(edge,3); ports(target) += 1;
          model.edges(edge,4) = ports(target);
        endfor
        model.edges = model.edges(randperm(count),:);
      endif
      compare_orders (model, false); compare_orders (model, true);
      model.blocks = repmat (struct('type','Gain'),1,n);
      compare_orders (model, true);
    endfor
  unwind_protect_cleanup
    rng (previous_rng);
  end_unwind_protect

  % Small tables retain the original find route. Left limits apply only to
  % ZOH interpolation, including the exact last knot.
  for count = [1 2 16 17 73]
    times = (0:count-1)' / 8;
    values = [(1:count)' (1:count)'.^2];
    queries = unique ([-1; times; times+1/32; times(end)+1]);
    for method = {'zoh','linear'}
      signal = ob_input_signal(times,values,[1 2],method{1});
      for time = queries'
        for left = [false true]
          assert(isequal(ob_input_value(signal,time,left),legacy_input_value(signal,time,left)));
        endfor
      endfor
      assert(isequal(ob_input_value(signal,times(end),true), ...
                    values(max(1,count-strcmp(method{1},'zoh')),:)));
    endfor
  endfor
  % Sparse requests cover actual binary search on a large table, without
  % querying every knot. Include endpoints, an interior knot, and inter-knot
  % samples for both interpolation modes and both left-limit settings.
  times=(0:8192)'/8; values=[times times.^2];
  queries=[-1 0 1/32 times(4097) times(4097)+1/32 times(end) times(end)+1];
  for method={'zoh','linear'}
    signal=ob_input_signal(times,values,[1 2],method{1});
    for time=queries
      for left=[false true]
        assert(isequal(ob_input_value(signal,time,left),legacy_input_value(signal,time,left)));
      endfor
    endfor
  endfor
  % lookup coerces mixed numeric classes: large integer queries can round up
  % to the next double knot, and single queries can merge many double knots.
  % Preserve the original mixed-class comparisons, including strict ZOH left
  % limits, rather than performing a lossy conversion before interval search.
  tables={2^53+(0:8192)'*2,[0;1+(-4095:4096)'*eps(1)]};
  queries={uint64(2^53)+uint64(3),single(1)};
  for index=1:numel(tables)
    for method={'zoh','linear'}
      signal=ob_input_signal(tables{index},(1:numel(tables{index}))',[1 1],method{1});
      for left=[false true]
        assert(isequal(ob_input_value(signal,queries{index},left), ...
                       legacy_input_value(signal,queries{index},left)));
      endfor
    endfor
  endfor
  fprintf ('Performance graph ordering parity passed (480 randomized comparisons); input lookup boundary parity passed\n');
endfunction

function compare_orders (model, allow_loops)
  expected_error = ''; actual_error = '';
  try
    [expected,edges,stateful,loops] = legacy_execution_order(model,allow_loops);
  catch err
    expected_error = err.message;
  end_try_catch
  try
    [actual,new_edges,new_stateful,new_loops] = ob_execution_order(model,allow_loops);
  catch err
    actual_error = err.message;
  end_try_catch
  assert(strcmp(actual_error,expected_error));
  if (isempty(expected_error))
    assert(isequal(actual,expected) && isequal(new_edges,edges) ...
           && isequal(new_stateful,stateful) && isequal(new_loops,loops));
  endif
endfunction

function value = legacy_input_value (signal,time,left_limit)
  times = signal.t;
  if (time <= times(1))
    row = signal.values(1,:);
  elseif (strcmp(signal.method,'zoh'))
    if(left_limit),index=find(times<time,1,'last');
    else index=find(times<=time,1,'last');endif
    row=signal.values(index,:);
  elseif(time>=times(end))
    row=signal.values(end,:);
  else
    index=find(times<=time,1,'last');
    alpha=(time-times(index))/(times(index+1)-times(index));
    row=(1-alpha)*signal.values(index,:)+alpha*signal.values(index+1,:);
  endif
  value=reshape(row,signal.shape);
endfunction

% Historical reference from commit 8aeec48; intentionally unoptimized.
function [order, edges, stateful, loops] = legacy_execution_order (model, allow_loops = false)
  % Dependency ordering for an already compiled, flat execution graph.
  % Keep the historical acyclic order.  Opted-in runtime callers also receive
  % supported algebraic strongly connected components, in execution order.
  n = numel (model.blocks);
  canonical = sortrows (ob_edges (model), [3 4]);
  edges = canonical(:, [1 3]);
  types = {model.blocks.type};
  delayed = strcmp (types, "Unit Delay") | strcmp (types, "Discrete Integrator") ...
            | strcmp (types, "Integrator");
  stateful = delayed | strcmp (types, "Rate Transition") | strcmp (types, 'Conditional Subsystem');
  direct = edges(! delayed(edges(:, 2)), :);
  indegree = zeros (1, n);
  for k = 1:rows (direct)
    indegree(direct(k, 2)) += 1;
  endfor
  queue = find (indegree == 0); order = []; loops = {};
  while (! isempty (queue))
    id = queue(1); queue(1) = []; order(end + 1) = id;
    for target = direct(direct(:, 1) == id, 2)'
      indegree(target) -= 1;
      if (indegree(target) == 0), queue(end + 1) = target; endif
    endfor
  endwhile
  if (numel (order) == n), return; endif
  if (! allow_loops)
    error ("ob_execution_order: algebraic loop without a stateful block");
  endif

  [components, membership] = legacy_strongly_connected (n, direct);
  dag = unique ([membership(direct(:, 1))' membership(direct(:, 2))'], 'rows');
  dag = dag(dag(:, 1) != dag(:, 2), :);
  indegree = zeros (1, numel (components));
  for k = 1:rows (dag)
    indegree(dag(k, 2)) += 1;
  endfor
  queue = find (indegree == 0); order = [];
  allowed = {'Gain', 'Sum', 'Product', 'Function', 'Scope', 'Inport', 'Outport'};
  while (! isempty (queue))
    component = queue(1); queue(1) = [];
    ids = components{component};
    cyclic = numel (ids) > 1 || any (direct(:, 1) == ids(1) & direct(:, 2) == ids(1));
    if (cyclic)
      for id = ids
        if (! any (strcmp (types{id}, allowed)))
          error ("ob_execution_order: algebraic loop contains unsupported block %d (%s)", id, types{id});
        endif
      endfor
      loops{end + 1} = ids;
    endif
    order = [order ids];
    for target = dag(dag(:, 1) == component, 2)'
      indegree(target) -= 1;
      if (indegree(target) == 0), queue(end + 1) = target; endif
    endfor
  endwhile
endfunction

function [components, membership] = legacy_strongly_connected (n, edges)
  % Iterative Kosaraju traversal avoids the interpreter's recursion limit for
  % long diagrams.  Component IDs follow their smallest original block ID.
  forward = reverse = cell (1, n);
  for k = 1:rows (edges)
    source = edges(k, 1); target = edges(k, 2);
    forward{source}(end + 1) = target;
    reverse{target}(end + 1) = source;
  endfor
  seen = false (1, n); finished = [];
  for root = 1:n
    if (seen(root)), continue; endif
    seen(root) = true; stack = root; cursor = 1;
    while (! isempty (stack))
      id = stack(end);
      if (cursor(end) <= numel (forward{id}))
        target = forward{id}(cursor(end)); cursor(end) += 1;
        if (! seen(target))
          seen(target) = true; stack(end + 1) = target; cursor(end + 1) = 1;
        endif
      else
        finished(end + 1) = id; stack(end) = []; cursor(end) = [];
      endif
    endwhile
  endfor
  membership = zeros (1, n); components = {};
  for root = fliplr (finished)
    if (membership(root) != 0), continue; endif
    component = numel (components) + 1;
    membership(root) = component; stack = root; ids = [];
    while (! isempty (stack))
      id = stack(end); stack(end) = []; ids(end + 1) = id;
      for source = reverse{id}
        if (membership(source) == 0)
          membership(source) = component; stack(end + 1) = source;
        endif
      endfor
    endwhile
    components{component} = sort (ids);
  endfor
  [~, permutation] = sort (cellfun (@(ids) ids(1), components));
  components = components(permutation);
  for component = 1:numel (components)
    membership(components{component}) = component;
  endfor
endfunction
