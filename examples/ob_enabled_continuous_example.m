function model = ob_enabled_continuous_example ()
  % A continuous ramp pauses while its sampled enable is low, then resumes.
  child = ob_subsystem_template ();
  child.blocks(2).type = 'Integrator'; child.blocks(2).value = 0;
  child.blocks(2).name = 'Continuous state';
  child.execution = struct ('mode', 'enabled', 'initial_outputs', {{-1}});
  model.blocks = struct ('type', {'Constant','Inport','Subsystem','Scope'}, ...
      'value', {1,1,child,[]}, 'name', {'Slope','Enable','Enabled integrator','Output'}, ...
      'x', {0.16,0.16,0.53,0.86}, 'y', {0.72,0.30,0.52,0.52});
  model.edges = [1 1 3 1;2 1 3 2;3 1 4 1];
  model.inputs = {ob_input_signal([0 1 2 3], [1;0;1;0])};
  model.sample_times = [0 0;0 0;0.25 0;0 0];
endfunction
