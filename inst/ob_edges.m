function edges = ob_edges (model)
  % Canonical edges: [source source_port target target_port].
  raw = model.edges;
  if (! isnumeric (raw) || ! isreal (raw) || ndims (raw) != 2 ...
      || ! any (columns (raw) == [2 4]) || any (! isfinite (raw(:))) ...
      || any (raw(:) < 1) || any (raw(:) != fix (raw(:))))
    error ("ob_edges: connections must be valid block indices/ports in an N-by-2 or N-by-4 matrix");
  endif
  if (columns (raw) == 4)
    edges = raw;
  else
    edges = zeros (rows (raw), 4);
    if (isempty(raw)), return; endif
    edges(:,[1 3]) = raw;
    edges(:,2) = 1;
    % Count each target's incoming wires in original row order. Grouping IDs
    % avoids storage proportional to the largest (possibly invalid) block ID.
    % An explicit row key preserves order without assuming a stable sort.
    [unused,unused,group] = unique (raw(:,2));
    ordinal = (1:rows(raw))';
    [unused,permutation] = sortrows ([group ordinal],[1 2]);
    sorted = group(permutation);
    starts = zeros(rows(raw),1);
    first = [true; diff(sorted)!=0];
    starts(first) = find(first);
    edges(permutation,4) = ordinal-cummax(starts)+1;
  endif
endfunction
