function model = ob_disconnect (model, source, target, source_port = [], target_port = [])
  if (isempty (source) || isempty (target))
    error ("ob_disconnect: use positive block and port indices");
  endif
  for value = {source, target, source_port, target_port}
    item = value{1};
    if (! isempty (item) && (! isnumeric (item) || ! isscalar (item) ...
        || ! isreal (item) || ! isfinite (item) || item < 1 || item != fix (item)))
      error ("ob_disconnect: use positive block and port indices");
    endif
  endfor
  edges = ob_edges (model);
  match = edges(:, 1) == source & edges(:, 3) == target;
  if (! isempty (source_port)), match &= edges(:, 2) == source_port; endif
  if (! isempty (target_port)), match &= edges(:, 4) == target_port; endif
  ids = find (match);
  if (isempty (ids)), error ("ob_disconnect: these blocks are not connected"); endif
  if (numel (ids) != 1), error ("ob_disconnect: specify ports to choose one connection"); endif
  % Canonical form prevents input slots shifting when a wire is removed.
  model.edges = edges;
  model.edges(ids, :) = [];
endfunction
