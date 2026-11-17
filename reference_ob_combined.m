function reference_ob_combined (file)
  % Independent MATLAB/Simulink reference; never substitutes Octave output.
  % Builds unsaved temporary models and closes them without saving.
  if exist ('load_system','file') == 0
    error ('reference_ob_combined:SimulinkMissing', ...
           'A local Simulink engine is required; no reference traces produced.');
  end
  load_system ('simulink');
  records = struct ('name',{},'trigger_type',{},'states',{},'outputs',{}, ...
                   'initial_trigger',{},'enable',{},'trigger',{},'t',{},'y',{});
  trigger = [-1 0 1 1 -1 0 0 1 -1 1 1 -1 1];
  enable = [0 0 1 1 1 1 1 1 0 0 1 1 1];
  for edge = {'rising','falling','either'}
    for states = {'held','reset'}
      for outputs = {'held','reset'}
        c = struct ('name',[edge{1} '_' states{1} '_' outputs{1}], ...
          'trigger_type',edge{1},'states',states{1},'outputs',outputs{1}, ...
          'initial_trigger','zero','enable',enable,'trigger',trigger);
        records(end+1) = combined_case (c);
      end
    end
  end
  % A pulse in enable without any trigger must not execute the delay.
  c = struct ('name','enable_only_reset_pending','trigger_type','rising', ...
      'states','reset','outputs','reset','initial_trigger','zero', ...
      'enable',[1 1 0 1 1 0 1 1 1], ...
      'trigger',[-1 1 1 1 1 1 1 -1 1]);
  records(end+1) = combined_case (c);
  % A rejected edge while disabled must not turn into an edge on enable.
  c.name = 'own_disabled_trigger_history'; c.states = 'held'; c.outputs = 'held';
  c.enable = [0 0 1 1 1 1]; c.trigger = [-1 1 1 -1 0 1];
  records(end+1) = combined_case (c);
  % Explicit initial trigger states, including MATLAB's separate default.
  for initial = {'zero','positive','negative','compatibility (no trigger on first evaluation)'}
    c.name = ['initial_' initial{1}]; c.initial_trigger = initial{1};
    c.enable = [1 1 1 1 1 1]; c.trigger = [1 1 -1 0 0 1];
    records(end+1) = combined_case (c);
  end
  evidence = struct ('matlab_version',version,'simulink_version',ver('simulink'), ...
      'reference_script','reference_ob_combined.m','records',records);
  fid = fopen (file,'w');
  if fid < 0, error ('Cannot write reference output'); end
  cleanup = onCleanup (@() fclose(fid));
  fprintf (fid,'%s\n',jsonencode(evidence));
end

function record = combined_case (c)
  [~,suffix] = fileparts (tempname);
  name = ['ob_combined_ref_' suffix];
  new_system (name);
  cleanup = onCleanup (@() close_system(name,0));
  times = (0:numel(c.enable)-1)';
  set_param (name,'SolverType','Fixed-step','Solver','FixedStepDiscrete', ...
      'FixedStep','1','StartTime','0','StopTime',num2str(times(end)), ...
      'ReturnWorkspaceOutputs','on');
  add_block ('simulink/Sources/Digital Clock',[name '/Data'],'SampleTime','1');
  for control = {'Enable','Trigger'}
    add_block ('simulink/Sources/From Workspace',[name '/' control{1}], ...
        'VariableName',[lower(control{1}) '_data'],'Interpolate','off','SampleTime','1');
  end
  child = [name '/Child'];
  add_block ('simulink/Ports & Subsystems/Enabled and Triggered Subsystem',child);
  set_param ([child '/Enable'],'StatesWhenEnabling',c.states);
  set_param ([child '/Trigger'],'TriggerType',c.trigger_type, ...
      'InitialTriggerSignalState',c.initial_trigger);
  delete_line (child,'In1/1','Out1/1');
  add_block ('simulink/Discrete/Unit Delay',[child '/Delay'], ...
      'InitialCondition','7','SampleTime','-1');
  add_line (child,'In1/1','Delay/1');
  add_line (child,'Delay/1','Out1/1');
  set_param ([child '/Out1'],'InitialOutput','-9','OutputWhenDisabled',c.outputs);
  add_block ('simulink/Sinks/To Workspace',[name '/Recorded'], ...
      'VariableName','reference_output','SaveFormat','Timeseries');
  add_line (name,'Data/1','Child/1');
  add_line (name,'Enable/1','Child/Enable');
  add_line (name,'Trigger/1','Child/Trigger');
  add_line (name,'Child/1','Recorded/1');
  input = Simulink.SimulationInput (name);
  input = input.setVariable ('enable_data',[times c.enable(:)]);
  input = input.setVariable ('trigger_data',[times c.trigger(:)]);
  result = sim (input);
  trace = result.reference_output;
  record = c;
  record.t = trace.Time(:)'; record.y = trace.Data(:)';
  fprintf ('%s: %s\n',record.name,mat2str(record.y));
end
