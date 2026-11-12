function [model, options] = ob_continuous_control_example ()
  % x'=1 while (t-.2)*(.7-t)>0, so the held final state is .5.
  child = ob_subsystem_template ();
  child.blocks(2).type = 'Integrator'; child.blocks(2).value = 0;
  child.blocks(2).name = 'Active state';
  child.execution = struct ('mode','enabled','control','continuous', ...
                           'initial_outputs',{{0}});
  model.blocks = struct ('type',{'Constant','Constant','Time','Function','Subsystem','Scope'}, ...
      'value',{1,[-1 .9 -.14],[],[],child,[]}, ...
      'name',{'Derivative','Gate polynomial','Time','polyval','Continuous enable','Output'}, ...
      'x',{.12,.12,.12,.36,.62,.87},'y',{.83,.27,.52,.5,.7,.28});
  model.edges = [2 1 4 1;3 1 4 2;1 1 5 1;4 1 5 2;5 1 6 1];
  options = struct ('solver','rk4','zero_crossings',true,'maxstep',.1);
endfunction
