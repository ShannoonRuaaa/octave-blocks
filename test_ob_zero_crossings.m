function test_ob_zero_crossings ()
  % Coarse output requests must not determine a computed switching time.
  rising = switched_integrator (1, .35, 3, -2);
  falling = switched_integrator (-1, -.35, 3, -2);
  for solver = {'rk4', 'ode45', 'ode15s'}
    options = event_options (solver{1});
    result = ob_run (rising, [0 1], options);
    assert_close (ob_scope_data(result,7)', [0 1.25]);
    assert (isequal (result.t, [0;1]));
    assert_events (result.events, 5, .35, 1, 1);

    result = ob_run (falling, [0 1], options);
    assert_close (ob_scope_data(result,7)', [0 -.25]);
    assert_events (result.events, 5, .35, 1, -1);

    % The incoming integration branch and public >= equality are distinct.
    result = ob_run (rising, [0 .35 1], options);
    assert_close (ob_scope_data(result,7)', [0 -.7 1.25]);
    assert (result.values{2,5} == 3);
    assert_events (result.events, 5, .35, 1, 1);
    result = ob_run (falling, [0 .35 1], options);
    assert_close (ob_scope_data(result,7)', [0 1.05 -.25]);
    assert (result.values{2,5} == 3);
    assert_events (result.events, 5, .35, 1, -1);

    % A guard initially at zero must select its outgoing side without
    % advancing time, consuming a discrete hit, or repeatedly rediscovering 0.
    departing = switched_integrator (-1, 0, 1, 0);
    result = ob_run (departing, [0 1], options);
    assert (result.values{1,5} == 1);
    assert_close (ob_scope_data(result,7)', [0 0]);
    constant = switched_integrator (0, 0, 1, 0);
    result = ob_run (constant, [0 1], options);
    assert_close (ob_scope_data(result,7)', [0 1]);
    assert (isempty (result.events));

    % A departure from zero arms its outgoing side. Returning to zero at an
    % output endpoint must then record the falling event, rather than treat
    % the endpoint as another unarmed initial zero.
    returning = returning_zero_switch ();
    result = ob_run (returning, [0 1 2], options);
    assert_close (ob_scope_data(result,7)', [0 1 1]);
    assert_events (result.events, 5, 1, 1, -1);

    % Native adaptive integration must also work where its physical start
    % time is much larger than a unit-length, representable event interval.
    late_origin = 1e15;
    late_adaptive = elapsed_switched_integrator (late_origin, .5, 3, -2);
    result = ob_run (late_adaptive, [late_origin late_origin+1], options);
    assert_close (ob_scope_data(result,7)', [0 .5]);
    assert (numel(result.events) == 1 && result.events.time-late_origin == .5);
    assert_events (result.events, 5, late_origin+.5, 1, 1);

    % Short physical intervals near a nonzero origin retain both the exact
    % representable threshold and the state integral on its outgoing side.
    short_start = 1000; short_stop = short_start+1e-8;
    short_threshold = short_start+5e-9;
    short = switched_integrator (1, short_threshold, 1e8, 0);
    result = ob_run (short, [short_start short_stop], options);
    assert_close (ob_scope_data(result,7)', [0 1e8*(short_stop-short_threshold)]);
    assert (numel(result.events) == 1 && result.events.time == short_threshold);
    assert_events (result.events, 5, short_threshold, 1, 1);

    % A guard may stay exactly zero for an interval before departing. The
    % bounded decimal search steps also exercise representable endpoint tails
    % when restarting ode15s after the plateau's falling transition.
    plateau = plateau_switched_integrator ();
    bounded = options; bounded.maxstep = .1;
    result = ob_run (plateau, [0 1], bounded);
    assert_close (ob_scope_data(result,7)', [0 .5]);
    assert_events (result.events, 5, .5, 1, -1);

    % Output boundaries must preserve the incoming plateau regime until its
    % departure is observed, then retain one event at the boundary itself.
    for grid = {[0 .5 1], [0 .25 .5 .75 1]}
      result = ob_run (plateau, grid{1}, options);
      assert_close (ob_scope_data(result,7)', min(grid{1},.5));
      assert_events (result.events, 5, .5, 1, -1);
    endfor

    % Forking or checkpointing exactly at the zero plateau's endpoint must
    % preserve the guard history that distinguishes departure from startup.
    runtime = ob_runtime_step (ob_runtime_init(plateau,0,options), .5);
    saved = runtime;
    later = ob_runtime_step (runtime, 1);
    earlier = ob_runtime_step (runtime, .75);
    assert (isequaln(runtime,saved));
    assert_close (ob_runtime_outputs(later,7), .5);
    assert_close (ob_runtime_outputs(earlier,7), .5);
    assert_events (later.events, 5, .5, 1, -1);
    assert_events (earlier.events, 5, .5, 1, -1);
    file = [tempname() '.mat'];
    unwind_protect
      save ('-mat7-binary', file, 'runtime');
      restored = load (file);
      assert (isequaln(ob_runtime_step(restored.runtime,1),later));
    unwind_protect_cleanup
      if (exist(file,'file')), unlink(file); endif
    end_unwind_protect

    % A clock hit coincident with plateau departure remains a single clock
    % hit; finding that departure adds no inherited delay/Euler execution.
    coincident = plateau_clocked_switch ();
    result = ob_run (coincident, [0 1], options);
    assert_close (ob_scope_data(result,7)', [0 .5]);
    assert_close (ob_scope_data(result,13)', [-9 .5]);
    assert_close (ob_scope_data(result,15)', [0 1]);
    assert_close (result.sample_hits{12}, [0 .5 1], 1e-12);
    assert_close (result.sample_hits{14}, [0 1], 1e-12);
    assert_events (result.events, 5, .5, 1, -1);

    % A state-defined guard verifies localization against the pre-event ODE,
    % rather than only finding a root of a known function of Time.
    feedback = state_switched_integrator ();
    result = ob_run (feedback, [0 1], options);
    assert_close (ob_scope_data(result,5)', [0 1.7]);
    assert_events (result.events, 4, .3, 1, 1);

    % Saturation and Dead Zone are continuous at their boundaries but change
    % derivative formula. Their exact integrals are independent references.
    saturation = limited_integrator ('Saturation', [.2 .7]);
    result = ob_run (saturation, [0 1], options);
    assert_close (ob_scope_data(result,4)', [0 .475]);
    assert_events (result.events, 2, [.2 .7], [1 1], [1 1]);
    dead = limited_integrator ('Dead Zone', [.2 .7]);
    result = ob_run (dead, [0 1], options);
    assert_close (ob_scope_data(result,4)', [0 .025]);
    assert_events (result.events, 2, [.2 .7], [1 1], [1 1]);
  endfor

  options = event_options ('rk4');
  % Simultaneous propagation through a deep feedthrough cascade must settle
  % according to the control graph, rather than an arbitrary shallow limit.
  cascade = cascaded_switches (20);
  result = ob_run (cascade, [0 1], options);
  assert (result.values{1,24} == 1);
  assert_close (ob_scope_data(result,26)', [0 -1]);

  % Localization scales with the interval instead of imposing a fixed
  % absolute time floor that would discard a physically significant event.
  tiny = switched_integrator (1, 3.5e-13, 1e12, 0);
  result = ob_run (tiny, [0 1e-12], options);
  assert_close (ob_scope_data(result,7)', [0 .65], 2e-9);
  assert (numel(result.events) == 1 && isequal(result.events.path,5));
  assert (abs(result.events.time/1e-12-.35) < 2e-10);
  assert (result.events.channel == 1 && result.events.direction == 1);

  % At a large origin, subdivision must continue until floating-point time
  % itself prevents progress. The first representable outgoing time is .375.
  origin = 1e15;
  late = switched_integrator (1, .35, 3, -2);
  late.blocks(3).type = 'Sum'; late.blocks(3).value = [];
  late = append_block (late, 'Constant', -origin);
  late.edges(end+1,:) = [8 1 3 2];
  result = ob_run (late, [origin origin+1], options);
  assert_close (ob_scope_data(result,7)', [0 1.125], 1e-12);
  assert (numel(result.events) == 1 && result.events.time-origin == .375);

  % Per-element controls use column-major channels; simultaneous crossings
  % share a timestamp without losing either matrix element.
  matrix = matrix_switched_integrator ();
  result = ob_run (matrix, [0 1], options);
  assert_close (result.values{end,8}, [2 1;2 -.5]);
  assert_events (result.events, 6, [.2 .2 .4 .7], [1 2 3 4], [1 1 1 1]);

  % An explicitly bounded search step reveals two crossings even though
  % the guard has the same sign at the two requested output times.
  oscillating = switched_integrator (1, .5, 1, 0);
  oscillating.blocks(3).type = 'Function'; oscillating.blocks(3).name = 'sin';
  oscillating = append_block (oscillating, 'Gain', 2*pi);
  oscillating.edges(oscillating.edges(:,3)==3,:) = [];
  oscillating.edges = [oscillating.edges;2 1 8 1;8 1 3 1];
  bounded = options; bounded.maxstep = .05;
  result = ob_run (oscillating, [0 1], bounded);
  assert_close (ob_scope_data(result,7)', [0 1/3]);
  assert_events (result.events, 5, [1/12 5/12], [1 1], [1 -1]);

  % Purely time-driven guard monitoring also works without continuous state.
  stateless = rising;
  stateless.blocks(6).type = 'Scope'; stateless.blocks(6).value = [];
  result = ob_run (stateless, [0 1], options);
  assert_close (ob_scope_data(result,7)', [-2 3]);
  assert_events (result.events, 5, .35, 1, 1);

  % Virtual paths and active enabled bodies retain public block identities.
  nested = hierarchical_switch (false);
  result = ob_run (nested, [0 1], options);
  assert_close (ob_scope_data(result,3)', [0 1.25]);
  assert_events (result.events, [2 4], .35, 1, 1);
  enabled = hierarchical_switch (true);
  result = ob_run (enabled, [0 1], options);
  assert_close (ob_scope_data(result,3)', [0 1.25]);
  assert_events (result.events, [2 4], .35, 1, 1);
  core = find (strcmp ({result.compiled_model.blocks.type}, 'Conditional Subsystem'));
  assert_close (result.sample_hits{core}, 0:.25:1, 1e-12);
  assert_close (result.flat_values{end,core}.executions, 0:.25:1, 1e-12);

  % Event boundaries are internal integration points, not additional output
  % samples or inherited delay/Euler clock hits.
  clocked = clocked_switch ();
  result = ob_run (clocked, [0 1], options);
  assert_close (ob_scope_data(result,7)', [0 1.25]);
  assert_close (ob_scope_data(result,9)', [-9 .75]);
  assert_close (ob_scope_data(result,11)', [0 1]);
  assert_close (result.sample_hits{8}, 0:.25:1, 1e-12);
  assert_close (result.sample_hits{10}, [0 1], 1e-12);
  assert_events (result.events, 5, .35, 1, 1);

  % Accepted event history and outgoing regimes belong to the runtime copy.
  runtime = ob_runtime_step (ob_runtime_init(clocked,0,options), .2);
  saved = runtime;
  later = ob_runtime_step (runtime, 1);
  earlier = ob_runtime_step (runtime, .5);
  assert (isequaln (runtime, saved));
  assert_close (ob_runtime_outputs(later,7), 1.25);
  assert_close (ob_runtime_outputs(earlier,7), -.25);
  assert_events (later.events, 5, .35, 1, 1);
  file = [tempname() '.mat'];
  unwind_protect
    runtime = earlier;
    save ('-mat7-binary', file, 'runtime');
    restored = load (file);
    assert (isequaln (ob_runtime_step(restored.runtime,1), ob_runtime_step(runtime,1)));
  unwind_protect_cleanup
    if (exist(file,'file')), unlink(file); endif
  end_unwind_protect

  % An invalid function domain after a crossing and hidden sample hits cannot
  % commit partial event history, pending captures, or continuous state.
  failing = failing_switch ();
  runtime = ob_runtime_init (failing, 0, options);
  saved = runtime; caught = false;
  try
    runtime = ob_runtime_step (runtime, 1);
  catch err
    caught = ! isempty (strfind(err.message,'finite')) ...
             || ! isempty (strfind(err.message,'real'));
  end_try_catch
  assert (caught && isequaln(runtime,saved));
  retry = ob_runtime_step (runtime, .5);
  assert_close (ob_runtime_outputs(retry,7), -.25);
  assert_events (retry.events, 5, .35, 1, 1);

  % Inward-pointing vector fields on opposite sides of a discontinuity have
  % no stable outgoing branch here. Report chattering instead of looping at
  % one timestamp or inventing a delayed/sliding-mode solution.
  chattering = state_switched_integrator ();
  chattering.blocks(1).value = -1;
  chattering.blocks(3).value = 1;
  chattering.blocks(4).value = 0;
  runtime = ob_runtime_init (chattering, 0, options);
  saved = runtime; caught = false;
  try
    runtime = ob_runtime_step (runtime, 1);
  catch err
    caught = ! isempty (strfind(err.message,'chattering'));
  end_try_catch
  assert (caught && isequaln(runtime,saved));

  % Changing a guard's channel count inside one interval is an explicit
  % failure, even in a diagram whose outputs have no continuous state.
  reshaped = make_model ({'Constant','Time','Function','Saturation','Scope'}, ...
                         {1,[],[],[-1 10],[]});
  reshaped.blocks(3).name = 'colon';
  reshaped.edges = [1 1 3 1;2 1 3 2;3 1 4 1;4 1 5 1];
  assert_error (@() ob_run(reshaped,[1 2],options), 'layout');

  % Event configuration survives ordinary model files. C must not silently
  % export a fixed-step model with different event-enabled dynamics.
  file = [tempname() '.mat'];
  source = [tempname() '.c'];
  sentinel = sprintf ('existing C source\n');
  unwind_protect
    ob_save_model (file, rising, [0 1 1], options);
    [restored, config, loaded] = ob_load_model (file);
    assert (isequaln(restored,rising) && isequal(config,[0 1 1]));
    assert (loaded.zero_crossings);
    assert_close (ob_scope_data(ob_run(restored,[0 1],loaded),7)', [0 1.25]);
    stream = fopen (source, 'w'); assert (stream >= 0);
    fputs (stream, sentinel); fclose (stream);
    assert_error (@() ob_codegen(rising,source,[0 1 1],options), 'zero');
    assert (strcmp (fileread(source), sentinel));
  unwind_protect_cleanup
    if (exist(file,'file')), unlink(file); endif
    if (exist(source,'file')), unlink(source); endif
  end_unwind_protect
  assert (! ob_solver_options().zero_crossings);
  for invalid = {2, NaN, [0 1]}
    assert_error (@() ob_solver_options(struct('zero_crossings',invalid{1})), 'zero_crossings');
  endfor
  disp ('Octave Blocks zero-crossing tests passed');
endfunction

function options = event_options (solver)
  options = struct ('solver',solver,'zero_crossings',true, ...
                    'reltol',1e-9,'abstol',1e-11,'maxstep',Inf);
endfunction

function model = switched_integrator (slope, threshold, high, low)
  model = make_model ({'Constant','Time','Gain','Constant','Switch','Integrator','Scope'}, ...
      {high,[],slope,low,threshold,0,[]});
  model.edges = [1 1 5 1;2 1 3 1;3 1 5 2;4 1 5 3;5 1 6 1;6 1 7 1];
endfunction

function model = state_switched_integrator ()
  model = make_model ({'Constant','Integrator','Constant','Switch','Scope'}, {2,0,1,.3,[]});
  model.edges = [1 1 4 1;2 1 4 2;3 1 4 3;4 1 2 1;2 1 5 1];
endfunction

function model = plateau_switched_integrator ()
  model = switched_integrator (-1, 0, 1, 0);
  model = append_block (model, 'Constant', .5);
  model = append_block (model, 'Sum', []);
  model = append_block (model, 'Constant', 0);
  model = append_block (model, 'Function', []);
  model.blocks(11).name = 'min';
  model.edges(model.edges(:,3)==5 & model.edges(:,4)==2,:) = [];
  model.edges = [model.edges;3 1 9 1;8 1 9 2;9 1 11 1;10 1 11 2;11 1 5 2];
endfunction

function model = returning_zero_switch ()
  model = switched_integrator (-1, 0, 1, 0);
  model = append_block (model, 'Constant', 1);
  model = append_block (model, 'Sum', []);
  model = append_block (model, 'Product', []);
  model.edges(model.edges(:,3)==5 & model.edges(:,4)==2,:) = [];
  model.edges = [model.edges;8 1 9 1;3 1 9 2;2 1 10 1;9 1 10 2;10 1 5 2];
endfunction

function model = elapsed_switched_integrator (origin, threshold, high, low)
  model = switched_integrator (1, threshold, high, low);
  model.blocks(3).type = 'Sum'; model.blocks(3).value = [];
  model = append_block (model, 'Constant', -origin);
  model.edges(end+1,:) = [8 1 3 2];
endfunction

function model = plateau_clocked_switch ()
  model = plateau_switched_integrator ();
  model = append_block (model, 'Unit Delay', -9);
  model = append_block (model, 'Scope', []);
  model = append_block (model, 'Discrete Integrator', 0);
  model = append_block (model, 'Scope', []);
  model = append_block (model, 'Constant', 1);
  model.edges = [model.edges;2 1 12 1;12 1 13 1;16 1 14 1;14 1 15 1];
  model.sample_times = zeros (16,2); model.sample_times(12,:) = [.5 0];
endfunction

function model = cascaded_switches (count)
  types = [{'Constant','Constant','Time','Gain'}, repmat({'Switch'},1,count), {'Integrator','Scope'}];
  values = [{1,-1,[],-1}, num2cell(zeros(1,count)), {0,[]}];
  model = make_model (types, values);
  model.edges = [3 1 4 1];
  for id = 5:count+4
    model.edges = [model.edges;1 1 id 1;id-1 1 id 2;2 1 id 3];
  endfor
  model.edges = [model.edges;count+4 1 count+5 1;count+5 1 count+6 1];
endfunction

function model = limited_integrator (type, limits)
  model = make_model ({'Time',type,'Integrator','Scope'}, {[],limits,0,[]});
  model.edges = [1 1 2 1;2 1 3 1;3 1 4 1];
endfunction

function model = matrix_switched_integrator ()
  model = make_model ({'Time','Gain','Constant','Sum','Constant','Switch','Integrator','Scope','Constant'}, ...
      {[],ones(2),[-.2 -.4;-.2 -.7],[],3*ones(2),0,zeros(2),[],-2*ones(2)});
  model.edges = [1 1 2 1;2 1 4 1;3 1 4 2;5 1 6 1;4 1 6 2;9 1 6 3;6 1 7 1;7 1 8 1];
endfunction

function model = hierarchical_switch (enabled)
  child = make_model ({'Inport','Constant','Constant','Switch','Integrator','Outport'}, ...
      {1,3,-2,.35,0,1});
  child.edges = [2 1 4 1;1 1 4 2;3 1 4 3;4 1 5 1;5 1 6 1];
  model = make_model ({'Time','Subsystem','Scope'}, {[],child,[]});
  model.edges = [1 1 2 1;2 1 3 1];
  if (enabled)
    child.execution = struct ('mode','enabled','initial_outputs',{{-9}});
    model.blocks(2).value = child;
    model = append_block (model, 'Constant', 1);
    model.edges(end+1,:) = [4 1 2 2];
    model.sample_times = [0 0;.25 0;0 0;0 0];
  endif
endfunction

function model = clocked_switch ()
  model = switched_integrator (1, .35, 3, -2);
  model = append_block (model, 'Unit Delay', -9);
  model = append_block (model, 'Scope', []);
  model = append_block (model, 'Discrete Integrator', 0);
  model = append_block (model, 'Scope', []);
  model = append_block (model, 'Constant', 1);
  model.edges = [model.edges;2 1 8 1;8 1 9 1;12 1 10 1;10 1 11 1];
  model.sample_times = zeros (12,2); model.sample_times(8,:) = [.25 0];
endfunction

function model = failing_switch ()
  model = clocked_switch ();
  model = append_block (model, 'Gain', -1);
  model = append_block (model, 'Constant', .8);
  model = append_block (model, 'Sum', []);
  model = append_block (model, 'Function', []);
  model.blocks(16).name = 'log';
  model = append_block (model, 'Saturation', [-100 100]);
  model = append_block (model, 'Scope', []);
  model.edges = [model.edges;2 1 13 1;14 1 15 1;13 1 15 2;15 1 16 1;16 1 17 1;17 1 18 1];
  model.sample_times(13:18,:) = 0;
endfunction

function model = append_block (model, type, value)
  block = model.blocks(1); block.type = type; block.value = value; block.name = type;
  model.blocks(end+1) = block;
endfunction

function model = make_model (types, values)
  n = numel (types);
  model.blocks = struct ('type',types,'value',values,'name',types, ...
      'x',num2cell(linspace(.1,.9,n)),'y',num2cell(.5*ones(1,n)));
  model.edges = zeros (0,4);
endfunction

function assert_events (events, path, times, channels, directions)
  selected = [];
  for k = 1:numel (events)
    if (isequal (events(k).path, path)), selected(end+1) = k; endif
  endfor
  assert (numel(selected) == numel(times));
  if (isempty(selected)), return; endif
  actual = [[events(selected).time]' [events(selected).channel]' [events(selected).direction]'];
  expected = [times(:) channels(:) directions(:)];
  assert_close (sortrows(actual,[2 1]), sortrows(expected,[2 1]), 2e-8);
  assert (all (isfield (events(selected), {'time','path','channel','side','direction'})));
endfunction

function assert_close (actual, expected, tolerance = 2e-7)
  assert (isequal(size(actual),size(expected)) && all(isfinite(actual(:))));
  assert (all(abs(actual(:)-expected(:)) <= tolerance));
endfunction

function assert_error (callback, fragment)
  caught = false;
  try callback(); catch err, caught = ! isempty(strfind(err.message,fragment)); end_try_catch
  assert (caught);
endfunction
