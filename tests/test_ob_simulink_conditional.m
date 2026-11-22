function test_ob_simulink_conditional ()
  test_path_cleanup = ob_test_setup ();
  % Rebuild every recorded Simulink conditional trace (see
  % ob_simulink_conditional_cases) as an Octave Blocks model and compare it
  % sample by sample.  A listed difference must still differ, so a stale
  % list fails, and its alternate model must reproduce the Simulink trace.
  cases = ob_simulink_conditional_cases ();
  failures = {}; matched = 0; documented = 0; worst = 0;
  for k = 1:numel (cases)
    c = cases(k);
    [error_value, first] = compare (c, c.model);
    if (isempty (c.differs))
      if (error_value <= 1e-9)
        matched++; worst = max (worst, error_value);
      else
        failures{end+1} = sprintf ('%s: error %g from sample %d', c.name, error_value, first);
      endif
    elseif (error_value <= 1e-9)
      failures{end+1} = sprintf ('%s: listed as differing (%s) but now matches', c.name, c.differs);
    elseif (compare (c, c.alternate) > 1e-9)
      failures{end+1} = sprintf ('%s: alternate model does not reproduce Simulink', c.name);
    else
      documented++;
    endif
  endfor
  if (! isempty (failures))
    error ('test_ob_simulink_conditional: %d mismatches\n  %s', numel (failures), ...
           strjoin (failures, "\n  "));
  endif
  fprintf ('Simulink conditional references: %d cases matched (worst %g), %d documented differences\n', ...
           matched, worst, documented);
endfunction

function [value, first] = compare (c, model)
  result = ob_run (model, c.times, c.options);
  actual = [];
  for id = c.scopes
    actual = [actual, reshape(ob_scope_data (result, id), [], 1)];
  endfor
  if (! isequal (size (actual), size (c.expected)))
    error ('test_ob_simulink_conditional: %s has shape %s, Simulink %s', c.name, ...
           mat2str (size (actual)), mat2str (size (c.expected)));
  endif
  difference = max (abs (actual - c.expected), [], 2);
  value = max (difference);
  first = find (difference > 1e-9, 1);
endfunction
