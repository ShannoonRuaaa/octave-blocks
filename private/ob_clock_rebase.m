function [ticks, next] = ob_clock_rebase (rates, explicit, origin, time, spacing = Inf)
  % Place each embedded clock at this globally aligned hit or its next hit.
  ticks = zeros (size (explicit)); next = Inf (size (explicit));
  for id = reshape (find (explicit), 1, [])
    period = rates(id,1); first = origin + rates(id,2);
    if (!isfinite(origin+period) || origin+period <= origin || !isfinite(first) ...
        || (rates(id,2) > 0 && first <= origin))
      error ('ob_run: embedded sample clock cannot advance the simulation origin');
    endif
    phase = (time - first) / period;
    if (!isfinite(phase) || phase > flintmax())
      error ('ob_run: embedded sample tick counter overflow');
    endif
    tick = max (0, floor(phase));
    candidate = first + tick * period;
    tolerance = min ([8 * eps(1) * max([realmin() abs(origin) abs(time) abs(candidate)]) ...
                     period/16 spacing/16]);
    if (candidate < time && abs(candidate-time) > tolerance), tick += 1; endif
    candidate = first + tick * period;
    if (!isfinite(candidate) || tick > flintmax() ...
        || candidate < time - tolerance || !isfinite(candidate+period) || candidate+period <= candidate)
      error ('ob_run: embedded sample period cannot advance event time');
    endif
    ticks(id) = tick; next(id) = candidate;
  endfor
endfunction
