function model = ob_subsystem_example ()
  % A feedback oscillator whose two states live behind subsystem boundaries.
  model = ob_oscillator ();
  for id = 1:2
    child = ob_subsystem_template ();
    child.blocks(2).type = "Integrator";
    child.blocks(2).value = double (id == 1);
    model.blocks(id).type = "Subsystem";
    model.blocks(id).name = sprintf ("State%d", id);
    model.blocks(id).value = child;
  endfor
endfunction
