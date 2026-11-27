function yes = ob_is_resettable_mode (mode)
  % Internal classification of the sampled reset modes accepted by the engine.
  yes = any (strcmp (mode, {'reset_rising','reset_falling','reset_either'}));
endfunction
