function combined = ob_is_combined_mode (mode)
  % Internal control classification shared by the editor, runtime and C exporter.
  % Combined controls use data ports, then enable, then trigger.
  combined = any (strcmp (mode, {'enabled_rising','enabled_falling','enabled_either'}));
endfunction
