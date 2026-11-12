function model = ob_function_example ()
  model = ob_example ();
  model.blocks(2).type = "Function";
  model.blocks(2).name = "ob_demo_function";
  model.blocks(2).value = [];
endfunction
