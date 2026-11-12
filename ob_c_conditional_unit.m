function unit = ob_c_conditional_unit (model, input_shapes = {}, prefix = 'ob_', root = true)
  % Compile atomic bodies separately; their runtime contexts remain typed trees.
  if (! root)
    model.inputs = cell (1, numel (input_shapes));
    for port = 1:numel (input_shapes)
      model.inputs{port} = ob_input_signal (0, zeros(1,prod(input_shapes{port})), input_shapes{port});
    endfor
  endif
  [unit.flat, unit.signal_map, unit.paths] = ob_compile_model (model);
  [unit.order, unit.edges, stateful] = ob_execution_order (unit.flat);
  unit.prefix = prefix; unit.root = root;
  unit.options = ob_execution_options (model);
  unit.types = {unit.flat.blocks.type}; unit.n = numel (unit.types);
  unit.has_continuous = ob_codegen_has_continuous (model);
  unit.has_continuous_children = false;
  unit.children = cell (1, unit.n);
  unit.function_shapes = cell (1, unit.n);
  unit.shapes = unit.expressions = cell (1, unit.n);
  for id = unit.order
    block = unit.flat.blocks(id);
    sources = unit.edges(unit.edges(:,2) == id, 1);
    shapes = unit.shapes(sources);
    location = strtrim (sprintf('%d ', unit.paths{id}));
    if (strcmp (block.type, 'Conditional Subsystem'))
      if (prod(shapes{end}) != 1)
        error ('ob_codegen: conditional control at block %s must be scalar', location);
      endif
      child_prefix = [prefix 'u' num2str(id) '_'];
      child = ob_c_conditional_unit (block.value, shapes(1:end-1), child_prefix, false);
      unit.children{id} = child;
      unit.has_continuous_children |= child.has_continuous;
      unit.shapes{id} = [0 0];
    elseif (strcmp (block.type, 'Multiple Function'))
      unit.function_shapes{id} = ob_c_multi_function (block, shapes, location);
      unit.shapes{id} = [0 0];
    elseif (strcmp (block.type, 'Function Output'))
      unit.shapes{id} = unit.function_shapes{sources(1)}{block.value};
    elseif (strcmp (block.type, 'Conditional Output'))
      child = unit.children{sources(1)};
      unit.shapes{id} = child.shapes{child.out_ids(block.value)};
    else
      [unit.shapes{id}, unit.expressions{id}] = numeric_shape (block, shapes, unit.flat.inputs, location);
    endif
  endfor
  unit.numeric_state = stateful & ! strcmp(unit.types, 'Conditional Subsystem');
  for id = reshape (find (unit.numeric_state), 1, [])
    source = unit.edges(unit.edges(:,2) == id, 1);
    if (! isequal (unit.shapes{id}, unit.shapes{source}))
      error ('ob_codegen: state input shape must match its initial condition at block %s', strtrim(sprintf('%d ',unit.paths{id})));
    endif
  endfor
  out_ids = find (strcmp ({model.blocks.type}, 'Outport'));
  unit.out_ids = zeros (1, numel (out_ids));
  for id = reshape(out_ids,1,[])
    port = model.blocks(id).value;
    for item = unit.signal_map
      if (isequal (item.path, id)), unit.out_ids(port) = item.outputs(1); break; endif
    endfor
  endfor
  if (! root)
    for port = 1:numel (unit.out_ids)
      if (! isequal (unit.shapes{unit.out_ids(port)}, size(unit.options.initial_outputs{port})))
        error ('ob_codegen: conditional output %d must match its initial output shape', port);
      endif
    endfor
  endif
  unit.sizes = cellfun (@prod, unit.shapes);
  unit.offsets = cumsum ([0 unit.sizes(1:end-1)]);
  if (unit.n == 0), unit.offsets = []; endif
  unit.value_count = sum (unit.sizes);
  unit.continuous_count = sum (unit.sizes(strcmp(unit.types,'Integrator')));
  for child = unit.children
    if (!isempty(child{1})), unit.continuous_count += child{1}.continuous_count; endif
  endfor
  unit.state_offsets = zeros (1,unit.n); unit.state_count = 0;
  for id = reshape(find(unit.numeric_state),1,[])
    unit.state_offsets(id) = unit.state_count; unit.state_count += unit.sizes(id);
  endfor
  unit.out_sizes = unit.sizes(unit.out_ids);
  unit.out_offsets = cumsum ([0 unit.out_sizes(1:end-1)]);
  if (isempty(unit.out_ids)), unit.out_offsets = []; endif
  unit.out_count = sum(unit.out_sizes);
  unit.input_sizes = cellfun (@(s) prod(s.shape), unit.flat.inputs);
  unit.input_offsets = cumsum ([0 unit.input_sizes(1:end-1)]);
  if (isempty(unit.input_sizes)), unit.input_offsets = []; endif
  unit.input_count = sum(unit.input_sizes);
endfunction

function yes = ob_codegen_has_continuous (model)
  yes = any (strcmp ({model.blocks.type}, 'Integrator'));
  for id = reshape (find (strcmp ({model.blocks.type}, 'Subsystem')), 1, [])
    yes |= ob_codegen_has_continuous (model.blocks(id).value);
  endfor
endfunction

function [shape, expression] = numeric_shape (block, inputs, signals, location)
  expression = '';
  if (any(strcmp(block.type, {'Constant','Gain','Step','Integrator','Unit Delay', ...
                             'Discrete Integrator','Rate Transition','Saturation','Dead Zone','Switch'})))
    if (! isa(block.value,'double') || ndims(block.value) != 2 || issparse(block.value))
      error ('ob_codegen: block %s needs a full real double parameter with at most two dimensions', location);
    endif
  endif
  switch (block.type)
    case {'Constant','Integrator','Unit Delay','Discrete Integrator','Rate Transition'}
      shape = size(block.value);
    case {'Time','Step'}, shape = [1 1];
    case 'External Input', shape = signals{block.value}.shape;
    case 'Gain', shape = product_shape(size(block.value), inputs{1}, location);
    case 'Product', shape = product_shape(inputs{1}, inputs{2}, location);
    case 'Sum', shape = broadcast_shape(inputs{1}, inputs{2}, location);
    case {'Scope','Inport','Outport','Saturation','Dead Zone'}, shape = inputs{1};
    case 'Switch'
      if (! isequal(inputs{1},inputs{3}) || (prod(inputs{2}) != 1 && ! isequal(inputs{1},inputs{2})))
        error ('ob_codegen: Switch block %s has incompatible data/control shapes',location);
      endif
      shape = inputs{1};
    case 'Function'
      [expression,arity] = ob_c_function(block.name);
      if (numel(inputs) != arity), error('ob_codegen: Function %s needs %d inputs',block.name,arity); endif
      if (arity == 1), shape = inputs{1}; else shape = broadcast_shape(inputs{1},inputs{2},location); endif
    otherwise, error('ob_codegen: unsupported block %s at %s',block.type,location);
  endswitch
endfunction

function shape = product_shape(a,b,location)
  if (prod(a)==1), shape=b;
  elseif (prod(b)==1), shape=a;
  elseif (a(2)==b(1)), shape=[a(1) b(2)];
  else error('ob_codegen: incompatible matrix multiplication at block %s',location); endif
endfunction

function shape = broadcast_shape(a,b,location)
  if (any(a!=b & a!=1 & b!=1)), error('ob_codegen: incompatible broadcast at block %s',location); endif
  shape=max(a,b);
endfunction
