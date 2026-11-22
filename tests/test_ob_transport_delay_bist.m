function test_ob_transport_delay_bist ()
  cleanup = ob_test_setup ();
  [passed,total] = test (mfilename("fullpath"), "quiet");
  assert (total > 0 && passed == total);
  fprintf ("test_ob_transport_delay_bist: %d/%d passed\n",passed,total);
endfunction

%!shared params, h
%! params = struct ('delay', 1, 'initial', 5);
%! h = ob_transport_delay ('init');
%! h = ob_transport_delay ('record', params, h, 0, 0, 'right', 1);
%! h = ob_transport_delay ('record', params, h, 1, 1, 'left', 1);
%! h = ob_transport_delay ('record', params, h, 1, 3, 'right', 1);
%! h = ob_transport_delay ('record', params, h, 1.5, 3.5, 'left', 1);
%!assert (ob_transport_delay ('output', params, h, 0.5), 5)
%!assert (ob_transport_delay ('output', params, h, 1.5), 0.5)
%!assert (ob_transport_delay ('output', params, h, 2, true), 1)
%!assert (ob_transport_delay ('output', params, h, 2), 3)
%!assert (ob_transport_delay ('output', params, h, 2.25), 3.25)
%!assert (ob_transport_delay ('output', params, h, 3), 3.5)
%!assert (ob_transport_delay ('jumps', params, h, 0, 10), [2 1])
%!assert (h.start, 0)
%!test
%! % At exactly start + T the output is u(start), right-continuous, while
%! % its left limit is still the initial output.
%! assert (ob_transport_delay ('output', params, h, 1), 0);
%! assert (ob_transport_delay ('output', params, h, 1, true), 5);
%! assert (ob_transport_delay ('output', params, h, 1 - eps, true), 5);
%!test
%! % A single recorded sample: the left limit at start + T is the initial value.
%! g = ob_transport_delay ('record', params, ob_transport_delay ('init'), 0, 2, 'right', 1);
%! assert (ob_transport_delay ('output', params, g, 1, true), 5);
%! assert (ob_transport_delay ('output', params, g, 1), 2);
%!test
%! % Pruning keeps the start time, so jumps () and the initial interval agree.
%! g = ob_transport_delay ('record', params, h, 4, 9, 'right', 1);
%! assert (g.t', [1 1.5 4]);
%! assert (g.start, 0);
%! assert (ob_transport_delay ('jumps', params, g, 0, 10), 1);
%! assert (ob_transport_delay ('output', params, g, 0.9, true), 5);
%!test
%! % Cubic Hermite slopes reproduce a quadratic input exactly.
%! q = ob_transport_delay ('init');
%! for s = 0:3, q = ob_transport_delay ('record', params, q, s, s^2, 'right', 1); endfor
%! assert (ob_transport_delay ('output', params, q, 2.5), 2.25, 1e-14);
%! assert (ob_transport_delay ('output', params, q, 3.25), 5.0625, 1e-14);
%!test
%! g = ob_transport_delay ('record', params, h, 1.5, 6, 'right', 1);
%! assert (g.t', [0 1 1 1.5 1.5]); assert (g.u(end), 6);
%! g = ob_transport_delay ('record', params, g, 1.5, 7, 'right', 1);
%! assert (g.t', [0 1 1 1.5 1.5]); assert (g.u(end), 7);
%!test
%! % 'shape' broadcasts a scalar initial output before any sample exists.
%! g = ob_transport_delay ('shape', params, ob_transport_delay ('init'), [1; 2], 1);
%! assert (isempty (g.t)); assert (isempty (g.start)); assert (g.shape, [2 1]);
%! assert (ob_transport_delay ('output', params, g, 0), [5; 5]);
%!test
%! % A scalar input is expanded to a matrix initial output's shape.
%! p = struct ('delay', 1, 'initial', [5; 6]);
%! g = ob_transport_delay ('record', p, ob_transport_delay ('init'), 0, 2, 'right', 1);
%! g = ob_transport_delay ('record', p, g, 0.5, 3, 'right', 1);
%! assert (g.shape, [2 1]);
%! assert (ob_transport_delay ('output', p, g, 0.5), [5; 6]);
%! assert (ob_transport_delay ('output', p, g, 1.5), [3; 3]);
%!test
%! % Histories saved without 'start' still use their oldest sample.
%! g = rmfield (h, 'start');
%! assert (ob_transport_delay ('output', params, g, 1, true), 5);
%! assert (ob_transport_delay ('jumps', params, g, 0, 10), [2 1]);
%!test
%! % (0.1 + 0.2) - 0.2 > 0.1: the start + T boundary and a stored jump shifted
%! % by T are still met exactly by queries at the sums jumps () returns.
%! p = struct ('delay', 0.2, 'initial', 7);
%! g = ob_transport_delay ('record', p, ob_transport_delay ('init'), 0.1, 0.1, 'right', 1);
%! g = ob_transport_delay ('record', p, g, 0.2, 0, 'left', 1);
%! g = ob_transport_delay ('record', p, g, 0.2, 1, 'right', 1);
%! g = ob_transport_delay ('record', p, g, 0.3, 1, 'left', 1);
%! assert ((0.1 + 0.2) - 0.2 > 0.1);
%! assert (ob_transport_delay ('output', p, g, 0.1 + 0.2, true), 7);
%! assert (ob_transport_delay ('output', p, g, 0.1 + 0.2), 0.1);
%! assert (ob_transport_delay ('output', p, g, 0.2 + 0.2, true), 0);
%! assert (ob_transport_delay ('output', p, g, 0.2 + 0.2), 1);
%! % A query a few ulps from start + T or t(j) + T is the same instant.
%! assert (ob_transport_delay ('output', p, g, 0.3, true), 7);
%! assert (ob_transport_delay ('output', p, g, 0.3), 0.1);
%! assert (ob_transport_delay ('output', p, g, 0.4 - eps (0.4), true), 0);
%! assert (ob_transport_delay ('output', p, g, 0.4 + eps (0.4)), 1);
%!test
%! % A Step at 0.7 and the output time 7 * 0.1 = 0.7 + ulp are one instant:
%! % the samples merge into a stored jump instead of a 1e-16 interval.
%! p = struct ('delay', 0.1, 'initial', 0);
%! g = ob_transport_delay ('record', p, ob_transport_delay ('init'), 0.6, 0, 'right', 1);
%! g = ob_transport_delay ('record', p, g, 0.7, 0, 'left', 1);
%! g = ob_transport_delay ('record', p, g, 7 * 0.1, 1, 'left', 1);
%! g = ob_transport_delay ('record', p, g, 7 * 0.1, 1, 'right', 1);
%! g = ob_transport_delay ('record', p, g, 0.8, 1, 'left', 1);
%! assert (g.t', [0.6 0.7 0.7 0.8]); assert (g.u', [0 0 1 1]);
%! assert (ob_transport_delay ('jumps', p, g, 0.7, 1), 0.7 + 0.1);
%! assert (ob_transport_delay ('output', p, g, 0.85), 1);
%! assert (ob_transport_delay ('output', p, g, 0.75), 0);
%! % A merged sample replaces the right limit of a stored jump.
%! g = ob_transport_delay ('record', p, g, 0.8 + eps (0.8), 2, 'left', 1);
%! assert (g.t', [0.6 0.7 0.7 0.8 0.8]); assert (g.u', [0 0 1 1 2]);
%! g = ob_transport_delay ('record', p, g, 0.8 + 2 * eps (0.8), 3, 'right', 1);
%! assert (g.u', [0 0 1 1 3]);
%!test
%! % jumps () leaves out a boundary at the same instant as an existing one.
%! p = struct ('delay', 0.1, 'initial', 0);
%! g = ob_transport_delay ('record', p, ob_transport_delay ('init'), 0.6, 0, 'right', 1);
%! g = ob_transport_delay ('record', p, g, 0.7, 0, 'left', 1);
%! g = ob_transport_delay ('record', p, g, 0.7, 1, 'right', 1);
%! assert (0.7 + 0.1 != 8 * 0.1);
%! assert (isempty (ob_transport_delay ('jumps', p, g, 0.7, 8 * 0.1)));
%! assert (isempty (ob_transport_delay ('jumps', p, g, 0.7, 1, [0.7 8 * 0.1 1])));
%! assert (ob_transport_delay ('jumps', p, g, 0.7, 1, [0.7 0.75 1]), 0.7 + 0.1);
%! assert (ob_transport_delay ('output', p, g, 8 * 0.1, true), 0);
%! assert (ob_transport_delay ('output', p, g, 8 * 0.1), 1);
%!error <backward> ob_transport_delay ('record', params, h, 1, 0, 'right', 1)
%!error <shape> ob_transport_delay ('record', struct ('delay', 1, 'initial', [1 2]), ob_transport_delay ('init'), 0, [1 2 3], 'right', 3)
