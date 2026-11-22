function options = ob_solver_options (input = struct ())
  % Normalize and validate supported solver settings without allocating a grid.
  if (! isstruct (input) || ! isscalar (input))
    error ("ob_solver_options: solver options must be a scalar struct");
  endif
  options = struct ("solver", "rk4", "reltol", 1e-6, "abstol", 1e-9, "maxstep", Inf, ...
                    'zero_crossings', false);
  fields = fieldnames (input);
  for k = 1:numel (fields)
    name = fields{k};
    if (! isfield (options, name))
      error ("ob_solver_options: unknown option '%s'", name);
    endif
    options.(name) = input.(name);
  endfor
  if (! ischar (options.solver) || rows (options.solver) != 1 ...
      || ! any (strcmp (options.solver, {"rk4", "ode45", "ode15s"})))
    error ("ob_solver_options: solver must be rk4, ode45, or ode15s");
  endif
  for name = {"reltol", "abstol", "maxstep"}
    value = options.(name{1});
    if (! isnumeric (value) || ! isscalar (value) || ! isreal (value) ...
        || isnan (value) || value <= 0 ...
        || (! strcmp (name{1}, "maxstep") && ! isfinite (value)))
      error ("ob_solver_options: %s must be a positive real scalar", name{1});
    endif
  endfor
  if ((! islogical (options.zero_crossings) && ! isnumeric (options.zero_crossings)) ...
      || ! isreal (options.zero_crossings) || ! isscalar (options.zero_crossings) ...
      || ! any (options.zero_crossings == [0 1]))
    error ('ob_solver_options: zero_crossings must be a scalar 0 or 1');
  endif
  options.zero_crossings = logical (options.zero_crossings);
endfunction
