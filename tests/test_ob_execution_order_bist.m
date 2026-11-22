function test_ob_execution_order_bist ()
  cleanup = ob_test_setup ();
  [passed,total] = test (mfilename("fullpath"), "quiet");
  assert (total > 0 && passed == total);
  fprintf ("test_ob_execution_order_bist: %d/%d passed\n", passed, total);
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
