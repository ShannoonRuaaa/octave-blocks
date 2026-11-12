function runtime = ob_runtime_step (runtime, next_time)
  % Assign the returned context; errors leave the caller's value unchanged.
  runtime = ob_runtime_engine ('step', runtime, next_time);
endfunction
