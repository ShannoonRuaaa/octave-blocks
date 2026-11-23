function model = ob_demux (outputs = 2, input_width = [])
% OB_DEMUX  Build a Simulink-style Demux subsystem (column vector -> signals).
%   MODEL = OB_DEMUX(N) splits an N-by-1 column vector input into N scalar
%   Outports.
%   MODEL = OB_DEMUX(N, M) splits an M-by-1 input into N outputs the way
%   Simulink does: when N divides M every output has M/N elements;
%   otherwise the first mod(M, N) outputs have ceil(M/N) elements and the
%   rest floor(M/N) (Simulink warns about the nonuniform distribution).
%   MODEL = OB_DEMUX(WIDTHS) with a vector of two or more widths gives
%   output k WIDTHS(k) elements, like Simulink's Outputs = '[1 3]'; the
%   input width is SUM(WIDTHS) (M, when given, must equal it).
%
%   Simulink's default is Outputs = 2.  Simulink infers the input width;
%   Octave Blocks needs it when the subsystem is built, so give M when it
%   differs from N.  The input must be a column vector (a scalar when M is
%   1).  Simulink's Demux also accepts a row vector, but the native Gain
%   selection needs a column, so a row vector, like a different width, is
%   reported by ob_run or ob_codegen as a Gain dimension error
%   ("nonconformant").  Outputs of width 1 are scalars, wider outputs are
%   column vectors.  Use it to take a vector apart again
%   (the role of a Bus Selector on a virtual bus, which Octave Blocks does
%   not provide).
%
%   Output k is the matching block of identity rows times the input (a
%   native Gain), so it works with ob_run, zero crossings, strict C99
%   ob_codegen and ob_accelerate.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/demux.html

  validateattributes (outputs, {'numeric'}, {'nonempty', 'vector', 'real', 'finite', 'integer', 'positive'}, ...
                      'ob_demux', 'outputs');
  if (! isempty (input_width))
    validateattributes (input_width, {'numeric'}, {'scalar', 'real', 'finite', 'integer', 'positive'}, ...
                        'ob_demux', 'input_width');
  endif
  outputs = double (outputs(:)');
  if (isscalar (outputs))
    n = outputs;
    if (isempty (input_width)), input_width = n; endif
    m = double (input_width);
    if (m < n)
      error ('ob_demux: input_width (%d) must be at least the number of outputs (%d)', m, n);
    endif
    widths = floor (m / n) * ones (1, n);
    widths(1:mod (m, n)) += 1;
  else
    widths = outputs;
    m = sum (widths);
    if (! isempty (input_width) && double (input_width) != m)
      error ('ob_demux: input_width (%d) must equal sum(widths) (%d)', double (input_width), m);
    endif
  endif

  n = numel (widths);
  last = cumsum (widths);
  identity = eye (m);
  model = ob_builder_block ();
  [model, u] = ob_builder_block (model, 'Inport', 1, 'u', 0.10, 0.50);
  for k = 1:n
    y = 0.85 - 0.70 * (k - 1) / max (1, n - 1);
    rows = last(k)-widths(k)+1:last(k);
    [model, g] = ob_builder_block (model, 'Gain', identity(rows, :), ...
                                   sprintf ('rows %d:%d', rows(1), rows(end)), 0.50, y, u);
    model = ob_builder_block (model, 'Outport', k, sprintf ('y%d', k), 0.88, y, g);
  endfor
endfunction
