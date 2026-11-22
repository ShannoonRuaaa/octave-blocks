function model = ob_connect (model, source, target, source_port = 1, target_port = [])
  ob_validate_model (model);
  n = numel (model.blocks);
  if (! valid_index (source, n) || ! valid_index (target, n))
    error ("ob_connect: select two valid blocks");
  endif
  edges = ob_edges (model);
  [unused, outputs] = ob_block_ports (model.blocks(source));
  inputs = ob_block_ports (model.blocks(target));
  if (! valid_index (source_port, outputs))
    error ("ob_connect: source output port does not exist");
  endif
  automatic = isempty (target_port);
  if (automatic)
    if (any (edges(:, 1) == source & edges(:, 2) == source_port & edges(:, 3) == target))
      error ("ob_connect: these blocks are already connected; specify a target port for another branch");
    endif
    target_port = 1;
    while (any (edges(:, 3) == target & edges(:, 4) == target_port))
      target_port += 1;
    endwhile
  endif
  if (! valid_index (target_port, inputs))
    error ("ob_connect: %s has no free input port", model.blocks(target).type);
  endif
  if (any (edges(:, 3) == target & edges(:, 4) == target_port))
    error ("ob_connect: target input port is already connected");
  endif
  if (automatic && nargin < 4 && columns (model.edges) == 2)
    model.edges(end + 1, :) = [source target];
  else
    model.edges = [edges; source source_port target target_port];
  endif
endfunction

function yes = valid_index (value, maximum)
  yes = isnumeric (value) && isscalar (value) && isreal (value) ...
        && isfinite (value) && value == fix (value) && value >= 1 && value <= maximum;
endfunction
