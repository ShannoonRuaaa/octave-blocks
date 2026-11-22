function count = ob_function_output_count (block)
  % Function.value remains available to legacy models; outputs is explicit.
  count = 1;
  if (isfield (block, 'outputs') && ! isempty (block.outputs)), count = block.outputs; endif
  if (! isnumeric (count) || ! isreal (count) || ! isscalar (count) ...
      || ! isfinite (count) || count < 1 || count != fix (count) || count > flintmax ())
    error ('ob_function_output_count: Function outputs must be a finite positive integer');
  endif
  count = double (count);
endfunction
