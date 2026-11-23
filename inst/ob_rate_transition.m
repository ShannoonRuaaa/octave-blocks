function model = ob_rate_transition (input_rate, output_rate, initial_condition = 0, deterministic = true, integrity = true, signal_size = [])
% OB_RATE_TRANSITION  Build a Simulink-style Rate Transition subsystem.
%   MODEL = OB_RATE_TRANSITION(IN_RATE, OUT_RATE[, IC[, DET[, INTEGRITY[, SIZE]]]])
%   transfers a signal produced at IN_RATE to OUT_RATE with Simulink's
%   single-tasking Rate Transition semantics.  IN_RATE is the sample time
%   of the block that drives the input: 0 for a continuous signal, Ts or
%   [Ts offset] for a discrete one.  OUT_RATE is Ts or [Ts offset] with
%   Ts > 0 (Simulink's OutPortSampleTime).  IC is InitialCondition
%   (default 0).  DET ('Ensure deterministic data transfer') and INTEGRITY
%   ('Ensure data integrity during data transfer') are logical scalars,
%   true by default like Simulink's.
%
%   Transfer               Settings            Output at an OUT_RATE hit
%   continuous->discrete,  any                 the input now (sample and
%   fast->slow, equal                          hold); with INTEGRITY, IC
%                                              until the input's first hit
%   slow->fast             INTEGRITY and DET   the input one slow period
%                                              ago (IC at first)
%   slow->fast             INTEGRITY only      the input at the last slow
%                                              hit strictly before now (IC
%                                              before that)
%   slow->fast             no INTEGRITY        the input now (DET ignored)
%
%   As recorded from Simulink: DET (with INTEGRITY) requires zero offsets on
%   both rates and periods that are integer multiples, otherwise an error
%   suggests DET = false; without INTEGRITY, DET has no effect.  With
%   INTEGRITY, IC is the output at every OUT_RATE hit before the input's
%   first sample (an IN_RATE offset larger than the OUT_RATE offset) and
%   the start value of the two delaying slow-to-fast modes; without
%   INTEGRITY such hits output 0.  Before the first OUT_RATE hit (OUT_RATE
%   offset > 0) the output is 0, as Simulink logs it.  OUT_RATE = 0
%   (discrete to continuous) and -1 (inherited) are rejected because Octave
%   Blocks does not propagate sample times: state both rates explicitly.  A
%   continuous integrator downstream of the output sees the held value
%   between hits (doc/MULTIRATE.md).  The integrity-only slow-to-fast mode
%   samples at the common base period of both rates, which must exist.
%
%   IC sets the signal shape (also for ob_codegen).  For a vector or matrix
%   signal give a full-size IC, or a scalar IC with SIZE, the signal width n
%   (a column) or [rows cols], which expands it as Simulink does.  Octave
%   Blocks does not propagate signal widths: a scalar IC without SIZE on a
%   vector signal fails at run time with a state-shape error.
%
%   This builder returns a Subsystem model.  The native 'Rate Transition'
%   block type (model.blocks(k).type = 'Rate Transition', the editor's Rate
%   Transition) is a plain sample and hold with no Integrity or
%   Deterministic options; this subsystem uses it, with Unit Delay blocks,
%   so it keeps strict C99 ob_codegen and ob_accelerate parity.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/ratetransition.html

  if (nargin < 2)
    error ('ob_rate_transition: supply input_rate, output_rate[, initial_condition, deterministic, integrity, signal_size]');
  endif
  in_rate = sample_rate (input_rate, 'input_rate', true);
  out_rate = sample_rate (output_rate, 'output_rate', false);
  validateattributes (initial_condition, {'numeric'}, {'nonempty', '2d', 'real', 'finite', 'nonsparse'}, ...
                      'ob_rate_transition', 'initial_condition');
  det = flag (deterministic, 'deterministic');
  integrity = flag (integrity, 'integrity');
  ic = expand_ic (double (initial_condition), signal_size);
  zero = zeros (size (ic));

  det = det && integrity;
  if (det)
    if (any ([in_rate(2) out_rate(2)] != 0))
      error (['ob_rate_transition: deterministic transfer needs zero sample-time offsets on both rates; ' ...
              'use deterministic = false']);
    endif
    if (in_rate(1) > 0 && ! integer_multiple (in_rate(1), out_rate(1)))
      error (['ob_rate_transition: deterministic transfer needs periods that are integer multiples ' ...
              '(%g and %g); use deterministic = false'], in_rate(1), out_rate(1));
    endif
  endif

  model = ob_builder_block ();
  [model, u] = ob_builder_block (model, 'Inport', 1, 'u', 0.08, 0.50);
  rates = zeros (0, 2);
  if (in_rate(1) > out_rate(1) && det)
    % One slow period late.
    [model, y] = ob_builder_block (model, 'Unit Delay', ic, 'slow delay', 0.50, 0.50, u);
    rates(y, :) = in_rate;
  elseif (in_rate(1) > out_rate(1) && integrity)
    % Last slow sample strictly before the output hit: hold the input at
    % the slow hits, then delay that hold by one base period, which is the
    % value just before any hit of either rate.
    base = base_period ([in_rate out_rate]);
    [model, held] = ob_builder_block (model, 'Rate Transition', ic, 'slow sample', 0.30, 0.50, u);
    [model, y] = ob_builder_block (model, 'Unit Delay', ic, 'previous base step', 0.55, 0.50, held);
    rates(held, :) = in_rate;
    rates(y, :) = [base 0];
    if (abs (base - out_rate(1)) > 8 * eps (base) || out_rate(2) != 0)
      [model, y] = ob_builder_block (model, 'Rate Transition', zero, 'output', 0.78, 0.50, y);
      rates(y, :) = out_rate;
    endif
  else
    if (integrity && ! det && in_rate(1) > 0 && out_rate(2) < in_rate(2) - 8 * eps (in_rate(1)))
      % OUT_RATE hits come before the input's first hit, and Simulink
      % outputs IC there: sample the input at its own rate, holding IC until
      % that first hit, then hold the sample at OUT_RATE.
      [model, u] = ob_builder_block (model, 'Rate Transition', ic, 'input sample', 0.30, 0.50, u);
      rates(u, :) = in_rate;
    endif
    [model, y] = ob_builder_block (model, 'Rate Transition', zero, 'hold', 0.60, 0.50, u);
    rates(y, :) = out_rate;
  endif
  model = ob_builder_block (model, 'Outport', 1, 'y', 0.92, 0.50, y);
  rates(end+1:numel (model.blocks), :) = 0;
  model.sample_times = rates;
endfunction

function rate = sample_rate (value, name, allow_continuous)
  validateattributes (value, {'numeric'}, {'nonempty', 'vector', 'real', 'finite'}, 'ob_rate_transition', name);
  if (numel (value) > 2)
    error ('ob_rate_transition: %s must be Ts or [Ts offset]', name);
  endif
  rate = [double(value(:)') 0](1:2);
  if (rate(1) == -1)
    error ('ob_rate_transition: inherited %s (-1) is not supported; give the sample time explicitly', name);
  endif
  if (rate(1) == 0 && ! allow_continuous)
    error ('ob_rate_transition: %s must be positive (discrete to continuous transfer is not supported)', name);
  endif
  if (rate(1) < 0 || (rate(1) == 0 && rate(2) != 0) || (rate(1) > 0 && (rate(2) < 0 || rate(2) >= rate(1))))
    error ('ob_rate_transition: %s must be 0, Ts > 0 or [Ts offset] with 0 <= offset < Ts', name);
  endif
endfunction

function ic = expand_ic (ic, signal_size)
  % A scalar IC expands to SIGNAL_SIZE (n means an n-by-1 column).
  if (isempty (signal_size))
    return;
  endif
  validateattributes (signal_size, {'numeric'}, {'vector', 'real', 'finite', 'integer', 'positive'}, ...
                      'ob_rate_transition', 'signal_size');
  if (numel (signal_size) > 2)
    error ('ob_rate_transition: signal_size must be a width n or [rows cols]');
  endif
  shape = [double(signal_size(:)') 1](1:2);
  if (isscalar (ic))
    ic = repmat (ic, shape);
  elseif (! isequal (size (ic), shape))
    error ('ob_rate_transition: initial_condition is %dx%d but signal_size is %dx%d', ...
           rows (ic), columns (ic), shape(1), shape(2));
  endif
endfunction

function value = flag (value, name)
  if (! (islogical (value) || isnumeric (value)) || ! isscalar (value) || ! isreal (value) ...
      || ! any (double (value) == [0 1]))
    error ('ob_rate_transition: %s must be a logical scalar', name);
  endif
  value = logical (value);
endfunction

function yes = integer_multiple (a, b)
  ratio = max (a, b) / min (a, b);
  yes = abs (ratio - round (ratio)) <= 8 * eps (ratio);
endfunction

function base = base_period (values)
  % Largest period that divides every positive period and offset: the
  % single-tasking base rate.
  values = values(values > 0);
  smallest = min (values);
  for divisor = 1:10000
    base = smallest / divisor;
    ratio = values / base;
    if (all (abs (ratio - round (ratio)) <= 1000 * eps * max (1, ratio)))
      return;
    endif
  endfor
  error ('ob_rate_transition: the sample times %s have no common base period', mat2str (values));
endfunction
