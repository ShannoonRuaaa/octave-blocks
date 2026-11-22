function y = ob_bench_mackey_term (z)
  % Mackey-Glass production term used by ob_benchmark_models.
  y = 0.2 * z ./ (1 + z.^10);
endfunction
