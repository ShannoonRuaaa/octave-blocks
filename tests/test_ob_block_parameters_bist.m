function test_ob_block_parameters_bist ()
  cleanup = ob_test_setup ();
  [passed,total] = test (mfilename("fullpath"), "quiet");
  assert (total > 0 && passed == total);
  fprintf ("test_ob_block_parameters_bist: %d/%d passed\n",passed,total);
endfunction

%!test
%! p = ob_block_parameters (struct ('type', 'Transport Delay', 'value', [0.5 2]));
%! assert (p.delay, 0.5); assert (p.initial, 2);
%!test
%! p = ob_block_parameters (struct ('type', 'Transport Delay', 'value', struct ('delay', 1, 'initial', [1 2; 3 4])));
%! assert (p.initial, [1 2; 3 4]);
%!error <positive> ob_block_parameters (struct ('type', 'Transport Delay', 'value', [0 1]))
%!error <delay initial> ob_block_parameters (struct ('type', 'Transport Delay', 'value', 1))
%!test
%! p = ob_block_parameters (struct ('type', 'Limited Integrator', 'value', 3));
%! assert (p.lower, -Inf); assert (p.upper, Inf); assert (p.reset, 'none'); assert (p.initial, 3);
%!test
%! p = ob_block_parameters (struct ('type', 'Limited Integrator', ...
%!       'value', struct ('initial', 5, 'lower', -1, 'upper', 2, 'reset', 'rising')));
%! assert (p.initial, 2); assert (p.reset, 'rising');
%!test
%! p = ob_block_parameters (struct ('type', 'Limited Integrator', ...
%!       'value', struct ('initial', 0, 'reset', 'level hold')));
%! assert (p.reset, 'level hold');
%!error <reset must> ob_block_parameters (struct ('type', 'Limited Integrator', 'value', struct ('initial', 0, 'reset', 'levelhold')))
%!error <lower <= upper> ob_block_parameters (struct ('type', 'Limited Integrator', 'value', struct ('initial', 0, 'lower', 1, 'upper', 0)))
%!error <reset must> ob_block_parameters (struct ('type', 'Limited Integrator', 'value', struct ('initial', 0, 'reset', 'sometimes')))
%!error <unknown parameter> ob_block_parameters (struct ('type', 'Limited Integrator', 'value', struct ('initial', 0, 'gain', 1)))
%!error <match the initial> ob_block_parameters (struct ('type', 'Limited Integrator', 'value', struct ('initial', [0 0], 'upper', [1 2 3])))
