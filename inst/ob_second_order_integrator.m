function model = ob_second_order_integrator (x0 = 0, dxdt0 = 0, signal_size = [])
% OB_SECOND_ORDER_INTEGRATOR  Build a Simulink-style 'Integrator, Second-Order' subsystem.
%   MODEL = OB_SECOND_ORDER_INTEGRATOR([X0[, DXDT0[, SIZE]]]) integrates the
%   input twice:
%       d^2x/dt^2 = u,   x(t0) = X0,   dx/dt(t0) = DXDT0
%   Outport 1 is x and Outport 2 is dx/dt, Simulink's port order with
%   ShowOutput = 'both'.  X0 and DXDT0 are Simulink's ICX and ICDXDT
%   (default 0): finite real arrays of one shape, or a scalar that expands
%   to the other's shape.  The input must have the state shape (ob_run also
%   accepts a scalar input; ob_codegen needs the exact shape).
%
%   SIZE is the signal width n (an n-by-1 column) or [rows cols].  With it,
%   scalar X0 and DXDT0 (the defaults included) expand to that shape, as
%   Simulink expands scalar ICX/ICDXDT to the input width.  Octave Blocks
%   does not propagate signal widths, so a vector input needs full-size
%   initial conditions or SIZE; otherwise the run fails with a state-shape
%   error.
%
%   Only the default configuration of Simulink's block is covered: internal
%   initial conditions (ICSourceX/ICSourceDXDT = internal), no limits on x
%   or dx/dt, no wrapping, no external reset and both outputs shown.
%   'Integrator, Second-Order Limited' and the other options are not
%   modelled; native 'Limited Integrator' blocks give saturated states.
%   Built from two native Integrator blocks in series, so it works with
%   every solver, strict C99 ob_codegen and ob_accelerate.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/secondorderintegrator.html

  validateattributes (x0, {'numeric'}, {'nonempty', '2d', 'real', 'finite', 'nonsparse'}, ...
                      'ob_second_order_integrator', 'x0');
  validateattributes (dxdt0, {'numeric'}, {'nonempty', '2d', 'real', 'finite', 'nonsparse'}, ...
                      'ob_second_order_integrator', 'dxdt0');
  x0 = double (x0); dxdt0 = double (dxdt0);
  if (! isempty (signal_size))
    validateattributes (signal_size, {'numeric'}, {'vector', 'real', 'finite', 'integer', 'positive'}, ...
                        'ob_second_order_integrator', 'signal_size');
    if (numel (signal_size) > 2)
      error ('ob_second_order_integrator: signal_size must be a width n or [rows cols]');
    endif
    shape = [double(signal_size(:)') 1](1:2);
    if (isscalar (x0)), x0 = repmat (x0, shape); endif
    if (isscalar (dxdt0)), dxdt0 = repmat (dxdt0, shape); endif
    if (! isequal (size (x0), shape) || ! isequal (size (dxdt0), shape))
      error ('ob_second_order_integrator: x0 and dxdt0 must be scalars or %dx%d arrays to match signal_size', ...
             shape(1), shape(2));
    endif
  endif
  if (isscalar (x0)), x0 = x0 * ones (size (dxdt0)); endif
  if (isscalar (dxdt0)), dxdt0 = dxdt0 * ones (size (x0)); endif
  if (! size_equal (x0, dxdt0))
    error ('ob_second_order_integrator: x0 and dxdt0 must have the same shape (or one must be scalar)');
  endif

  model = ob_builder_block ();
  [model, u] = ob_builder_block (model, 'Inport', 1, 'd2x/dt2', 0.10, 0.50);
  [model, v] = ob_builder_block (model, 'Integrator', dxdt0, 'dx/dt', 0.36, 0.50, u);
  [model, x] = ob_builder_block (model, 'Integrator', x0, 'x', 0.62, 0.65, v);
  model = ob_builder_block (model, 'Outport', 1, 'x', 0.90, 0.65, x);
  model = ob_builder_block (model, 'Outport', 2, 'dx/dt', 0.90, 0.30, v);
endfunction
