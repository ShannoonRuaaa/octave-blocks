function model = ob_mux (inputs = 2, widths = [])
% OB_MUX  Build a Simulink-style Mux subsystem (signals -> one column vector).
%   MODEL = OB_MUX(N) concatenates N >= 1 scalar inputs into an N-by-1
%   column vector.
%   MODEL = OB_MUX(N, WIDTHS) declares the width of each input: WIDTHS is a
%   vector of N positive integers, and input k must be a WIDTHS(k)-by-1
%   column vector (a scalar when the width is 1).  The output is the
%   SUM(WIDTHS)-by-1 concatenation, input 1 first.
%   MODEL = OB_MUX(WIDTHS) with a vector of two or more widths is the same
%   as OB_MUX(NUMEL(WIDTHS), WIDTHS), like Simulink's Inputs = '[2 1]'.
%
%   Simulink's default is Inputs = 2.  Simulink infers the width of each
%   input (and its Inputs width -1 means inherited); Octave Blocks needs the
%   widths when the subsystem is built, so inputs that are not scalars must
%   be declared.  Inputs must be column vectors: Simulink's Mux also
%   accepts a row vector (Mux(2) of [1 2] and 3 gives [1;2;3]), but the
%   native Gain selection needs a column, so a row vector, like a signal of
%   the wrong width, is reported by ob_run or ob_codegen as a Gain
%   dimension error ("nonconformant").  Use this builder to bundle signals
%   into a vector (the role of a virtual Bus Creator, which Octave Blocks
%   does not provide).
%
%   Input k is scaled by the selection matrix that places it in rows
%   OFFSET+1..OFFSET+WIDTHS(k), and the products are added by a chain of
%   native 2-input Sum blocks, so any N works with ob_run, zero crossings,
%   strict C99 ob_codegen and ob_accelerate.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/mux.html

  validateattributes (inputs, {'numeric'}, {'nonempty', 'vector', 'real', 'finite', 'integer', 'positive'}, ...
                      'ob_mux', 'inputs');
  if (! isscalar (inputs))
    if (nargin > 1)
      error ('ob_mux: give the widths either as the first argument or as WIDTHS, not both');
    endif
    widths = inputs;
  elseif (isempty (widths))
    widths = ones (1, inputs);
  endif
  validateattributes (widths, {'numeric'}, {'nonempty', 'vector', 'real', 'finite', 'integer', 'positive'}, ...
                      'ob_mux', 'widths');
  widths = double (widths(:)');
  n = numel (widths);
  if (isscalar (inputs) && n != inputs)
    error ('ob_mux: WIDTHS must have one entry per input (%d)', double (inputs));
  endif

  total = sum (widths);
  last = cumsum (widths);
  identity = eye (total);
  model = ob_builder_block ();
  chain = [];
  for k = 1:n
    y = 0.85 - 0.70 * (k - 1) / max (1, n - 1);
    [model, u] = ob_builder_block (model, 'Inport', k, sprintf ('u%d', k), 0.08, y);
    [model, g] = ob_builder_block (model, 'Gain', identity(:, last(k)-widths(k)+1:last(k)), ...
                                   sprintf ('rows %d:%d', last(k)-widths(k)+1, last(k)), 0.35, y, u);
    if (isempty (chain))
      chain = g;
    else
      [model, chain] = ob_builder_block (model, 'Sum', [], sprintf ('stack %d', k), ...
                                         0.55 + 0.30 * (k - 1) / n, 0.50, [chain g]);
    endif
  endfor
  model = ob_builder_block (model, 'Outport', 1, 'y', 0.94, 0.50, chain);
endfunction
