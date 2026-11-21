function model = ob_hold_builder_output (model, outport, initial, rate)
  rates = ob_sample_times(model);
  index = numel(model.blocks)+1;
  node = model.blocks(outport);
  node.type = 'Rate Transition'; node.name = 'Sampled output'; node.value = initial;
  node.x = max(0,node.x-.06);
  model.blocks(index) = node;
  model.edges(model.edges(:,3)==outport,3) = index;
  model.edges(end+1,:) = [index 1 outport 1];
  model.sample_times = [rates;rate];
endfunction
