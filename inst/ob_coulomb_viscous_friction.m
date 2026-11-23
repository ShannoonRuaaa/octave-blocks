function model = ob_coulomb_viscous_friction (offset = [1 3 2 0], gain = 1)
% OB_COULOMB_VISCOUS_FRICTION  Build Simulink's Coulomb & Viscous Friction.
%   MODEL = OB_COULOMB_VISCOUS_FRICTION([OFFSET[, GAIN]]) models static
%   (Coulomb) plus viscous friction:
%       y = GAIN .* u + OFFSET .* sign(u)
%   so y(0) = 0 and the output jumps by 2*OFFSET where u changes sign.
%   The defaults are Simulink's: OFFSET = [1 3 2 0] (Coulomb friction
%   value, so a scalar input gives a 1-by-4 output) and GAIN = 1
%   (viscous coefficient).  OFFSET and GAIN may be scalars or arrays of
%   the same size; two vectors of equal length pair element by element
%   whatever their orientation (GAIN takes OFFSET's), like Simulink's 1-D
%   parameters, and other size mixes are rejected.  They broadcast against
%   u; a non-scalar u must have the parameters' size (a row against a
%   column vector would broadcast into a matrix in the engine).  Negative
%   values are accepted, as Simulink does not restrict them.  Sample time
%   is inherited.
%
%   The structure mirrors the library mask (Gain, Gain1, Sign, Sum): the
%   sign is an ob_sign subsystem, so the discontinuity at u = 0 registers
%   zero-crossing guards.  Built from native primitives for full Octave,
%   strict C99 ob_codegen and ob_accelerate parity.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/coulombandviscousfriction.html

  validateattributes (offset, {'numeric'}, {'nonempty', '2d', 'real', 'finite'}, ...
                      'ob_coulomb_viscous_friction', 'offset');
  validateattributes (gain, {'numeric'}, {'nonempty', '2d', 'real', 'finite'}, ...
                      'ob_coulomb_viscous_friction', 'gain');
  offset = full (double (offset)); gain = full (double (gain));
  if (! isscalar (offset) && ! isscalar (gain) && ! size_equal (offset, gain))
    if (isvector (offset) && isvector (gain) && numel (offset) == numel (gain))
      gain = reshape (gain, size (offset));   % Simulink 1-D vectors pair element-wise
    else
      error ('ob_coulomb_viscous_friction: offset and gain sizes must match (or one be scalar); got %dx%d and %dx%d', ...
             rows (offset), columns (offset), rows (gain), columns (gain));
    endif
  endif

  B = @ob_builder_block;
  model = B ();
  [model, u] = B (model, 'Inport', 1, 'u', 0.06, 0.50);
  [model, viscous] = scaled (model, u, gain, 'Gain', 0.40, 0.75);
  [model, sgn] = B (model, 'Subsystem', ob_sign (), 'Sign', 0.24, 0.30, u);
  [model, coulomb] = scaled (model, sgn, offset, 'Gain1', 0.48, 0.30);
  [model, y] = B (model, 'Sum', [], 'Sum', 0.72, 0.50, [viscous coulomb]);
  model = B (model, 'Outport', 1, 'y', 0.92, 0.50, y);
endfunction

function [model, id] = scaled (model, source, factor, name, x, y)
  % K.*u: a native Gain for scalar K, else a C-mapped 'times' of a Constant.
  if (isscalar (factor))
    [model, id] = ob_builder_block (model, 'Gain', factor, name, x, y, source);
  else
    [model, k] = ob_builder_block (model, 'Constant', factor, [name ' value'], x - 0.08, y + 0.12);
    [model, id] = ob_builder_block (model, 'Function', [], 'times', x, y, [k source]);
  endif
endfunction
