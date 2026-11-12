function model = ob_transfer_function (numerator, denominator, x0 = [])
  % OB_TRANSFER_FUNCTION  Build a proper continuous SISO transfer function.
  %   MODEL = OB_TRANSFER_FUNCTION(NUM,DEN[,X0]) returns an ordinary virtual
  %   subsystem implementing H(s)=NUM(s)/DEN(s). Coefficient row or column
  %   vectors use descending powers of s. Leading zeros are removed before
  %   order checks; DEN must contain a nonzero coefficient, and the effective
  %   numerator order cannot exceed the denominator order. Coefficients must
  %   be finite full real numeric vectors; normalization converts to double.
  %   Constant gain and identically zero numerators are supported. No control
  %   package is required and common pole/zero factors are not cancelled.
  %
  %   For normalized DEN=[1 a1 ... an], the controllable companion realization
  %   has x=[z z' ... z^(n-1)]', z^(n)+a1*z^(n-1)+...+an*z=u.
  %   A has ones on the superdiagonal and last row [-an ... -a1]; B=e_n.
  %   Padding normalized NUM to [b0 b1 ... bn] gives D=b0 and
  %   C=[bn ... b1]-b0*[an ... a1]. X0 is this realization's n-by-1 initial
  %   state, defaulting to zero; it is not a list of output derivatives.
  %   A constant denominator has no states and accepts only empty X0.
  %
  %   The optional nonzero X0 is a builder extension: Simulink's Transfer Fcn
  %   block uses zero initial states and directs nonzero-state models toward
  %   a State-Space realization. This builder uses OB_STATE_SPACE and does not
  %   claim identical internal state order to MATLAB tf2ss or native block parity.
  %   Public coefficient convention and properness reference:
  %   https://www.mathworks.com/help/simulink/slref/transferfcn.html
  if (nargin < 2 || nargin > 3)
    error ('ob_transfer_function: supply numerator, denominator, and optional column state x0');
  endif
  numerator = polynomial (numerator,'numerator');
  denominator = polynomial (denominator,'denominator');
  first = find(denominator!=0,1);
  if (isempty(first)), error ('ob_transfer_function: denominator must not be the zero polynomial'); endif
  denominator = denominator(first:end);
  first = find(numerator!=0,1);
  if (isempty(first)), numerator = 0; else numerator = numerator(first:end); endif
  n = numel(denominator)-1;
  if (numel(numerator)>n+1)
    error ('ob_transfer_function: numerator order must not exceed denominator order (proper systems only)');
  endif
  scale = denominator(1); denominator /= scale; numerator /= scale;
  if (any(!isfinite(denominator)) || any(!isfinite(numerator)))
    error ('ob_transfer_function: normalized coefficients must remain finite');
  endif
  numerator = [zeros(1,n+1-numel(numerator)) numerator];
  D = numerator(1);
  if (n == 0)
    model = ob_state_space (zeros(0),zeros(0,1),zeros(1,0),D,x0);
  else
    A = [zeros(n-1,1) eye(n-1);-fliplr(denominator(2:end))];
    B = [zeros(n-1,1);1];
    C = fliplr(numerator(2:end)-D*denominator(2:end));
    if (any(!isfinite(C)))
      error ('ob_transfer_function: realization coefficients must remain finite');
    endif
    model = ob_state_space (A,B,C,D,x0);
  endif
endfunction

function coefficients = polynomial (coefficients, name)
  if (!isnumeric(coefficients) || !isreal(coefficients) || issparse(coefficients) ...
      || !isvector(coefficients) || isempty(coefficients) || any(!isfinite(coefficients(:))))
    error ('ob_transfer_function: %s must be a nonempty finite full real coefficient vector',name);
  endif
  coefficients = double(coefficients(:)');
endfunction
