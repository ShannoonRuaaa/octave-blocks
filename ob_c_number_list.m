function text = ob_c_number_list (values)
  % Round-trip real doubles as C99 floating constants in column-major order.
  % Even array initializers need floating tokens: decimal integer constants
  % above LLONG_MAX are invalid in strict C99, and -0 would lose its sign.
  if (isempty (values)), text = ''; return; endif
  text = sprintf ('%.17g,', double (values(:)));
  text = regexprep (text, '(^|,)(-?[0-9]+)(?=,)', '$1$2.0');
  text(end) = [];
endfunction
