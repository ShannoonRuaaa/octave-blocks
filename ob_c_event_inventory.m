function [unit, guards] = ob_c_event_inventory (unit, first = 1, prefix = [])
  % Assign static global guard and frozen-regime IDs across typed C units.
  % IDs and model paths are one-based. Numeric buffer offsets are zero-based.
  % Inventory includes dormant bodies; generated collection decides activity.
  if (! isnumeric(first) || ! isreal(first) || ! isscalar(first) ...
      || ! isfinite(first) || first < 1 || first != fix(first))
    error ('ob_c_event_inventory: first guard ID must be a positive integer');
  endif
  if (! isnumeric(prefix) || ! isreal(prefix) || (! isempty(prefix) && ! isvector(prefix)) ...
      || any(! isfinite(prefix(:))) || any(prefix(:)<1 | prefix(:)!=fix(prefix(:))))
    error ('ob_c_event_inventory: public prefix must contain positive integer block IDs');
  endif
  [unit, guards] = inventory (unit, double(first), double(prefix(:)'), []);
  unit.event_count = numel (guards);
endfunction

function [unit, guards] = inventory (unit, first, public_prefix, compiled_prefix)
  guards = empty_guards ();
  unit.event_ids = unit.mode_ids = cell (1,unit.n);
  unit.own_events = unit.descendant_events = unit.all_events = [];
  for id = 1:unit.n
    block = unit.flat.blocks(id);
    sources = unit.edges(unit.edges(:,2)==id,1)';
    path = unit.paths{id};
    if (! isempty(path) && path(end)==0), path(end)=[]; endif
    public_path = [public_prefix path];
    compiled_path = [compiled_prefix id];
    source = []; boundaries = []; sides = {};
    if (strcmp(block.type,'Switch'))
      source = sources(2); boundaries = double(block.value); sides = {'threshold'};
    elseif (any(strcmp(block.type,{'Saturation','Dead Zone'})))
      source = sources(1); boundaries = double(block.value(:)'); sides = {'lower','upper'};
    elseif (strcmp(block.type,'Conditional Subsystem'))
      options = ob_execution_options (block.value,false);
      if (strcmp(options.control,'continuous'))
        source = sources(end); boundaries = 0; sides = {'control'};
      endif
    endif
    if (! isempty(source))
      channels = unit.sizes(source);
      first_mode = first+numel(guards);
      unit.mode_ids{id} = first_mode+(0:channels-1);
      for boundary = 1:numel(boundaries)
        for channel = 1:channels
          event_id = first+numel(guards);
          descriptor = struct ('path',public_path,'compiled_path',compiled_path, ...
              'type',block.type,'side',sides{boundary},'boundary',boundaries(boundary), ...
              'channel',channel,'unit_prefix',unit.prefix,'block_id',id, ...
              'source_id',source,'source_offset',unit.offsets(source)+channel-1, ...
              'mode_id',unit.mode_ids{id}(channel));
          guards(end+1) = descriptor;
          unit.event_ids{id}(end+1) = event_id;
          unit.own_events(end+1) = event_id;
          unit.all_events(end+1) = event_id;
        endfor
      endfor
    endif
    child = unit.children{id};
    if (! isempty(child))
      [child, nested] = inventory (child,first+numel(guards),public_path,compiled_path);
      unit.children{id} = child;
      unit.descendant_events = [unit.descendant_events child.all_events];
      unit.all_events = [unit.all_events child.all_events];
      guards = [guards nested];
    endif
  endfor
endfunction

function guards = empty_guards ()
  guards = struct ('path',{},'compiled_path',{},'type',{},'side',{},'boundary',{}, ...
      'channel',{},'unit_prefix',{},'block_id',{},'source_id',{},'source_offset',{},'mode_id',{});
endfunction
