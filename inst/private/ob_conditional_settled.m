function yes = ob_conditional_settled (runtime, id)
  % Whether the value of block ID of a body (a numbered Outport) has its
  % final shape in RUNTIME: false while it can still be the scalar initial
  % output of a nested conditional subsystem whose port shape is not known
  % yet (that subsystem expands it when it learns the shape, so a scalar
  % seen now must not fix the outer port's shape).  The walk goes backward
  % through blocks without state; state blocks keep the shape of their
  % initial condition.
  yes = true;
  start = [];
  for item = runtime.signal_map
    if (isequal (item.path, id)), start = item.outputs(1); break; endif
  endfor
  if (isempty (start)), return; endif
  types = runtime.types; edges = runtime.edges;
  fixed = ismember (types, {'Unit Delay', 'Discrete Integrator', 'Integrator', 'Rate Transition', ...
                            'Limited Integrator', 'Constant', 'Time', 'Step'});
  seen = false (1, numel (types));
  pending = start;
  while (! isempty (pending))
    b = pending(end); pending(end) = [];
    if (seen(b)), continue; endif
    seen(b) = true;
    if (strcmp (types{b}, 'Conditional Output'))
      core = edges(edges(:, 2) == b, 1);
      state = runtime.states{core(1)};
      port = runtime.model.blocks(b).value;
      if (isstruct (state) && isfield (state, 'output_shaped') ...
          && port <= numel (state.output_shaped) && ! state.output_shaped(port))
        yes = false; return;
      endif
    elseif (! fixed(b))
      pending = [pending reshape(edges(edges(:, 2) == b, 1), 1, [])];
    endif
  endwhile
endfunction
