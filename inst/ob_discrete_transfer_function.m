function model = ob_discrete_transfer_function (numerator, denominator, Ts = 0.1, x0 = [], offset = 0)
% OB_DISCRETE_TRANSFER_FUNCTION  Build a Simulink-style Discrete Transfer Fcn.
%   MODEL = OB_DISCRETE_TRANSFER_FUNCTION(NUM,DEN[,Ts[,X0[,OFFSET]]])
%   builds a virtual subsystem realizing H(z) = NUM(z) / DEN(z) in
%   descending powers of z using Octave's built-in deconv() and compan()
%   plus ob_discrete_state_space().
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/discretetransferfcn.html

  if (nargin < 2 || nargin > 5)
    error ('ob_discrete_transfer_function: supply numerator, denominator[, Ts, x0, offset]');
  endif
  numerator = poly_vec (numerator, 'numerator');
  denominator = poly_vec (denominator, 'denominator');
  first = find (denominator != 0, 1);
  if (isempty (first))
    error ('ob_discrete_transfer_function: denominator must not be the zero polynomial');
  endif
  denominator = denominator(first:end);
  first_n = find (numerator != 0, 1);
  if (isempty (first_n)), numerator = 0; else numerator = numerator(first_n:end); endif
  n = numel (denominator) - 1;
  if (numel (numerator) > n + 1)
    error ('ob_discrete_transfer_function: numerator order must not exceed denominator order');
  endif
  scale = denominator(1);
  denominator /= scale;
  numerator /= scale;
  if (any (! isfinite (denominator)) || any (! isfinite (numerator)))
    error ('ob_discrete_transfer_function: normalized coefficients must remain finite');
  endif
  numerator = [zeros(1, n + 1 - numel (numerator)), numerator];
  [D, rem] = deconv (numerator, denominator);
  if (n == 0)
    model = ob_discrete_state_space (zeros (0), zeros (0, 1), zeros (1, 0), D, Ts, x0, offset);
  else
    A = rot90 (compan (denominator), 2);
    B = [zeros(n - 1, 1); 1];
    C = fliplr (rem(2:end));
    model = ob_discrete_state_space (A, B, C, D, Ts, x0, offset);
  endif
endfunction

function v = poly_vec (v, name)
  if (! isnumeric (v) || ! isreal (v) || issparse (v) || ! isvector (v) ...
      || isempty (v) || any (! isfinite (v(:))))
    error ('ob_discrete_transfer_function: %s must be a nonempty finite real vector', name);
  endif
  v = double (v(:)');
endfunction
