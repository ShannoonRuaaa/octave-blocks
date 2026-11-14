function report = benchmark_ob_optimizations (source = pwd (), output = '', repetitions = 3)
  % Run each source version in a fresh process; do not mix cached functions.
  % Timings include initialization, with independent analytical checks.
  if (!ischar(source) || !exist(source,'dir') || !ischar(output))
    error ('benchmark_ob_optimizations: supply source directory and optional JSON output path');
  endif
  if (!isnumeric(repetitions) || !isscalar(repetitions) || !isreal(repetitions) ...
      || !isfinite(repetitions) || repetitions<1 || repetitions!=fix(repetitions))
    error ('benchmark_ob_optimizations: repetitions must be a positive integer');
  endif
  addpath (source);
  legacy = ob_enabled_continuous_example ();
  continuous = legacy;
  continuous.blocks(3).value.execution.control = 'continuous';
  continuous.sample_times = zeros (4,2);
  models = {legacy,continuous,ob_zero_crossing_example()};
  grids = {0:.03:3,0:.03:3,[0 1]};
  options = {struct(),struct('zero_crossings',true,'maxstep',.1), ...
             struct('zero_crossings',true)};
  names = {'sampled_enabled','continuous_enabled','primitive_event'};
  runtime = struct ('name',{},'times',{},'median',{},'integration_steps',{},'events',{},'final',{});
  for k = 1:3
    sample = ob_run (models{k},grids{k},options{k});
    check_runtime (sample,k,grids{k});
    times = zeros (1,repetitions);
    for repetition = 1:repetitions
      elapsed = tic ();
      sample = ob_run (models{k},grids{k},options{k});
      times(repetition) = toc (elapsed);
      check_runtime (sample,k,grids{k});
    endfor
    if (k<3), last=ob_scope_data(sample,4)(end);
    else last=ob_scope_data(sample,6)(end); endif
    runtime(end+1) = struct ('name',names{k},'times',times,'median',median(times), ...
        'integration_steps',sample.integration_steps,'events',numel(sample.events),'final',last);
    fprintf ('%s median %.6f s; steps %d events %d final %.12g\n', ...
             names{k},median(times),sample.integration_steps,numel(sample.events),last);
  endfor

  graphs = struct ('n',{},'times',{},'median',{});
  for n = [250 1000 3000 10000]
    model.blocks = struct ('type',repmat({'Gain'},1,n));
    model.blocks(1).type='Constant'; model.blocks(end).type='Scope';
    model.edges = [(1:n-1)' (2:n)'];
    assert (isequal(ob_execution_order(model),1:n));
    times = zeros (1,repetitions);
    for repetition = 1:repetitions
      elapsed=tic(); order=ob_execution_order(model); times(repetition)=toc(elapsed);
      assert (isequal(order,1:n));
    endfor
    graphs(end+1)=struct('n',n,'times',times,'median',median(times));
    fprintf ('graph n%d median %.6f s\n',n,median(times));
  endfor

  inputs = struct ('rows',{},'times',{},'median',{},'checksum',{});
  for n = [16 1000 100000]
    signal=ob_input_signal((0:n-1)',(0:n-1)'); queries=linspace(-1,n,500);
    wanted=sum(min(n-1,max(0,floor(queries)))); times=zeros(1,repetitions);
    for repetition = 0:repetitions
      elapsed=tic(); total=0;
      for query=queries, total+=ob_input_value(signal,query); endfor
      seconds=toc(elapsed); assert(total==wanted);
      if (repetition), times(repetition)=seconds; endif
    endfor
    inputs(end+1)=struct('rows',n,'times',times,'median',median(times),'checksum',total);
    fprintf ('input rows%d median %.6f s\n',n,median(times));
  endfor
  report=struct('octave',version(),'runtime',runtime,'graphs',graphs,'inputs',inputs);
  if (!isempty(output))
    fid=fopen(output,'wb');
    if (fid<0), error('benchmark_ob_optimizations: cannot write %s',output); endif
    unwind_protect
      text=jsonencode(report); assert(fwrite(fid,text,'char')==numel(text));
    unwind_protect_cleanup
      fclose(fid);
    end_unwind_protect
  endif
endfunction

function check_runtime (sample,k,grid)
  if (k<3)
    expected=min(grid,1)+max(0,min(grid-2,1));
    assert(max(abs(ob_scope_data(sample,4)'-expected))<1e-8);
  else
    assert(abs(ob_scope_data(sample,6)(end)-1.25)<1e-8);
  endif
endfunction
