function model = ob_subsystem_template ()
  model = ob_example ();
  model.blocks(1).type = "Inport"; model.blocks(1).value = 1; model.blocks(1).name = "In1";
  model.blocks(2).value = 1;
  model.blocks(3).type = "Outport"; model.blocks(3).value = 1; model.blocks(3).name = "Out1";
endfunction
