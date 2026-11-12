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

  [components, membership] = strongly_connected (n, direct);
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

function [components, membership] = strongly_connected (n, edges)
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
