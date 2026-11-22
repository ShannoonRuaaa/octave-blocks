function model = ob_zero_pole (zeros_vec, poles_vec, gain = 1, x0 = [])
% OB_ZERO_POLE  Build a Simulink-style Zero-Pole transfer function subsystem.
%   MODEL = OB_ZERO_POLE(Z,P[,K[,X0]]) implements
%       H(s) = K * prod(s - Z_j) / prod(s - P_i)
%   supporting both SISO (Z vector, K scalar) and SIMO (Z matrix with one
%   column per output, K scalar or length-p vector matching columns(Z))
%   systems using GNU Octave's built-in poly() and ob_state_space().
%
%   Complex poles and zeros must occur in complex-conjugate pairs so that
%   the resulting polynomial coefficients are real. The number of zeros per
%   output must not exceed the number of poles (proper systems only).
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/zeropole.html

  if (nargin < 2 || nargin > 4)
    error ('ob_zero_pole: supply zeros, poles, optional gain, and optional x0');
  endif
  if (! isnumeric (poles_vec) || issparse (poles_vec) || (! isempty (poles_vec) && ! isvector (poles_vec)) ...
      || any (! isfinite (poles_vec(:))))
    error ('ob_zero_pole: poles must be a finite numeric vector');
  endif
  if (! isnumeric (zeros_vec) || issparse (zeros_vec) || ndims (zeros_vec) > 2 ...
      || any (! isfinite (zeros_vec(:))))
    error ('ob_zero_pole: zeros must be a finite numeric vector or 2-D matrix');
  endif
  if (! isnumeric (gain) || ! isreal (gain) || issparse (gain) || isempty (gain) ...
      || ! isvector (gain) || any (! isfinite (gain(:))))
    error ('ob_zero_pole: gain must be a nonempty finite real scalar or vector');
  endif

  poles_vec = double (poles_vec(:));
  n = numel (poles_vec);
  den = real_poly (poles_vec, 'poles');

  if (isempty (zeros_vec))
    p = numel (gain);
    num_mat = zeros (p, n + 1);
    num_mat(:, end) = double (gain(:));
  else
    if (isvector (zeros_vec) && !(isrow(zeros_vec) && numel(gain)>1))
      Z = double (zeros_vec(:));
    else
      Z = double (zeros_vec);
    endif
    m_z = rows (Z);
    p = columns (Z);
    if (m_z > n)
      error ('ob_zero_pole: number of zeros (%d) must not exceed number of poles (%d)', m_z, n);
    endif
    gain = double (gain(:));
    if (isscalar (gain))
      gain = repmat (gain, p, 1);
    elseif (numel (gain) != p)
      error ('ob_zero_pole: gain length (%d) must match output count (%d)', numel (gain), p);
    endif
    num_mat = zeros (p, n + 1);
    for col = 1:p
      num_poly = gain(col) * real_poly (Z(:, col), 'zeros');
      num_mat(col, (n + 2 - numel (num_poly)):end) = num_poly;
    endfor
  endif

  D = num_mat(:, 1);
  if (n == 0)
    model = ob_state_space (zeros (0), zeros (0, 1), zeros (p, 0), D, x0);
  else
    A = rot90 (compan (den), 2);
    B = [zeros(n - 1, 1); 1];
    C = fliplr (num_mat(:, 2:end) - D * den(2:end));
    if (any (! isfinite (C(:))))
      error ('ob_zero_pole: realization coefficients must remain finite');
    endif
    model = ob_state_space (A, B, C, D, x0);
  endif
endfunction

function coeffs = real_poly (roots_vec, name)
  if (isempty (roots_vec))
    coeffs = 1;
    return;
  endif
  coeffs = poly (roots_vec);
  if (any(!isfinite(coeffs)))
    error ('ob_zero_pole: polynomial coefficients must remain finite');
  endif
  tol = 1e-10 * max (1, max (abs (coeffs)));
  if (max (abs (imag (coeffs))) > tol)
    error ('ob_zero_pole: complex %s must appear in conjugate pairs', name);
  endif
  coeffs = real (coeffs);
endfunction
