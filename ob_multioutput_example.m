function model = ob_multioutput_example ()
  % Values and first-occurrence indices from one two-output Octave call.
  model = ob_example ();
  model.blocks(1).type = 'Constant'; model.blocks(1).value = [3 8 -1;3 2 -1];
  model.blocks(2).type = 'Function'; model.blocks(2).name = 'max';
  model.blocks(2).value = []; model.blocks(2).outputs = 2;
  model.blocks(4) = model.blocks(3);
  model.blocks(1).x = 0.15; model.blocks(2).x = 0.48;
  model.blocks(3).x = model.blocks(4).x = 0.86;
  model.blocks(3).y = 0.72; model.blocks(4).y = 0.28;
  model.edges = [1 1 2 1;2 1 3 1;2 2 4 1];
endfunction
