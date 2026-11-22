function y = ob_demo_function (t)
  % An ordinary Octave function used by ob_function_example.
  y = exp (-0.2 * t) .* sin (t);
endfunction
