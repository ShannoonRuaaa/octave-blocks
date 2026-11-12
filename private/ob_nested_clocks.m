function clocks = ob_nested_clocks (flat, origin, prefix = [])
  % Discover clocks without evaluating a lazily initialized conditional body.
  clocks = struct ('path', {}, 'rate', {}, 'tick', {}, 'next', {});
  for id = reshape (find (strcmp ({flat.blocks.type}, 'Conditional Subsystem')), 1, [])
    child = flat.blocks(id).value;
    count = sum (strcmp ({child.blocks.type}, 'Inport'));
    child.inputs = repmat ({ob_input_signal(origin,0)}, 1, count);
    compiled = ob_compile_model (child);
    rates = compiled.sample_times;
    for leaf = reshape (find (rates(:,1)' > 0), 1, [])
      period = rates(leaf,1); offset = rates(leaf,2); first = origin + offset;
      if (!isfinite(origin+period) || origin+period <= origin ...
          || !isfinite(first) || (offset > 0 && first <= origin))
        error ('ob_run: nested sample clock cannot advance the simulation origin');
      endif
      clocks(end+1) = struct ('path',[prefix id leaf], 'rate',rates(leaf,:), 'tick',0, 'next',first);
    endfor
    descendants = ob_nested_clocks(compiled, origin, [prefix id]);
    if (!isempty(descendants)), clocks = [clocks descendants]; endif
  endfor
endfunction
