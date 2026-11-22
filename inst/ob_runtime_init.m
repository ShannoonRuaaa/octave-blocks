function runtime = ob_runtime_init (model, start_time = 0, options = struct ())
  % Create an independent, resumable model execution context.
  runtime = ob_runtime_engine ('init', model, start_time, options);
endfunction
