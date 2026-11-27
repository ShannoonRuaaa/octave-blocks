function model = ob_conditional_example ()
  ## -*- texinfo -*-
  ## @deftypefn {} {@var{model} =} ob_conditional_example ()
  ## Return an enabled subsystem model with a Unit Delay and a Scope.
  ## The example's control source gates the subsystem's discrete updates.
  ##
  ## @example
  ## r = ob_run (ob_conditional_example (), 0:0.1:2);
  ## @end example
  ## @seealso{ob_subsystem_template, ob_enabled_multirate_example}
  ## @end deftypefn

  child = ob_subsystem_template ();
  child.blocks(2).type = 'Unit Delay'; child.blocks(2).value = 0;
  child.execution = struct ('mode', 'enabled', 'initial_outputs', {{-1}});
  model.blocks = struct ('type', {'Time','Inport','Subsystem','Scope'}, ...
      'value', {[],1,child,[]}, 'name', {'Time','Enable','Conditional delay','Output'}, ...
      'x', {0.16,0.16,0.53,0.86}, 'y', {0.72,0.30,0.52,0.52});
  model.edges = [1 1 3 1;2 1 3 2;3 1 4 1];
  model.inputs = {ob_input_signal(0:6,[0;1;1;0;0;1;1])};
endfunction
