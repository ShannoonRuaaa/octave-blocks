function test_ob_codegen (directory, conditional_references_only = false)
  % Prepare real exports and Octave references; Test-Codegen.ps1 compiles/runs them.
  if (! exist (directory, 'dir')), mkdir (directory); endif
  cases = struct ('name', {}, 'source', {}, 'standalone', {}, 'expected', {});
  add_case ('time_gain', ob_example (), [0 1 0.3]);
  add_case ('nested', ob_subsystem_example (), [0 10 0.1]);
  [inner_cases, inner_api] = test_ob_inner_clock_c_cases ();
  for item = inner_cases
    add_case (item.name,item.model,item.config);
  endfor
  linear = ob_linear_system_example ();
  add_case ('linear_transfer_step',linear,[0 4 .1]);
  linear.blocks(1).type = 'Constant'; linear.blocks(1).value = 1;
  linear.blocks(2).value = ob_state_space(-2,1,1,0,.2);
  add_case ('linear_state_space',linear,[0 2 .05]);
  linear.blocks(1).value = [1;2];
  linear.blocks(2).value = ob_state_space(diag([-1 -2]),eye(2),[1 2;3 -1],[.5 0;0 -.25],[.2;-.3]);
  add_case ('linear_mimo_feedthrough',linear,[0 2 .05]);
  linear.blocks(1).value = 1;
  linear.blocks(2).value = ob_transfer_function([2 1],[1 3]);
  add_case ('linear_transfer_feedthrough',linear,[0 1 .025]);
  linear.blocks(1).value = [3;4];
  linear.blocks(2).value = ob_state_space(zeros(0),zeros(0,2),zeros(2,0),[1 2;3 4]);
  add_case ('linear_zero_state',linear,[0 1 .1]);
  linear.blocks(1).value = 0;
  linear.blocks(2).value = ob_transfer_function(1,[1 0 1],[1;0]);
  add_case ('linear_transfer_initial_state',linear,[0 2 .05]);
  linear.blocks(1).value = 1;
  linear.blocks(2).value = ob_transfer_function(0,[1 2 1]);
  add_case ('linear_transfer_zero',linear,[0 1 .1]);
  linear.blocks(1).type = 'Gain'; linear.blocks(1).value = -1;
  linear.blocks(2).value = ob_state_space(0,1,1,0,1);
  linear.edges = [2 1 1 1;1 1 2 1;2 1 3 1];
  add_case ('linear_closed_feedback',linear,[0 2 .05]);
  autonomous_linear.blocks = struct('type',{'Subsystem','Scope'}, ...
    'value',{ob_state_space([0 1;-1 0],[],eye(2),[],[1;0]),[]}, ...
    'name',{'Autonomous oscillator','Output'},'x',{.3,.8},'y',{.5,.5});
  autonomous_linear.edges = [1 1 2 1];
  add_case ('linear_autonomous_oscillator',autonomous_linear,[0 2 .05]);
  autonomous_linear.blocks(1).value = ob_state_space(zeros(0),[],zeros(2,0),[]);
  add_case ('linear_autonomous_zero',autonomous_linear,[0 1 .1]);
  precision = ob_example ();
  precision.blocks(1).type = 'Constant'; precision.blocks(1).value = 1;
  precision.blocks(2).type = 'Discrete Integrator'; precision.blocks(2).value = 0;
  precision.sample_times = [0 0;8 2;0 0];
  assert (ob_scope_data(ob_run(precision,[1e16 1e16+24]),3)(end) == 16);
  add_case ('clock_large_origin',precision,[1e16 1e16+24 24]);
  precision = ob_conditional_example (); precision = rmfield(precision,'inputs');
  precision.blocks(1).type = precision.blocks(2).type = 'Constant';
  precision.blocks(1).value = precision.blocks(2).value = 1;
  precision.blocks(3).value.blocks(2).type = 'Discrete Integrator';
  precision.sample_times = zeros(4,2);
  precision.sample_times(3,:) = [8 0];
  assert (ob_scope_data(ob_run(precision,[1e16 1e16+24]),4)(end) == 24);
  add_case ('conditional_clock_large_origin',precision,[1e16 1e16+24 24]);
  precision = ob_example ();
  precision.blocks(1).type = 'Constant'; precision.blocks(1).value = 1;
  precision.blocks(2).type = 'Discrete Integrator'; precision.blocks(2).value = 0;
  precision.sample_times = [0 0;.1 .07;0 0];
  assert (abs(ob_scope_data(ob_run(precision,[1000 1000.17]),3)(end)-.1) < 1e-14);
  add_case ('clock_decimal_origin',precision,[1000 1000.17 .17]);
  precision = ob_conditional_example (); precision = rmfield(precision,'inputs');
  precision.blocks(1).type = precision.blocks(2).type = 'Constant';
  precision.blocks(1).value = precision.blocks(2).value = 1;
  precision.blocks(3).value.blocks(2).type = 'Discrete Integrator';
  precision.sample_times = zeros(4,2); precision.sample_times(3,:) = [.1 .07];
  assert (abs(ob_scope_data(ob_run(precision,[1000 1000.17]),4)(end)-.1) < 1e-14);
  add_case ('conditional_clock_decimal_origin',precision,[1000 1000.17 .17]);

  % Atomic lifecycle/discrete updates execute on major hits; continuous flow
  % evaluation uses independent RK stage snapshots.
  % Log their numeric output proxies, not the nonnumeric child-context core.
  for states = {'held','reset'}
    for outputs = {'held','reset'}
      conditional = ob_conditional_example ();
      conditional.blocks(3).value.execution.states = states{1};
      conditional.blocks(3).value.execution.outputs = outputs{1};
      add_case (['conditional_enabled_' states{1} '_' outputs{1}], conditional, [0 6 1]);
    endfor
  endfor
  conditional = ob_conditional_example ();
  conditional.sample_times = [0 0;0 0;1 0.5;0 0];
  add_case ('conditional_offset', conditional, [0 7 1]);
  for mode = {'rising','falling','either'}
    conditional = ob_conditional_example ();
    conditional.inputs = {ob_input_signal(0:9, [-1;0;1;0;0;1;-1;0;0;1])};
    conditional.blocks(3).value.execution.mode = mode{1};
    add_case (['conditional_trigger_' mode{1}], conditional, [0 9 1]);
  endfor
  conditional.blocks(3).value.execution.mode = 'falling';
  conditional.blocks(3).value.execution.initial_control = -1;
  add_case ('conditional_initial_control', conditional, [0 9 1]);

  conditional = ob_conditional_example ();
  conditional.blocks(1).type = 'Constant'; conditional.blocks(1).value = [1 2;3 4];
  conditional.blocks(3).value.blocks(2).value = zeros (2);
  conditional.blocks(3).value.blocks(4) = conditional.blocks(3).value.blocks(3);
  conditional.blocks(3).value.blocks(4).value = 2;
  conditional.blocks(3).value.edges = [1 1 2 1;2 1 3 1;1 1 4 1];
  conditional.blocks(3).value.execution.initial_outputs = {-ones(2),zeros(2)};
  conditional.blocks(5) = conditional.blocks(4);
  conditional.edges(end+1,:) = [3 2 5 1];
  add_case ('conditional_matrix_ports', conditional, [0 6 1]);
  child.blocks = struct ('type',{'Inport','Gain','Constant','Product','Constant','Function','Rate Transition','Outport'}, ...
    'value',{1,[1 2;0 1],[2 0;0 3],[],[1 2],[],zeros(2),1}, ...
    'name',{'Input','Gain','Multiplier','Product','Bias','plus','Hold','Output'}, ...
    'x',{0.1,0.3,0.3,0.5,0.5,0.7,0.8,0.9},'y',{0.5,0.7,0.3,0.6,0.2,0.5,0.5,0.5});
  child.edges = [1 1 2 1;2 1 4 1;3 1 4 2;4 1 6 1;5 1 6 2;6 1 7 1;7 1 8 1];
  child.execution = struct ('mode','enabled','initial_outputs',{{-ones(2)}});
  conditional = ob_conditional_example ();
  conditional.blocks(1).type = 'Constant'; conditional.blocks(1).value = [1 2;3 4];
  conditional.blocks(3).value = child;
  probe = ob_run (conditional, 0:6);
  assert (isequal (probe.values{2,4}, [15 32;7 14]));
  add_case ('conditional_numeric_body', conditional, [0 6 1]);

  conditional = ob_conditional_example ();
  conditional.blocks(3).value = conditional_wrapper (conditional.blocks(3).value);
  add_case ('conditional_virtual_wrapper', conditional, [0 6 1]);
  conditional.blocks(3).value.execution = struct ('mode','enabled','initial_outputs',{{-9}});
  conditional.blocks(3).value.blocks(3).value.execution.mode = 'rising';
  conditional.blocks(5) = conditional.blocks(1);
  conditional.blocks(5).type = 'Constant'; conditional.blocks(5).value = 1;
  conditional.edges(end+1,:) = [5 1 3 3];
  add_case ('conditional_nested_trigger', conditional, [0 6 1]);

  conditional = ob_conditional_example ();
  conditional.blocks(4).type = 'Integrator'; conditional.blocks(4).value = 0;
  conditional.blocks(5) = conditional.blocks(4);
  conditional.blocks(5).type = 'Scope'; conditional.blocks(5).value = [];
  conditional.edges(end+1,:) = [4 1 5 1];
  conditional.sample_times = [0 0;0 0;1 0;0 0;0 0];
  add_case ('conditional_parent_integrator', conditional, [0 6 0.5]);

  conditional = ob_conditional_example ();
  conditional.blocks(1).type = 'Constant'; conditional.blocks(1).value = 1;
  conditional.blocks(3).value.blocks(2).type = 'Discrete Integrator';
  add_case ('conditional_enabled_euler', conditional, [0 6 1]);
  conditional.blocks(3).value.execution.mode = 'rising';
  add_case ('conditional_triggered_euler', conditional, [0 6 1]);
  conditional.blocks(3).value.execution.mode = 'enabled';
  conditional.inputs = {ob_input_signal([0 0.25 4], [1;0;1])};
  add_case ('conditional_enabled_euler_pause', conditional, [0 6 0.25]);

  conditional = conditional_nested_euler (false);
  assert (isequal (ob_scope_data(ob_run(conditional,0:6),4)', [-1 0 1 1 1 2 3]));
  add_case ('conditional_nested_enabled_euler', conditional, [0 6 1]);
  conditional = conditional_nested_euler (true);
  assert (isequal (ob_scope_data(ob_run(conditional,0:6),4)', [-1 0 0 0 0 4 4]));
  add_case ('conditional_nested_triggered_euler', conditional, [0 6 1]);

  conditional = ob_conditional_example (); conditional = rmfield(conditional,'inputs');
  conditional.blocks(1).type = 'Step'; conditional.blocks(1).value = [2 -1 4];
  conditional.blocks(2).type = 'Step'; conditional.blocks(2).value = [2 0 1];
  conditional.blocks(3).value.blocks(2).type = 'Function';
  conditional.blocks(3).value.blocks(2).name = 'sqrt'; conditional.blocks(3).value.blocks(2).value = [];
  assert (isequal (ob_scope_data(ob_run(conditional,0:3),4)', [-1 -1 2 2]));
  add_case ('conditional_inactive_domain', conditional, [0 3 1]);
  conditional = conditional_host_model ();
  assert (isequal (ob_scope_data(ob_run(conditional,0:3),4)', [-1 2 7 12]));
  add_case ('conditional_host_nested', conditional, [0 3 1]);
  blank.blocks = struct ('type',{},'value',{},'name',{},'x',{},'y',{});
  blank.edges = zeros (0,2); blank.execution = struct ('mode','enabled');
  conditional = ob_conditional_example (); conditional.blocks = conditional.blocks(1:3);
  conditional.blocks(3).value = blank; conditional.edges = [2 1 3 1];
  add_case ('conditional_empty_child', conditional, [0 2 1]);

  % Continuous enabled children share every RK stage with their parent.
  for states={'held','reset'}
    for outputs={'held','reset'}
      flow=ob_enabled_continuous_example ();
      flow.blocks(3).value.execution.states=states{1};
      flow.blocks(3).value.execution.outputs=outputs{1};
      add_case (['continuous_enabled_' states{1} '_' outputs{1}],flow,[0 4 .1]);
    endfor
  endfor
  flow=ob_enabled_continuous_example (); flow.sample_times(3,:)=[.25 .125];
  add_case ('continuous_enabled_offset',flow,[0 4 .3]);
  flow=rmfield(flow,'sample_times');
  add_case ('continuous_enabled_inherited',flow,[0 4 .3]);
  flow=ob_enabled_continuous_example ();
  flow.blocks(1).value=[1 -2;3 .5];
  flow.blocks(3).value.blocks(2).value=[4 0;-1 2];
  flow.blocks(3).value.execution.initial_outputs={-ones(2)};
  add_case ('continuous_enabled_matrix',flow,[0 4 .1]);
  flow=continuous_coupled ();
  probe=ob_run(flow,0:.05:2);
  assert(max(abs(ob_scope_data(probe,4)'-cos(0:.05:2)))<2e-7);
  add_case ('continuous_enabled_coupled',flow,[0 2 .05]);
  flow=ob_enabled_continuous_example ();
  flow.blocks(3).value.blocks(1).type='Step';
  flow.blocks(3).value.blocks(1).value=[.375 2 5];
  flow.edges=[2 1 3 1;3 1 4 1];
  flow.inputs={ob_input_signal(0,1)}; flow.sample_times(3,:)=[.5 0];
  add_case ('continuous_enabled_inner_step',flow,[0 1 1]);
  flow=continuous_mixed ();
  add_case ('continuous_enabled_mixed',flow,[0 4 .1]);
  flow.inputs={ob_input_signal(0,1)};
  add_case ('continuous_enabled_mixed_always',flow,[0 1 .1]);
  for reset={'held','reset'}
    flow=continuous_nested ();
    flow.blocks(3).value.execution.states=reset{1};
    add_case (['continuous_enabled_nested_' reset{1}],flow,[0 7 .5]);
  endfor
  flow=continuous_nested ();
  flow.blocks(3).value.blocks(2).type='Constant'; flow.blocks(3).value.blocks(2).value=0;
  flow.blocks(3).value.edges=[1 1 3 1;2 1 3 2;1 1 4 1];
  flow.blocks(1).type='Time'; flow.blocks(1).value=[];
  flow.edges=[1 1 3 1;2 1 3 2;3 1 4 1];
  flow.inputs={ob_input_signal([0 1],[1;0])};
  add_case ('continuous_enabled_empty_active',flow,[0 2 .1]);
  flow=ob_enabled_continuous_example ();
  inner=flow.blocks(3).value;
  inner.blocks(4)=inner.blocks(2); inner.blocks(4).type='Function';
  inner.blocks(4).name='sqrt'; inner.blocks(4).value=[];
  inner.edges=[1 1 4 1;4 1 2 1;2 1 3 1];
  flow.blocks(3).value=inner;
  flow.blocks(1).type='Step'; flow.blocks(1).value=[1 -1 4];
  flow.inputs={ob_input_signal([0 1],[0;1])};
  add_case ('continuous_enabled_inactive_domain',flow,[0 2 .1]);
  % Host callbacks below test failures inside an already initialized child.
  flow.blocks(1).type='Inport'; flow.blocks(1).value=1;
  flow.blocks(2).value=2;
  flow.inputs={ob_input_signal(0,4),ob_input_signal(0,1)};
  add_case ('continuous_enabled_host',flow,[0 1 .1]);
  if (conditional_references_only)
    disp ('Octave conditional codegen reference timelines passed');
    return;
  endif

  step = ob_example ();
  step.blocks(1).type = 'Step'; step.blocks(1).value = [0.35 0 1];
  step.blocks(2).type = 'Integrator'; step.blocks(2).value = 0;
  add_case ('step_unaligned', step, [0 1 0.3]);
  step.blocks(1).value = [1 0 1];
  add_case ('step_aligned', step, [0 2 0.5]);

  discrete = ob_subsystem_example ();
  for id = 1:2, discrete.blocks(id).value.blocks(2).type = 'Unit Delay'; endfor
  add_case ('delay_feedback', discrete, [0 6 1]);
  mixed = ob_oscillator ();
  mixed.blocks(1).type = 'Step'; mixed.blocks(1).value = [0.35 0 1];
  mixed.blocks(2).type = 'Unit Delay'; mixed.blocks(2).value = 0;
  mixed.blocks(3).type = 'Integrator'; mixed.blocks(3).value = 0;
  mixed.edges = [1 2; 2 3; 3 4];
  add_case ('mixed_states', mixed, [0 2 0.3]);

  matrix = ob_example ();
  matrix.blocks(1).type = 'Constant'; matrix.blocks(1).value = [1 2; 3 4];
  matrix.blocks(2).type = 'Integrator'; matrix.blocks(2).value = zeros (2);
  add_case ('matrix_integrator', matrix, [0 1 0.3]);
  matrix.blocks(2).type = 'Discrete Integrator';
  add_case ('matrix_discrete', matrix, [0 1 0.3]);
  matrix.blocks(2).type = 'Gain'; matrix.blocks(2).value = [1 2; 0 1; -1 3];
  add_case ('matrix_gain', matrix, [0 1 0.3]);
  matrix = ob_oscillator ();
  matrix.blocks(1).type = 'Constant'; matrix.blocks(1).value = [1 2; 0 1];
  matrix.blocks(2).type = 'Constant'; matrix.blocks(2).value = [2 0; 3 1];
  matrix.blocks(3).type = 'Product'; matrix.blocks(3).value = [];
  matrix.edges = [1 3; 2 3; 3 4];
  add_case ('matrix_product', matrix, [0 1 0.5]);
  matrix.blocks(1).value = [1 2 3]; matrix.blocks(2).value = [10; 20];
  matrix.blocks(3).type = 'Sum';
  add_case ('broadcast_sum', matrix, [0 1 0.5]);

  math = ob_example ();
  math.blocks = math.blocks(1:2);
  math.blocks(1).type = math.blocks(2).type = 'Constant';
  math.blocks(1).value = [0.1 0.2; 0.3 0.4]; math.blocks(2).value = [1.5; 2.5];
  math.edges = zeros (0, 4);
  unary = {'sin','cos','tan','asin','acos','atan','sinh','cosh','tanh','exp', ...
           'log','log10','sqrt','abs','floor','ceil','round','sign','uminus'};
  binary = {'power','atan2','hypot','plus','times','minus','rdivide'};
  for name = [unary binary]
    id = numel (math.blocks) + 1;
    math.blocks(id) = struct ('type', 'Function', 'name', name{1}, 'value', [], 'x', 0.5, 'y', 0.5);
    math.edges(end + 1, :) = [1 1 id 1];
    if (any (strcmp (name{1}, binary))), math.edges(end + 1, :) = [2 1 id 2]; endif
  endfor
  add_case ('builtin_math', math, [0 1 0.5]);
  function_state = ob_oscillator ();
  function_state.blocks(1).type = 'Time'; function_state.blocks(1).value = [];
  function_state.blocks(2).type = 'Function'; function_state.blocks(2).name = 'sin';
  function_state.blocks(3).type = 'Integrator'; function_state.blocks(3).value = 0;
  function_state.edges = [1 2; 2 3; 3 4];
  add_case ('function_dynamics', function_state, [0 3 0.1]);

  child = ob_subsystem_template ();
  child.blocks(2).type = 'Inport'; child.blocks(2).value = 2;
  child.blocks(3).type = 'Function'; child.blocks(3).name = 'power'; child.blocks(3).value = [];
  child.blocks(4) = child.blocks(1); child.blocks(4).type = 'Outport'; child.blocks(4).value = 1;
  child.blocks(5) = child.blocks(4); child.blocks(5).value = 2;
  child.edges = [2 1 3 2; 1 1 3 1; 3 1 4 1; 1 1 5 1];
  multi = ob_oscillator ();
  multi.blocks(1).type = multi.blocks(2).type = 'Constant';
  multi.blocks(1).value = 2; multi.blocks(2).value = 3;
  multi.blocks(3).type = 'Subsystem'; multi.blocks(3).value = child;
  multi.blocks(5) = multi.blocks(4);
  multi.edges = [3 2 5 1; 2 1 3 2; 3 1 4 1; 1 1 3 1];
  add_case ('multiple_ports', multi, [0 1 0.5]);

  % Nonlinear control primitives: exact boundaries, shapes, branch order, and
  % smooth feedback. Unknown interior crossings are not treated as events.
  control = control_unary ('Saturation', [0.25 0.75], 0);
  control.blocks(1).type = 'Time'; control.blocks(1).value = [];
  add_case ('control_saturation_scalar', control, [0 1 0.25]);
  control.blocks(2).type = 'Dead Zone';
  add_case ('control_deadzone_scalar', control, [0 1 0.25]);
  control = control_unary ('Saturation', [-1 2], [-3 -1 0; 1 2 4]);
  add_case ('control_saturation_matrix', control, [0 1 0.5]);
  control.blocks(2).type = 'Dead Zone';
  add_case ('control_deadzone_matrix', control, [0 1 0.5]);
  control.blocks(2).value = [0 0];
  add_case ('control_deadzone_equal_limits', control, [0 1 0.5]);
  control.blocks(2).type = 'Saturation'; control.blocks(2).value = [2 2];
  add_case ('control_saturation_equal_limits', control, [0 1 0.5]);
  control = control_switch (42, -7, 0, 0.5);
  control.blocks(2).type = 'Time'; control.blocks(2).value = [];
  add_case ('control_switch_threshold', control, [0 1 0.25]);
  control = control_switch ([11 12;13 14], [-11 -12;-13 -14], [-1 0;1 -1], 0);
  add_case ('control_switch_matrix', control, [0 1 0.5]);
  control.blocks(2).value = 0;
  add_case ('control_switch_scalar_mask', control, [0 1 0.5]);
  initial = [2 0.5; -0.25 -2];
  add_case ('control_saturation_feedback', control_feedback('Saturation', initial), [0 0.5 0.05]);
  add_case ('control_deadzone_feedback', control_feedback('Dead Zone', initial), [0 0.5 0.05]);
  feedback = control_switch (0, zeros(size(initial)), 1, 0);
  feedback.blocks(1).type = 'Integrator'; feedback.blocks(1).value = initial;
  feedback.blocks(5).type = 'Gain'; feedback.blocks(5).value = -1;
  feedback.blocks(6) = feedback.blocks(5); feedback.blocks(6).type = 'Scope'; feedback.blocks(6).value = [];
  feedback.edges = [1 1 5 1; 5 1 4 1; 2 1 4 2; 3 1 4 3; 4 1 1 1; 1 1 6 1];
  add_case ('control_switch_feedback', feedback, [0 0.5 0.05]);
  signed_zero = control_unary ('Saturation', [0 1], -0.0);
  signed_zero.blocks(4) = signed_zero.blocks(3);
  signed_zero.blocks(3).type = 'Function'; signed_zero.blocks(3).name = 'atan2';
  signed_zero.blocks(5) = signed_zero.blocks(1); signed_zero.blocks(5).value = -1;
  signed_zero.edges = [1 1 2 1; 2 1 3 1; 5 1 3 2; 3 1 4 1];
  add_case ('control_saturation_signed_zero', signed_zero, [0 1 0.5]);
  add_case ('control_demo', ob_control_example (), [0 4 0.5]);
  control = ob_oscillator ();
  control.blocks(1).type = 'Inport'; control.blocks(1).value = 1;
  control.blocks(2).type = 'Subsystem'; control.blocks(2).value = ob_subsystem_template ();
  control.blocks(2).value.blocks(2).type = 'Saturation'; control.blocks(2).value.blocks(2).value = [-1 1];
  control.blocks(3).type = 'Rate Transition'; control.blocks(3).value = 0;
  control.blocks(4).type = 'Integrator'; control.blocks(4).value = 0;
  control.blocks(5) = control.blocks(4); control.blocks(5).type = 'Scope'; control.blocks(5).value = [];
  control.edges = [1 2;2 3;3 4;4 5];
  control.inputs = {ob_input_signal([0 0.25 0.5 0.75 1], [-2;-1;0;1;2])};
  control.sample_times = [0 0;0 0;0.25 0;0 0;0 0];
  add_case ('control_nested_multirate', control, [0 1 0.1]);

  % Independent clocks must be honored between sparse caller output times.
  rate = ob_multirate_example ();
  add_case ('multirate_hold', rate, [0 1 0.5]);
  inherited_rate = rmfield (rate, 'sample_times');
  add_case ('multirate_inherited_hold', inherited_rate, [0 1 0.3]);
  sampled = ob_example ();
  sampled.blocks(2).type = 'Unit Delay'; sampled.blocks(2).value = -1;
  sampled.sample_times = [0 0; 0.25 0; 0 0];
  add_case ('multirate_delay', sampled, [0 1.1 0.49]);
  sampled.blocks(2).type = 'Rate Transition'; sampled.sample_times(2, :) = [0.1 0];
  add_case ('multirate_origin', sampled, [-0.3 0.3 0.3]);
  sampled.sample_times(2, :) = [1e-10 1e-16];
  add_case ('multirate_tiny', sampled, [0 2e-16 5e-17]);
  sampled.sample_times(2, :) = [0.1 eps(1)];
  add_case ('multirate_tiny_offset', sampled, [1 1.05 0.05]);
  sampled.blocks(1).type = 'Constant'; sampled.blocks(1).value = 2;
  sampled.blocks(2).type = 'Discrete Integrator'; sampled.blocks(2).value = 5;
  sampled.sample_times(2, :) = [0.3 0.1];
  add_case ('multirate_euler', sampled, [10 11 0.3]);
  sampled.blocks(1).value = [1 2; 3 4]; sampled.blocks(2).value = zeros(2);
  sampled.sample_times(2, :) = [0.2 0.05];
  add_case ('multirate_matrix', sampled, [0 1 0.3]);
  cross = ob_oscillator ();
  cross.blocks(1).type = cross.blocks(2).type = 'Unit Delay';
  cross.blocks(1).value = 1; cross.blocks(2).value = 2;
  cross.blocks(3).type = cross.blocks(4).type = 'Scope';
  cross.edges = [2 1; 1 2; 1 3; 2 4];
  cross.sample_times = [0.5 0; 1 0; 0 0; 0 0];
  add_case ('multirate_feedback', cross, [0 2 0.5]);
  cross.sample_times(1, :) = [0 0];
  add_case ('multirate_collision', cross, [0 2 0.5]);
  cascade = ob_oscillator ();
  cascade.blocks(1).type = 'Time'; cascade.blocks(1).value = [];
  cascade.blocks(2).type = cascade.blocks(3).type = 'Rate Transition';
  cascade.blocks(2).value = -1; cascade.blocks(3).value = -2;
  cascade.edges = [1 2; 2 3; 3 4];
  cascade.sample_times = [0 0; 0.1 0; 0.3 0; 0 0];
  add_case ('multirate_decimal', cascade, [0 0.6 0.3]);
  child = ob_subsystem_template ();
  child.blocks(2).type = 'Rate Transition'; child.blocks(2).value = 0;
  child.sample_times = [0 0; 0.25 0; 0 0];
  nested_rate = ob_example ();
  nested_rate.blocks(2).type = 'Subsystem'; nested_rate.blocks(2).value = child;
  add_case ('multirate_nested', nested_rate, [0 1 0.3]);
  input_rate = rate;
  input_rate.blocks(1).type = 'Inport'; input_rate.blocks(1).value = 1;
  input_rate.sample_times(2, :) = [0.1 0];
  input_rate.inputs = {ob_input_signal([0 0.3 3*0.1 0.5], [0; 1; 2; 2])};
  add_case ('multirate_near_knots', input_rate, [0 0.5 0.5]);

  rate_api = {'#include <assert.h>', '#include <stdio.h>', '#include "multirate_near_knots.c"', ...
    'typedef struct { int fail; } rate_user;', ...
    'static int forcing(double time, int left, double *out, size_t count, void *user) {', ...
    '  rate_user *data = (rate_user *)user; (void)left;', ...
    '  if (count != 1 || (data->fail && time > 0.2)) return 1;', ...
    '  out[0] = 2.0; return OB_OK;', '}', ...
    'int main(void) {', '  ob_model model, saved; rate_user data = {1};', ...
    '  assert(ob_model_init_inputs(&model, 0.0, forcing, NULL, &data) == OB_OK);', ...
    '  saved = model;', ...
    '  assert(ob_model_step(&model, 0.5) == OB_INPUT_ERROR);', ...
    '  assert(memcmp(&model, &saved, sizeof(model)) == 0);', ...
    '  data.fail = 0;', ...
    '  assert(ob_model_step(&model, 0.5) == OB_OK);', ...
    '  assert(fabs(model.value[ob_block_offset[3]] - 1.0) < 1e-12);', ...
    '  assert(ob_sample_period[1] == 0.1);', ...
    '  puts("C multirate callback rollback tests passed");', '  return 0;', '}'};
  write_text (fullfile(directory, 'multirate_api.c'), strjoin(rate_api, char(10)));
  cases(end + 1) = struct ('name','multirate_api','source','multirate_api.c','standalone',false,'expected','');

  input = ob_input_example ();
  input.inputs = {ob_input_signal([0; 0.35; 1], [0; 1; 0], [1 1], 'zoh')};
  add_case ('input_zoh', input, [0 1 0.3]);
  input.inputs{1}.method = 'linear';
  add_case ('input_linear', input, [0 1 0.3]);
  input.inputs = {ob_input_signal([-0.2; 0.4; 1.2], [1 3 2 4; 2 6 4 8; -1 -3 -2 -4], [2 2], 'linear')};
  input.blocks(2).value = zeros (2);
  add_case ('input_matrix', input, [0 1 0.3]);
  input = ob_input_example ();
  input.blocks(2).type = 'Subsystem';
  input.blocks(2).value = ob_subsystem_template ();
  input.blocks(2).value.blocks(2).type = 'Integrator';
  input.blocks(2).value.blocks(2).value = 0;
  add_case ('input_nested', input, [0 1.5 0.3]);
  input.blocks(2).type = 'Unit Delay'; input.blocks(2).value = 0;
  add_case ('input_discrete', input, [0 1.5 0.3]);
  input = ob_oscillator ();
  input.blocks(1).type = input.blocks(2).type = 'Inport';
  input.blocks(1).value = 1; input.blocks(2).value = 2;
  input.blocks(3).type = 'Sum'; input.blocks(3).value = [];
  input.edges = [1 3; 2 3; 3 4];
  input.inputs = {ob_input_signal([0; 1], [1 2 3; 2 4 6], [1 3], 'linear'), ...
                  ob_input_signal([0.2; 0.7], [10 20; 20 40], [2 1], 'zoh')};
  add_case ('input_multiple_ports', input, [0 1 0.3]);
  input = ob_input_example ();
  input.inputs = {ob_input_signal(0, 3, [1 1], 'linear')};
  add_case ('input_single_sample', input, [0 1 0.3]);
  input.blocks = input.blocks([1 3]); input.edges = [1 2];
  input.inputs = {ob_input_signal([0;1], [realmax; -realmax], [1 1], 'linear')};
  add_case ('input_finite_extremes', input, [0 1 0.5]);

  % Numbered builtin outputs carry different static shapes and first-tie indices.
  multi_inputs = {-7, [-4 -2 -2 -6], [-2;-3;-3;5], [3 1 -2;3 4 -2]};
  multi_labels = {'scalar','row','column','matrix'};
  for name = {'size','max','min'}
    for k = 1:numel(multi_inputs)
      add_case (['multi_' name{1} '_' multi_labels{k}], ...
        multi_builtin(name{1},multi_inputs{k}), [0 1 0.3]);
    endfor
    for port = 1:2
      add_case (sprintf('multi_%s_feedback_%d',name{1},port), ...
        multi_builtin_feedback(name{1},port), [0 4 1]);
    endfor
    nested_multi = multi_builtin (name{1},[3 1 -2;3 4 -2]);
    child_multi = multi_builtin (name{1},1);
    child_multi.blocks(1).type = 'Inport';
    child_multi.blocks(3).type = child_multi.blocks(4).type = 'Outport';
    child_multi.blocks(3).value = 1; child_multi.blocks(4).value = 2;
    nested_multi.blocks(2).type = 'Subsystem'; nested_multi.blocks(2).value = child_multi;
    nested_multi.blocks(2).outputs = [];
    add_case (['multi_' name{1} '_virtual'],nested_multi,[0 1 0.3]);

    [first,second] = builtin (name{1},nested_multi.blocks(1).value);
    child_multi.execution = struct ('mode','enabled', ...
      'initial_outputs',{{-ones(size(first)),-ones(size(second))}});
    nested_multi.blocks(2).value = child_multi;
    nested_multi.blocks(5) = nested_multi.blocks(1);
    nested_multi.blocks(5).type = 'Step'; nested_multi.blocks(5).value = [1 0 1];
    nested_multi.edges(end+1,:) = [5 1 2 2];
    nested_multi.sample_times = zeros (5,2); nested_multi.sample_times(2,:) = [0.5 0];
    add_case (['multi_' name{1} '_conditional'],nested_multi,[0 2 0.25]);
  endfor
  % atan2 exposes the sign of an extremum when a zero tie selects its first input.
  for name = {'max','min'}
    signed = multi_builtin (name{1},[-0.0 0.0]);
    signed.blocks(5) = signed.blocks(1); signed.blocks(5).value = -1;
    signed.blocks(6) = signed.blocks(2); signed.blocks(6).name = 'atan2'; signed.blocks(6).outputs = [];
    signed.blocks(7) = signed.blocks(3);
    signed.edges = [signed.edges;2 1 6 1;5 1 6 2;6 1 7 1];
    assert (ob_run(signed,0).values{1,7} == -pi);
    add_case (['multi_' name{1} '_signed_zero'],signed,[0 1 0.3]);
  endfor

  % A dormant child must not evaluate its sqrt or either reduction output.
  masked = multi_builtin ('max',1);
  masked.blocks(1).type = 'Step'; masked.blocks(1).value = [1 -1 4];
  child_multi = multi_builtin ('max',1);
  child_multi.blocks(1).type = 'Inport';
  child_multi.blocks(3).type = child_multi.blocks(4).type = 'Outport';
  child_multi.blocks(3).value = 1; child_multi.blocks(4).value = 2;
  child_multi.blocks(5) = child_multi.blocks(2);
  child_multi.blocks(5).name = 'sqrt'; child_multi.blocks(5).outputs = [];
  child_multi.edges = [1 1 5 1;5 1 2 1;2 1 3 1;2 2 4 1];
  child_multi.execution = struct ('mode','enabled','initial_outputs',{{-9,-8}});
  masked.blocks(2).type = 'Subsystem'; masked.blocks(2).value = child_multi; masked.blocks(2).outputs = [];
  masked.blocks(5) = masked.blocks(1); masked.blocks(5).value = [1 0 1];
  masked.edges(end+1,:) = [5 1 2 2];
  add_case ('multi_masked_domain',masked,[0 2 0.5]);

  % Unsupported exports must not replace an existing source file.
  protected = fullfile (directory, 'protected.c'); write_text (protected, 'keep me');
  assert_error (@() ob_codegen (ob_function_example (), protected), 'unsupported Function');
  assert (strcmp (fileread(protected), 'keep me'));

  for name = {'test_ob_multi_function','sin'}
    invalid = multi_builtin (name{1},1);
    assert_error (@() ob_codegen(invalid,protected), 'unsupported multiple-output Function');
    assert (strcmp(fileread(protected),'keep me'));
  endfor
  for name = {'size','max','min'}
    invalid = multi_builtin (name{1},1); invalid.blocks(2).outputs = 3;
    assert_error (@() ob_codegen(invalid,protected), 'needs one input and exactly two outputs');
    invalid = multi_builtin (name{1},1);
    invalid.blocks(5) = invalid.blocks(1); invalid.edges(end+1,:) = [5 1 2 2];
    assert_error (@() ob_codegen(invalid,protected), 'needs one input and exactly two outputs');
    assert (strcmp(fileread(protected),'keep me'));
  endfor

  invalid = control_unary ('Saturation', [2 1], 0);
  assert_error (@() ob_codegen (invalid, protected), 'ordered [lower upper]');
  invalid = control_unary ('Dead Zone', [0 Inf], 0);
  assert_error (@() ob_codegen (invalid, protected), 'finite real numeric value');
  invalid = control_switch (ones(2), 0, 1, 0);
  assert_error (@() ob_codegen (invalid, protected), 'identical shapes');
  invalid = control_switch (ones(2), zeros(2), ones(1,2), 0);
  assert_error (@() ob_codegen (invalid, protected), 'scalar or match the data shape');
  invalid = control_switch (7, -7, 1, 0); invalid.edges(1, 1) = 4;
  assert_error (@() ob_codegen (invalid, protected), 'algebraic loop');
  assert (strcmp (fileread(protected), 'keep me'));
  assert_error (@() ob_codegen (ob_example (), protected, [0 1 0.1], struct('solver','ode45')), 'requires rk4');
  invalid = ob_example (); invalid.blocks(2).value = [1 2];
  invalid.blocks(1).type = 'Constant'; invalid.blocks(1).value = [1 2];
  assert_error (@() ob_codegen (invalid, protected), 'incompatible matrix multiplication');
  invalid.blocks(1).value = single (1);
  assert_error (@() ob_codegen (invalid, protected), 'real double parameter');
  invalid = step; invalid.blocks(1).type = 'Constant'; invalid.blocks(1).value = [1; 2];
  assert_error (@() ob_codegen (invalid, protected), 'state input shape');
  assert (strcmp (fileread(protected), 'keep me'));

  shadow = fullfile (directory, 'shadow'); mkdir (shadow);
  write_text (fullfile(shadow, 'sin.m'), sprintf('function y = sin(x)\n error("shadow function must not execute during export");\nendfunction\n'));
  previous_warning = warning ('query', 'Octave:shadowed-function');
  unwind_protect
    warning ('off', 'Octave:shadowed-function'); addpath (shadow); clear sin;
    invalid = ob_example (); invalid.blocks(2).type = 'Function'; invalid.blocks(2).name = 'sin';
    assert_error (@() ob_codegen (invalid, protected), 'shadowed or is not');
    assert (strcmp (fileread(protected), 'keep me'));
  unwind_protect_cleanup
    rmpath (shadow); clear sin;
    warning (previous_warning.state, previous_warning.identifier);
  end_unwind_protect
  for name = {'size','max','min'}
    write_text (fullfile(shadow,[name{1} '.m']), sprintf ( ...
      'function varargout = %s(varargin)\n [varargout{1:nargout}] = builtin("%s",varargin{:});\nendfunction\n', ...
      name{1},name{1}));
  endfor
  unwind_protect
    warning ('off','Octave:shadowed-function'); addpath (shadow); clear size max min;
    for name = {'size','max','min'}
      invalid = multi_builtin (name{1},1);
      assert_error (@() ob_codegen(invalid,protected), 'shadowed or is not');
      assert (strcmp(fileread(protected),'keep me'));
    endfor
  unwind_protect_cleanup
    rmpath (shadow); clear size max min;
    warning (previous_warning.state,previous_warning.identifier);
  end_unwind_protect
  loop = ob_example (); loop.edges = [2 2; 2 3];
  assert_error (@() ob_codegen (loop, protected), 'algebraic loop');
  assert (strcmp (fileread(protected), 'keep me'));

  % Exercise the public C API independently of the CSV main program.
  api = {'#include <assert.h>', '#include <stdio.h>', '#include "nested.c"', ...
    'int main(void) {', '  ob_model a, b, saved;', ...
    '  assert(ob_model_init(&a, 0.0) == OB_OK);', ...
    '  assert(ob_model_init(&b, 0.0) == OB_OK);', ...
    '  assert(ob_model_step(&a, 0.1) == OB_OK);', '  assert(b.time == 0.0);', ...
    '  saved = a;', '  assert(ob_model_step(&a, 0.1) == OB_BAD_ARGUMENT);', ...
    '  assert(memcmp(&a, &saved, sizeof(a)) == 0);', ...
    '  assert(ob_model_step(&a, NAN) == OB_BAD_ARGUMENT);', ...
    '  assert(ob_model_init(&a, INFINITY) == OB_BAD_ARGUMENT);', ...
    '  assert(memcmp(&a, &saved, sizeof(a)) == 0);', ...
    '  assert(ob_model_init(NULL, 0.0) == OB_BAD_ARGUMENT);', ...
    '  assert(ob_model_outputs(NULL) == OB_BAD_ARGUMENT);', ...
    '  assert(strcmp(ob_block_path[0], "1/1") == 0);', ...
    '  puts("C API tests passed");', '  return 0;', '}'};
  write_text (fullfile(directory, 'api.c'), strjoin(api, char(10)));
  cases(end + 1) = struct ('name','api','source','api.c','standalone',false,'expected','');
  domain = ob_example ();
  domain.blocks(1).type = 'Constant'; domain.blocks(1).value = -1;
  domain.blocks(2).type = 'Function'; domain.blocks(2).name = 'power';
  domain.blocks(4) = domain.blocks(1); domain.blocks(4).type = 'Time'; domain.blocks(4).value = [];
  domain.edges = [1 1 2 1; 4 1 2 2; 2 1 3 1];
  ob_codegen (domain, fullfile(directory, 'domain.c'));
  failure = {'#include <assert.h>', '#include <stdio.h>', '#include "domain.c"', ...
    'int main(void) {', '  ob_model model, saved;', ...
    '  assert(ob_model_init(&model, 0.0) == OB_OK);', '  saved = model;', ...
    '  assert(ob_model_step(&model, 0.5) == OB_NONFINITE);', ...
    '  assert(memcmp(&model, &saved, sizeof(model)) == 0);', ...
    '  puts("C runtime failure tests passed");', '  return 0;', '}'};
  write_text (fullfile(directory, 'api_failure.c'), strjoin(failure, char(10)));
  cases(end + 1) = struct ('name','api_failure','source','api_failure.c','standalone',false,'expected','');
  input_api = {'#include <assert.h>', '#include <stdio.h>', '#include "input_zoh.c"', ...
    'typedef struct { int fail; int nonfinite; int bad_event; } provider_data;', ...
    'static int forcing(double time, int left, double *out, size_t count, void *user) {', ...
    '  provider_data *data = (provider_data *)user;', ...
    '  if (count != 1 || data->fail == 1 || (data->fail == 2 && time > 0.1)) return 17;', ...
    '  out[0] = data->nonfinite ? NAN : ((time < 0.35 || (left && time == 0.35)) ? 2.0 : 4.0);', ...
    '  return OB_OK;', '}', ...
    'static double boundary(double after, double before, void *user) {', ...
    '  provider_data *data = (provider_data *)user;', ...
    '  if (data->bad_event == 1) return after;', ...
    '  if (data->bad_event == 2) return NAN;', ...
    '  if (data->bad_event == 3) return before + 1.0;', ...
    '  return after < 0.35 && 0.35 < before ? 0.35 : before;', '}', ...
    'static int ramp(double time, int left, double *out, size_t count, void *user) {', ...
    '  (void)left; (void)user; if (count != 1) return 1; out[0] = time; return OB_OK;', '}', ...
    'static int failing(double time, int left, double *out, size_t count, void *user) {', ...
    '  (void)time; (void)left; (void)out; (void)count; (void)user; return 1;', '}', ...
    'static int incomplete(double time, int left, double *out, size_t count, void *user) {', ...
    '  (void)time; (void)left; (void)out; (void)count; (void)user; return OB_OK;', '}', ...
    'int main(void) {', '  ob_model model, saved, other;', '  provider_data data = {0, 0, 0};', ...
    '  assert(OB_INPUT_PORT_COUNT == 1 && OB_INPUT_VALUE_COUNT == 1);', ...
    '  assert(ob_input_offset[0] == 0 && ob_input_rows[0] == 1 && ob_input_cols[0] == 1);', ...
    '  assert(ob_model_init_inputs(&model, 0.0, forcing, boundary, &data) == OB_OK);', ...
    '  assert(ob_model_init(&other, 0.0) == OB_OK);', ...
    '  assert(ob_model_step(&model, 1.0) == OB_OK);', ...
    '  assert(fabs(model.state[0] - 3.3) < 1e-12);', ...
    '  assert(ob_model_step(&other, 1.0) == OB_OK);', ...
    '  assert(fabs(other.state[0] - 0.65) < 1e-12);', '  saved = model;', ...
    '  data.fail = 1;', '  assert(ob_model_step(&model, 1.1) == OB_INPUT_ERROR);', ...
    '  assert(memcmp(&model, &saved, sizeof(model)) == 0);', '  data.fail = 0;', ...
    '  data.nonfinite = 1;', '  assert(ob_model_step(&model, 1.1) == OB_NONFINITE);', ...
    '  assert(memcmp(&model, &saved, sizeof(model)) == 0);', '  data.nonfinite = 0;', ...
    '  for (int mode = 1; mode <= 3; ++mode) {', '    data.bad_event = mode;', ...
    '    assert(ob_model_step(&model, 1.1) == OB_INPUT_ERROR);', ...
    '    assert(memcmp(&model, &saved, sizeof(model)) == 0);', '  }', '  data.bad_event = 0;', ...
    '  assert(ob_model_set_input_provider(&model, failing, NULL, NULL) == OB_INPUT_ERROR);', ...
    '  assert(memcmp(&model, &saved, sizeof(model)) == 0);', ...
    '  assert(ob_model_init_inputs(&model, 0.0, failing, NULL, NULL) == OB_INPUT_ERROR);', ...
    '  assert(memcmp(&model, &saved, sizeof(model)) == 0);', ...
    '  assert(ob_model_set_input_provider(&model, incomplete, NULL, NULL) == OB_NONFINITE);', ...
    '  assert(memcmp(&model, &saved, sizeof(model)) == 0);', ...
    '  assert(ob_model_set_input_provider(&model, NULL, boundary, &data) == OB_BAD_ARGUMENT);', ...
    '  assert(ob_model_set_input_provider(&model, NULL, NULL, NULL) == OB_OK);', ...
    '  assert(ob_model_step(&model, 1.1) == OB_OK);', ...
    '  assert(fabs(model.state[0] - 3.3) < 1e-12);', ...
    '  data.fail = 2;', ...
    '  assert(ob_model_init_inputs(&other, 0.0, forcing, boundary, &data) == OB_OK);', ...
    '  saved = other;', '  assert(ob_model_step(&other, 1.0) == OB_INPUT_ERROR);', ...
    '  assert(memcmp(&other, &saved, sizeof(other)) == 0);', '  data.fail = 0;', ...
    '  assert(ob_model_init_inputs(&other, 0.0, ramp, NULL, NULL) == OB_OK);', ...
    '  assert(ob_model_step(&other, 1.0) == OB_OK);', ...
    '  assert(fabs(other.state[0] - 0.5) < 1e-12);', ...
    '  puts("C external input API tests passed");', '  return 0;', '}'};
  write_text (fullfile(directory, 'api_inputs.c'), strjoin(input_api, char(10)));
  cases(end + 1) = struct ('name','api_inputs','source','api_inputs.c','standalone',false,'expected','');
  packed_api = {'#include <assert.h>', '#include <stdio.h>', '#include "input_multiple_ports.c"', ...
    'static int packed(double time, int left, double *out, size_t count, void *user) {', ...
    '  (void)time; (void)left; (void)user; if (count != 5) return 1;', ...
    '  out[0] = 2.0; out[1] = 4.0; out[2] = 6.0; out[3] = 100.0; out[4] = 200.0; return OB_OK;', '}', ...
    'int main(void) {', '  ob_model model;', ...
    '  const double expected[6] = {102.0, 202.0, 104.0, 204.0, 106.0, 206.0};', ...
    '  assert(OB_INPUT_PORT_COUNT == 2 && OB_INPUT_VALUE_COUNT == 5);', ...
    '  assert(ob_input_offset[0] == 0 && ob_input_offset[1] == 3);', ...
    '  assert(ob_input_rows[0] == 1 && ob_input_cols[0] == 3);', ...
    '  assert(ob_input_rows[1] == 2 && ob_input_cols[1] == 1);', ...
    '  assert(ob_model_init_inputs(&model, 0.0, packed, NULL, NULL) == OB_OK);', ...
    '  for (size_t i = 0; i < 6; ++i) assert(model.value[ob_block_offset[3]+i] == expected[i]);', ...
    '  assert(ob_model_step(&model, 0.5) == OB_OK);', ...
    '  for (size_t i = 0; i < 6; ++i) assert(model.value[ob_block_offset[3]+i] == expected[i]);', ...
    '  puts("C packed multi-port input tests passed");', '  return 0;', '}'};
  write_text (fullfile(directory, 'api_packed_inputs.c'), strjoin(packed_api, char(10)));
  cases(end + 1) = struct ('name','api_packed_inputs','source','api_packed_inputs.c','standalone',false,'expected','');
  % Runtime arithmetic overflow must fail without committing the C context.
  overflow = control_unary ('Dead Zone', [-realmax -realmax], 0);
  overflow.blocks(1).type = 'Time'; overflow.blocks(1).value = [];
  ob_codegen (overflow, fullfile(directory, 'control_overflow.c'));
  overflow_api = {'#include <assert.h>', '#include <float.h>', '#include <stdio.h>', '#include "control_overflow.c"', ...
    'int main(void) {', '  ob_model model, saved;', ...
    '  assert(ob_model_init(&model, 0.0) == OB_OK);', '  saved = model;', ...
    '  assert(ob_model_step(&model, DBL_MAX) == OB_NONFINITE);', ...
    '  assert(memcmp(&model, &saved, sizeof(model)) == 0);', ...
    '  assert(ob_model_init(&model, DBL_MAX) == OB_NONFINITE);', ...
    '  assert(memcmp(&model, &saved, sizeof(model)) == 0);', ...
    '  puts("C control overflow rollback tests passed");', '  return 0;', '}'};
  write_text (fullfile(directory, 'api_control_overflow.c'), strjoin(overflow_api, char(10)));
  cases(end + 1) = struct ('name','api_control_overflow','source','api_control_overflow.c','standalone',false,'expected','');
  conditional_api = {'#include <assert.h>', '#include <stdio.h>', '#include "conditional_host_nested.c"', ...
    'typedef struct { double data; double control; int fail; } supplied_input;', ...
    'static int supplied(double time, int left, double *out, size_t count, void *user) {', ...
    '  supplied_input *input = (supplied_input *)user;', ...
    '  (void)time; (void)left;', ...
    '  if (count != 2 || input->fail) return 1;', ...
    '  out[0] = input->data; out[1] = input->control; return OB_OK;', '}', ...
    'static size_t output_index(void) {', ...
    '  for (size_t b = 0; b < OB_BLOCK_COUNT; ++b)', ...
    '    if (strcmp(ob_block_path[b], "4") == 0) return ob_block_offset[b];', ...
    '  assert(0); return 0;', '}', ...
    'int main(void) {', '  ob_model model, other, saved;', ...
    '  supplied_input input = {-1.0, 0.0, 0};', ...
    '  supplied_input other_input = {-1.0, 0.0, 0};', ...
    '  size_t output = output_index();', ...
    '  assert(OB_INPUT_PORT_COUNT == 2 && OB_INPUT_VALUE_COUNT == 2);', ...
    '  assert(ob_model_init_inputs(&model, 0.0, supplied, NULL, &input) == OB_OK);', ...
    '  assert(model.value[output] == -1.0);', ...
    '  assert(ob_model_init_inputs(&other, 0.0, supplied, NULL, &other_input) == OB_OK);', ...
    '  input.data = 4.0; input.control = 1.0;', ...
    '  assert(ob_model_step(&model, 1.0) == OB_OK);', ...
    '  assert(model.value[output] == 2.0);', ...
    '  assert(other.time == 0.0 && other.value[output] == -1.0);', ...
    '  saved = model; input.data = -1.0;', ...
    '  assert(ob_model_step(&model, 2.0) == OB_NONFINITE);', ...
    '  assert(memcmp(&model, &saved, sizeof(model)) == 0);', ...
    '  assert(ob_model_step(&model, 1.5) == OB_OK);', ...
    '  assert(model.value[output] == 2.0);', ...
    '  input.data = 9.0;', ...
    '  assert(ob_model_step(&model, 2.0) == OB_OK);', ...
    '  assert(model.value[output] == 7.0);', ...
    '  saved = model; input.fail = 1;', ...
    '  assert(ob_model_step(&model, 3.0) == OB_INPUT_ERROR);', ...
    '  assert(memcmp(&model, &saved, sizeof(model)) == 0);', ...
    '  input.fail = 0;', ...
    '  assert(ob_model_step(&model, 3.0) == OB_OK);', ...
    '  assert(model.value[output] == 12.0);', ...
    '  other_input.data = 16.0; other_input.control = 1.0;', ...
    '  assert(ob_model_step(&other, 2.0) == OB_OK);', ...
    '  assert(other.value[output] == 20.0);', ...
    '  assert(model.time == 3.0 && model.value[output] == 12.0);', ...
    '  puts("C nested conditional input/rollback tests passed");', '  return 0;', '}'};
  write_text (fullfile(directory, 'api_conditional.c'), strjoin(conditional_api,char(10)));
  cases(end+1) = struct ('name','api_conditional','source','api_conditional.c','standalone',false,'expected','');
  pause_api = {'#include <assert.h>', '#include <stdio.h>', '#include "conditional_enabled_euler_pause.c"', ...
    'static size_t output_index(void) {', ...
    '  for (size_t b = 0; b < OB_BLOCK_COUNT; ++b)', ...
    '    if (strcmp(ob_block_path[b], "4") == 0) return ob_block_offset[b];', ...
    '  assert(0); return 0;', '}', ...
    'int main(void) {', '  ob_model model;', '  size_t output = output_index();', ...
    '  assert(ob_model_init(&model, 0.0) == OB_OK);', '  assert(model.value[output] == 0.0);', ...
    '  assert(ob_model_step(&model, 0.25) == OB_OK);', '  assert(model.value[output] == 0.0);', ...
    '  assert(ob_model_step(&model, 2.0) == OB_OK);', '  assert(model.value[output] == 0.0);', ...
    '  assert(ob_model_step(&model, 4.0) == OB_OK);', '  assert(model.value[output] == 0.25);', ...
    '  assert(ob_model_step(&model, 6.0) == OB_OK);', '  assert(model.value[output] == 2.25);', ...
    '  puts("C enabled Euler irregular pause tests passed");', '  return 0;', '}'};
  write_text (fullfile(directory, 'api_conditional_pause.c'), strjoin(pause_api,char(10)));
  cases(end+1) = struct ('name','api_conditional_pause','source','api_conditional_pause.c','standalone',false,'expected','');
  continuous_api={'#include <assert.h>','#include <stdio.h>','#include "continuous_enabled_host.c"', ...
    'typedef struct {int mode;} input_data;', ...
    'static int provider(double time,int left,double *out,size_t count,void *user){', ...
    '  input_data *data=(input_data*)user;if(count!=2)return 1;', ...
    '  if(data->mode==2&&time>0.3)return 17;', ...
    '  out[0]=4.0;out[1]=1.0;', ...
    '  if(data->mode==1&&time>0.3)out[0]=-1.0;', ...
    '  if(data->mode==3&&time>0.3)out[0]=NAN;', ...
    '  if(data->mode==4)out[0]=(time<0.35||(left&&time==0.35))?4.0:9.0;', ...
    '  return OB_OK;}', ...
    'static double event(double after,double before,void *user){', ...
    '  (void)user;return after<0.35&&0.35<before?0.35:before;}', ...
    'int main(void){ob_model model,other,saved;input_data data={0};', ...
    '  const size_t output=ob_block_offset[4];', ...
    '  assert(OB_CONTINUOUS_COUNT==1);', ...
    '  assert(ob_model_init_inputs(&model,0.0,provider,NULL,&data)==OB_OK);', ...
    '  assert(ob_model_init(&other,0.0)==OB_OK);', ...
    '  assert(ob_model_step(&model,0.25)==OB_OK);', ...
    '  assert(fabs(model.value[output]-0.5)<1e-12);assert(other.time==0.0);saved=model;', ...
    '  for(int mode=1;mode<=3;++mode){data.mode=mode;', ...
    '    assert(ob_model_step(&model,0.75)==(mode==2?OB_INPUT_ERROR:OB_NONFINITE));', ...
    '    assert(memcmp(&model,&saved,sizeof(model))==0);}', ...
    '  data.mode=0;assert(ob_model_outputs(&model)==OB_OK);', ...
    '  assert(memcmp(&model,&saved,sizeof(model))==0);', ...
    '  assert(ob_model_step(&model,0.3)==OB_OK);assert(fabs(model.value[output]-0.6)<1e-12);', ...
    '  data.mode=4;assert(ob_model_init_inputs(&model,0.0,provider,event,&data)==OB_OK);', ...
    '  assert(ob_model_step(&model,1.0)==OB_OK);assert(fabs(model.value[output]-2.65)<1e-12);', ...
    '  assert(ob_model_step(&other,1.0)==OB_OK);assert(fabs(other.value[output]-2.0)<1e-12);', ...
    '  puts("C continuous enabled shared-stage and rollback tests passed");return 0;}'};
  write_text(fullfile(directory,'api_continuous.c'),strjoin(continuous_api,char(10)));
  cases(end+1)=struct('name','api_continuous','source','api_continuous.c','standalone',false,'expected','');
  write_text(fullfile(directory,inner_api.source),inner_api.text);
  cases(end+1)=struct('name',inner_api.name,'source',inner_api.source,'standalone',false,'expected','');
  write_text (fullfile(directory, 'manifest.json'), jsonencode(cases));
  fprintf ('Prepared %d C compilation cases and validated export rejection paths\n', numel(cases));

  function add_case (name, model, config)
    source = [name '.c']; expected_file = [name '.expected.csv'];
    if (conditional_references_only)
      result = ob_run (model, ob_time_grid(config(1),config(2),config(3)));
      for block = 1:numel (result.compiled_model.blocks)
        if (strcmp (result.compiled_model.blocks(block).type, 'Conditional Subsystem')), continue; endif
        for sample = 1:numel(result.t)
          value = result.flat_values{sample,block};
          assert (isnumeric(value) && isreal(value) && all(isfinite(value(:))));
        endfor
      endfor
      return;
    endif
    info = ob_codegen (model, fullfile(directory, source), config);
    result = ob_run (model, ob_time_grid(config(1),config(2),config(3)));
    expected = result.t;
    for block = 1:numel (result.compiled_model.blocks)
      count = prod (info.shapes{block});
      if (count == 0), continue; endif
      traces = zeros (numel(result.t), count);
      for sample = 1:numel(result.t)
        value = result.flat_values{sample,block};
        assert (isnumeric(value) && isreal(value) && isequal(size(value),info.shapes{block}));
        traces(sample,:) = value(:)';
      endfor
      assert (all(isfinite(traces(:))));
      expected = [expected traces];
    endfor
    dlmwrite (fullfile(directory, expected_file), expected, 'precision', '%.17g');
    cases(end + 1) = struct ('name',name,'source',source,'standalone',true,'expected',expected_file);
  endfunction
endfunction

function model=continuous_coupled ()
  child.blocks=struct('type',{'Inport','Gain','Integrator','Outport'}, ...
    'value',{1,-1,0,1},'name',{'Parent','Negative','Child state','Output'}, ...
    'x',{.1,.35,.6,.9},'y',{.5,.5,.5,.5});
  child.edges=[1 1 2 1;2 1 3 1;3 1 4 1];
  child.execution=struct('mode','enabled','initial_outputs',{{0}});
  model.blocks=struct('type',{'Integrator','Constant','Subsystem','Scope','Scope'}, ...
    'value',{1,1,child,[],[]},'name',{'Parent','Enable','Child','x','y'}, ...
    'x',{.1,.1,.5,.9,.9},'y',{.7,.3,.5,.7,.3});
  model.edges=[1 1 3 1;2 1 3 2;3 1 1 1;1 1 4 1;3 1 5 1];
  model.sample_times=[0 0;0 0;.05 0;0 0;0 0];
endfunction

function model=continuous_mixed ()
  model=ob_enabled_continuous_example (); child=model.blocks(3).value;
  child.blocks(4)=child.blocks(1); child.blocks(4).type='Time'; child.blocks(4).value=[];
  child.blocks(5)=child.blocks(2); child.blocks(5).type='Unit Delay';
  child.blocks(6)=child.blocks(3); child.blocks(6).value=2;
  child.blocks(7)=child.blocks(2); child.blocks(7).type='Discrete Integrator';
  child.blocks(8)=child.blocks(3); child.blocks(8).value=3;
  child.edges=[ob_edges(child);4 1 5 1;5 1 6 1;4 1 7 1;7 1 8 1];
  child.execution.initial_outputs={-1,0,0}; model.blocks(3).value=child;
  model.blocks(5)=model.blocks(4); model.blocks(6)=model.blocks(4);
  model.edges=[model.edges;3 2 5 1;3 3 6 1];
  model.sample_times(5:6,:)=zeros(2);
endfunction

function model=continuous_nested ()
  model=ob_enabled_continuous_example ();
  wrapper=conditional_wrapper(model.blocks(3).value);
  wrapper.execution=struct('mode','enabled','initial_outputs',{{-9}});
  model.blocks(3).value=wrapper;
  model.blocks(5)=model.blocks(1);
  model.edges=[1 1 3 1;5 1 3 2;2 1 3 3;3 1 4 1];
  model.sample_times(5,:)=[0 0];
  model.inputs={ob_input_signal([0 1 3 5 7],[0;1;0;1;0])};
endfunction

function model = multi_builtin (name, input)
  model.blocks = struct ('type',{'Constant','Function','Scope','Scope'}, ...
    'value',{input,[],[],[]},'name',{'Input',name,'Values','Indices'}, ...
    'x',{0.1,0.4,0.9,0.9},'y',{0.5,0.5,0.7,0.3},'outputs',{[],2,[],[]});
  % Reverse the source-port order to exercise explicit routing.
  model.edges = [1 1 2 1;2 2 4 1;2 1 3 1];
endfunction

function model = multi_builtin_feedback (name, port)
  model.blocks = struct ('type',{'Unit Delay','Constant','Sum','Function','Scope','Scope'}, ...
    'value',{2,[1;3;3],[],[],[],[]},'name',{'State','Bias','Sum',name,'Values','Indices'}, ...
    'x',{0.1,0.1,0.3,0.5,0.9,0.9},'y',{0.7,0.3,0.5,0.5,0.7,0.3},'outputs',{[],[],[],2,[],[]});
  model.edges = [1 1 3 1;2 1 3 2;3 1 4 1;4 2 6 1;4 1 5 1;4 port 1 1];
endfunction

function model = conditional_wrapper (child)
  model.blocks = struct ('type',{'Inport','Inport','Subsystem','Outport'}, ...
      'value',{1,2,child,1},'name',{'Data','Control','Child','Output'}, ...
      'x',{0.1,0.1,0.5,0.9},'y',{0.7,0.3,0.5,0.5});
  model.edges = [1 1 3 1;2 1 3 2;3 1 4 1];
endfunction

function model = conditional_nested_euler (triggered)
  inner = ob_subsystem_template ();
  inner.blocks(2).type = 'Discrete Integrator'; inner.blocks(2).value = 0;
  inner.execution = struct ('mode','enabled','initial_outputs',{{-1}});
  if (! triggered)
    wrapper.blocks = struct ('type',{'Inport','Subsystem','Constant','Outport'}, ...
      'value',{1,inner,1,1},'name',{'Data','Inner','Enable','Output'}, ...
      'x',{0.1,0.5,0.1,0.9},'y',{0.7,0.5,0.3,0.5});
    wrapper.edges = [1 1 2 1;3 1 2 2;2 1 4 1];
  else
    inner.blocks(1).type = 'Constant'; inner.blocks(1).value = 1;
    inner.execution.mode = 'rising';
    wrapper.blocks = struct ('type',{'Inport','Subsystem','Outport'}, ...
      'value',{1,inner,1},'name',{'Control','Inner','Output'}, ...
      'x',{0.1,0.5,0.9},'y',{0.5,0.5,0.5});
    wrapper.edges = [1 1 2 1;2 1 3 1];
  endif
  wrapper.execution = struct ('mode','enabled','initial_outputs',{{-1}});
  model = ob_conditional_example (); model.blocks(3).value = wrapper;
  if (! triggered)
    model.blocks(1).type = 'Constant'; model.blocks(1).value = 1;
  else
    model.blocks(1).type = 'Inport'; model.blocks(1).value = 1;
    model.blocks(2).value = 2;
    model.inputs = {ob_input_signal(0:6,[0;1;0;0;0;1;1]), ...
                    ob_input_signal(0:6,[0;1;1;0;0;1;1])};
  endif
endfunction

function model = conditional_host_model ()
  child.blocks = struct ('type',{'Inport','Unit Delay','Function','Sum','Outport'}, ...
      'value',{1,0,[],[],1},'name',{'Data','Delay','sqrt','Sum','Output'}, ...
      'x',{0.1,0.35,0.35,0.65,0.9},'y',{0.5,0.7,0.3,0.5,0.5});
  child.edges = [1 1 2 1;1 1 3 1;2 1 4 1;3 1 4 2;4 1 5 1];
  child.execution = struct ('mode','enabled','initial_outputs',{{-1}});
  wrapper = conditional_wrapper (child);
  wrapper.execution = struct ('mode','enabled','initial_outputs',{{-9}});
  model = ob_conditional_example ();
  model.blocks(1).type = 'Inport'; model.blocks(1).value = 1;
  model.blocks(2).value = 2; model.blocks(3).value = wrapper;
  model.blocks(5) = model.blocks(1); model.blocks(5).type = 'Constant'; model.blocks(5).value = 1;
  model.edges(end+1,:) = [5 1 3 3];
  model.inputs = {ob_input_signal(0:2,[-1;4;9]), ob_input_signal(0:2,[0;1;1])};
  model.sample_times = [0 0;0 0;1 0;0 0;0 0];
endfunction

function model = control_unary (type, parameter, input)
  model = ob_example ();
  model.blocks(1).type = 'Constant'; model.blocks(1).value = input;
  model.blocks(2).type = type; model.blocks(2).value = parameter;
endfunction

function model = control_switch (yes, no, control, threshold)
  model.blocks = struct ('type', {'Constant','Constant','Constant','Switch','Scope'}, ...
    'value', {yes, control, no, threshold, []}, 'name', {'True','Control','False','Switch','Scope'}, ...
    'x', {0.15,0.15,0.15,0.5,0.85}, 'y', {0.75,0.5,0.25,0.5,0.5});
  model.edges = [3 1 4 3;1 1 4 1;2 1 4 2;4 1 5 1];
endfunction

function model = control_feedback (type, initial)
  model = ob_oscillator ();
  model.blocks(1).value = initial;
  model.blocks(2).type = 'Gain'; model.blocks(2).value = -1;
  model.blocks(3).type = type; model.blocks(3).value = [-1 1];
  model.edges = [1 2;2 3;3 1;1 4];
endfunction

function write_text (file, text)
  fid = fopen (file, 'wb');
  if (fid < 0), error ('test_ob_codegen: cannot write %s', file); endif
  unwind_protect
    assert (fwrite(fid, text, 'char') == numel(text));
  unwind_protect_cleanup
    fclose (fid);
  end_unwind_protect
endfunction

function assert_error (callback, fragment)
  caught = false;
  try
    callback ();
  catch err
    caught = ! isempty (strfind (err.message, fragment));
  end_try_catch
  assert (caught);
endfunction
