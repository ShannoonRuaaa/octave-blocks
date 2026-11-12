function model = ob_state_space (A, B, C, D, x0 = [])
  % OB_STATE_SPACE  Build a continuous linear system as a virtual subsystem.
  %   MODEL = OB_STATE_SPACE(A,B,C,D[,X0]) implements
  %       x' = A*x + B*u,   y = C*x + D*u,   x(t0) = X0.
  %   For n states, m inputs, and p outputs, dimensions must be A(n,n),
  %   B(n,m), C(p,n), D(p,m), X0(n,1), with m nonnegative and p positive. Empty
  %   B and D select an autonomous system with no input port. Omitted/empty X0
  %   defaults to zeros(n,1). Parameters must be finite full real numeric
  %   matrices and are converted to double. An n=0 system is pure feedthrough.
  %
  %   The returned ordinary model has one numbered Inport when m is positive, carrying the m-by-1
  %   input vector and one Outport carrying the p-by-1 output vector (scalars
  %   when the corresponding count is one). Place it in a Subsystem block;
  %   it uses the existing editor, solvers, save/load, and supported C exporter.
  %   Parameters are fixed model values; this is not a native Simulink block
  %   or an implementation of its tunability/descriptor-system options.
  %   When D is exactly zero, the output graph omits the input feedthrough
  %   branch, preserving state-breaking feedback through the subsystem.
  %
  %   Equations and vector-port convention follow the public reference:
  %   https://www.mathworks.com/help/simulink/slref/statespace.html
  if (nargin < 4 || nargin > 5)
    error ('ob_state_space: supply A, B, C, D, and optional column state x0');
  endif
  A = linear_matrix (A,'A'); B = linear_matrix (B,'B');
  C = linear_matrix (C,'C'); D = linear_matrix (D,'D');
  n = rows(A); p = rows(C);
  if (isempty(B) && isempty(D)), B = zeros(n,0); D = zeros(p,0); endif
  m = columns(B);
  if (columns(A) != n)
    error ('ob_state_space: A must be a square n-by-n matrix');
  endif
  if (p < 1)
    error ('ob_state_space: output count must be positive');
  endif
  if (rows(B) != n || columns(C) != n || !isequal(size(D),[p m]))
    error ('ob_state_space: dimensions must be A(n,n), B(n,m), C(p,n), D(p,m)');
  endif
  if (isempty(x0)), x0 = zeros(n,1); endif
  x0 = linear_matrix (x0,'x0');
  if (!isequal(size(x0),[n 1]))
    error ('ob_state_space: x0 must be an n-by-1 column matching A');
  endif
  if (m == 0 && n == 0)
    model.blocks = struct ('type',{'Constant','Outport'}, ...
        'value',{zeros(p,1),1},'name',{'Zero output','y'}, ...
        'x',{.3,.8},'y',{.5,.5});
    model.edges = [1 1 2 1];
  elseif (m == 0)
    model.blocks = struct ('type',{'Integrator','Gain','Gain','Outport'}, ...
        'value',{x0,A,C,1},'name',{'x','A','C','y'}, ...
        'x',{.4,.4,.7,.9},'y',{.4,.8,.4,.4});
    model.edges = [1 1 2 1;2 1 1 1;1 1 3 1;3 1 4 1];
  elseif (n == 0)
    model.blocks = struct ('type',{'Inport','Gain','Outport'}, ...
        'value',{1,D,1},'name',{'u','D','y'}, ...
        'x',{.12,.5,.88},'y',{.5,.5,.5});
    model.edges = [1 1 2 1;2 1 3 1];
  elseif (all(D(:)==0))
    model.blocks = struct ('type',{'Inport','Gain','Integrator','Gain','Sum','Gain','Outport'}, ...
        'value',{1,B,x0,A,[],C,1},'name',{'u','B','x','A','Ax + Bu','C','y'}, ...
        'x',{.1,.3,.55,.3,.55,.75,.9},'y',{.2,.2,.65,.85,.35,.65,.65});
    model.edges = [1 1 2 1;3 1 4 1;4 1 5 1;2 1 5 2;5 1 3 1;3 1 6 1;6 1 7 1];
  else
    model.blocks = struct ('type',{'Inport','Gain','Integrator','Gain','Sum','Gain','Gain','Sum','Outport'}, ...
        'value',{1,B,x0,A,[],C,D,[],1},'name',{'u','B','x','A','Ax + Bu','C','D','Cx + Du','y'}, ...
        'x',{.1,.3,.55,.3,.55,.7,.7,.85,.95},'y',{.2,.2,.65,.85,.35,.65,.15,.45,.45});
    model.edges = [1 1 2 1;3 1 4 1;4 1 5 1;2 1 5 2;5 1 3 1; ...
                   3 1 6 1;1 1 7 1;6 1 8 1;7 1 8 2;8 1 9 1];
  endif
  model.execution = struct ('mode','virtual');
endfunction

function value = linear_matrix (value, name)
  if (!isnumeric(value) || !isreal(value) || issparse(value) ...
      || ndims(value)>2 || any(!isfinite(value(:))))
    error ('ob_state_space: %s must be a finite full real numeric matrix',name);
  endif
  value = double(value);
endfunction
