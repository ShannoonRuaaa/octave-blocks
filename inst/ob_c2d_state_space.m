function [Ad, Bd, Cd, Dd] = ob_c2d_state_space (A, B, C, D, Ts, method = 'zoh')
% OB_C2D_STATE_SPACE  Discretize a continuous state-space model without extra packages.
%   [Ad,Bd,Cd,Dd] = OB_C2D_STATE_SPACE(A,B,C,D,Ts[,METHOD]) discretizes
%       x' = A*x + B*u,  y = C*x + D*u
%   at sample period Ts > 0 using Octave's built-in expm() (for 'zoh',
%   Van Loan block matrix exponential) or bilinear transform ('tustin').
%   Pass the returned matrices directly to ob_discrete_state_space().

  if (nargin < 5 || nargin > 6)
    error ('ob_c2d_state_space: supply A, B, C, D, Ts[, method]');
  endif
  if (! isnumeric (Ts) || ! isreal (Ts) || ! isscalar (Ts) || ! isfinite (Ts) || Ts <= 0)
    error ('ob_c2d_state_space: Ts must be a finite positive scalar');
  endif
  for value = {A,B,C,D}
    validateattributes (value{1}, {'numeric'}, {'2d','real','finite','nonsparse'});
  endfor
  A = double (A); B = double (B); C = double (C); D = double (D);
  n = rows (A); p = rows(C);
  if (isempty(B) && isempty(D)), B = zeros(n,0); D = zeros(p,0); endif
  m = columns (B);
  if (columns(A) != n || rows(B) != n || columns(C) != n || !isequal(size(D),[p m]) || p < 1)
    error ('ob_c2d_state_space: dimensions must be A(n,n), B(n,m), C(p,n), D(p,m)');
  endif
  if (!ischar(method) || !isrow(method))
    error ('ob_c2d_state_space: method must be "zoh" or "tustin"');
  endif
  switch (lower (method))
    case 'zoh'
      M = [A, B; zeros(m, n + m)] * Ts;
      E = expm (M);
      Ad = E(1:n, 1:n);
      Bd = E(1:n, n + 1:end);
      Cd = C;
      Dd = D;
    case 'tustin'
      I_n = eye (n);
      P = I_n - (Ts / 2) * A;
      if (n > 0 && rcond (P) <= eps)
        error ('ob_c2d_state_space: (I - Ts/2*A) is singular for Tustin transform');
      endif
      Ad = P \ (I_n + (Ts / 2) * A);
      Bd = P \ (sqrt (Ts) * B);
      Cd = (sqrt (Ts) * C) / P;
      Dd = D + (Ts / 2) * (C / P) * B;
    otherwise
      error ('ob_c2d_state_space: method must be "zoh" or "tustin"');
  endswitch
  if (any(!isfinite([Ad(:);Bd(:);Cd(:);Dd(:)])))
    error ('ob_c2d_state_space: discretized matrices must remain finite');
  endif
endfunction
