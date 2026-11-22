function [same, transposed, total] = test_ob_multi_function (input, increment = 1)
  % A deterministic arbitrary Octave function for numbered-output tests.
  if (any (input(:) < -100))
    error ('test_ob_multi_function: deterministic domain failure');
  endif
  same = input + increment;
  transposed = input.';
  total = sum (input(:));
endfunction
