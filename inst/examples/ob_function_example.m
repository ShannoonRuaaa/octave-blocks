function model = ob_function_example ()
  ## -*- texinfo -*-
  ## @deftypefn {} {@var{model} =} ob_function_example ()
  ## Return a model calling @code{ob_demo_function} in a Function block.
  ## The Time source feeds the damped sine function and a Scope logs its output.
  ##
  ## @example
  ## r = ob_run (ob_function_example (), 0:0.1:10);
  ## @end example
  ## @seealso{ob_demo_function, ob_example}
  ## @end deftypefn

  model = ob_example ();
  model.blocks(2).type = "Function";
  model.blocks(2).name = "ob_demo_function";
  model.blocks(2).value = [];
endfunction
