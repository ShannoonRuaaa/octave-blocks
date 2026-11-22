function config = ob_validate_config (config)
  if (! isnumeric (config) || ! isreal (config) || ! isvector (config) ...
      || numel (config) != 3 || any (! isfinite (config(:))) ...
      || config(2) <= config(1) || config(3) <= 0)
    error ("ob_validate_config: settings must be finite [start stop step], stop > start, step > 0");
  endif
  config = config(:)';
endfunction
