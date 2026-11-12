function model = ob_multirate_example ()
  % Sample Time every 0.25s, then integrate the held signal continuously.
  model = ob_oscillator ();
  model.blocks(1).type = 'Time'; model.blocks(1).value = [];
  model.blocks(2).type = 'Rate Transition'; model.blocks(2).value = 0;
  model.blocks(3).type = 'Integrator'; model.blocks(3).value = 0;
  model.edges = [1 2; 2 3; 3 4];
  model.sample_times = [0 0; 0.25 0; 0 0; 0 0];
endfunction
