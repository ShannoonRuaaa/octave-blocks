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
    for k = 1:rows (raw)
      edges(k, :) = [raw(k, 1), 1, raw(k, 2), 1 + sum(raw(1:k-1, 2) == raw(k, 2))];
    endfor
  endif
endfunction
