function reference_ob_conditional (file)
  % Run only in MATLAB with Simulink. Build temporary behavioral references.
  modes = {'enabled','enabled','enabled','rising','falling','either'};
  states = {'held','reset','held','held','held','held'};
  outputs = {'held','held','reset','held','held','held'};
  records = struct ('name',{},'mode',{},'states',{},'outputs',{},'control',{},'t',{},'y',{});
  if exist ('load_system','file') == 0
    error ('reference_ob_conditional:SimulinkMissing', ...
           'A local Simulink engine is required; a successful license test alone is insufficient.');
  end
  load_system ('simulink');
  for k = 1:numel(modes)
    [~, suffix] = fileparts (tempname);
    name = ['ob_ref_' suffix];
    new_system (name);
    cleanup = onCleanup (@() close_system(name,0));
    set_param (name,'SolverType','Fixed-step','Solver','FixedStepDiscrete', ...
                    'FixedStep','1','StartTime','0','ReturnWorkspaceOutputs','on');
    add_block ('simulink/Sources/Digital Clock',[name '/Data'],'SampleTime','1');
    add_block ('simulink/Sources/From Workspace',[name '/Control'], ...
               'VariableName','control_data','Interpolate','off','SampleTime','1');
    if strcmp(modes{k},'enabled')
      control = [0 1 1 0 0 1 1];
      add_block ('simulink/Ports & Subsystems/Enabled Subsystem',[name '/Child']);
      set_param ([name '/Child/Enable'],'StatesWhenEnabling',states{k});
      control_port = 'Enable';
    else
      control = [-1 0 1 0 0 1 -1 0 0 1];
      add_block ('simulink/Ports & Subsystems/Triggered Subsystem',[name '/Child']);
      set_param ([name '/Child/Trigger'],'TriggerType',modes{k},'InitialTriggerSignalState','zero');
      control_port = 'Trigger';
    end
    delete_line ([name '/Child'],'In1/1','Out1/1');
    add_block ('simulink/Discrete/Unit Delay',[name '/Child/Delay'], ...
               'InitialCondition','0','SampleTime','-1');
    add_line ([name '/Child'],'In1/1','Delay/1');
    add_line ([name '/Child'],'Delay/1','Out1/1');
    set_param ([name '/Child/Out1'],'InitialOutput','-1','OutputWhenDisabled',outputs{k});
    add_block ('simulink/Sinks/To Workspace',[name '/Recorded'], ...
               'VariableName','reference_output','SaveFormat','Timeseries');
    add_line (name,'Data/1','Child/1');
    add_line (name,'Control/1',['Child/' control_port]);
    add_line (name,'Child/1','Recorded/1');
    times = (0:numel(control)-1)';
    set_param (name,'StopTime',num2str(times(end)));
    input = Simulink.SimulationInput (name);
    input = input.setVariable ('control_data',[times control(:)]);
    result = sim (input);
    trace = result.reference_output;
    records(end+1) = struct ('name',[modes{k} '_' states{k} '_' outputs{k}], ...
        'mode',modes{k},'states',states{k},'outputs',outputs{k}, ...
        'control',control,'t',trace.Time(:)','y',trace.Data(:)');
    fprintf ('%s: %s\n',records(end).name,mat2str(records(end).y));
    clear cleanup;
  end
  evidence = struct ('matlab_version',version,'simulink_version',ver('simulink'), ...
                    'reference_script','reference_ob_conditional.m','records',records);
  fid = fopen (file,'w');
  if fid < 0, error ('Cannot write reference output'); end
  cleanup = onCleanup (@() fclose(fid));
  fprintf (fid,'%s\n',jsonencode(evidence));
end
