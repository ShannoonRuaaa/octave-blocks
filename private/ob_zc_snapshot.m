function snapshot = ob_zc_snapshot (model, edges, current, prefix = [])
  % Describe guard values and piecewise regimes from one evaluated graph.
  % Raw source signals determine guards even when outputs used frozen modes.
  count = numel (model.blocks);
  snapshot.values = zeros (0, 1);
  snapshot.descriptors = struct ('path', {}, 'type', {}, 'channel', {}, ...
                                'boundary', {}, 'side', {});
  snapshot.flow = struct ('modes', {cell(1, count)}, 'children', {cell(1, count)});
  for id = 1:count
    block = model.blocks(id);
    path = [prefix id];
    if (any (strcmp (block.type, {'Switch', 'Saturation', 'Dead Zone'})))
      sources = edges(edges(:, 2) == id, 1)';
      inputs = current(sources);
      % Share the ordinary input cardinality, shape and finite-domain checks.
      ob_control_output (block, inputs, id);
      if (strcmp (block.type, 'Switch'))
        input = full (double (inputs{2}));
        boundary = double (block.value);
        snapshot.flow.modes{id} = double (input >= boundary);
        [values, descriptors] = guards (input, path, block.type, boundary, 'threshold');
      else
        input = full (double (inputs{1}));
        limits = double (block.value);
        mode = zeros (size (input));
        mode(input < limits(1)) = -1;
        mode(input > limits(2)) = 1;
        snapshot.flow.modes{id} = mode;
        [lower_values, lower_descriptors] = guards (input, path, block.type, limits(1), 'lower');
        [upper_values, upper_descriptors] = guards (input, path, block.type, limits(2), 'upper');
        values = [lower_values; upper_values];
        descriptors = [lower_descriptors upper_descriptors];
      endif
      snapshot.values = [snapshot.values; values];
      snapshot.descriptors = [snapshot.descriptors descriptors];
    elseif (strcmp (block.type, 'Conditional Subsystem'))
      state = current{id};
      continuous = isfield(block.value,'execution') ...
                   && isfield(block.value.execution,'control') ...
                   && strcmp(block.value.execution.control,'continuous');
      if (continuous)
        sources = edges(edges(:,2) == id,1)';
        if (isempty(sources))
          error ('ob_run: continuous conditional block needs a control input');
        endif
        control = current{sources(end)};
        if ((! isnumeric(control) && ! islogical(control)) || ! isreal(control) ...
            || ! isscalar(control) || ! isfinite(control))
          error ('ob_run: conditional control must be a finite real scalar');
        endif
        control = full (double(control));
        mode = sign (control);
        if (mode == 0)
          if (isfield(state,'control_sign'))
            mode = state.control_sign;
          elseif (isfield(state,'previous_sign'))
            mode = state.previous_sign;
          endif
        endif
        snapshot.flow.modes{id} = mode;
        [values, descriptors] = guards (control,path,block.type,0,'control');
        snapshot.values = [snapshot.values; values];
        snapshot.descriptors = [snapshot.descriptors descriptors];
      endif
      if (strcmp(ob_execution_mode(block.value),'enabled') ...
          && state.initialized && state.was_enabled)
        child = state.child;
        nested = ob_zc_snapshot (child.model, child.edges, child.current, path);
        snapshot.values = [snapshot.values; nested.values];
        snapshot.descriptors = [snapshot.descriptors nested.descriptors];
        snapshot.flow.children{id} = nested.flow;
      endif
    endif
  endfor
endfunction

function [values, descriptors] = guards (input, path, type, boundary, side)
  values = input(:) - boundary;
  if (any (! isfinite (values)))
    label = sprintf ('%d/', path);
    error ('ob_run: zero-crossing guard at block %s must be finite', label(1:end-1));
  endif
  descriptor = struct ('path', path, 'type', type, 'channel', 0, ...
                       'boundary', boundary, 'side', side);
  descriptors = repmat (descriptor, 1, numel (values));
  for channel = 1:numel (values)
    descriptors(channel).channel = channel;
  endfor
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
