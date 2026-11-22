function model = ob_staggered_enables_example ()
  % Two continuous enables around Integrators of 1 whose events one
  % zero-crossing search finds together: block 9 is enabled by -(t-.2)^2,
  % which touches zero at .2 from below, and block 5 by t-.2-1e-13, which
  % crosses one bisection tolerance after .2.  Scopes 11 and 12 show their
  % outputs.  Run with zero_crossings=true and maxstep 0.1 on 0:0.1:0.5, the
  % search starting at the stop 0.2 records block 9's departure from zero at
  % exactly 0.2 (rising, then falling back) and block 5's crossing at
  % 0.2000000000007276.  The records are kept in time order: ob_run,
  % ob_accelerate and the generated event C (whose last_event_time is the
  % latest counted time) all agree (ZERO_CROSSINGS.md).
  child = make_model ({'Inport','Integrator','Outport'}, {1,0,1});
  child.edges = [1 1 2 1;2 1 3 1];
  child.execution = struct ('mode','enabled','control','continuous','initial_outputs',{{-9}});
  model = make_model ({'Constant','Time','Constant','Sum','Subsystem','Constant','Sum', ...
                       'Product','Subsystem','Gain','Scope','Scope'}, ...
                      {1,[],-.2,[],child,-1e-13,[],[],child,-1,[],[]});
  model.edges = [2 1 4 1;3 1 4 2;4 1 7 1;6 1 7 2;1 1 5 1;7 1 5 2; ...
                 4 1 8 1;4 1 8 2;8 1 10 1;1 1 9 1;10 1 9 2;5 1 11 1;9 1 12 1];
endfunction

function model = make_model (types, values)
  n = numel (types);
  model.blocks = struct ('type',types,'value',values,'name',types, ...
      'x',num2cell(linspace(.1,.9,n)),'y',num2cell(.5*ones(1,n)));
  model.edges = zeros (0,4);
endfunction
