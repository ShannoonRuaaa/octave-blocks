function result=audit_timed_case(label)
 if(any(strcmp(label,{'sampled','continuous','primitive'})))
   model=ob_enabled_continuous_example();grid=0:.03:3;options=struct();scope=4;
   if(strcmp(label,'continuous')),model.blocks(3).value.execution.control='continuous';model.sample_times=zeros(4,2);options=struct('zero_crossings',true,'maxstep',.1);
   elseif(strcmp(label,'primitive')),model=ob_zero_crossing_example();grid=[0 1];options=struct('zero_crossings',true);scope=6;endif
   ob_run(model,grid,options);
   cpu=cputime();elapsed=tic();sample=ob_run(model,grid,options);wall=toc(elapsed);cpu=cputime()-cpu;
   values=ob_scope_data(sample,scope);
   if(scope==4),wanted=min(grid,1)+max(0,min(grid-2,1));assert(max(abs(values'-wanted))<1e-8);else assert(abs(values(end)-1.25)<1e-8);endif
   result=struct('wall',wall,'cpu',cpu,'checksum',values(end),'steps',sample.integration_steps,'events',numel(sample.events));
 elseif(strncmp(label,'graph',5))
   n=str2double(label(6:end));model.blocks=struct('type',repmat({'Gain'},1,n));model.blocks(1).type='Constant';model.blocks(end).type='Scope';model.edges=[(1:n-1)' (2:n)'];
   assert(isequal(ob_execution_order(model),1:n));cpu=cputime();elapsed=tic();order=ob_execution_order(model);wall=toc(elapsed);cpu=cputime()-cpu;assert(isequal(order,1:n));
   result=struct('wall',wall,'cpu',cpu,'checksum',sum(order),'steps',0,'events',0);
 else
   n=str2double(label(6:end));signal=ob_input_signal((0:n-1)',(0:n-1)');queries=linspace(-1,n,500);
   total=0;for q=queries,total+=ob_input_value(signal,q);endfor;wanted=sum(min(n-1,max(0,floor(queries))));assert(total==wanted);
   cpu=cputime();elapsed=tic();total=0;for q=queries,total+=ob_input_value(signal,q);endfor;wall=toc(elapsed);cpu=cputime()-cpu;assert(total==wanted);
   result=struct('wall',wall,'cpu',cpu,'checksum',total,'steps',0,'events',0);
 endif
endfunction
