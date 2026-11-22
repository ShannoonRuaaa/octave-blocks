function test_ob_combined_codegen (directory, verify = false, advanced_only = false)
  test_path_cleanup = ob_test_setup ();
  % Compare every exported numerical channel, including matrix state outputs.
  manifest_file = fullfile(directory,'combined-manifest.json');
  if (verify)
    cases = jsondecode(fileread(manifest_file));
    for k = 1:numel(cases)
      expected = dlmread(fullfile(directory,cases(k).expected),',');
      actual = dlmread(fullfile(directory,[cases(k).name '.csv']),',',1,0);
      assert(isequal(size(actual),size(expected)));
      assert(all(isfinite(actual(:))));
      assert(max(abs(actual(:)-expected(:))./(1+abs(expected(:)))) < 1e-8);
    endfor
    fprintf('combined generated C: %d cases passed\n',numel(cases));
    return;
  endif
  if (!exist(directory,'dir')),mkdir(directory);endif
  manifest = struct('name',{},'source',{},'standalone',{},'expected',{});
  if (!advanced_only)
  for mode = {'enabled_rising','enabled_falling','enabled_either'}
    for states = {'held','reset'}
      for outputs = {'held','reset'}
        for event = [false true]
          model = ob_combined_control_example();
          model.blocks(4).value.execution.mode = mode{1};
          model.blocks(4).value.execution.states = states{1};
          model.blocks(4).value.execution.outputs = outputs{1};
          if(event),model.blocks(4).value.execution.control='continuous';endif
          options=struct('zero_crossings',event,'maxstep',.25);
          name=sprintf('combined_%s_%s_%s_%d',mode{1},states{1},outputs{1},event);
          export_case(model,name,[0 6 1],options);
        endfor
      endfor
    endfor
  endfor
  model=ob_combined_continuous_example();
  export_case(model,'combined_smooth',[0 1.8 1.8],struct('zero_crossings',true,'maxstep',.08));
  model=ob_combined_control_example();
  model.blocks(1).type='Inport'; model.blocks(1).value=1;
  model.blocks(2).value=2; model.blocks(3).value=3;
  model.inputs=[{ob_input_signal([0 6],[1:6;7:12],[3 2])} model.inputs];
  model.blocks(4).value.blocks(2).value=zeros(3,2);
  model.blocks(4).value.execution.initial_outputs={-ones(3,2)};
  export_case(model,'combined_matrix',[0 6 1],struct());
  child=rmfield(model,'inputs'); child.blocks(5).type='Outport'; child.blocks(5).value=1;
  child.execution=struct('mode','enabled','initial_outputs',{{-ones(3,2)}});
  wrapper.blocks=struct('type',{'Inport','Inport','Inport','Constant','Subsystem','Scope'}, ...
    'value',{1,2,3,1,child,[]},'name',{'Data','Enable','Trigger','Outer enable','Nested','Output'}, ...
    'x',{.1,.1,.1,.1,.6,.9},'y',{.1,.3,.5,.7,.5,.5});
  wrapper.edges=[1 1 5 1;2 1 5 2;3 1 5 3;4 1 5 4;5 1 6 1];
  wrapper.inputs=model.inputs; wrapper.sample_times=zeros(6,2); wrapper.sample_times(5,:)=[.5 0];
  export_case(wrapper,'combined_nested_clock',[0 6 1],struct());
  for c = ob_nested_reset_cases ()
    export_case(c.model,c.name,[0 7 1],c.options,c.expected);
  endfor
  % Simulink-recorded first evaluations and ancestor resets, also checked
  % against the Simulink trace.  Root combined probes run in both emitters.
  simulink=ob_simulink_conditional_cases();
  names={simulink.name};
  compat='compatibility (no trigger on first evaluation)';
  root_probes={'combined/initial_negative','probes/C4_either_negative', ...
               'probes/P1_rising_zero_start_negative','probes/P2_falling_zero_start_positive', ...
               'probes/P3_either_zero_start_negative','probes/P5_disabled_zero_start_negative'};
  % Trigger-only 'compatibility' first evaluations: negative, positive and
  % zero first samples.
  for probe = {'falling',1; 'rising',2; 'either',4; 'either',5; 'either',6}'
    root_probes{end+1}=sprintf('probes/trigger_%s_%s_control%d',probe{1},compat,probe{2});
  endfor
  for name = root_probes
    c=simulink(strcmp(names,name{1}));
    for event = [false true]
      label=sprintf('simulink_%s_%d',regexprep(name{1},'\W','_'),event);
      options=c.options; if(event),options=struct('zero_crossings',true,'maxstep',.25);endif
      export_case(c.model,label,[0 c.times(end) 1],options,c.expected,c.scopes);
    endfor
  endfor
  for name = {'Q1_combined_late_high','Q2_combined_late_zero','Q3_combined_late_falling', ...
              'Q4_trigger_direct_late_high','R1_combined_executed_reset', ...
              'R2_combined_unexecuted_reset','N3_combined_frozen_low_reset', ...
              'N1_trigger_direct_reset','M1_trigger_direct_double_reset_reset', ...
              'Q6_combined_late_either','W1_wrapper_combined_zero_start', ...
              'W2_wrapper_combined_high_start','W3_wrapper_combined_outer_reset', ...
              'W4_wrapper_combined_reset_executed', ...
              'K1_trigger_direct_late_high_compat','K4_trigger_direct_late_zero_compat', ...
              'E2_trigger_direct_reenable_zero_reset','E4_trigger_direct_reenable_either_reset', ...
              'D1_trigger_direct_double_reset_compat','D2_trigger_direct_double_reset_falling_compat', ...
              'D3_trigger_direct_double_reset_negative','D5_trigger_direct_double_held_compat', ...
              'V1_wrapper_trigger_high_start','V3_wrapper_trigger_zero_start', ...
              'V4_wrapper_trigger_outer_reset', ...
              ... % Edge flags across an outer reset: kept for compat, cleared for 'zero'.
              'F1_trigger_direct_reset_after_rise_to_zero_compat', ...
              'F2_trigger_direct_reset_after_fall_to_zero_compat', ...
              'F3_trigger_direct_reset_after_fall_to_zero_either_compat', ...
              'F4_trigger_direct_reset_after_rise_to_zero_zero', ...
              'N2_wrapper_retrigger_compat_reset'}
    for variant = {'sampled','continuous'}
      c=simulink(strcmp(names,['probes/' name{1} '/' variant{1}]));
      label=sprintf('simulink_%s_%s',name{1},variant{1});
      export_case(c.model,label,[0 c.times(end) 1],c.options,c.expected,c.scopes);
    endfor
  endfor
  % Continuous 'compatibility' triggers (ode45 in Simulink) as RK4 event C:
  % compared with Octave here; test_ob_continuous_controls compares Octave
  % RK4 with the recorded crossing times.
  for mode = {'rising','either'}
    c=simulink(strcmp(names,sprintf('probes/continuous_%s_high_%s',mode{1},compat)));
    options=struct('zero_crossings',true,'maxstep',.05);
    export_case(c.model,['simulink_continuous_' mode{1} '_high_compat'],[0 2 .05],options);
  endfor
  endif
  for c = test_ob_advanced_simulink ()
    export_case(c.model,c.name,c.config,c.options);
  endfor
  fid=fopen(manifest_file,'w');assert(fid>=0);
  unwind_protect,fputs(fid,jsonencode(manifest));unwind_protect_cleanup,fclose(fid);end_unwind_protect
  function export_case(model,name,config,options,scope_expected = [],scopes = [])
          info=ob_codegen(model,fullfile(directory,[name '.c']),config,options);
          result=ob_run(model,ob_time_grid(config(1),config(2),config(3)),options);
          if(isempty(scopes)),scopes=3+(1:columns(scope_expected));endif
          for port = 1:columns(scope_expected)
            assert(ob_scope_data(result,scopes(port)),scope_expected(:,port),0);
          endfor
          expected=result.t;
          for block=1:numel(result.compiled_model.blocks)
            count=prod(info.shapes{block});
            if(count==0),continue;endif
            trace=zeros(numel(result.t),count);
            for sample=1:numel(result.t)
              value=result.flat_values{sample,block};
              assert(isnumeric(value)&&isequal(size(value),info.shapes{block}));
              trace(sample,:)=value(:)';
            endfor
            expected=[expected trace];
          endfor
          if(strcmp(name,'combined_smooth')),assert(abs(expected(end,end)-1.44)<1e-7);endif
          expected_file=[name '.expected.csv'];
          dlmwrite(fullfile(directory,expected_file),expected,'precision','%.17g');
          manifest(end+1)=struct('name',name,'source',[name '.c'],'standalone',true,'expected',expected_file);
  endfunction
endfunction
