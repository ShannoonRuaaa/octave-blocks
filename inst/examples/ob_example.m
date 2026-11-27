function model = ob_example ()
  ## -*- texinfo -*-
  ## @deftypefn {} {@var{model} =} ob_example ()
  ## Return a Time--Gain--Scope model with gain 2.
  ##
  ## @example
  ## r = ob_run (ob_example (), 0:0.1:1);
  ## @end example
  ## @seealso{octave_blocks, ob_function_example}
  ## @end deftypefn

  model.blocks = struct ("type", {"Time", "Gain", "Scope"}, ...
                         "value", {[], 2, []}, ...
                         "name", {"Time", "Gain", "Scope"}, ...
                         "x", {0.12, 0.43, 0.74}, ...
                         "y", {0.55, 0.55, 0.55});
  model.edges = [1 2; 2 3];
endfunction
