function model = ob_discrete_state_space (A, B, C, D, Ts = 0.1, x0 = [], offset = 0)
% OB_DISCRETE_STATE_SPACE  Build a Simulink-style Discrete State-Space subsystem.
%   MODEL = OB_DISCRETE_STATE_SPACE(A,B,C,D[,Ts[,X0[,OFFSET]]]) implements
%       x[k+1] = A*x[k] + B*u[k],   y[k] = C*x[k] + D*u[k],   x[0] = X0
%   using Unit Delay with sample time [Ts OFFSET]. Set Ts = 0 for inherited
%   sample time. When D is identically zero, the direct-feedthrough branch
%   is omitted to preserve state-broken feedback loops.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/discretestatespace.html

  if (nargin < 4 || nargin > 7)
    error ('ob_discrete_state_space: supply A, B, C, D[, Ts, x0, offset]');
  endif
  A = linear_matrix (A, 'A');
  B = linear_matrix (B, 'B');
  C = linear_matrix (C, 'C');
  D = linear_matrix (D, 'D');
  n = rows (A);
  p = rows (C);
  if (isempty (B) && isempty (D)), B = zeros (n, 0); D = zeros (p, 0); endif
  m = columns (B);
  if (columns (A) != n)
    error ('ob_discrete_state_space: A must be square');
  endif
  if (p < 1)
    error ('ob_discrete_state_space: output count must be positive');
  endif
  if (rows (B) != n || columns (C) != n || ! isequal (size (D), [p m]))
    error ('ob_discrete_state_space: dimensions must be A(n,n), B(n,m), C(p,n), D(p,m)');
  endif
  if (! isnumeric (Ts) || ! isreal (Ts) || ! isscalar (Ts) || ! isfinite (Ts) || Ts < 0)
    error ('ob_discrete_state_space: Ts must be a finite nonnegative scalar');
  endif
  if (! isnumeric (offset) || ! isreal (offset) || ! isscalar (offset) || ! isfinite (offset) || offset < 0)
    error ('ob_discrete_state_space: offset must be a finite nonnegative scalar');
  endif
  if (Ts > 0 && offset >= Ts)
    error ('ob_discrete_state_space: offset must satisfy 0 <= offset < Ts');
  endif
  if (Ts == 0 && offset != 0)
    error ('ob_discrete_state_space: offset must be 0 when Ts is inherited (0)');
  endif
  if (isempty (x0)), x0 = zeros (n, 1); endif
  x0 = linear_matrix (x0, 'x0');
  if (! isequal (size (x0), [n 1]))
    error ('ob_discrete_state_space: x0 must be an n-by-1 column matching A');
  endif

  rate = [double(Ts), double(offset)];
  if (m == 0 && n == 0)
    model.blocks = struct ('type', {'Constant', 'Outport'}, ...
      'value', {zeros(p, 1), 1}, 'name', {'Zero output', 'y'}, ...
      'x', {.3, .8}, 'y', {.5, .5});
    model.edges = [1 1 2 1];
    delay_id = [];
  elseif (m == 0)
    model.blocks = struct ('type', {'Unit Delay', 'Gain', 'Gain', 'Outport'}, ...
      'value', {x0, A, C, 1}, 'name', {'x', 'A', 'C', 'y'}, ...
      'x', {.4, .4, .7, .9}, 'y', {.4, .8, .4, .4});
    model.edges = [1 1 2 1; 2 1 1 1; 1 1 3 1; 3 1 4 1];
    delay_id = 1;
  elseif (n == 0)
    model.blocks = struct ('type', {'Inport', 'Gain', 'Outport'}, ...
      'value', {1, D, 1}, 'name', {'u', 'D', 'y'}, ...
      'x', {.12, .5, .88}, 'y', {.5, .5, .5});
    model.edges = [1 1 2 1; 2 1 3 1];
    delay_id = [];
  elseif (all (D(:) == 0))
    model.blocks = struct ('type', {'Inport', 'Gain', 'Unit Delay', 'Gain', 'Sum', 'Gain', 'Outport'}, ...
      'value', {1, B, x0, A, [], C, 1}, 'name', {'u', 'B', 'x', 'A', 'Ax + Bu', 'C', 'y'}, ...
      'x', {.1, .3, .55, .3, .55, .75, .9}, 'y', {.2, .2, .65, .85, .35, .65, .65});
    model.edges = [1 1 2 1; 3 1 4 1; 4 1 5 1; 2 1 5 2; 5 1 3 1; 3 1 6 1; 6 1 7 1];
    delay_id = 3;
  else
    model.blocks = struct ('type', {'Inport', 'Gain', 'Unit Delay', 'Gain', 'Sum', 'Gain', 'Gain', 'Sum', 'Outport'}, ...
      'value', {1, B, x0, A, [], C, D, [], 1}, 'name', {'u', 'B', 'x', 'A', 'Ax + Bu', 'C', 'D', 'Cx + Du', 'y'}, ...
      'x', {.1, .3, .55, .3, .55, .7, .7, .85, .95}, 'y', {.2, .2, .65, .85, .35, .65, .15, .45, .45});
    model.edges = [1 1 2 1; 3 1 4 1; 4 1 5 1; 2 1 5 2; 5 1 3 1; ...
                   3 1 6 1; 1 1 7 1; 6 1 8 1; 7 1 8 2; 8 1 9 1];
    delay_id = 3;
  endif
  if (! isempty (delay_id) && Ts > 0)
    rates = zeros (numel (model.blocks), 2);
    rates(delay_id, :) = rate;
    model.sample_times = rates;
  endif
  model.execution = struct ('mode', 'virtual');
  initial = zeros(p,1);
  if (n > 0), initial = C*x0; endif
  if (any(!isfinite(initial))), error ('ob_discrete_state_space: initial output must remain finite'); endif
  if (m > 0 && (n == 0 || any(D(:) != 0)))
    model = ob_hold_builder_output (model, numel(model.blocks), initial, rate);
  endif
endfunction

function value = linear_matrix (value, name)
  if (! isnumeric (value) || ! isreal (value) || issparse (value) ...
      || ndims (value) > 2 || any (! isfinite (value(:))))
    error ('ob_discrete_state_space: %s must be a finite full real numeric matrix', name);
  endif
  value = double (value);
endfunction
