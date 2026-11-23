function [model, id] = ob_builder_block (model, type, value, name, x, y, sources = [])
% OB_BUILDER_BLOCK  Append one native block to a builder model and wire it.
%   MODEL = OB_BUILDER_BLOCK () returns an empty builder model: no blocks
%   (fields type, value, name, x, y), no edges and execution mode
%   'virtual', the shape every subsystem builder in inst/ returns.
%
%   [MODEL, ID] = OB_BUILDER_BLOCK (MODEL, TYPE, VALUE, NAME, X, Y[, SOURCES])
%   appends a block and returns its index ID.  SOURCES lists the blocks
%   whose output port 1 feeds input ports 1..numel(SOURCES) of the new
%   block, in order; wire other output ports with explicit edges.  X and Y
%   are the editor coordinates in [0, 1].
%
%   Shared by the subsystem builders (ob_sign, ob_minmax, ...) so that each
%   builder states its block graph once instead of hand-numbering edges.

  if (nargin == 0)
    model = struct ('blocks', struct ('type', {}, 'value', {}, 'name', {}, 'x', {}, 'y', {}), ...
                    'edges', zeros (0, 4), 'execution', struct ('mode', 'virtual'));
    return;
  endif
  if (nargin < 6 || ! isstruct (model) || ! isfield (model, 'blocks') || ! ischar (type) || ! ischar (name))
    error ('ob_builder_block: supply MODEL, TYPE, VALUE, NAME, X, Y[, SOURCES]');
  endif
  id = numel (model.blocks) + 1;
  model.blocks(id) = struct ('type', type, 'value', value, 'name', name, 'x', x, 'y', y);
  sources = sources(:);
  if (! isempty (sources))
    if (any (sources < 1 | sources >= id | sources != fix (sources)))
      error ('ob_builder_block: SOURCES must name blocks added before ''%s''', name);
    endif
    count = numel (sources);
    model.edges(end+1:end+count, :) = [sources, ones(count, 1), repmat(id, count, 1), (1:count)'];
  endif
endfunction
