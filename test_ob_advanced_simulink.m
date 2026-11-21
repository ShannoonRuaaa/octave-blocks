function cases = test_ob_advanced_simulink ()
% TEST_OB_ADVANCED_SIMULINK  Verify Simulink-referenced advanced builders.
%   Tests ob_pid_controller, ob_zero_pole, ob_discrete_state_space,
%   ob_discrete_transfer_function, ob_c2d_state_space, ob_lookup_table_1d,
%   ob_rate_limiter, ob_relay, and ob_atomic_feedthrough against exact
%   analytical solutions.

  % 1. Continuous PID with filtered derivative on unit step:
  %    e(t) = 1 => u(t) = P + I*t + D*N*exp(-N*t)
  pid = ob_pid_controller (2, 3, 0.5, 10);
  m = wrap_step_model (pid, [0 1 1]);
  t = [0:0.1:1];
  res = ob_run (m, t, struct ('solver', 'ode45', 'reltol', 1e-8, 'abstol', 1e-10));
  y = ob_scope_data (res, 3);
  expected = 2 + 3 * t(:) + 0.5 * 10 * exp (-10 * t(:));
  assert (max (abs (y - expected)) < 1e-5, 'Continuous PID analytical mismatch');

  % 2. Saturated PID with anti-windup stays bounded within limits
  pid_aw = ob_pid_controller (2, 5, 0, 100, struct ('limits', [-1 3], 'Kb', 2));
  m_aw = wrap_step_model (pid_aw, [0 1 1]);
  res_aw = ob_run (m_aw, [0:0.1:2], struct ('solver', 'rk4', 'zero_crossings', true));
  y_aw = ob_scope_data (res_aw, 3);
  assert (all (y_aw >= -1 - 1e-12 & y_aw <= 3 + 1e-12), 'PID saturation bounds violated');

  % 3. Zero-Pole SISO: H(s) = 4 / (s + 2) -> step response 2*(1 - exp(-2*t))
  zp = ob_zero_pole ([], -2, 4);
  m_zp = wrap_step_model (zp, [0 1 1]);
  res_zp = ob_run (m_zp, t, struct ('solver', 'ode45', 'reltol', 1e-8, 'abstol', 1e-10));
  y_zp = ob_scope_data (res_zp, 3);
  assert (max (abs (y_zp - 2 * (1 - exp (-2 * t(:))))) < 1e-6, 'Zero-Pole SISO mismatch');

  % 4. Discrete State-Space via ZOH discretization of x' = -2*x + 4*u, y = x
  [Ad, Bd, Cd, Dd] = ob_c2d_state_space (-2, 4, 1, 0, 0.1, 'zoh');
  dss = ob_discrete_state_space (Ad, Bd, Cd, Dd, 0.1);
  m_dss = wrap_step_model (dss, [0 1 1]);
  res_dss = ob_run (m_dss, t, struct ('solver', 'rk4'));
  y_dss = ob_scope_data (res_dss, 3);
  assert (max (abs (y_dss - 2 * (1 - exp (-2 * t(:))))) < 1e-12, 'ZOH discrete state-space mismatch');

  % 5. Discrete Transfer Function: H(z) = 1 / (z - 0.5), Ts = 0.5
  dtf = ob_discrete_transfer_function (1, [1 -0.5], 0.5);
  m_dtf = wrap_step_model (dtf, [0 1 1]);
  res_dtf = ob_run (m_dtf, [0 0.5 1.0 1.5], struct ('solver', 'rk4'));
  y_dtf = ob_scope_data (res_dtf, 3);
  assert (max (abs (y_dtf - [0; 1; 1.5; 1.75])) < 1e-12, 'Discrete TF impulse/step mismatch');

  % 6. 1-D Lookup Table (clip mode) driven by Time block on [0, 4]
  lut = ob_lookup_table_1d ([1 2 3], [10 20 15], 'clip');
  m_lut = wrap_time_model (lut);
  res_lut = ob_run (m_lut, [0 0.5 1 1.5 2 2.5 3 4], struct ('solver', 'rk4', 'zero_crossings', true));
  y_lut = ob_scope_data (res_lut, 3);
  assert (max (abs (y_lut - [10; 10; 10; 15; 20; 17.5; 15; 15])) < 1e-12, '1-D LUT clip mismatch');

  % 7. Rate Limiter: R = 2, F = -1, Ts = 0.5 => max step +1 per 0.5s
  rl = ob_rate_limiter (2, -1, 0.5, 0);
  m_rl = wrap_step_model (rl, [0 5 5]);
  res_rl = ob_run (m_rl, [0 0.5 1.0 1.5], struct ('solver', 'rk4'));
  y_rl = ob_scope_data (res_rl, 3);
  assert (max (abs (y_rl - [1; 2; 3; 4])) < 1e-12, 'Rate limiter mismatch');

  % 8. Atomic direct-feedthrough analysis
  [ft_pid, any_pid] = ob_atomic_feedthrough (pid);
  assert (ft_pid == true && any_pid == true, 'PID with P=2 must have direct feedthrough');
  [ft_zp, any_zp] = ob_atomic_feedthrough (zp);
  assert (ft_zp == false && any_zp == false, 'Strictly proper Zero-Pole must be state-broken');

  cases = struct('name',{},'model',{},'config',{},'options',{});
  fine=(0:.02:1)';
  add('advanced_pid',m,[0 1 .02],struct(),2+3*fine+5*exp(-10*fine),5e-5);
  add('advanced_pid_antiwindup',m_aw,[0 2 .1],struct('zero_crossings',true),y_aw,1e-10);
  add('advanced_zero_pole',m_zp,[0 1 .02],struct(),2*(1-exp(-2*fine)),1e-6);
  add('advanced_discrete_state',m_dss,[0 1 .1],struct(),y_dss,1e-12);
  add('advanced_discrete_tf',m_dtf,[0 1.5 .5],struct(),[0;1;1.5;1.75],1e-12);
  add('advanced_lut',m_lut,[0 4 .5],struct('zero_crossings',true),[10;10;10;15;20;17.5;15;15;15],1e-12);
  add('advanced_rate_limiter',m_rl,[0 1.5 .25],struct(),[1;1;2;2;3;3;4],1e-12);
  add('advanced_relay',wrap_signal(ob_relay(1,-1,4,-2,.5,.25),[-2;2;0;0;-2;-2;2;2]), ...
      [0 1.75 .25],struct(),[-2;4;4;4;4;-2;-2;4],1e-12);
  add('advanced_discrete_pid',wrap_time_model(ob_pid_controller(2,0,0,10,struct('domain','discrete','Ts',.5,'offset',.25))), ...
      [0 1 .25],struct(),[0;.5;.5;1.5;1.5],1e-12);
  pid_two = ob_pid_controller(2,3,0,10,struct('two_dof',true,'form','ideal','b',.5, ...
                              'domain','discrete','Ts',.5));
  two = wrap_step_model(pid_two,[0 3 3]);
  two.blocks(4)=two.blocks(1); two.blocks(4).type='Constant'; two.blocks(4).value=1;
  two.edges(end+1,:)=[4 1 2 2];
  add('advanced_two_dof_pid',two,[0 1 .25],struct(),[1;1;7;7;13],1e-12);
  simo = wrap_step_model(ob_zero_pole([0 -1],-2,[2 3]),[0 1 1]);
  add('advanced_simo',simo,[0 1 .02],struct(),[2*exp(-2*fine),1.5+1.5*exp(-2*fine)],1e-6);
  add('advanced_direct_transfer',wrap_time_model(ob_discrete_transfer_function(2,1,.5)), ...
      [0 1 .25],struct(),[0;0;1;1;2],1e-12);
  matrix_lut=wrap_signal(ob_lookup_table_1d([1 2 3],[10 20 15],'linear'),[0 1 2 4]);
  matrix_lut.inputs{1}=ob_input_signal(0,[0 1 2 4],[2 2]);
  for zc = [false true]
    add(sprintf('advanced_linear_matrix_%d',zc),matrix_lut,[0 .5 .5],struct('zero_crossings',zc), ...
        [0 10 20 10;0 10 20 10],1e-12);
  endfor
  [at,bt,ct,dt] = ob_c2d_state_space(-2,4,1,0,.5,'tustin');
  assert(dt+ct*((1-at)\bt),2,1e-12);
  assert(at,1/3,1e-12);

  child=ob_subsystem_template();
  child.blocks(2).type='Discrete Integrator'; child.blocks(2).value=0;
  for mode = {'reset_rising','reset_falling','reset_either'}
    child.execution = struct('mode',mode{1},'initial_control',-1);
    model = wrap_step_model(child,[0 1 1]);
    model.blocks(4)=model.blocks(1); model.blocks(4).type='Inport'; model.blocks(4).value=1;
    model.inputs = {ob_input_signal(0:5,[-1;-1;1;1;-1;-1])};
    model.edges(end+1,:) = [4 1 2 2];
    switch mode{1}
      case 'reset_rising', trace=[0;1;0;1;2;3];
      case 'reset_falling', trace=[0;1;2;3;0;1];
      otherwise, trace=[0;1;0;1;0;1];
    endswitch
    for zc = [false true]
      add(sprintf('advanced_%s_%d',mode{1},zc),model,[0 5 1],struct('zero_crossings',zc),trace,1e-12);
    endfor
    model.sample_times=zeros(4,2); model.sample_times(2,:)=[1 0];
    held_trace = repelem(trace,2);
    for zc = [false true]
      add(sprintf('advanced_clocked_%s_%d',mode{1},zc),model,[0 5 .5], ...
          struct('zero_crossings',zc),held_trace(1:11),1e-12);
    endfor
  endfor
  nested=wrap_time_model(ob_state_space(-2,4,1,0));
  nested.blocks(1).type='Inport'; nested.blocks(1).value=1;
  nested.blocks(2).value.execution=struct('mode','enabled');
  nested.blocks(3).type='Outport'; nested.blocks(3).value=1;
  nested.blocks(4)=nested.blocks(1); nested.blocks(4).value=2;
  nested.edges(end+1,:)=[4 1 2 2];
  [ft,direct]=ob_atomic_feedthrough(nested);
  assert(ft,logical([0;1])); assert(direct);

  fprintf ('advanced subsystem extensions: %d trace cases passed\n',numel(cases));

  function add (name, model, config, options, want, tol)
    result = ob_run(model,ob_time_grid(config(1),config(2),config(3)),options);
    samples=ob_signal_values(result,3);
    rows=cellfun(@(v) v(:)',samples(:),'uniformoutput',false);
    got=vertcat(rows{:});
    if (!isequal(size(got),size(want)) || max(abs(got(:)-want(:))) > tol)
      error('advanced extension %s: got %s, expected %s',name,mat2str(got),mat2str(want));
    endif
    cases(end+1) = struct('name',name,'model',model,'config',config,'options',options);
  endfunction
endfunction

function model = wrap_signal (sub, values)
  model = wrap_step_model(sub,[0 0 0]);
  model.blocks(1).type='Inport'; model.blocks(1).value=1;
  model.inputs={ob_input_signal((0:numel(values)-1)*.25,values(:))};
endfunction

function model = wrap_step_model (sub, step_val)
  model.blocks = struct ( ...
    'type', {'Step', 'Subsystem', 'Scope'}, ...
    'value', {step_val, sub, []}, ...
    'name', {'Step', 'DUT', 'Scope'}, ...
    'x', {0.1, 0.5, 0.9}, 'y', {0.5, 0.5, 0.5});
  model.edges = [1 1 2 1; 2 1 3 1];
endfunction

function model = wrap_time_model (sub)
  model.blocks = struct ( ...
    'type', {'Time', 'Subsystem', 'Scope'}, ...
    'value', {[], sub, []}, ...
    'name', {'Time', 'DUT', 'Scope'}, ...
    'x', {0.1, 0.5, 0.9}, 'y', {0.5, 0.5, 0.5});
  model.edges = [1 1 2 1; 2 1 3 1];
endfunction
