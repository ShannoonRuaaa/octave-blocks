function test_ob_zc_snapshot_bist ()
  cleanup = ob_test_setup ();
  [passed,total] = test (mfilename("fullpath"), "quiet");
  assert (total > 0 && passed == total);
  fprintf ("test_ob_zc_snapshot_bist: %d/%d passed\n", passed, total);
endfunction

%!test
%! model.blocks = struct ('type', {'Constant', 'Saturation', 'Dead Zone'}, ...
%!                        'value', {[], [-1 2], [-1 2]});
%! current = {[-2 0;1 3], zeros(2), zeros(2)};
%! before = current;
%! snapshot = ob_zc_snapshot (model, [1 2;1 3], current);
%! assert (snapshot.values, [-1;2;1;4;-4;-1;-2;1;-1;2;1;4;-4;-1;-2;1]);
%! assert (snapshot.flow.modes{2}, [-1 0;0 1]);
%! assert (snapshot.flow.modes{3}, [-1 0;0 1]);
%! assert ([snapshot.descriptors(1:4).channel], 1:4);
%! assert ({snapshot.descriptors(1:4).side}, repmat({'lower'},1,4));
%! assert ({snapshot.descriptors(5:8).side}, repmat({'upper'},1,4));
%! assert (snapshot.descriptors(9).path, 3);
%! assert (isequal (current, before));

%!test
%! model.blocks = struct ('type', {'Constant', 'Constant', 'Constant', 'Switch'}, ...
%!                        'value', {[], [], [], .5});
%! current = {ones(2), .5, -ones(2), ones(2)};
%! snapshot = ob_zc_snapshot (model, [1 4;2 4;3 4], current, [7 8]);
%! assert (snapshot.values, 0);
%! assert (snapshot.flow.modes{4}, 1);
%! assert (snapshot.descriptors.path, [7 8 4]);
%! assert (snapshot.descriptors.side, 'threshold');
%! current{2} = [0 .5;1 -.5];
%! snapshot = ob_zc_snapshot (model, [1 4;2 4;3 4], current);
%! assert (snapshot.values, [-.5;.5;0;-1]);
%! assert (snapshot.flow.modes{4}, [0 1;1 0]);

%!test
%! % Equal bounds retain two stable, distinct threshold descriptors.
%! model.blocks = struct ('type', {'Constant', 'Saturation'}, 'value', {[], [1 1]});
%! snapshot = ob_zc_snapshot (model, [1 2], {1,1});
%! assert (snapshot.values, [0;0]);
%! assert ({snapshot.descriptors.side}, {'lower','upper'});
%! assert (snapshot.flow.modes{2}, 0);

%!test
%! % Only active enabled bodies contribute guards or frozen child modes.
%! child.model.blocks = struct ('type', {'Constant','Dead Zone'}, 'value', {[],[-1 1]});
%! child.edges = [1 2]; child.current = {[0;2],[0;1]};
%! enabled.execution.mode = 'enabled'; rising.execution.mode = 'rising';
%! state = struct ('initialized',true,'was_enabled',true,'child',child);
%! model.blocks = struct ('type', {'Conditional Subsystem','Conditional Subsystem', ...
%!                                 'Conditional Subsystem','Conditional Subsystem'}, ...
%!                        'value', {enabled,enabled,rising,enabled});
%! dormant = state; dormant.was_enabled = false; dormant.child = [];
%! uninitialized = dormant; uninitialized.initialized = false;
%! snapshot = ob_zc_snapshot (model, zeros(0,2), {state,dormant,state,uninitialized});
%! assert (snapshot.values, [1;3;-1;1]);
%! assert (snapshot.descriptors(1).path, [1 2]);
%! assert (snapshot.flow.children{1}.modes{2}, [0;1]);
%! assert (all(cellfun(@isempty,snapshot.flow.children(2:4))));

%!test
%! model.blocks = struct ('type', {}, 'value', {});
%! snapshot = ob_zc_snapshot (model, zeros(0,2), {});
%! assert (size(snapshot.values), [0 1]);
%! assert (isempty(snapshot.descriptors) && isempty(snapshot.flow.modes));

%!test
%! model.blocks = struct ('type', {'Constant','Saturation'}, 'value', {[],[-realmax() 0]});
%! fail ('ob_zc_snapshot (model, [1 2], {realmax(),0})', 'zero-crossing guard');

%!test
%! model.blocks = struct ('type', {'Constant','Saturation'}, 'value', {[],[-1 1]});
%! fail ('ob_zc_snapshot (model, [1 2], {NaN,0})', 'finite real numeric matrix');

%!test
%! % A continuous gate remains observable while its body is lazy/inactive.
%! state = struct('initialized',false,'was_enabled',false,'child',[], ...
%!                'control_sign',-1,'previous_sign',1);
%! for mode = {'enabled','rising','falling','either'}
%!   body.execution = struct('mode',mode{1},'control','continuous');
%!   model.blocks = struct('type',{'Constant','Conditional Subsystem'},'value',{[],body});
%!   snapshot = ob_zc_snapshot(model,[1 2],{-2,state},7);
%!   assert(snapshot.values,-2); assert(snapshot.flow.modes{2},-1);
%!   assert(snapshot.descriptors.path,[7 2]);
%!   assert(snapshot.descriptors.type,'Conditional Subsystem');
%!   assert(snapshot.descriptors.side,'control');
%!   assert(snapshot.descriptors.channel,1); assert(snapshot.descriptors.boundary,0);
%!   assert(isempty(snapshot.flow.children{2}));
%! endfor

%!test
%! % Zero preserves the accepted sign; logical values become numeric guards.
%! body.execution = struct('mode','rising','control','continuous');
%! model.blocks = struct('type',{'Constant','Conditional Subsystem'},'value',{[],body});
%! state = struct('initialized',false,'was_enabled',false,'child',[], ...
%!                'control_sign',-1,'previous_sign',1);
%! snapshot = ob_zc_snapshot(model,[1 2],{false,state});
%! assert(snapshot.values,0); assert(snapshot.flow.modes{2},-1);
%! state = rmfield(state,'control_sign');
%! assert(ob_zc_snapshot(model,[1 2],{false,state}).flow.modes{2},1);
%! state = rmfield(state,'previous_sign');
%! assert(ob_zc_snapshot(model,[1 2],{false,state}).flow.modes{2},0);
%! snapshot = ob_zc_snapshot(model,[1 2],{true,state});
%! assert(snapshot.values,1); assert(snapshot.flow.modes{2},1);

%!test
%! % Register the outer gate before its active body's primitive guards.
%! body.execution = struct('mode','enabled','control','continuous');
%! model.blocks = struct('type',{'Constant','Conditional Subsystem'},'value',{[],body});
%! child.model.blocks = struct('type',{'Constant','Dead Zone'},'value',{[],[-1 1]});
%! child.edges = [1 2]; child.current = {2,1};
%! state = struct('initialized',true,'was_enabled',true,'child',child,'control_sign',1);
%! snapshot = ob_zc_snapshot(model,[1 2],{0,state});
%! assert(snapshot.values,[0;3;1]);
%! assert(snapshot.descriptors(1).path,2);
%! assert(snapshot.descriptors(2).path,[2 2]);
%! assert(snapshot.flow.modes{2},1);
%! assert(snapshot.flow.children{2}.modes{2},1);
%! model.blocks(2).value.execution.mode = 'either';
%! snapshot = ob_zc_snapshot(model,[1 2],{0,state});
%! assert(snapshot.values,0); assert(isempty(snapshot.flow.children{2}));

%!test
%! % An active body can contain a still-lazy continuous descendant gate.
%! inner.execution = struct('mode','rising','control','continuous');
%! child.model.blocks = struct('type',{'Constant','Conditional Subsystem'},'value',{[],inner});
%! child.edges = [1 2];
%! dormant = struct('initialized',false,'was_enabled',false,'child',[],'control_sign',0);
%! child.current = {-2,dormant};
%! outer.execution = struct('mode','enabled','control','continuous');
%! model.blocks = struct('type',{'Constant','Conditional Subsystem'},'value',{[],outer});
%! state = struct('initialized',true,'was_enabled',true,'child',child,'control_sign',1);
%! snapshot = ob_zc_snapshot(model,[1 2],{1,state});
%! assert(snapshot.values,[1;-2]);
%! assert(snapshot.descriptors(1).path,2);
%! assert(snapshot.descriptors(2).path,[2 2]);
%! assert(snapshot.flow.children{2}.modes{2},-1);

%!test
%! body.execution = struct('mode','enabled','control','continuous');
%! model.blocks = struct('type',{'Constant','Conditional Subsystem'},'value',{[],body});
%! state = struct('initialized',false,'was_enabled',false,'child',[],'control_sign',0);
%! for control = {NaN,Inf,[1 2],complex(1,1),[],struct()}
%!   current = {control{1},state};
%!   fail('ob_zc_snapshot(model,[1 2],current)','finite real scalar');
%! endfor
%! fail('ob_zc_snapshot(model,zeros(0,2),{1,state})','control input');
