function [cases, api] = test_ob_event_codegen_edges (directory = '', verify = false, experimental = false)
  % Independent edge specifications, with optional C preparation/verification.
  % Compile the emitted edge manifest with the same strict flags as the main
  % event suite, then call this function with verify=true to compare channels.
  cases = struct ('name',{},'model',{},'config',{},'options',{});
  api = struct ('name',{},'model_name',{},'checks',{});
  if (verify), verify_exports(directory); return; endif
  settings = struct('solver','rk4','zero_crossings',true,'maxstep',Inf);

  plain = make_model({'Constant','Integrator','Scope'},{2,3,[]});
  plain.edges = [1 1 2 1;2 1 3 1];
  add('event_edge_no_guards',plain,[0 1 1],5);

  % Dyadic roots make the large-origin analytical result independent of
  % decimal timestamp quantization. The interval remains only one second.
  large = switched_integrator(1,2^26+.375,3,-2);
  add('event_edge_large_origin',large,[2^26 2^26+1 1],1.125);
  tiny = switched_integrator(1e10,.35,3e10,-2e10);
  add('event_edge_tiny_time',tiny,[0 1e-10 1e-10],1.25);

  child = make_model({'Inport','Saturation','Integrator','Outport'}, ...
                     {1,[.4 .6],0,1});
  child.edges = [1 1 2 1;2 1 3 1;3 1 4 1];
  child.execution = struct('mode','enabled','control','continuous', ...
                           'initial_outputs',{{-9}});
  lazy = make_model({'Time','Step','Subsystem','Scope'}, ...
                    {[],[.2 -1 1],child,[]});
  lazy.edges = [1 1 3 1;2 1 3 2;3 1 4 1];
  add('event_edge_lazy_guard_activation',lazy,[0 1 1],.42);
  lazy.blocks(2).type='Constant'; lazy.blocks(2).value=-1;
  add('event_edge_dormant_guards',lazy,[0 1 1],-9);

  % The numeric graph stays finite while input minus threshold can overflow.
  overflow = make_model({'Constant','Inport','Constant','Switch','Scope'}, ...
                        {1,1,-1,-1e308,[]});
  overflow.edges = [1 1 4 1;2 1 4 2;3 1 4 3;4 1 5 1];
  overflow.inputs = {ob_input_signal(0,0)};
  add('event_edge_guard_overflow',overflow,[0 1 1],1);
  invalid = overflow; invalid.inputs = {ob_input_signal(0,1e308)};
  assert_error(@()ob_run(invalid,[0 1],settings),'zero-crossing guard');

  api(end+1) = struct('name','api_event_edge_guard_overflow', ...
    'model_name','event_edge_guard_overflow','checks',{{ ...
      'Finite callback input 1e308 minus finite threshold -1e308 returns OB_NONFINITE', ...
      'Failed provider replacement and initialization preserve the complete model', ...
      'Mutating provider data makes outputs and step fail without changing the model', ...
      'Restoring provider data permits outputs and stepping from the accepted state'}});
  if (isempty(directory)), return; endif
  if (!exist(directory,'dir')), mkdir(directory); endif
  manifest = struct('name',{},'source',{},'standalone',{},'expected',{});
  for item = cases
    source=[item.name '.c']; expected_file=[item.name '.expected.csv'];
    if (experimental)
      % Developer opt-in only; the public exporter retains its event guard.
      info=ob_codegen_conditional(item.model,fullfile(directory,source),item.config,item.options);
    else
      info=ob_codegen(item.model,fullfile(directory,source),item.config,item.options);
    endif
    result=ob_run(item.model,ob_time_grid(item.config(1),item.config(2),item.config(3)),item.options);
    expected=result.t;
    for block=1:numel(result.compiled_model.blocks)
      count=prod(info.shapes{block});
      if(count==0),continue;endif
      trace=zeros(numel(result.t),count);
      for sample=1:numel(result.t)
        value=result.flat_values{sample,block};
        assert(isnumeric(value)&&isreal(value)&&isequal(size(value),info.shapes{block}));
        trace(sample,:)=value(:)';
      endfor
      assert(all(isfinite(trace(:)))); expected=[expected trace];
    endfor
    dlmwrite(fullfile(directory,expected_file),expected,'precision','%.17g');
    manifest(end+1)=struct('name',item.name,'source',source,'standalone',true,'expected',expected_file);
  endfor
  name=api(1).name; source=[name '.c'];
  write_text(fullfile(directory,source),[strjoin(overflow_harness(),char(10)) char(10)]);
  manifest(end+1)=struct('name',name,'source',source,'standalone',false,'expected','');
  write_text(fullfile(directory,'event-edge-manifest.json'),jsonencode(manifest));
  write_text(fullfile(directory,'event-edge-api-specifications.json'),jsonencode(api));
  fprintf('Prepared %d event C edge cases\n',numel(manifest));

  function add(name,model,config,wanted)
    result=ob_run(model,ob_time_grid(config(1),config(2),config(3)),settings);
    scopes=find(strcmp({model.blocks.type},'Scope'));
    assert(numel(scopes)==1);
    value=ob_signal_values(result,scopes(1)); actual=value{end};
    assert(isfinite(actual)&&abs(actual-wanted)<=2e-8*max(1,abs(wanted)), ...
      sprintf('edge analytical mismatch %s: actual %.17g expected %.17g',name,actual,wanted));
    cases(end+1)=struct('name',name,'model',model,'config',config,'options',settings);
  endfunction
endfunction

function lines = overflow_harness()
  lines={'#include <assert.h>','#include <stdio.h>', ...
    '#include "event_edge_guard_overflow.c"', ...
    'static int supplied(double time,int left,double *out,size_t count,void *user){', ...
    '  (void)time;(void)left;if(count!=1)return 1;out[0]=*(double*)user;return OB_OK;}', ...
    'int main(void){', ...
    '  ob_model model,saved,other,other_saved;double input=0.0;', ...
    '  assert(ob_model_init_inputs(&model,0.0,supplied,NULL,&input)==OB_OK);', ...
    '  assert(ob_model_init(&other,0.0)==OB_OK);saved=model;other_saved=other;', ...
    '  input=1e308;', ...
    '  assert(ob_model_outputs(&model)==OB_NONFINITE);', ...
    '  assert(memcmp(&model,&saved,sizeof(model))==0);', ...
    '  assert(ob_model_step(&model,1.0)==OB_NONFINITE);', ...
    '  assert(memcmp(&model,&saved,sizeof(model))==0);', ...
    '  assert(ob_model_set_input_provider(&model,supplied,NULL,&input)==OB_NONFINITE);', ...
    '  assert(memcmp(&model,&saved,sizeof(model))==0);', ...
    '  assert(ob_model_init_inputs(&model,0.0,supplied,NULL,&input)==OB_NONFINITE);', ...
    '  assert(memcmp(&model,&saved,sizeof(model))==0);', ...
    '  assert(memcmp(&other,&other_saved,sizeof(other))==0);input=0.0;', ...
    '  assert(ob_model_outputs(&model)==OB_OK);', ...
    '  assert(memcmp(&model,&saved,sizeof(model))==0);', ...
    '  assert(ob_model_step(&model,1.0)==OB_OK);', ...
    '  assert(model.event_count==0);', ...
    '  puts("C event finite-guard overflow, output rollback and retry tests passed");return 0;}'};
endfunction

function verify_exports(directory)
  manifest=jsondecode(fileread(fullfile(directory,'event-edge-manifest.json')));
  worst=0; compared=0; channels=0;
  for item=reshape(manifest,1,[])
    if(!item.standalone),continue;endif
    expected=dlmread(fullfile(directory,item.expected),',');
    actual=dlmread(fullfile(directory,[item.name '.csv']),',',1,0);
    assert(isequal(size(actual),size(expected)),['edge CSV shape: ' item.name]);
    assert(all(isfinite(actual(:))),['nonfinite edge C output: ' item.name]);
    scaled=abs(actual-expected)./max(1,abs(expected));
    [error,index]=max(scaled(:));
    [sample,column]=ind2sub(size(expected),index);
    assert(error<2e-8,sprintf('edge C/Octave mismatch %s sample %d column %d: actual %.17g expected %.17g scaled %.17g', ...
      item.name,sample,column,actual(index),expected(index),error));
    worst=max(worst,error);compared+=1;channels+=columns(actual)-1;
  endfor
  fprintf('Compared %d event C edge models (%d numeric channels); worst scaled error %.3g\n',compared,channels,worst);
endfunction

function model=switched_integrator(slope,threshold,high,low)
  model=make_model({'Constant','Time','Gain','Constant','Switch','Integrator','Scope'}, ...
                   {high,[],slope,low,threshold,0,[]});
  model.edges=[1 1 5 1;2 1 3 1;3 1 5 2;4 1 5 3;5 1 6 1;6 1 7 1];
endfunction

function model=make_model(types,values)
  count=numel(types);
  model.blocks=struct('type',types,'value',values,'name',types, ...
    'x',num2cell(linspace(.1,.9,count)),'y',num2cell(.5*ones(1,count)));
  model.edges=zeros(0,4);
endfunction

function assert_error(callback,fragment)
  caught=false;
  try callback();catch err,caught=!isempty(strfind(err.message,fragment));end_try_catch
  assert(caught);
endfunction

function write_text(file,value)
  fid=fopen(file,'wb');assert(fid>=0);
  unwind_protect
    assert(fwrite(fid,value,'char')==numel(value));
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
