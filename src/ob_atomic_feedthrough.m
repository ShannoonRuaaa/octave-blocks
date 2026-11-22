function [matrix, any_direct] = ob_atomic_feedthrough (model)
% OB_ATOMIC_FEEDTHROUGH  Compute Simulink-style per-port direct feedthrough.
%   [MATRIX, ANY_DIRECT] = OB_ATOMIC_FEEDTHROUGH(MODEL) returns an
%   n_in-by-n_out logical matrix where MATRIX(i, j) is true iff Inport i has
%   a combinational (direct-feedthrough) path to Outport j inside MODEL.
%   State-breaking blocks (Integrator, Unit Delay, Discrete Integrator)
%   break direct-feedthrough paths. Virtual Subsystems are flattened first;
%   nested Conditional Subsystems are analyzed recursively.
%
%   This reports structural paths for diagnostics. The scheduler does not
%   use this matrix to reorder conditional execution or permit feedback.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/ug/algebraic-loops.html

  ob_validate_model (model, false);
  count = sum(strcmp({model.blocks.type},'Inport'));
  model.inputs = repmat({ob_input_signal(0,0)},1,count);
  flat = ob_compile_model (model);
  n = numel (flat.blocks);
  types = {flat.blocks.type};
  in_ids = find (strcmp (types, 'Inport') | strcmp (types, 'External Input'));
  out_ids = find (strcmp (types, 'Outport'));

  n_in = numel (in_ids);
  n_out = numel (out_ids);
  matrix = false (n_in, n_out);

  in_port_to_node = zeros (1, n_in);
  for k = 1:n_in
    in_port_to_node(flat.blocks(in_ids(k)).value) = in_ids(k);
  endfor
  out_port_to_node = zeros (1, n_out);
  for k = 1:n_out
    out_port_to_node(flat.blocks(out_ids(k)).value) = out_ids(k);
  endfor

  edges = ob_edges (flat);
  state_break = strcmp (types, 'Integrator') | strcmp (types, 'Unit Delay') ...
              | strcmp (types, 'Discrete Integrator');

  % Build reverse direct-feedthrough adjacency list
  rev = cell (1, n);
  core_inputs = cell (1, n);
  for k = 1:rows (edges)
    src = edges(k, 1);
    tgt = edges(k, 3);
    if (! state_break(tgt))
      rev{tgt}(end + 1) = src;
    endif
    if (strcmp(types{tgt},'Conditional Subsystem'))
      core_inputs{tgt}(end+1,:) = edges(k,[1 4]);
    endif
  endfor

  % Precompute nested conditional subsystem feedthrough matrices
  cond_ft = cell (1, n);
  for id = reshape (find (strcmp (types, 'Conditional Subsystem')),1,[])
    cond_ft{id} = ob_atomic_feedthrough (flat.blocks(id).value);
  endfor

  for j = 1:n_out
    target_node = out_port_to_node(j);
    visited = false (1, n);
    stack = target_node;
    visited(target_node) = true;
    while (! isempty (stack))
      node = stack(end);
      stack(end) = [];
      if (strcmp (types{node}, 'Conditional Output'))
        % Only traverse back to data Inports that feed this specific output port
        out_port = flat.blocks(node).value;
        core = rev{node};
        if (! isempty (core))
          core_id = core(1);
          ft_sub = cond_ft{core_id};
          core_in_edges = core_inputs{core_id};
          for e = 1:rows (core_in_edges)
            in_port = core_in_edges(e, 2);
            src = core_in_edges(e, 1);
            % Control ports (in_port > rows(ft_sub)) always have direct feedthrough
            if (in_port > rows (ft_sub) || (out_port <= columns (ft_sub) && ft_sub(in_port, out_port)))
              if (! visited(src))
                visited(src) = true;
                stack(end + 1) = src;
              endif
            endif
          endfor
        endif
        continue;
      endif
      for src = rev{node}
        if (! visited(src))
          visited(src) = true;
          stack(end + 1) = src;
        endif
      endfor
    endwhile
    for i = 1:n_in
      matrix(i, j) = visited(in_port_to_node(i));
    endfor
  endfor

  any_direct = any (matrix(:));
endfunction
