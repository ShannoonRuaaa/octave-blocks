function yes = ob_is_resettable_mode (mode)
  yes = any (strcmp (mode, {'reset_rising','reset_falling','reset_either'}));
endfunction
