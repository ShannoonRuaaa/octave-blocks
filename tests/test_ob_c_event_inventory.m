function test_ob_c_event_inventory ()
  empty = struct ('blocks',struct('type',{},'value',{},'name',{},'x',{},'y',{}), ...
                  'edges',zeros(0,4));
  [unit, guards] = ob_c_event_inventory (ob_c_conditional_unit(empty));
  assert (isempty(guards) && isempty(unit.event_ids) && isempty(unit.mode_ids));
  assert (isempty(unit.own_events) && isempty(unit.descendant_events) ...
          && isempty(unit.all_events) && unit.event_count==0);

  original = ob_c_conditional_unit (ob_control_example());
  [unit, guards] = ob_c_event_inventory (original);
  assert (numel(guards)==5 && unit.event_count==5);
  assert (isequal(unit.event_ids{2},[1 2]) && unit.mode_ids{2}==1);
  assert (isequal(unit.event_ids{3},[3 4]) && unit.mode_ids{3}==3);
  assert (unit.event_ids{4}==5 && unit.mode_ids{4}==5);
  assert (isequal(unit.own_events,1:5) && isempty(unit.descendant_events));
  assert (isequal(unit.all_events,1:5));
  assert (isequal({guards.side},{'lower','upper','lower','upper','threshold'}));
  assert (isequal([guards.boundary],[0 3 1 2 2]));
  assert (isequal([guards.mode_id],[1 1 3 3 5]));
  assert (isequal([guards.source_id],ones(1,5)) && isequal([guards.source_offset],zeros(1,5)));
  assert (isequal(guards(1).path,2) && isequal(guards(1).compiled_path,2));
  assert (strcmp(guards(1).unit_prefix,'ob_') && guards(1).block_id==2);
  assert (!isfield(original,'event_ids')); % Inventory decorates its value copy.

  % Every matrix element owns a mode, shared by its lower/upper guards.
  matrix = ob_control_example ();
  matrix.blocks(1).type='Constant'; matrix.blocks(1).value=[-2 0;1 3];
  matrix.blocks(6).value=-ones(2);
  [unit, guards] = ob_c_event_inventory (ob_c_conditional_unit(matrix));
  assert (unit.event_count==20 && isequal(unit.all_events,1:20));
  assert (isequal(unit.event_ids{2},1:8) && isequal(unit.mode_ids{2},1:4));
  assert (isequal(unit.event_ids{3},9:16) && isequal(unit.mode_ids{3},9:12));
  assert (isequal(unit.event_ids{4},17:20) && isequal(unit.mode_ids{4},17:20));
  assert (isequal([guards(1:8).channel],[1:4 1:4]));
  assert (isequal([guards(1:8).source_offset],[0:3 0:3]));
  assert (isequal([guards(1:8).mode_id],[1:4 1:4]));

  % Scalar Switch control is one guard even with a matrix-valued data branch.
  scalar_control = matrix;
  scalar_control.blocks(8)=scalar_control.blocks(1);
  scalar_control.blocks(8).type='Time';scalar_control.blocks(8).value=[];
  scalar_control.edges(scalar_control.edges(:,3)==4 & scalar_control.edges(:,4)==2,1)=8;
  [unit, guards] = ob_c_event_inventory (ob_c_conditional_unit(scalar_control));
  assert (numel(unit.event_ids{4})==1 && guards(end).channel==1);
  assert (guards(end).source_id==8 && guards(end).source_offset==unit.offsets(8));

  % Depth-first IDs include dormant typed bodies and preserve public virtual
  % hierarchy independently of the compiled typed-context traversal path.
  leaf=ob_subsystem_template();leaf.blocks(2).type='Saturation';leaf.blocks(2).value=[-1 1];
  middle=ob_subsystem_template();middle.blocks(2).type='Subsystem';middle.blocks(2).value=leaf;
  body=ob_subsystem_template();body.blocks(2).type='Subsystem';body.blocks(2).value=middle;
  body.execution=struct('mode','enabled','control','continuous','initial_outputs',{{0}});
  nested.blocks=struct('type',{'Time','Constant','Subsystem','Saturation','Scope'}, ...
      'value',{[],-1,body,[-2 2],[]},'name',{'Data','Disabled gate','Body','Root clamp','Output'}, ...
      'x',{.1,.1,.5,.6,.9},'y',{.8,.2,.5,.8,.5});
  nested.edges=[1 1 3 1;2 1 3 2;1 1 4 1;3 1 5 1];
  raw=ob_c_conditional_unit(nested);
  [unit, guards] = ob_c_event_inventory(raw);
  core=find(strcmp(unit.types,'Conditional Subsystem'));
  clamp=find(strcmp(unit.types,'Saturation'));
  child=unit.children{core};child_clamp=find(strcmp(child.types,'Saturation'));
  assert (unit.event_count==5 && isequal(unit.own_events,[1 4 5]));
  assert (isequal(unit.descendant_events,[2 3]) && isequal(unit.all_events,1:5));
  assert (unit.event_ids{core}==1 && isequal(unit.event_ids{clamp},[4 5]));
  assert (isequal(child.event_ids{child_clamp},[2 3]) && child.mode_ids{child_clamp}==2);
  assert (strcmp(guards(1).type,'Conditional Subsystem') && strcmp(guards(1).side,'control'));
  assert (isequal(guards(1).path,3) && isequal(guards(1).compiled_path,core));
  assert (isequal(guards(2).path,[3 2 2 2]));
  assert (isequal(guards(2).compiled_path,[core child_clamp]));
  assert (strcmp(guards(2).unit_prefix,child.prefix));
  assert (guards(2).source_offset==child.offsets(guards(2).source_id));
  assert (guards(1).source_id==2 && guards(1).source_offset==unit.offsets(2));

  % Sampled parents have no control guard, but still inventory child guards.
  nested.blocks(3).value.execution.control='sampled';
  [unit, guards] = ob_c_event_inventory(ob_c_conditional_unit(nested),7,[9 8]);
  assert (unit.event_count==4 && isequal(unit.all_events,7:10));
  assert (isempty(unit.event_ids{core}) && isempty(unit.mode_ids{core}));
  assert (isequal(guards(1).path,[9 8 3 2 2 2]));
  assert (isequal(guards(1).compiled_path,[core child_clamp]));
  assert (guards(1).mode_id==7 && guards(2).mode_id==7);

  % Trigger control guards exist statically even though triggered body guards
  % will be excluded from continuous collection while its output is held.
  trigger=ob_subsystem_template();trigger.blocks(2).type='Dead Zone';trigger.blocks(2).value=[0 1];
  trigger.execution=struct('mode','rising','control','continuous','initial_outputs',{{0}});
  nested.blocks(3).value=trigger;
  [unit, guards] = ob_c_event_inventory(ob_c_conditional_unit(nested));
  assert (strcmp(guards(1).side,'control') && strcmp(guards(2).type,'Dead Zone'));
  assert (numel(guards)==5);
  assert_error(@()ob_c_event_inventory(raw,0),'positive integer');
  assert_error(@()ob_c_event_inventory(raw,1,[1 0]),'positive integer');
  disp('Octave Blocks C event inventory tests passed');
endfunction

function assert_error (callback, fragment)
  caught=false;
  try callback();catch err,caught=!isempty(strfind(err.message,fragment));end_try_catch
  assert(caught);
endfunction
