function values = ob_runtime_outputs (runtime, path = [], port = 1)
  % Read current root outputs, or one numbered output at a hierarchical path.
  values = ob_runtime_engine ('outputs', runtime, path, port);
endfunction
