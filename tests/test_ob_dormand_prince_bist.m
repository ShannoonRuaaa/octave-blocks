function test_ob_dormand_prince_bist ()
  cleanup = ob_test_setup ();
  [passed,total] = test (mfilename("fullpath"), "quiet");
  assert (total > 0 && passed == total);
  fprintf ("test_ob_dormand_prince_bist: %d/%d passed\n",passed,total);
endfunction

%!test
%! % Bit-identical to Octave's ode45 on a nonlinear system, accepted steps
%! % and right-hand side calls included.
%! if (ob_dormand_prince ('available'))
%!   f = @(t, y) [y(2); -sin(y(1)) + 0.1*cos(3*t)];
%!   for config = {{1e-6, 1e-9, 0.7}, {1e-10, 1e-12, 0.05}, {1e-3, 1e-6, 2}}
%!     [r, a, m] = config{1}{:};
%!     [t1, y1] = ode45 (f, [0.3 4.1], [1; 0], odeset ('RelTol', r, 'AbsTol', a, 'MaxStep', m, 'Refine', 1));
%!     [t2, y2] = ob_dormand_prince (f, 0.3, 4.1, [1; 0], r, a, m);
%!     assert (isequal (t1, t2) && isequal (y1, y2));
%!   endfor
%!   [t1, y1] = ode45 (@(t, y) -2*y, [0 1], 1, odeset ('RelTol', 1e-8, 'AbsTol', 1e-10, 'MaxStep', 1, 'Refine', 1));
%!   [t2, y2] = ob_dormand_prince (@(t, y) -2*y, 0, 1, 1, 1e-8, 1e-10, 1);
%!   assert (isequal (t1, t2) && isequal (y1, y2));
%! endif

%!test
%! % A monitor stop ends integration after the stopping step, as OutputFcn does.
%! if (ob_dormand_prince ('available'))
%!   stop_after = @(t, y, flag) isempty (flag) && t > 0.5;
%!   options = odeset ('RelTol', 1e-6, 'AbsTol', 1e-9, 'MaxStep', 0.1, 'Refine', 1, 'OutputFcn', stop_after);
%!   [t1, y1] = ode45 (@(t, y) cos (t) * y, [0 2], [1; 2], options);
%!   [t2, y2] = ob_dormand_prince (@(t, y) cos (t) * y, 0, 2, [1; 2], 1e-6, 1e-9, 0.1, stop_after);
%!   assert (isequal (t1, t2) && isequal (y1, y2));
%!   assert (t2(end) > 0.5 && t2(end-1) <= 0.5);
%! endif
