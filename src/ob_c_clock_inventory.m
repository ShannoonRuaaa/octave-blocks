function [unit, clocks] = ob_c_clock_inventory (unit, first = 1, prefix = [])
  % Assign global clocks independently of lazy typed child initialization.
  clocks = struct ('path',{},'rate',{});
  unit.clock_ids = zeros(1,unit.n);
  for id = reshape(find(unit.flat.sample_times(:,1)' > 0),1,[])
    path = unit.paths{id};
    if (path(end)==0), path(end)=[]; endif
    unit.clock_ids(id) = first + numel(clocks);
    clocks(end+1) = struct('path',[prefix path],'rate',unit.flat.sample_times(id,:));
  endfor
  unit.descendant_clocks = [];
  for id = 1:unit.n
    if (!isempty(unit.children{id}))
      path = unit.paths{id}; path(end)=[];
      [child, nested] = ob_c_clock_inventory(unit.children{id},first+numel(clocks),[prefix path]);
      unit.children{id} = child;
      unit.descendant_clocks = [unit.descendant_clocks child.all_clocks];
      if(!isempty(nested)),clocks = [clocks nested];endif
    endif
  endfor
  unit.all_clocks = [unit.clock_ids(unit.clock_ids>0) unit.descendant_clocks];
  unit.clocked = !isempty(unit.all_clocks);
endfunction
