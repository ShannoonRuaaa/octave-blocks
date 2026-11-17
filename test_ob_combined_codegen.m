function test_ob_combined_codegen (directory, verify = false)
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
  fid=fopen(manifest_file,'w');assert(fid>=0);
  unwind_protect,fputs(fid,jsonencode(manifest));unwind_protect_cleanup,fclose(fid);end_unwind_protect
  function export_case(model,name,config,options)
          info=ob_codegen(model,fullfile(directory,[name '.c']),config,options);
          result=ob_run(model,ob_time_grid(config(1),config(2),config(3)),options);
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
