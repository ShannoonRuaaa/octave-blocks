function model = ob_input_example ()
  model = ob_example ();
  model.blocks(1).type = 'Inport'; model.blocks(1).value = 1; model.blocks(1).name = 'External force';
  model.blocks(2).type = 'Integrator'; model.blocks(2).value = 0;
  model.inputs = {ob_input_signal([0; 0.5; 1], [0; 1; 0], [1 1], 'zoh')};
endfunction
