function test_ob_multioutput ()
  input = [1 2 3;4 5 6];
  answers = {input+1, input.', sum(input(:))};
  model = multi_model (input, 3);
  % One source can branch; distinct outputs can feed the same consumer.
  model.blocks(6) = model.blocks(3); model.blocks(6).name = 'Branch';
  model.blocks(7) = model.blocks(2); model.blocks(7).type = 'Product';
  model.blocks(7).name = 'Multiply'; model.blocks(7).outputs = [];
  model.blocks(8) = model.blocks(3); model.blocks(8).name = 'Product output';
  model.edges = [model.edges;2 2 6 1;2 2 7 2;2 1 7 1;7 1 8 1];
  for solver = {'rk4','ode45','ode15s'}
    result = ob_run (model, [0 0.2 1], struct('solver',solver{1}));
    for port = 1:3
      samples = ob_signal_values (result, 2, port);
      assert (all(cellfun(@(x) isequal(x,answers{port}),samples)));
      assert (isequal(result.values{end,port+2},answers{port}));
    endfor
    assert (isequal(result.values{end,6},input.'));
    assert (isequal(result.values{end,8},(input+1)*input.'));
    assert (isequal(result.values{end,2},answers{1}));
    assert (sum(strcmp({result.compiled_model.blocks.type},'Multiple Function')) == 1);
    assert (sum(strcmp({result.compiled_model.blocks.type},'Function Output')) == 3);
    assert_error (@() ob_signal_values(result,2,4), 'port does not exist');
  endfor

  % Two outputs are independent of the legacy value parameter.
  two = multi_model (input, 2); two.blocks(2).value = 999;
  result = ob_run (two,0);
  assert (isequal(result.values{1,3},answers{1}) && isequal(result.values{1,4},answers{2}));
  arguments = two;
  arguments.blocks(5) = arguments.blocks(1); arguments.blocks(5).value = 10;
  arguments.edges = [5 1 2 2;arguments.edges];
  result = ob_run (arguments,0);
  assert (isequal(result.values{1,3},input+10) && isequal(result.values{1,4},input.'));
  one = ob_function_example (); one.blocks(2).name = 'test_ob_multi_function';
  one.blocks(1).type = 'Constant'; one.blocks(1).value = input;
  one.blocks(2).value = 2;
  assert (ob_function_output_count(one.blocks(2)) == 1);
  assert (isequal(ob_run(one,0).values{1,3},answers{1}));
  one.blocks(2).outputs = [];
  assert (ob_function_output_count(one.blocks(2)) == 1);
  assert (isequal(ob_run(one,0).values{1,3},answers{1}));
  one.blocks(2).outputs = 1;
  assert (isequal(ob_run(one,0).values{1,3},answers{1}));

  % A virtual boundary preserves both user paths and numbered port routing.
  child = multi_child (3);
  nested = multi_model (input,3);
  nested.blocks(2).type = 'Subsystem'; nested.blocks(2).value = child;
  nested.blocks(2).outputs = [];
  result = ob_run (nested,[0 1]);
  for port = 1:3
    assert (isequal(ob_signal_values(result,[2 2],port){end},answers{port}));
    assert (isequal(ob_signal_values(result,2,port){end},answers{port}));
  endfor

  % Conditional snapshots expose all inner outputs after the first execution.
  conditional = nested;
  conditional.blocks(2).value.execution = struct ('mode','enabled', ...
    'initial_outputs',{{-ones(size(input)),-ones(size(input.')),-1}});
  conditional.blocks(6) = conditional.blocks(1);
  conditional.blocks(6).type = 'Step'; conditional.blocks(6).value = [1 0 1];
  conditional.edges(end+1,:) = [6 1 2 2];
  result = ob_run (conditional,0:2);
  for port = 1:3
    samples = ob_signal_values (result,[2 2],port);
    assert (all(isnan(samples{1}(:))) && isequal(samples{2},answers{port}));
    assert (isequal(result.values{end,port+2},answers{port}));
  endfor
  runtime = ob_runtime_init (conditional);
  assert_error (@() ob_runtime_outputs(runtime,[2 2],2), 'has not executed');
  runtime = ob_runtime_step (runtime,1);
  assert (isequal(ob_runtime_outputs(runtime,[2 2],3),answers{3}));

  % Checkpoint both numbered outputs and pending state, then fork execution.
  feedback = multi_feedback ();
  runtime = ob_runtime_step (ob_runtime_init(feedback),1);
  assert (ob_runtime_outputs(runtime,2,1) == 2 && ob_runtime_outputs(runtime,2,2) == 1);
  saved = runtime;
  file = [tempname() '.mat']; model_file = [tempname() '.mat'];
  unwind_protect
    save ('-mat7-binary',file,'runtime'); restored = load (file);
    resumed = ob_runtime_step (restored.runtime,2);
    assert (isequal(resumed,ob_runtime_step(runtime,2)));
    assert (ob_runtime_outputs(resumed,2,1) == 3 && ob_runtime_outputs(resumed,2,2) == 2);
    assert (isequal(runtime,saved));
    ob_save_model (model_file,conditional,[0 2 0.5]);
    [loaded,settings] = ob_load_model (model_file);
    assert (isequal(loaded,conditional) && isequal(settings,[0 2 0.5]));
    assert (isequal(ob_run(loaded,0:2).values,result.values));
  unwind_protect_cleanup
    if (exist(file,'file')), unlink(file); endif
    if (exist(model_file,'file')), unlink(model_file); endif
  end_unwind_protect

  % Failed output arity and user-code failures leave a live context untouched.
  invalid = multi_model (1,4);
  assert_error (@() ob_runtime_init(invalid), 'outputs');
  failing = multi_model (1,3);
  failing.blocks(1).type = 'Step'; failing.blocks(1).value = [1 1 -101];
  failing.blocks(6) = failing.blocks(1);
  failing.blocks(6).type = 'Unit Delay'; failing.blocks(6).value = 0;
  failing.edges(end+1,:) = [1 1 6 1];
  runtime = ob_runtime_step (ob_runtime_init(failing),0.5); saved = runtime;
  caught = false;
  try
    runtime = ob_runtime_step (runtime,1);
  catch err
    caught = ! isempty(strfind(err.message,'deterministic domain failure'));
  end_try_catch
  assert (caught && isequal(runtime,saved));
  assert (isequal(ob_runtime_step(runtime,0.75),ob_runtime_step(saved,0.75)));
  inactive = conditional;
  inactive.blocks(2).value.blocks(2).outputs = 4;
  inactive.blocks(2).value.blocks(6) = inactive.blocks(2).value.blocks(3);
  inactive.blocks(2).value.blocks(6).value = 4;
  inactive.blocks(2).value.edges(end+1,:) = [2 4 6 1];
  inactive.blocks(2).value.execution.initial_outputs{4} = 0;
  % The fourth child output need not be wired at the root.
  runtime = ob_runtime_init (inactive); saved = runtime; caught = false;
  try
    runtime = ob_runtime_step (runtime,1);
  catch err
    caught = ! isempty(strfind(err.message,'outputs'));
  end_try_catch
  assert (caught && isequal(runtime,saved));

  for count = {0,-1,1.5,NaN,Inf,[1 2],1+1i,'2',true,flintmax()+2}
    invalid = two; invalid.blocks(2).outputs = count{1};
    assert_error (@() ob_validate_model(invalid), 'output');
  endfor
  invalid = two; invalid.edges(2,2) = 3;
  assert_error (@() ob_validate_model(invalid), 'port');
  disp ('Octave Blocks multiple Function output tests passed');
endfunction

function model = multi_model (input, count)
  model.blocks = struct ('type',{'Constant','Function'},'value',{input,[]}, ...
    'name',{'Input','test_ob_multi_function'},'x',{0.1,0.4},'y',{0.5,0.5},'outputs',{[],count});
  model.edges = [1 1 2 1];
  for port = 1:min(count,3)
    block = model.blocks(1); block.type = 'Scope'; block.value = [];
    block.name = sprintf('Output %d',port); block.x = 0.9; block.outputs = [];
    model.blocks(end+1) = block;
    model.edges(end+1,:) = [2 port port+2 1];
  endfor
endfunction

function child = multi_child (count)
  child = multi_model (1,count);
  child.blocks(1).type = 'Inport';
  for port = 1:count
    child.blocks(port+2).type = 'Outport'; child.blocks(port+2).value = port;
  endfor
endfunction

function model = multi_feedback ()
  model = multi_model (0,2);
  model.blocks(1).type = 'Unit Delay';
  model.edges(end+1,:) = [2 1 1 1];
endfunction

function assert_error (callback, fragment)
  caught = false;
  try
    callback ();
  catch err
    caught = ! isempty(strfind(lower(err.message),lower(fragment)));
    if (! caught), rethrow(err); endif
  end_try_catch
  assert (caught);
endfunction
