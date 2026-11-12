function ob_save_model (file, model, config, options = struct ())
  ob_validate_model (model);
  config = ob_validate_config (config);
  options = ob_solver_options (options);
  % Write beside the destination, then replace it only after a successful save.
  folder = fileparts (file);
  if (isempty (folder)), folder = pwd (); endif
  temporary = [tempname(folder) ".mat"];
  unwind_protect
    save ("-mat7-binary", temporary, "model", "config", "options");
    [ok, message] = movefile (temporary, file, "f");
    if (! ok), error ("ob_save_model: %s", message); endif
  unwind_protect_cleanup
    if (exist (temporary, "file")), unlink (temporary); endif
  end_unwind_protect
endfunction
