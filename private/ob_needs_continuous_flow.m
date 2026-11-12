function yes = ob_needs_continuous_flow (model)
  options = ob_execution_options (model, false);
  yes = (strcmp (options.mode, 'enabled') && strcmp (options.control, 'continuous')) ...
        || ob_has_continuous_control (model) || ob_has_continuous (model) || ob_has_inner_clocks (model);
endfunction
