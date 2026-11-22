function ob_require_runtime_support (model, options, context = 'ob_runtime_init')
  % Reject Transport Delay and Limited Integrator where their contract is
  % not implemented: conditional subsystem bodies and zero-crossing runs,
  % for simulation and C export alike, and the typed conditional/event C
  % exporter (context 'ob_codegen_conditional').  The flat RK4 C exporter
  % (context 'ob_codegen') supports both blocks.
  types = {'Transport Delay', 'Limited Integrator'};
  found = find_blocks (model, types, [], false);
  if (isempty (found)), return; endif
  first = found(1);
  location = sprintf ('%d/', first.path); location(end) = [];
  if (strcmp (context, 'ob_codegen_conditional'))
    error (['ob_codegen: %s at block %s is not supported by the conditional/event C exporter; ' ...
            'C export supports it only in flat RK4 models without conditional subsystems, ' ...
            'multiple-output Functions or zero crossings'], first.type, location);
  endif
  conditional = found([found.conditional]);
  if (! isempty (conditional))
    location = sprintf ('%d/', conditional(1).path); location(end) = [];
    error ('%s: %s at block %s is not supported inside a conditional subsystem', ...
           context, conditional(1).type, location);
  endif
  if (isstruct (options) && isfield (options, 'zero_crossings') && options.zero_crossings)
    error ('%s: %s at block %s is not supported with zero_crossings=true', ...
           context, first.type, location);
  endif
endfunction

function found = find_blocks (model, types, prefix, conditional)
  found = struct ('path', {}, 'type', {}, 'conditional', {});
  for id = 1:numel (model.blocks)
    block = model.blocks(id);
    if (any (strcmp (block.type, types)))
      found(end+1) = struct ('path', [prefix id], 'type', block.type, 'conditional', conditional);
    elseif (strcmp (block.type, 'Subsystem'))
      inner = conditional || ! strcmp (ob_execution_mode (block.value), 'virtual');
      found = [found find_blocks(block.value, types, [prefix id], inner)];
    endif
  endfor
endfunction
