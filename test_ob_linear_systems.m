function test_ob_linear_systems ()
  times = 0:.05:1;
  for solver = {'rk4','ode45','ode15s'}
    options = struct ('solver',solver{1},'reltol',1e-9,'abstol',1e-11,'maxstep',.05);
    model = linear_model(ob_state_space(-2,1,1,0),1);
    result = ob_run(model,times,options);
    assert_close(ob_scope_data(result,3)',.5*(1-exp(-2*times)),2e-7);
    model = linear_model(ob_state_space([0 1;-1 0],zeros(2,1),eye(2),zeros(2,1),[1;0]),0);
    result = ob_run(model,times,options);
    samples = ob_signal_values(result,3);
    for k = 1:numel(times),assert_close(samples{k},[cos(times(k));-sin(times(k))],1e-7);endfor
    A = diag([-1 -2]); C = [1 2;3 -1]; D = [.5 0;0 -.25];
    model = linear_model(ob_state_space(A,eye(2),C,D,[.2;-.3]),[1;2]);
    result = ob_run(model,times,options); samples = ob_signal_values(result,3);
    for k = 1:numel(times)
      x = [1-.8*exp(-times(k));1-1.3*exp(-2*times(k))];
      assert_close(samples{k},C*x+D*[1;2],1e-6);
    endfor
  endfor
  % Transfer-function coefficients are checked against independent solutions,
  % including a direct term and a nonzero companion-state initial condition.
  model = linear_model(ob_transfer_function(2,[1 2]),1);
  assert_close(ob_scope_data(ob_run(model,times),3)',1-exp(-2*times),4e-7);
  model = linear_model(ob_transfer_function(1,[1 2 1]),1);
  assert_close(ob_scope_data(ob_run(model,times),3)',1-(1+times).*exp(-times),1e-7);
  model = linear_model(ob_transfer_function([2 1],[1 3]),1);
  assert_close(ob_scope_data(ob_run(model,0:.025:1),3)',1/3+(5/3)*exp(-3*(0:.025:1)),3e-7);
  model = linear_model(ob_transfer_function(1,[1 0 1],[1;0]),0);
  assert_close(ob_scope_data(ob_run(model,times),3)',cos(times),1e-7);
  model = linear_model(ob_transfer_function([0 4],[0 2]),3);
  assert_close(ob_scope_data(ob_run(model,[0 1]),3)',[6 6],0);
  model = linear_model(ob_transfer_function([0 0],[1 2 1]),1);
  assert_close(ob_scope_data(ob_run(model,times),3)',zeros(size(times)),0);
  feed = ob_state_space(zeros(0),zeros(0,2),zeros(2,0),[1 2;3 4]);
  model = linear_model(feed,[3;4]);
  assert_close(ob_signal_values(ob_run(model,0),3){1},[11;25],0);
  source = autonomous_model(ob_state_space([0 1;-1 0],[],eye(2),[],[1;0]));
  values = ob_signal_values(ob_run(source,times),2);
  for k = 1:numel(times),assert_close(values{k},[cos(times(k));-sin(times(k))],1e-7);endfor
  source = autonomous_model(ob_state_space(zeros(0),[],zeros(2,0),[]));
  assert_close(ob_signal_values(ob_run(source,[0 1]),2){end},zeros(2,1),0);

  % A zero D branch must preserve the Integrator's state-breaking feedback.
  model = linear_model(ob_state_space(0,1,1,0,1),1);
  model.blocks(1).type = 'Gain'; model.blocks(1).value = -1;
  model.edges = [2 1 1 1;1 1 2 1;2 1 3 1];
  assert_close(ob_scope_data(ob_run(model,times),3)',exp(-times),3e-8);
  model.blocks(2).value = ob_state_space(0,1,1,1,1);
  % y=x+u, u=-y => y=x/2 and x'=-x/2.
  assert_close(ob_scope_data(ob_run(model,times),3)',.5*exp(-times/2),3e-8);

  model = linear_model(ob_transfer_function(2,[1 2]),1);
  file = [tempname() '.mat'];
  unwind_protect
    ob_save_model(file,model,[0 1 .05],struct('solver','ode45'));
    [restored,config,options] = ob_load_model(file);
    assert(isequaln(restored,model) && isequal(config,[0 1 .05]) && strcmp(options.solver,'ode45'));
    assert_close(ob_scope_data(ob_run(restored,times,options),3)',1-exp(-2*times),4e-7);
  unwind_protect_cleanup
    if(exist(file,'file')),unlink(file);endif
  end_unwind_protect
  assert_error(@() ob_state_space([1 2],1,1,0),'square');
  assert_error(@() ob_state_space(eye(2),1,1,0),'dimensions');
  assert_error(@() ob_state_space(eye(2),ones(2,1),ones(1,2),0,[1 2]),'column');
  assert_error(@() ob_state_space(Inf,1,1,0),'finite');
  assert_error(@() ob_state_space(sparse(1),1,1,0),'full');
  assert_error(@() ob_transfer_function([1 2],[0 0]),'zero polynomial');
  assert_error(@() ob_transfer_function([1 2 3],[1 2]),'proper');
  assert_error(@() ob_transfer_function([1 Inf],[1 2]),'finite');
  assert_error(@() ob_transfer_function(ones(2),[1 2]),'vector');
  assert_error(@() ob_transfer_function(1,2,1),'column');
  assert_error(@() ob_transfer_function([1 1],[realmin() realmax()]),'normalized');
  disp('Octave Blocks linear-system builder tests passed');
endfunction

function model = linear_model (child, input)
  model.blocks = struct('type',{'Constant','Subsystem','Scope'}, ...
      'value',{input,child,[]},'name',{'Input','Linear system','Output'}, ...
      'x',{.15,.5,.85},'y',{.5,.5,.5});
  model.edges = [1 1 2 1;2 1 3 1];
endfunction

function model = autonomous_model (child)
  model.blocks = struct('type',{'Subsystem','Scope'},'value',{child,[]}, ...
      'name',{'Autonomous system','Output'},'x',{.3,.8},'y',{.5,.5});
  model.edges = [1 1 2 1];
endfunction

function assert_close (actual, expected, tolerance)
  assert(isequal(size(actual),size(expected)) && all(isfinite(actual(:))));
  assert(all(abs(actual(:)-expected(:))<=tolerance));
endfunction

function assert_error (callback, fragment)
  caught=false;
  try callback();catch err,caught=!isempty(strfind(err.message,fragment));end_try_catch
  assert(caught);
endfunction
