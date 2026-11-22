function model = ob_gated_outputs_example (states = 'held')
  % Enabled body whose Outports follow the rates of their sources.  Time
  % feeds Unit Delays at 0.125 s (IC -1) and 0.25 s (IC -2); a 0.125 s Rate
  % Transition samples the slow delay; a Sum mixes both rates.  Initial
  % outputs are -9 and only the slow delay's port resets while disabled.
  % The enable, sampled every 0.125 s, is on over [0.375, 0.875) and
  % [1.125, 1.625).  STATES is the body's states policy ('held' or 'reset').
  %
  % As recorded in Simulink (simulink-conditional-outputs-reference.json,
  % gating_*), each Outport takes a new value only when one of its clocked
  % sources executes, and the slow delay, which drives the Slow port
  % directly, shares that port's buffer: until it executes after
  % (re)activation, and after the port's reset, the Rate Transition and the
  % Sum read the port's value.  So the Slow port shows -9 until 0.5, the
  % mixed port -1 + -9 = -10 at 0.375, the slow port returns to -9 at the
  % next 0.25 s hit after disabling (1.0), not at the disable sample, and at
  % the 1.125 reactivation the Transition and Mixed ports read that -9.
  child.blocks = struct ('type',{'Inport','Unit Delay','Unit Delay','Rate Transition','Sum', ...
                                 'Outport','Outport','Outport','Outport'}, ...
      'value',{1,-1,-2,-4,[],1,2,3,4},'name',{'Data','Fast','Slow','Slow to fast','Sum', ...
                                              'Fast','Slow','Transition','Mixed'}, ...
      'x',{.1,.4,.4,.6,.6,.9,.9,.9,.9},'y',{.5,.8,.5,.3,.1,.8,.6,.4,.2});
  child.edges = [1 1 2 1;1 1 3 1;3 1 4 1;2 1 5 1;3 1 5 2;2 1 6 1;3 1 7 1;4 1 8 1;5 1 9 1];
  child.sample_times = zeros (9, 2); child.sample_times(2:4,:) = [.125 0;.25 0;.125 0];
  child.execution = struct ('mode','enabled','states',states,'outputs',{{'held','reset','held','held'}}, ...
                            'initial_outputs',{{-9,-9,-9,-9}});
  model.blocks = struct ('type',{'Time','Inport','Subsystem','Scope','Scope','Scope','Scope'}, ...
      'value',{[],1,child,[],[],[],[]},'name',{'Time','Enable','Gated','Fast','Slow','Transition','Mixed'}, ...
      'x',{.1,.1,.5,.9,.9,.9,.9},'y',{.7,.3,.5,.8,.6,.4,.2});
  model.edges = [1 1 3 1;2 1 3 2;3 1 4 1;3 2 5 1;3 3 6 1;3 4 7 1];
  model.inputs = {ob_input_signal([0 .375 .875 1.125 1.625],[0;1;0;1;0])};
  model.sample_times = zeros (7, 2); model.sample_times(3,:) = [.125 0];
endfunction
