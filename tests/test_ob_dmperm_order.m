function timings = test_ob_dmperm_order (benchmark = false)
  % Compare native SCC partitioning against the previous iterative Kosaraju
  % implementation, including exact FIFO order, loop groups, and diagnostics.
  previous = rng ();
  unwind_protect
    rng (6143, 'twister');
    cases = {zeros(0,2), [1 1], [1 2;2 1], [3 1;1 2;2 1;2 4;4 4], ...
             [1 2;1 2;2 1;4 5;5 4], [8 1;8 2;8 3;1 1;6 6]};
    sizes = [0 1 2 7 8 10];
    for k = 1:numel(cases)
      compare_graph (sizes(k), cases{k});
    endfor
    for k = 1:160
      n = randi(40); count = randi(5*n);
      edges = randi(n,count,2);
      compare_graph (n,edges);
      % Exercise direct-feedthrough filtering and unsupported cycle diagnostics.
      types = repmat({'Gain'},1,n);
      types{randi(n)} = 'Integrator';
      types{randi(n)} = 'Rate Transition';
      compare_graph (n,edges,types);
    endfor
    n = 3000;
    compare_graph (n,[(1:n-1)' (2:n)';n n]);
    compare_graph (n,[n*ones(n-1,1) (1:n-1)';n n]);
    compare_graph (n,[(1:n-1)' n*ones(n-1,1);n n]);
    compare_graph (n,[(1:n)' [2:n 1]']);
    timings = [];
    if (benchmark)
      n = 10000;
      model.blocks = repmat(struct('type','Gain'),1,n);
      model.edges = [(1:n)' ones(n,1) [2:n 1]' ones(n,1)];
      native = legacy = zeros(1,3);
      for k=1:3
        tic; ob_execution_order(model,true); native(k)=toc;
        tic; reference_order(model,true); legacy(k)=toc;
      endfor
      timings = [median(native), median(legacy)];
      fprintf('10000-block cycle median seconds: dmperm %.6f; Kosaraju %.6f\n',timings);
    endif
  unwind_protect_cleanup
    rng (previous);
  end_unwind_protect
endfunction

function compare_graph (n, edges, types = repmat({'Gain'},1,n))
  model.blocks = struct('type',types);
  % Check both canonical ports and legacy two-column port normalization.
  model.edges = [edges(:,1) ones(rows(edges),1) edges(:,2) (1:rows(edges))'];
  for legacy_ports = [false true]
    if (legacy_ports), model.edges = edges; endif
    for allow = [false true]
      actual = expected = {}; actual_error = expected_error = '';
      try
        [actual{1:4}] = ob_execution_order(model,allow);
      catch exception
        actual_error = exception.message;
      end_try_catch
      try
        [expected{1:4}] = reference_order(model,allow);
      catch exception
        expected_error = exception.message;
      end_try_catch
      assert(actual_error,expected_error);
      if (isempty(actual_error)), assert(actual,expected); endif
    endfor
  endfor
endfunction

%!test
%! test_ob_dmperm_order ();

% Independent pre-dmperm implementation retained as a regression oracle.
function [order, edges, stateful, loops] = reference_order (model, allow_loops = false)
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
  if (!isempty(direct)), indegree = accumarray(direct(:,2),1,[n 1])'; endif
  [forward, targets] = adjacency (n, direct);
  queue = zeros (1, n); ready = find (indegree == 0);
  tail = numel (ready); queue(1:tail) = ready; head = 1;
  order = zeros (1, n); used = 0; loops = {};
  while (head <= tail)
    id = queue(head); head += 1; used += 1; order(used) = id;
    for target = targets(forward(id):forward(id+1)-1)'
      indegree(target) -= 1;
      if (indegree(target) == 0), tail += 1; queue(tail) = target; endif
    endfor
  endwhile
  if (used == n)
    if (n == 0), order = []; endif
    return;
  endif
  if (! allow_loops)
    error ("ob_execution_order: algebraic loop without a stateful block");
  endif

  [components, membership] = strongly_connected (n, direct, forward, targets);
  dag = unique ([membership(direct(:, 1))' membership(direct(:, 2))'], 'rows');
  dag = dag(dag(:, 1) != dag(:, 2), :);
  indegree = zeros (1, numel (components));
  if (!isempty(dag)), indegree = accumarray(dag(:,2),1,[numel(components) 1])'; endif
  [dag_forward, dag_targets] = adjacency (numel(components), dag);
  ready = find (indegree == 0); tail = numel (ready); head = 1;
  queue(1:tail) = ready; used = 0;
  self_loop = false (1, n);
  self_loop(direct(direct(:,1)==direct(:,2),1)) = true;
  allowed = {'Gain', 'Sum', 'Product', 'Function', 'Scope', 'Inport', 'Outport'};
  while (head <= tail)
    component = queue(head); head += 1;
    ids = components{component};
    cyclic = numel (ids) > 1 || self_loop(ids(1));
    if (cyclic)
      for id = ids
        if (! any (strcmp (types{id}, allowed)))
          error ("ob_execution_order: algebraic loop contains unsupported block %d (%s)", id, types{id});
        endif
      endfor
      loops{end + 1} = ids;
    endif
    order(used+(1:numel(ids))) = ids; used += numel (ids);
    for target = dag_targets(dag_forward(component):dag_forward(component+1)-1)'
      indegree(target) -= 1;
      if (indegree(target) == 0), tail += 1; queue(tail) = target; endif
    endfor
  endwhile
endfunction

function [offsets, targets] = adjacency (n, edges)
  % Compact adjacency preserves the original edge order within each source.
  if (isempty(edges))
    offsets = ones (n+1, 1); targets = zeros (0, 1); return;
  endif
  counts = accumarray (edges(:,1), 1, [n 1]);
  offsets = [1; 1+cumsum(counts)];
  % The original row is an explicit secondary key: ordering does not depend
  % on a sorting implementation's treatment of equal source IDs.
  [unused, permutation] = sortrows ([edges(:,1) (1:rows(edges))'], [1 2]);
  targets = edges(permutation,2);
endfunction

function [components, membership] = strongly_connected (n, edges, forward, targets)
  % Iterative Kosaraju traversal avoids the interpreter's recursion limit for
  % long diagrams.  Component IDs follow their smallest original block ID.
  [reverse, sources] = adjacency (n, edges(:,[2 1]));
  seen = false (1, n); finished = zeros (1, n); completed = 0;
  stack = cursor = zeros (1, n);
  for root = 1:n
    if (seen(root)), continue; endif
    seen(root) = true; depth = 1; stack(1) = root; cursor(1) = forward(root);
    while (depth > 0)
      id = stack(depth);
      if (cursor(depth) < forward(id+1))
        target = targets(cursor(depth)); cursor(depth) += 1;
        if (! seen(target))
          seen(target) = true; depth += 1; stack(depth) = target; cursor(depth) = forward(target);
        endif
      else
        completed += 1; finished(completed) = id; depth -= 1;
      endif
    endwhile
  endfor
  membership = zeros (1, n); components = cell (1, n); component = 0;
  ids = zeros (1, n);
  for root = fliplr (finished)
    if (membership(root) != 0), continue; endif
    component += 1;
    membership(root) = component; depth = 1; stack(1) = root; used = 0;
    while (depth > 0)
      id = stack(depth); depth -= 1; used += 1; ids(used) = id;
      for source = sources(reverse(id):reverse(id+1)-1)'
        if (membership(source) == 0)
          membership(source) = component; depth += 1; stack(depth) = source;
        endif
      endfor
    endwhile
    components{component} = sort (ids(1:used));
  endfor
  components = components(1:component);
  [~, permutation] = sort (cellfun (@(ids) ids(1), components));
  components = components(permutation);
  for component = 1:numel (components)
    membership(components{component}) = component;
  endfor
endfunction
