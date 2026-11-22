function test_ob_algebraic ()
  % A gain above unity rules out a fixed-point-only implementation: y=3+2y.
  affine = feedback_model (3, 2);
  original = affine;
  result = ob_run (affine, [0 .13 .9]);
  assert_close (ob_scope_data(result,4)', [-3 -3 -3]);
  assert (isequal (affine, original));

  % Nonlinear residuals are solved rather than evaluating the loop once.
  nonlinear = make_model ({'Function','Scope'}, {[],[]}, {'cos','Output'});
  nonlinear.edges = [1 1 1 1;1 1 2 1];
  root = .7390851332151607;
  assert_close (ob_scope_data(ob_run(nonlinear,[0 .2 1]),2)', root*ones(1,3));

  % Multiple roots are selected by a user guess, not asserted to be unique.
  quadratic = make_model ({'Product','Scope'}, {[],[]}, {'Square','Output'});
  quadratic.edges = [1 1 1 1;1 1 1 2;1 1 2 1];
  quadratic.blocks(1).algebraic_initial = .9;
  assert_close (ob_scope_data(ob_run(quadratic,[0 .2 1]),2)', ones(1,3));
  quadratic.blocks(1).algebraic_initial = .1;
  assert_close (ob_scope_data(ob_run(quadratic,[0 .2 1]),2)', zeros(1,3));
  quadratic.blocks(1).algebraic_initial = .9;
  file = [tempname() '.mat'];
  unwind_protect
    ob_save_model (file, quadratic, [0 1 .2]);
    [restored, config] = ob_load_model (file);
    assert (isequal(restored,quadratic) && isequal(config,[0 1 .2]));
    assert_close (ob_scope_data(ob_run(restored,[0 .2 1]),2)', ones(1,3));
  unwind_protect_cleanup
    if (exist(file,'file')), unlink(file); endif
  end_unwind_protect

  % Separate SCCs can depend on each other, with an independent self-loop too.
  coupled = make_model ({'Constant','Sum','Gain','Scope','Sum','Gain','Scope','Function','Scope'}, ...
      {2,[],2,[],[],-.5,[],[],[]}, ...
      {'Input','First sum','First gain','First output','Second sum','Second gain','Second output','cos','Third output'});
  coupled.edges = [1 1 2 1;3 1 2 2;2 1 3 1;2 1 4 1; ...
                   4 1 5 1;6 1 5 2;5 1 6 1;5 1 7 1;8 1 8 1;8 1 9 1];
  result = ob_run (coupled, [0 1]);
  assert_close (ob_scope_data(result,4)', [-2 -2]);
  assert_close (ob_scope_data(result,7)', [-4/3 -4/3]);
  assert_close (ob_scope_data(result,9)', [root root]);

  % Fixed matrix dimensions come from explicit guesses for every loop signal.
  A = [2 .2;.1 1.5]; u = [1;-.5];
  matrix = feedback_model (u, A);
  matrix.blocks(2).algebraic_initial = zeros (2,1);
  matrix.blocks(3).algebraic_initial = zeros (2,1);
  result = ob_run (matrix, [0 .4 1]);
  expected = (eye(2)-A)\u;
  for sample = ob_signal_values (result, 4)'
    assert_close (sample{1}, expected);
  endfor
  matrix.blocks(1).value = [u 2*u];
  matrix.blocks(2).algebraic_initial = zeros (2);
  matrix.blocks(3).algebraic_initial = zeros (2);
  result = ob_run (matrix, [0 .4 1]);
  for sample = ob_signal_values (result, 4)'
    assert_close (sample{1}, [expected 2*expected]);
  endfor

  % Virtual boundaries remain visible to SCC discovery and numerical solving.
  hierarchical = affine;
  child = ob_subsystem_template ();
  child.blocks(2).value = 2;
  hierarchical.blocks(3).type = 'Subsystem';
  hierarchical.blocks(3).value = child;
  result = ob_run (hierarchical, [0 1]);
  assert_close (ob_scope_data(result,4)', [-3 -3]);
  assert_close (ob_scope_data(result,[3 2])', [-6 -6]);

  % Each ODE stage needs a fresh algebraic solution: x'=y, y=x+2y => x'=-x.
  continuous = make_model ({'Integrator','Sum','Gain','Scope'}, {1,[],2,[]}, ...
                           {'State','Derivative','Feedback','Output'});
  continuous.edges = [1 1 2 1;3 1 2 2;2 1 3 1;2 1 1 1;1 1 4 1];
  times = 0:.05:1;
  for solver = {'rk4','ode45','ode15s'}
    options = struct ('solver',solver{1},'reltol',1e-8,'abstol',1e-10,'maxstep',.05);
    result = ob_run (continuous, times, options);
    assert_close (ob_scope_data(result,4)', exp(-times), 2e-7);
    assert_close (ob_scope_data(result,2)', -ob_scope_data(result,4)');
  endfor

  % Known source/input knots split integration even when logging skips them.
  % z=(u-x)-z, x'=z gives x'=(u-x)/2.
  forced = forced_model ();
  times = [0:.05:.3 .4:.05:.6 .7:.05:1];
  for solver = {'rk4','ode45','ode15s'}
    options = struct ('solver',solver{1},'reltol',1e-9,'abstol',1e-11,'maxstep',.05);
    result = ob_run (forced, times, options);
    expected = 1-exp(-max(times-.35,0)/2);
    forcing = double(times >= .35);
    assert_close (ob_scope_data(result,7)', expected, 2e-7);
    assert_close (ob_scope_data(result,8)', .5*(forcing-expected), 2e-7);
    external = forced;
    external.blocks(1).type = 'Inport'; external.blocks(1).value = 1;
    external.inputs = {ob_input_signal([0 .35 .65], [0;1;-.5])};
    result = ob_run (external, times, options);
    expected -= 1.5*(1-exp(-max(times-.65,0)/2));
    forcing -= 1.5*double(times >= .65);
    assert_close (ob_scope_data(result,7)', expected, 2e-7);
    assert_close (ob_scope_data(result,8)', .5*(forcing-expected), 2e-7);
  endfor

  % Inner residual iterations must not redispatch a conditional body or delay.
  conditional = conditional_model ();
  result = ob_run (conditional, 0:6);
  assert_close (ob_scope_data(result,4)', [-9 7 -1 -1 -1 -2 -5]);
  core = find (strcmp({result.compiled_model.blocks.type},'Conditional Subsystem'));
  assert (isequal(result.flat_values{end,core}.executions,[1 2 5 6]));
  conditional.blocks(3).value.execution.mode = 'rising';
  result = ob_run (conditional, 0:6);
  assert_close (ob_scope_data(result,4)', [-9 7 7 7 7 -1 -1]);
  core = find (strcmp({result.compiled_model.blocks.type},'Conditional Subsystem'));
  assert (isequal(result.flat_values{end,core}.executions,[1 5]));

  % Residual iterations must not consume hidden discrete sample hits.
  sampled = feedback_model ([], 2);
  sampled.blocks(1).type = 'Time';
  sampled.blocks(4).type = 'Unit Delay'; sampled.blocks(4).value = -.5;
  sampled.blocks(5) = sampled.blocks(4);
  sampled.blocks(5).type = 'Scope'; sampled.blocks(5).value = [];
  sampled.edges(end+1,:) = [4 1 5 1];
  sampled.sample_times = [0 0;0 0;0 0;.25 0;0 0];
  result = ob_run (sampled, [0 .6 1.1]);
  assert_close (ob_scope_data(result,5)', [-.5 -.25 -.75]);
  assert_close (result.sample_hits{4}, 0:.25:1);

  % Copies and MAT checkpoints include the solved guesses and clock captures.
  runtime = ob_runtime_step (ob_runtime_init(sampled), .6);
  saved = runtime;
  later = ob_runtime_step (runtime, 1.1);
  earlier = ob_runtime_step (runtime, .8);
  assert (isequal (runtime, saved));
  assert_close (ob_runtime_outputs(later,5), -.75);
  assert_close (ob_runtime_outputs(earlier,5), -.5);
  file = [tempname() '.mat'];
  unwind_protect
    save ('-mat7-binary', file, 'runtime');
    restored = load (file);
    assert (isequal (ob_runtime_step(restored.runtime,1.1), later));
  unwind_protect_cleanup
    if (exist(file,'file')), unlink(file); endif
  end_unwind_protect

  % An inconsistent constraint after earlier hidden hits must roll back fully.
  % y=1+t*y is regular at t=0 and becomes inconsistent at t=1.
  failing = make_model ({'Time','Constant','Sum','Product','Unit Delay','Scope'}, ...
      {[],1,[],[],-1,[]}, {'Time','One','Constraint','Product','Delay','Output'});
  failing.edges = [1 1 4 1;3 1 4 2;2 1 3 1;4 1 3 2;1 1 5 1;5 1 6 1];
  failing.sample_times = [0 0;0 0;0 0;0 0;.1 0;0 0];
  runtime = ob_runtime_init (failing);
  saved = runtime;
  caught = false;
  try
    runtime = ob_runtime_step (runtime, 1);
  catch err
    caught = ! isempty (strfind(err.message,'algebraic'));
  end_try_catch
  assert (caught && isequal(runtime,saved));
  retry = ob_runtime_step (runtime, .3);
  assert_close (ob_runtime_outputs(retry,6), .2);

  % A continuum of roots is not a well-posed algebraic constraint.
  singular = make_model ({'Scope'}, {[]}, {'Identity'});
  singular.edges = [1 1 1 1];
  assert_error (@() ob_run(singular,0), 'algebraic');
  % A large guess must not hide a constant residual behind relative scaling.
  inconsistent = make_model ({'Time','Sum'}, {[],[]}, {'Time','Constraint'});
  inconsistent.edges = [1 1 2 1;2 1 2 2];
  inconsistent.blocks(2).algebraic_initial = 1e12;
  assert_error (@() ob_run(inconsistent,1), 'algebraic');

  invalid = matrix;
  invalid.blocks(2).algebraic_initial = NaN;
  assert_error (@() ob_run(invalid,0), 'algebraic');
  invalid.blocks(2).algebraic_initial = complex(1,1);
  assert_error (@() ob_run(invalid,0), 'algebraic');
  invalid.blocks(2).algebraic_initial = sparse(zeros(2,1));
  assert_error (@() ob_run(invalid,0), 'algebraic');
  invalid.blocks(2).algebraic_initial = single(zeros(2,1));
  assert_error (@() ob_run(invalid,0), 'algebraic');
  invalid = matrix;
  invalid.blocks(3).algebraic_initial = zeros (1,2);
  assert_error (@() ob_run(invalid,0), 'algebraic');

  % Functions that leave the real finite domain cannot yield accepted roots.
  invalid = nonlinear;
  invalid.blocks(1).name = 'log';
  invalid.blocks(1).algebraic_initial = -1;
  assert_error (@() ob_run(invalid,0), 'algebraic');
  disp ('Octave Blocks algebraic-loop tests passed');
endfunction

function model = feedback_model (input, gain)
  model = make_model ({'Constant','Sum','Gain','Scope'}, {input,[],gain,[]}, ...
                      {'Input','Sum','Gain','Output'});
  model.edges = [1 1 2 1;3 1 2 2;2 1 3 1;2 1 4 1];
endfunction

function model = forced_model ()
  model = make_model ({'Step','Integrator','Gain','Sum','Sum','Gain','Scope','Scope'}, ...
      {[.35 0 1],0,-1,[],[],-1,[],[]}, ...
      {'Input','State','Negative state','Drive','Derivative','Feedback','State output','Derivative output'});
  model.edges = [1 1 4 1;3 1 4 2;2 1 3 1;4 1 5 1;6 1 5 2; ...
                 5 1 6 1;5 1 2 1;2 1 7 1;5 1 8 1];
endfunction

function model = conditional_model ()
  child = make_model ({'Inport','Sum','Gain','Unit Delay','Outport'}, {1,[],2,7,1}, ...
      {'Input','Sum','Gain','Delay','Output'});
  child.edges = [1 1 2 1;3 1 2 2;2 1 3 1;2 1 4 1;4 1 5 1];
  child.execution = struct ('mode','enabled','initial_outputs',{{-9}});
  model = make_model ({'Time','Inport','Subsystem','Scope'}, {[],1,child,[]}, ...
      {'Time','Control','Conditional loop','Output'});
  model.edges = [1 1 3 1;2 1 3 2;3 1 4 1];
  model.inputs = {ob_input_signal(0:6,[0;1;1;0;0;1;1])};
endfunction

function model = make_model (types, values, names)
  n = numel (types);
  model.blocks = struct ('type',types,'value',values,'name',names, ...
                         'x',num2cell(linspace(.1,.9,n)), ...
                         'y',num2cell(.5*ones(1,n)));
  model.edges = zeros (0,4);
endfunction

function assert_close (actual, expected, tolerance = 1e-8)
  assert (isequal(size(actual),size(expected)) && all(isfinite(actual(:))));
  assert (all(abs(actual(:)-expected(:)) <= tolerance));
endfunction

function assert_error (callback, fragment)
  caught = false;
  try callback(); catch err, caught = ! isempty(strfind(err.message,fragment)); end_try_catch
  assert (caught);
endfunction
