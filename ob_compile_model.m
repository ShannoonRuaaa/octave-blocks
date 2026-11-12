function [flat, signal_map, block_paths] = ob_compile_model (model)
  % Inline virtual subsystem boundaries before dependency sorting/integration.
  ob_validate_model (model, true);
  [flat, signal_map, block_paths] = compile_level (model, []);
  flat.inputs = ob_model_inputs (model, true);
endfunction

function [flat, signal_map, block_paths, interface_in, interface_out] = compile_level (model, prefix)
  flat.blocks = struct ("type", {}, "value", {}, "name", {}, "x", {}, "y", {});
  flat.edges = zeros (0, 4);
  flat.sample_times = zeros (0, 2);
  rates = ob_sample_times (model);
  signal_map = struct ("path", {}, "outputs", {});
  block_paths = {};
  inputs = outputs = cell (1, numel (model.blocks));
  interface_in = interface_out = [];
  for id = 1:numel (model.blocks)
    block = model.blocks(id);
    path = [prefix id];
    offset = numel (flat.blocks);
    options = struct ('mode', 'virtual');
    if (strcmp (block.type, 'Subsystem')), options = ob_execution_options (block.value); endif
    if (strcmp (block.type, 'Subsystem') && ! strcmp (options.mode, 'virtual'))
      core = struct ('type', 'Conditional Subsystem', 'value', block.value, ...
                     'name', block.name, 'x', block.x, 'y', block.y);
      flat.blocks(end + 1) = core;
      flat.sample_times(end + 1, :) = rates(id, :);
      inputs{id} = offset + 1;
      outputs{id} = zeros (1, numel (options.initial_outputs));
      block_paths{end + 1} = [path 0];
      for port = 1:numel (outputs{id})
        proxy = struct ('type', 'Conditional Output', 'value', port, ...
                        'name', sprintf('Out%d',port), 'x', block.x, 'y', block.y);
        flat.blocks(end + 1) = proxy;
        flat.sample_times(end + 1, :) = [0 0];
        outputs{id}(port) = numel (flat.blocks);
        flat.edges(end + 1, :) = [offset+1 1 outputs{id}(port) 1];
        block_paths{end + 1} = [path 0 port];
      endfor
    elseif (strcmp (block.type, "Subsystem"))
      [child, child_map, child_paths, cin, cout] = compile_level (block.value, path);
      for k = 1:numel (child_map)
        child_map(k).outputs += offset;
      endfor
      child.edges(:, [1 3]) += offset;
      flat.blocks = [flat.blocks child.blocks];
      flat.edges = [flat.edges; child.edges];
      flat.sample_times = [flat.sample_times; child.sample_times];
      signal_map = [signal_map child_map];
      block_paths = [block_paths child_paths];
      inputs{id} = cin + offset;
      outputs{id} = cout + offset;
    elseif (strcmp (block.type, 'Function') && ob_function_output_count(block) > 1)
      count = ob_function_output_count (block);
      core = struct ('type', 'Multiple Function', 'value', count, ...
                     'name', block.name, 'x', block.x, 'y', block.y);
      flat.blocks(end + 1) = core;
      flat.sample_times(end + 1, :) = [0 0];
      inputs{id} = offset + 1;
      outputs{id} = zeros (1, count);
      block_paths{end + 1} = [path 0];
      for port = 1:count
        proxy = struct ('type', 'Function Output', 'value', port, ...
                        'name', sprintf('Output%d',port), 'x', block.x, 'y', block.y);
        flat.blocks(end + 1) = proxy;
        flat.sample_times(end + 1, :) = [0 0];
        outputs{id}(port) = numel (flat.blocks);
        flat.edges(end + 1, :) = [offset+1 1 outputs{id}(port) 1];
        block_paths{end + 1} = [path 0 port];
      endfor
    else
      leaf = struct ("type", block.type, "value", block.value, "name", block.name, ...
                     "x", block.x, "y", block.y);
      if (isempty (prefix) && strcmp (block.type, 'Inport'))
        leaf.type = 'External Input';
      endif
      flat.blocks(end + 1) = leaf;
      flat.sample_times(end + 1, :) = rates(id, :);
      inputs{id} = outputs{id} = offset + 1;
      block_paths{end + 1} = path;
      if (strcmp (block.type, "Inport")), interface_in(block.value) = offset + 1; endif
      if (strcmp (block.type, "Outport")), interface_out(block.value) = offset + 1; endif
    endif
    signal_map(end + 1) = struct ("path", path, "outputs", outputs{id});
  endfor
  edges = ob_edges (model);
  for k = 1:rows (edges)
    edge = edges(k, :);
    source = outputs{edge(1)}(edge(2));
    conditional = false;
    if (strcmp (model.blocks(edge(3)).type, 'Subsystem'))
      options = ob_execution_options (model.blocks(edge(3)).value, false);
      conditional = ! strcmp (options.mode, 'virtual');
    endif
    if (conditional)
      target = inputs{edge(3)}; target_port = edge(4);
    elseif (strcmp (model.blocks(edge(3)).type, "Subsystem"))
      target = inputs{edge(3)}(edge(4)); target_port = 1;
    else
      target = inputs{edge(3)}; target_port = edge(4);
    endif
    flat.edges(end + 1, :) = [source 1 target target_port];
  endfor
endfunction
