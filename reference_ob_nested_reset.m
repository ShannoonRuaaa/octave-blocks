function reference_ob_nested_reset (file)
  % Independent Simulink reference, using unsaved models only.
  % Positive inner enables isolate the effect of an ancestor's disable.
  if exist ('load_system','file') == 0
    error ('reference_ob_nested_reset:SimulinkMissing', ...
           'A local Simulink engine is required; no reference traces produced.');
  end
  load_system ('simulink');
  policies = {{'held','held'}, {'held','reset'}, ...
              {'reset','held'}, {'reset','reset'}, ...
              {'reset','reset','held'}, {'held','held','reset'}, ...
              {'reset','held','reset'}};
  records = cell (1,2*numel(policies));
  index = 0;
  for kind = {'discrete','continuous'}
    for k = 1:numel(policies)
      index = index+1;
      records{index} = nested_case (kind{1},policies{k});
    end
  end
  evidence = struct ('matlab_version',version,'simulink_version',ver('simulink'), ...
      'reference_script','reference_ob_nested_reset.m','records',{records});
  fid = fopen (file,'w');
  if fid < 0, error ('Cannot write reference output'); end
  cleanup = onCleanup (@() fclose(fid)); %#ok<NASGU>
  fprintf (fid,'%s\n',jsonencode(evidence));
end

function record = nested_case (kind,policies)
  [~,suffix] = fileparts (tempname);
  name = ['ob_nested_reset_' suffix];
  new_system (name);
  cleanup = onCleanup (@() close_system(name,0)); %#ok<NASGU>
  enable = [1 1 0 0 1 1 0 1];
  times = (0:numel(enable)-1)';
  if strcmp(kind,'discrete')
    set_param (name,'SolverType','Fixed-step','Solver','FixedStepDiscrete', ...
        'FixedStep','1');
    add_block ('simulink/Sources/Digital Clock',[name '/Data'],'SampleTime','1');
  else
    set_param (name,'SolverType','Fixed-step','Solver','ode4','FixedStep','0.25');
    add_block ('simulink/Sources/Constant',[name '/Data'],'Value','1');
  end
  set_param (name,'StartTime','0','StopTime',num2str(times(end)), ...
      'ReturnWorkspaceOutputs','on');
  add_block ('simulink/Sources/From Workspace',[name '/Enable'], ...
      'VariableName','enable_data','Interpolate','off','SampleTime','1');
  add_layer ([name '/Outer'],kind,policies,1);
  add_block ('simulink/Sinks/To Workspace',[name '/Recorded'], ...
      'VariableName','reference_output','SaveFormat','Timeseries');
  add_line (name,'Data/1','Outer/1');
  add_line (name,'Enable/1','Outer/Enable');
  add_line (name,'Outer/1','Recorded/1');
  input = Simulink.SimulationInput (name);
  input = input.setVariable ('enable_data',[times enable(:)]);
  result = sim (input);
  trace = result.reference_output;
  data = squeeze(trace.Data);
  if size(data,1) ~= numel(trace.Time), data = data'; end
  record = struct ('kind',kind,'policies',{policies},'enable',enable, ...
      'local_enables','all inner enables constant 1', ...
      'initial_states',7+10*(0:numel(policies)-1), ...
      'output_policy','held; explicit initial vector -9', ...
      't',trace.Time(:)','y',data);
  fprintf ('%s %s: %s\n',kind,strjoin(policies,'/'),mat2str(data));
end

function add_layer (path,kind,policies,level)
  add_block ('simulink/Ports & Subsystems/Enabled Subsystem',path);
  set_param ([path '/Enable'],'StatesWhenEnabling',policies{level});
  delete_line (path,'In1/1','Out1/1');
  initial = num2str (7+10*(level-1));
  if strcmp(kind,'discrete')
    add_block ('simulink/Discrete/Unit Delay',[path '/State'], ...
        'InitialCondition',initial,'SampleTime','1');
  else
    add_block ('simulink/Continuous/Integrator',[path '/State'], ...
        'InitialCondition',initial);
  end
  add_line (path,'In1/1','State/1');
  width = numel(policies)-level+1;
  set_param ([path '/Out1'],'OutputWhenDisabled','held', ...
      'InitialOutput',mat2str(-9*ones(1,width)));
  if level < numel(policies)
    add_layer ([path '/Inner'],kind,policies,level+1);
    add_block ('simulink/Sources/Constant',[path '/InnerEnable'],'Value','1');
    add_block ('simulink/Signal Routing/Mux',[path '/States'],'Inputs','2');
    add_line (path,'In1/1','Inner/1');
    add_line (path,'InnerEnable/1','Inner/Enable');
    add_line (path,'State/1','States/1');
    add_line (path,'Inner/1','States/2');
    add_line (path,'States/1','Out1/1');
  else
    add_line (path,'State/1','Out1/1');
  end
end
