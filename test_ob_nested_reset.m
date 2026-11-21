function test_ob_nested_reset ()
  cases = ob_nested_reset_cases ();
  for k = 1:numel (cases)
    c = cases(k);
    result = ob_run (c.model,0:7,c.options);
    for port = 1:columns (c.expected)
      actual = ob_scope_data (result,3+port);
      assert (actual,c.expected(:,port),0);
    endfor
  endfor
  fprintf ('nested enable reset: %d cases passed\n',numel (cases));
endfunction
