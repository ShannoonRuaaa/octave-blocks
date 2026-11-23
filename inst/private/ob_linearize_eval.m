function [dx, y, y_parts] = ob_linearize_eval (ctx, x, u)
  % State derivatives DX and root outputs Y of a compiled ob_linearize_context
  % at state vector X and input vector U, at the context's time.  One
  % algebraic evaluation of the compiled graph (the pass the solvers make at
  % each stage); nothing is recompiled.  Limited Integrator outputs are the
  % clamped state and an outward derivative at a limit is zero, as in ob_run.
  rt = ctx.rt;
  states = rt.states;
  offset = 0;
  for k = 1:numel (ctx.state_ids)
    c = ctx.state_counts(k);
    states{ctx.state_ids(k)} = reshape (x(offset + (1:c)), ctx.state_shapes{k});
    offset += c;
  endfor
  model = rt.model;
  offset = 0;
  for p = 1:numel (ctx.input_shapes)
    c = prod (ctx.input_shapes{p});
    model.inputs{p} = struct ('t', ctx.t0, 'values', reshape (u(offset + (1:c)), 1, c), ...
                              'shape', ctx.input_shapes{p}, 'method', 'zoh');
    offset += c;
  endfor
  current = ob_runtime_eval (model, rt.edges, rt.order, ctx.t0, states);
  dx_parts = cell (numel (ctx.state_ids), 1);
  for k = 1:numel (ctx.state_ids)
    id = ctx.state_ids(k);
    value = current{ctx.routes(k)};
    if (! isnumeric (value) || ! isreal (value) || numel (value) != ctx.state_counts(k) ...
        || any (! isfinite (value(:))))
      error ([ctx.caller ':evaluation'], ...
             '%s: derivative of %s is not finite, real and of the state''s size at this point', ...
             ctx.caller, ctx.state_names{find(ctx.state_index(:, 1) == k, 1)});
    endif
    value = double (value(:));
    limit = ctx.limits{k};
    if (! isempty (limit))
      state = states{id}(:);
      lower = limit.lower(:) .* ones (size (state));
      upper = limit.upper(:) .* ones (size (state));
      value((state >= upper & value > 0) | (state <= lower & value < 0)) = 0;
    endif
    dx_parts{k} = value;
  endfor
  dx = vertcat (dx_parts{:});
  if (isempty (dx)), dx = zeros (0, 1); endif
  y_parts = cell (numel (ctx.out_ids), 1);
  for k = 1:numel (ctx.out_ids)
    value = current{ctx.out_ids(k)};
    if (! isnumeric (value) || ! isreal (value) || any (! isfinite (value(:))))
      error ([ctx.caller ':evaluation'], '%s: root Outport %d is not finite and real at this point', ...
             ctx.caller, ctx.output_ports(k));
    endif
    y_parts{k} = double (value(:));
  endfor
  y = vertcat (y_parts{:});
  if (isempty (y)), y = zeros (0, 1); endif
endfunction
