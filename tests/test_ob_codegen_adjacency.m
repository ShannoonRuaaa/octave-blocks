function test_ob_codegen_adjacency ()
  test_path_cleanup = ob_test_setup ();
  % Compare indexes to the historical filters, including empty column shapes.
  edges = [4 3;2 5;1 3;4 5;2 3;4 2;2 3];
  [sources, proxies] = ob_c_adjacency(6,edges);
  check_indexes(sources,proxies,edges,6);
  assert (isequal(sources{3},[4;1;2;2]));
  assert (isequal(proxies{4},[3;5;2]));
  [sources, proxies] = ob_c_adjacency(3,zeros(0,2));
  check_indexes(sources,proxies,zeros(0,2),3);
  [sources, proxies] = ob_c_adjacency(0,zeros(0,2));
  assert (isequal(size(sources),[1 0]) && isequal(size(proxies),[1 0]));

  model = ob_zero_crossing_example();
  % Caller edge order differs from port order: the switch still gets a,b,c.
  model.edges = model.edges([3 5 2 4 1],:);
  unit = ob_c_conditional_unit(model); check_unit(unit);
  assert (isequal(unit.sources{4},[1;2;3]));
  [old_shapes, old_expressions] = ob_c_shapes(unit.flat,unit.order,unit.edges,unit.paths);
  [new_shapes, new_expressions] = ob_c_shapes(unit.flat,unit.order,unit.edges,unit.paths,unit.sources);
  assert (isequal(old_shapes,new_shapes) && isequal(old_expressions,new_expressions));
  old_lines = ob_c_schedule_lines(unit.flat,unit.edges,unit.offsets,unit.state_offsets,unit.sizes);
  new_lines = ob_c_schedule_lines(unit.flat,unit.edges,unit.offsets,unit.state_offsets,unit.sizes,unit.sources);
  assert (isequal(old_lines,new_lines));
  nested = ob_enabled_multirate_example();
  nested.edges = nested.edges([4 2 3 1],:);
  check_unit(ob_c_conditional_unit(nested));
  multi.blocks = struct('type',{'Constant','Function','Scope','Scope'}, ...
    'value',{[3 1;-2 4],[],[],[]},'name',{'Input','max','Values','Indices'}, ...
    'x',{.1,.4,.9,.9},'y',{.5,.5,.7,.3},'outputs',{[],2,[],[]});
  multi.edges = [2 2 4 1;1 1 2 1;2 1 3 1];
  unit = ob_c_conditional_unit(multi); check_unit(unit);
  assert (isequal(unit.proxies{2},[3;4]));
  assert (unit.flat.blocks(unit.proxies{2}(1)).value==1);
  assert (unit.flat.blocks(unit.proxies{2}(2)).value==2);

  directory = tempname(); mkdir(directory);
  file = fullfile(directory,'protected.c');
  sentinel = sprintf('caller source\n');
  unwind_protect
    fid = fopen(file,'wb'); fwrite(fid,sentinel); fclose(fid);
    invalid = ob_example();
    invalid.blocks(1).type='Constant';invalid.blocks(1).value=ones(2);
    invalid.blocks(2).type='Integrator';invalid.blocks(2).value=0;
    assert_error(@()ob_codegen(invalid,file),'state input shape must match');
    assert_error(@()ob_codegen(invalid,file,[0 1 .5],struct('zero_crossings',true)), ...
                 'state input shape must match');
    assert (strcmp(fileread(file),sentinel));
  unwind_protect_cleanup
    rmdir(directory,'s');
  end_unwind_protect
  disp ('Octave Blocks codegen adjacency tests passed');
endfunction

function check_indexes (sources,proxies,edges,count)
  for id=1:count
    assert (isequal(sources{id},edges(edges(:,2)==id,1)));
    assert (isequal(proxies{id},edges(edges(:,1)==id,2)));
  endfor
endfunction

function check_unit (unit)
  check_indexes(unit.sources,unit.proxies,unit.edges,unit.n);
  for child=unit.children
    if (!isempty(child{1})),check_unit(child{1});endif
  endfor
endfunction

function assert_error (callback, fragment)
  caught=false;
  try callback();catch err,caught=!isempty(strfind(err.message,fragment));end_try_catch
  assert(caught,['missing error: ' fragment]);
endfunction
