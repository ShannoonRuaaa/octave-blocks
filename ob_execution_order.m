function [order, edges, stateful, loops] = ob_execution_order (model, allow_loops = false)
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

%!test
%! model.blocks = struct ('type', {'Constant', 'Gain', 'Scope'});
%! model.edges = [1 2; 2 3];
%! [order, edges, stateful, loops] = ob_execution_order (model, true);
%! assert (order, [1 2 3]); assert (edges, model.edges);
%! assert (stateful, [false false false]); assert (isempty (loops));
%! assert (ob_execution_order (model), order);

%!test
%! model.blocks = struct ('type', {'Gain', 'Sum', 'Constant', 'Gain', 'Scope'});
%! model.edges = [1 2; 2 1; 3 2; 2 4; 4 4; 4 5];
%! [order, ~, ~, loops] = ob_execution_order (model, true);
%! assert (order, [3 1 2 4 5]); assert (loops, {[1 2], 4});
%! fail ('ob_execution_order (model)', 'algebraic loop');

%!test
%! model.blocks = struct ('type', {'Gain', 'Integrator', 'Scope'});
%! model.edges = [1 2; 2 1; 1 3];
%! [order, ~, stateful, loops] = ob_execution_order (model, true);
%! assert (order, [2 1 3]); assert (stateful, [false true false]);
%! assert (isempty (loops));

%!test
%! model.blocks = struct ('type', {'Gain', 'Rate Transition'});
%! model.edges = [1 2; 2 1];
%! fail ('ob_execution_order (model, true)', 'unsupported block 2');

%!test
%! for type = {'Saturation', 'Dead Zone', 'Switch', 'Multiple Function', ...
%!             'Function Output', 'Conditional Subsystem', 'Conditional Output'}
%!   model.blocks = struct ('type', type); model.edges = [1 1];
%!   fail ('ob_execution_order (model, true)', 'unsupported block 1');
%! endfor

%!test
%! model.blocks = struct ('type', {}); model.edges = zeros (0, 2);
%! [order, edges, stateful, loops] = ob_execution_order (model, true);
%! assert (isempty (order)); assert (size (edges), [0 2]);
%! assert (isempty (stateful)); assert (isempty (loops));

%!test
%! % A long cycle must not depend on Octave's function-recursion limit.
%! count = 1000;
%! model.blocks = repmat (struct ('type', 'Gain'), 1, count);
%! model.edges = [(1:count)' [2:count 1]'];
%! [order, ~, ~, loops] = ob_execution_order (model, true);
%! assert (order, 1:count); assert (loops, {1:count});

%!test
%! % Large four-port chains exercise queue progression independently of the
%! % legacy two-column edge-normalization cost.
%! count = 10000;
%! model.blocks = repmat (struct ('type','Gain'),1,count);
%! model.edges = [(1:count-1)' ones(count-1,1) (2:count)' ones(count-1,1)];
%! [order,~,~,loops] = ob_execution_order(model,true);
%! assert (order,1:count); assert (isempty(loops));

%!test
%! % A single source releasing many targets must retain historical FIFO IDs.
%! count = 30000;
%! model.blocks = repmat (struct ('type','Gain'),1,count);
%! model.edges = [count*ones(count-1,1) ones(count-1,1) (1:count-1)' ones(count-1,1)];
%! [order,~,~,loops] = ob_execution_order(model,true);
%! assert (order,[count 1:count-1]); assert (isempty(loops));
