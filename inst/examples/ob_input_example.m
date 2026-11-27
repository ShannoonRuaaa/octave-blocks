function model = ob_input_example ()
  ## -*- texinfo -*-
  ## @deftypefn {} {@var{model} =} ob_input_example ()
  ## Return a model with an external input, an Integrator and a Scope.
  ## The model includes a dataset for its root Inport; replace
  ## @code{model.inputs} to supply a different signal.
  ##
  ## @example
  ## r = ob_run (ob_input_example (), 0:0.1:1);
  ## @end example
  ## @seealso{ob_input_signal, ob_input_value}
  ## @end deftypefn

  model = ob_example ();
  model.blocks(1).type = 'Inport'; model.blocks(1).value = 1; model.blocks(1).name = 'External force';
  model.blocks(2).type = 'Integrator'; model.blocks(2).value = 0;
  model.inputs = {ob_input_signal([0; 0.5; 1], [0; 1; 0], [1 1], 'zoh')};
endfunction
