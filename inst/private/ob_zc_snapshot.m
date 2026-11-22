function [snapshot, simple] = ob_zc_snapshot (model, edges, current, prefix = [])
  % Describe guard values and piecewise regimes from one evaluated graph.
  % Raw source signals determine guards even when outputs used frozen modes.
  % SIMPLE is true when every guard came from the scalar branch below and
  % there is no conditional block: the layout (descriptors, value count and
  % regime shapes) then depends only on the model, so two simple snapshots
  % of one model always have the same layout.
  count = numel (model.blocks);
  snapshot.values = zeros (0, 1);
  snapshot.descriptors = struct ('path', {}, 'type', {}, 'channel', {}, ...
                                'boundary', {}, 'side', {});
  snapshot.flow = struct ('modes', {cell(1, count)}, 'children', {cell(1, count)});
  cached = isfield(model,'runtime_info') && isstruct(model.runtime_info) ...
      && isscalar(model.runtime_info) && isfield(model.runtime_info,'kind') ...
      && ischar(model.runtime_info.kind) ...
      && strcmp(model.runtime_info.kind,'octave-blocks-runtime-info-v1');
  % A prepared plan carries its own trusted guard-block list and codes
  % (8-10 are Saturation, Dead Zone and Switch); see ob_prepare_runtime_model.
  planned = cached && isfield(model.runtime_info,'plan');
  simple = planned;
  if (planned)
    ids = model.runtime_info.plan.guard_blocks;
    codes = model.runtime_info.plan.codes;
  elseif (cached && isfield(model.runtime_info,'zc_ids') ...
      && valid_ids(model.runtime_info.zc_ids,count))
    ids = model.runtime_info.zc_ids;
  else
    ids = find(ismember({model.blocks.type}, ...
        {'Switch','Saturation','Dead Zone','Conditional Subsystem'}));
  endif
  % The plan carries its own source map; other caches are checked first.
  if (planned)
    cached_sources = true;
    source_map = model.runtime_info.plan.sources;
  else
    cached_sources = cached && isfield(model.runtime_info,'sources') ...
        && iscell(model.runtime_info.sources) && numel(model.runtime_info.sources)==count;
    if (cached_sources), source_map = model.runtime_info.sources; endif
  endif
  for id = reshape(ids,1,[])
    block = model.blocks(id);
    path = [prefix id];
    if (planned), primitive = codes(id) >= 8 && codes(id) <= 10;
    else primitive = any (strcmp (block.type, {'Switch', 'Saturation', 'Dead Zone'})); endif
    if (primitive)
      if (cached_sources), sources = source_map{id};
      else sources = edges(edges(:, 2) == id, 1)'; endif
      inputs = current(sources);
      % Inputs that ob_control_output accepts without conversion (finite real
      % full double scalars, as many as the block takes) and a block value
      % with as many elements as the guards index (one threshold or two
      % limits).  Inlined: every snapshot runs it for each guard block.
      scalar = planned && numel (inputs) == 1 + 2 * (codes(id) == 10) ...
               && numel (block.value) == 2 - (codes(id) == 10) ...
               && all (cellfun ('isclass', inputs, 'double')) && all (cellfun ('prodofsize', inputs) == 1);
      if (scalar)
        packed = [inputs{:}];
        scalar = isreal (packed) && ! issparse (packed) && all (isfinite (packed));
      endif
      if (scalar)
        % Finite real full double scalar inputs (the usual case) with a
        % threshold or a [lower upper] pair: the same values, regimes,
        % descriptors and errors as the general branch below, without
        % calling ob_control_output (whose checks pass for such inputs; only
        % its nonfinite-output check can fail, and it then runs to report
        % it) or building each descriptor and value separately.
        if (codes(id) == 10)
          input = inputs{2};
          boundary = double (block.value);
          snapshot.flow.modes{id} = double (input >= boundary);
          values = input - boundary;
          if (! isfinite (values)), guards (input, path, block.type, boundary, 'threshold'); endif
          descriptors = struct ('path', path, 'type', block.type, 'channel', 1, ...
                                'boundary', boundary, 'side', 'threshold');
        else
          input = inputs{1};
          limits = double (block.value);
          if (codes(id) == 8)
            output = min (max (input, limits(1)), limits(2));
          else
            output = 0;
            if (input < limits(1)), output = input - limits(1); endif
            if (input > limits(2)), output = input - limits(2); endif
          endif
          if (! isfinite (output)), ob_control_output (block, inputs, id); endif
          mode = 0;
          if (input < limits(1)), mode = -1; endif
          if (input > limits(2)), mode = 1; endif
          snapshot.flow.modes{id} = mode;
          values = [input - limits(1); input - limits(2)];
          if (! all (isfinite (values)))
            guards (input, path, block.type, limits(1), 'lower');
            guards (input, path, block.type, limits(2), 'upper');
          endif
          descriptors = struct ('path', {path, path}, 'type', block.type, 'channel', {1, 1}, ...
                                'boundary', {limits(1), limits(2)}, 'side', {'lower', 'upper'});
        endif
        snapshot.values = [snapshot.values; values];
        snapshot.descriptors = [snapshot.descriptors descriptors];
        continue;
      endif
      simple = false;
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
      simple = false;
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
        combined = ob_is_combined_mode(descriptor.options.mode);
      else
        continuous = isfield(block.value,'execution') ...
                     && isfield(block.value.execution,'control') ...
                     && strcmp(block.value.execution.control,'continuous');
        enabled = strcmp(ob_execution_mode(block.value),'enabled');
        combined = ob_is_combined_mode(ob_execution_mode(block.value));
      endif
      if (continuous)
        if (cached_sources), sources = source_map{id};
        else sources = edges(edges(:,2) == id,1)'; endif
        if (isempty(sources))
          error ('ob_run: continuous conditional block needs a control input');
        endif
        controls = current(sources(end-combined:end));
        modes = zeros(1,numel(controls));
        for channel = 1:numel(controls)
          control = controls{channel};
          if ((! isnumeric(control) && ! islogical(control)) || ! isreal(control) ...
              || ! isscalar(control) || ! isfinite(control))
            error ('ob_run: conditional control must be a finite real scalar');
          endif
          control = full(double(control)); mode = sign(control);
          enable_channel = combined && channel == 1;
          if (mode == 0)
            if (enable_channel)
              if (isfield(state,'enable_sign')), mode = state.enable_sign;
              else mode = double(state.was_enabled); endif
            elseif (isfield(state,'control_sign')), mode = state.control_sign;
            elseif (isfield(state,'previous_sign')), mode = state.previous_sign;
            endif
          endif
          modes(channel) = mode;
          side = 'control'; if (enable_channel), side = 'enable'; endif
          [values, descriptors] = guards(control,path,block.type,0,side);
          descriptors.channel = channel;
          snapshot.values = [snapshot.values; values];
          snapshot.descriptors = [snapshot.descriptors descriptors];
        endfor
        snapshot.flow.modes{id} = modes;
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
