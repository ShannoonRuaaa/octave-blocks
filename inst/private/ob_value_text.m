function text = ob_value_text (value)
  % Show a saved block parameter as an editable Octave expression.
  if (nargin == 0)
    text = "";
    return;
  endif
  if (isnumeric (value) || islogical (value))
    text = mat2str (value);
  elseif (ischar (value))
    text = value;
  else
    text = "";
  endif
endfunction
