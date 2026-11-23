function x = ob_linearize_limits (ctx, x, mode)
  % Limited Integrator states of an ob_linearize_context against their limits.
  %
  % MODE 'strict': every Limited Integrator state must lie strictly inside its
  %   limits (where the block is locally an Integrator); otherwise raise
  %   CALLER:unsupported.  Used before a linearization.
  % MODE 'closed': every such state must lie in [lower, upper]; otherwise
  %   raise CALLER:state.  Used for a starting point.
  % MODE 'clamp': return X with every such state clamped to [lower, upper],
  %   the values ob_run can reach (its integrator clamps the same way).
  for k = 1:numel (ctx.limits)
    limit = ctx.limits{k};
    if (isempty (limit)), continue; endif
    rows = find (ctx.state_index(:, 1) == k);
    state = x(rows);
    lower = limit.lower(:) .* ones (size (state));
    upper = limit.upper(:) .* ones (size (state));
    switch (mode)
      case 'strict'
        if (any (state <= lower | state >= upper))
          error ([ctx.caller ':unsupported'], ...
                 '%s: Limited Integrator %s must lie strictly inside its limits at the operating point', ...
                 ctx.caller, ctx.state_names{rows(1)});
        endif
      case 'closed'
        if (any (state < lower | state > upper))
          error ([ctx.caller ':state'], ...
                 '%s: X0 puts Limited Integrator %s outside its limits [%g, %g]', ...
                 ctx.caller, ctx.state_names{rows(1)}, min (lower), max (upper));
        endif
      case 'clamp'
        x(rows) = min (max (state, lower), upper);
      otherwise
        error ('ob_linearize_limits: unknown mode ''%s''', mode);
    endswitch
  endfor
endfunction
