function shapes = ob_c_multi_function (block, inputs, location)
  % Static signatures for actual builtins with numeric, allocation-free outputs.
  if (! any (strcmp (block.name, {'size', 'max', 'min'})))
    error ('ob_codegen: unsupported multiple-output Function %s at block %s', block.name, location);
  endif
  implementation = functions (str2func (block.name));
  if (exist (block.name, 'builtin') != 5 || ! isempty (implementation.file))
    error ('ob_codegen: Function %s is shadowed or is not the supported builtin', block.name);
  endif
  if (block.value != 2 || numel (inputs) != 1)
    error ('ob_codegen: multiple-output Function %s needs one input and exactly two outputs', block.name);
  endif
  if (strcmp (block.name, 'size'))
    shape = [1 1];
  elseif (inputs{1}(1) == 1)
    shape = [1 1];
  else
    shape = [1 inputs{1}(2)];
  endif
  shapes = {shape, shape};
endfunction
