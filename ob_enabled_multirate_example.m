function model = ob_enabled_multirate_example ()
  % Inner clocks retain global phase while sampled enable gates their updates.
  child.blocks = struct ('type',{'Inport','Discrete Integrator','Discrete Integrator','Outport','Outport'}, ...
      'value',{1,0,0,1,2},'name',{'Slope','Fast Euler','Slow Euler','Fast','Slow'}, ...
      'x',{.1,.45,.45,.9,.9},'y',{.5,.7,.3,.7,.3});
  child.edges = [1 1 2 1;1 1 3 1;2 1 4 1;3 1 5 1];
  child.sample_times = [0 0;.125 0;.25 0;0 0;0 0];
  child.execution = struct ('mode','enabled','initial_outputs',{{0,0}});
  model.blocks = struct ('type',{'Constant','Inport','Subsystem','Scope','Scope'}, ...
      'value',{1,1,child,[],[]},'name',{'Slope','Enable','Multirate enabled','Fast','Slow'}, ...
      'x',{.1,.1,.5,.9,.9},'y',{.7,.3,.5,.7,.3});
  model.edges = [1 1 3 1;2 1 3 2;3 1 4 1;3 2 5 1];
  model.inputs = {ob_input_signal([0 .375 .875],[0;1;0])};
  model.sample_times = [0 0;0 0;.125 0;0 0;0 0];
endfunction
