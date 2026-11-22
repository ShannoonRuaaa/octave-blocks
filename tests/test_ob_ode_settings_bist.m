function test_ob_ode_settings_bist ()
  cleanup = ob_test_setup ();
  [passed,total] = test (mfilename("fullpath"), "quiet");
  assert (total > 0 && passed == total);
  fprintf ("test_ob_ode_settings_bist: %d/%d passed\n",passed,total);
endfunction

%!test
%! expected = odeset ('RelTol', 1e-7, 'AbsTol', 1e-9, 'MaxStep', 0.25, 'Refine', 1);
%! actual = ob_ode_settings ('RelTol', 1e-7, 'AbsTol', 1e-9, 'MaxStep', 0.25, 'Refine', 1);
%! assert (isequal (fieldnames (actual), fieldnames (expected)));
%! assert (isequal (actual, expected));
%! handle = @(t, y, flag) false;
%! assert (isequal (ob_ode_settings (actual, 'OutputFcn', handle), odeset (expected, 'OutputFcn', handle)));
%! assert (isequal (ob_ode_settings (actual, 'InitialSlope', [1; 2]), odeset (expected, 'InitialSlope', [1; 2])));
