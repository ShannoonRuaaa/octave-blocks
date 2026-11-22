function model = ob_lookup_table_1d (breakpoints, table_data, extrapolate = 'clip')
% OB_LOOKUP_TABLE_1D  Build a Simulink-style 1-D Lookup Table subsystem.
%   MODEL = OB_LOOKUP_TABLE_1D(BREAKPOINTS, TABLE_DATA[, EXTRAPOLATE])
%   realizes a piecewise-linear 1-D lookup table using only Constant, Sum,
%   Saturation, and Gain blocks:
%       f(u) = y_1 + sum_{k=1}^{M-1} m_k * sat_{[0, dx_k]}(u - x_k)
%   where dx_k = x_{k+1} - x_k and m_k = (y_{k+1} - y_k) / dx_k.
%
%   Because the realization uses only native primitives, it automatically
%   supports RK4/ode45/ode15s, exact zero-crossing detection at every
%   breakpoint (via Saturation guards), matrix inputs, and strict C99
%   export via ob_codegen without external C runtime helpers.
%
%   EXTRAPOLATE: 'clip' (default, clamp outside [x_1, x_M]) or 'linear'
%   (extend the first and last segment slopes outside the breakpoint range).
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/1dlookuptable.html

  if (nargin < 2 || nargin > 3)
    error ('ob_lookup_table_1d: supply breakpoints, table_data[, extrapolate]');
  endif
  if (! isnumeric (breakpoints) || ! isreal (breakpoints) || ! isvector (breakpoints) ...
      || numel (breakpoints) < 2 || any (! isfinite (breakpoints)))
    error ('ob_lookup_table_1d: breakpoints must be a finite real vector with at least 2 points');
  endif
  if (! isnumeric (table_data) || ! isreal (table_data) || ! isvector (table_data) ...
      || numel (table_data) != numel (breakpoints) || any (! isfinite (table_data)))
    error ('ob_lookup_table_1d: table_data must be a finite real vector matching breakpoints length');
  endif
  if (! ischar (extrapolate) || ! any (strcmp (extrapolate, {'clip', 'linear'})))
    error ('ob_lookup_table_1d: extrapolate must be "clip" or "linear"');
  endif

  bp = double (breakpoints(:)');
  td = double (table_data(:)');
  dx = diff (bp);
  if (any (dx <= 0) || any (! isfinite(dx)))
    error ('ob_lookup_table_1d: breakpoints must be strictly increasing');
  endif
  slopes = diff (td) ./ dx;
  if (any (! isfinite(slopes)))
    error ('ob_lookup_table_1d: segment slopes must remain finite');
  endif
  n_seg = numel (dx);

  blocks = struct ('type', {}, 'value', {}, 'name', {}, 'x', {}, 'y', {});
  edges = zeros (0, 4);

  function id = add_block (type, value, name, x, y)
    id = numel (blocks) + 1;
    blocks(id) = struct ('type', type, 'value', value, 'name', name, 'x', x, 'y', y);
  endfunction

  function wire (src, dst, dst_port)
    if (nargin < 3), dst_port = 1; endif
    edges(end + 1, :) = [src 1 dst dst_port];
  endfunction

  id_u = add_block ('Inport', 1, 'u', 0.06, 0.50);
  id_y0 = add_block ('Constant', td(1), 'y0', 0.55, 0.90);
  sum_inputs = id_y0;

  for k = 1:n_seg
    y_pos = 0.80 - 0.65 * (k - 1) / max (1, n_seg - 1);
    id_neg_xk = add_block ('Constant', -bp(k), sprintf ('-x%d', k), 0.18, y_pos);
    id_shift = add_block ('Sum', [], sprintf ('u-x%d', k), 0.30, y_pos);
    wire (id_u, id_shift, 1);
    wire (id_neg_xk, id_shift, 2);

    if (strcmp (extrapolate, 'linear') && n_seg == 1)
      id_seg = id_shift;
    elseif (strcmp (extrapolate, 'linear') && k == 1)
      id_seg = select_segment (id_shift, dx(1), true, y_pos);
    elseif (strcmp (extrapolate, 'linear') && k == n_seg)
      id_seg = select_segment (id_shift, 0, false, y_pos);
    else
      id_seg = add_block ('Saturation', [0, dx(k)], sprintf ('Seg%d', k), 0.46, y_pos);
      wire (id_shift, id_seg, 1);
    endif

    id_m = add_block ('Gain', slopes(k), sprintf ('m%d', k), 0.62, y_pos);
    wire (id_seg, id_m, 1);
    sum_inputs(end + 1) = id_m;
  endfor

  id_sum = sum_inputs(1);
  for k = 2:numel (sum_inputs)
    next = add_block ('Sum', [], 'LUT Sum', 0.70+0.18*(k-1)/n_seg, 0.50);
    wire (id_sum, next, 1);
    wire (sum_inputs(k), next, 2);
    id_sum = next;
  endfor
  id_out = add_block ('Outport', 1, 'y', 0.92, 0.50);
  wire (id_sum, id_out, 1);

  model = struct ('blocks', blocks, 'edges', edges, ...
                  'execution', struct ('mode', 'virtual'));

  function id = select_segment (shift, bound, upper, y)
    zero = add_block ('Gain', 0, 'Shaped zero', 0.34, y);
    wire (shift, zero);
    fixed = zero;
    if (bound != 0)
      value = add_block ('Constant', bound, 'Segment endpoint', 0.37, y);
      fixed = add_block ('Sum', [], 'Shaped endpoint', 0.42, y);
      wire (zero, fixed, 1);
      wire (value, fixed, 2);
    endif
    id = add_block ('Switch', bound, 'Linear extrapolation', 0.52, y);
    wire (shift, id, 2);
    if (upper)
      wire (fixed, id, 1);
      wire (shift, id, 3);
    else
      wire (shift, id, 1);
      wire (fixed, id, 3);
    endif
  endfunction
endfunction
