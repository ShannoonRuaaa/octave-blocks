function clocks = ob_nested_clocks (flat, origin, prefix = [])
  % Discover clocks without evaluating a lazily initialized conditional body.
  clocks = struct ('path', {}, 'rate', {}, 'tick', {}, 'next', {});
  cached = isfield(flat,'runtime_info') && isstruct(flat.runtime_info) ...
      && isscalar(flat.runtime_info) && isfield(flat.runtime_info,'kind') ...
      && ischar(flat.runtime_info.kind) ...
      && strcmp(flat.runtime_info.kind,'octave-blocks-runtime-info-v1');
  if (cached && isfield(flat.runtime_info,'conditional_ids') ...
      && valid_ids(flat.runtime_info.conditional_ids,numel(flat.blocks)))
    ids = flat.runtime_info.conditional_ids;
  else
    ids = find(strcmp({flat.blocks.type},'Conditional Subsystem'));
  endif
  for id = reshape(ids,1,[])
    child = flat.blocks(id).value;
    if (cached)
      descriptor = ob_runtime_execution (flat,id);
      % Prepared metadata follows full recursive model validation. A legacy
      % uncached caller still compiles the body and retains those checks.
      if (!descriptor.clocked && !ob_has_inner_clocks(child)), continue; endif
      count = descriptor.input_ports;
    else
      count = sum (strcmp ({child.blocks.type}, 'Inport'));
    endif
    child.inputs = repmat ({ob_input_signal(origin,0)}, 1, count);
    compiled = ob_compile_model (child);
    rates = compiled.sample_times;
    for leaf = reshape (find (rates(:,1)' > 0), 1, [])
      period = rates(leaf,1); offset = rates(leaf,2); first = origin + offset;
      if (!isfinite(origin+period) || origin+period <= origin ...
          || !isfinite(first) || (offset > 0 && first <= origin))
        error ('ob_run: nested sample clock cannot advance the simulation origin');
      endif
      clocks(end+1) = struct ('path',[prefix id leaf], 'rate',rates(leaf,:), 'tick',0, 'next',first);
    endfor
    descendants = ob_nested_clocks(compiled, origin, [prefix id]);
    if (!isempty(descendants)), clocks = [clocks descendants]; endif
  endfor
endfunction

function yes = valid_ids (ids,count)
  yes=isnumeric(ids) && isreal(ids) && ndims(ids)==2 && rows(ids)==1 ...
      && all(isfinite(ids)) && all(ids==fix(ids)) ...
      && all(ids>=1 & ids<=count) && all(diff(double(ids))>0);
endfunction
