function model = ob_subsystem_template ()
  ## -*- texinfo -*-
  ## @deftypefn {} {@var{model} =} ob_subsystem_template ()
  ## Return a virtual subsystem model with Inport, unit Gain and Outport.
  ## The ports are numbered 1.  Edit the returned model struct and assign
  ## it to a Subsystem block's value to embed it in another diagram.
  ##
  ## @example
  ## child = ob_subsystem_template ();
  ## child.blocks(2).value = 2;
  ## @end example
  ## @seealso{ob_model_at, ob_subsystem_example}
  ## @end deftypefn

  model = ob_example ();
  model.blocks(1).type = "Inport"; model.blocks(1).value = 1; model.blocks(1).name = "In1";
  model.blocks(2).value = 1;
  model.blocks(3).type = "Outport"; model.blocks(3).value = 1; model.blocks(3).name = "Out1";
endfunction
