function snapshot = ob_zc_snapshot (model, edges, current, prefix = [])
  % Describe guard values and piecewise regimes from one evaluated graph.
  % Raw source signals determine guards even when outputs used frozen modes.
  count = numel (model.blocks);
  snapshot.values = zeros (0, 1);
  snapshot.descriptors = struct ('path', {}, 'type', {}, 'channel', {}, ...
                                'boundary', {}, 'side', {});
  snapshot.flow = struct ('modes', {cell(1, count)}, 'children', {cell(1, count)});
  cached = isfield(model,'runtime_info') && isstruct(model.runtime_info) ...
      && isscalar(model.runtime_info) && isfield(model.runtime_info,'kind') ...
      && ischar(model.runtime_info.kind) ...
      && strcmp(model.runtime_info.kind,'octave-blocks-runtime-info-v1');
  if (cached && isfield(model.runtime_info,'zc_ids') ...
      && valid_ids(model.runtime_info.zc_ids,count))
    ids = model.runtime_info.zc_ids;
  else
    ids = find(ismember({model.blocks.type}, ...
        {'Switch','Saturation','Dead Zone','Conditional Subsystem'}));
  endif
  cached_sources = cached && isfield(model.runtime_info,'sources') ...
      && iscell(model.runtime_info.sources) && numel(model.runtime_info.sources)==count;
  for id = reshape(ids,1,[])
    block = model.blocks(id);
    path = [prefix id];
    if (any (strcmp (block.type, {'Switch', 'Saturation', 'Dead Zone'})))
      if (cached_sources), sources = model.runtime_info.sources{id};
      else sources = edges(edges(:, 2) == id, 1)'; endif
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
      descriptor = [];
      if (cached && isfield(model.runtime_info,'conditional') ...
          && iscell(model.runtime_info.conditional) ...
          && numel(model.runtime_info.conditional)>=id)
        candidate = model.runtime_info.conditional{id};
        if (isstruct(candidate) && isscalar(candidate) ...
            && all(isfield(candidate,{'kind','options','needs_flow','clocked', ...
                                     'continuous_controls','input_ports','output_ids','output_ports'})) ...
            && ischar(candidate.kind) ...
            && strcmp(candidate.kind,'octave-blocks-execution-descriptor-v1') ...
            && isstruct(candidate.options) && isscalar(candidate.options) ...
            && all(isfield(candidate.options,{'mode','states','outputs', ...
                                             'initial_outputs','initial_control','control'})))
          descriptor = candidate;
        endif
      endif
      if (!isempty(descriptor))
        continuous = strcmp(descriptor.options.control,'continuous');
        enabled = strcmp(descriptor.options.mode,'enabled');
      else
        continuous = isfield(block.value,'execution') ...
                     && isfield(block.value.execution,'control') ...
                     && strcmp(block.value.execution.control,'continuous');
        enabled = strcmp(ob_execution_mode(block.value),'enabled');
      endif
      if (continuous)
        if (cached_sources), sources = model.runtime_info.sources{id};
        else sources = edges(edges(:,2) == id,1)'; endif
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
      if (enabled && state.initialized && state.was_enabled)
        child = state.child;
        nested = ob_zc_snapshot (child.model, child.edges, child.current, path);
        snapshot.values = [snapshot.values; nested.values];
        snapshot.descriptors = [snapshot.descriptors nested.descriptors];
        snapshot.flow.children{id} = nested.flow;
      endif
    endif
  endfor
endfunction

function yes = valid_ids (ids,count)
  yes=isnumeric(ids) && isreal(ids) && ndims(ids)==2 && rows(ids)==1 ...
      && all(isfinite(ids)) && all(ids==fix(ids)) ...
      && all(ids>=1 & ids<=count) && all(diff(double(ids))>0);
endfunction

function [values, descriptors] = guards (input, path, type, boundary, side)
  values = input(:) - boundary;
  if (any (! isfinite (values)))
    label = sprintf ('%d/', path);
    error ('ob_run: zero-crossing guard at block %s must be finite', label(1:end-1));
  endif
  if (isscalar(values))
    descriptors = struct ('path',path,'type',type,'channel',1, ...
                          'boundary',boundary,'side',side);
  else
    descriptors = struct ('path',path,'type',type,'channel',num2cell(1:numel(values)), ...
                          'boundary',boundary,'side',side);
  endif
endfunction
