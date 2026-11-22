function test_ob_runtime_fast_paths (mode = 'check')
  % Regression tests for the interpreted engine's fast paths
  % (RUNTIME_PERFORMANCE.md, 2026-11-21).
  %
  % 1. Golden fingerprints of ob_run results recorded from the engine before
  %    the fast paths existed.  They cover the paths that do not depend on
  %    the evaluation plan: packed scalar RK4/adaptive stages, the flat
  %    zero-crossing right-hand side, the scalar control-output path, inlined
  %    Transport Delay interpolation, guard comparisons, held state outputs
  %    and positional input records.
  % 2. Packed scalar solver stages against the general cell path in the same
  %    run (independent of the platform's libm and BLAS).
  % 3. The prepared evaluation plan (runtime_info.plan) selects numeric
  %    dispatch, its own index lists, source map and parameters, and a
  %    single-hit step for models without clocks or conditional bodies.
  %    Contexts without it (older checkpoints) or with a cache of another
  %    kind take the general paths.  All must give bit-identical contexts and
  %    the same errors.
  % 4. The evaluation program (plan.program, built for the context's order)
  %    exists exactly for models without algebraic loops, conditional bodies
  %    or Rate Transitions.  A plan without it (contexts saved before it
  %    existed) must give identical contexts, and its inline control outputs
  %    must report the same errors.
  %
  % test_ob_runtime_fast_paths ('record') prints the golden table for the
  % engine first on the path instead of testing; it was run once with the
  % pre-change tree first on the path.
  if (strcmp (mode, 'record'))
    record_goldens ();
    return;
  endif
  check_goldens ();
  check_packed_stages ();

  B = @(type, value, name) struct ('type', type, 'value', value, 'name', name, 'x', 0, 'y', 0);
  cases = {};
  add = @(name, model, options, times) struct ('name', name, 'model', model, ...
                                               'options', options, 'times', times);
  oscillator = ob_oscillator ();
  cases{end+1} = add ('oscillator rk4', oscillator, struct ('solver', 'rk4'), [0.1 0.35 1]);
  cases{end+1} = add ('oscillator ode45', oscillator, struct ('solver', 'ode45'), [0.2 0.7]);
  cases{end+1} = add ('oscillator ode15s', oscillator, struct ('solver', 'ode15s'), [0.2 0.5]);

  % A matrix state (general cell path) and a single-precision derivative,
  % whose stage values change class exactly as the general path's do.
  matrix.blocks = [B('Constant', [1 2; 3 4], 'u') B('Integrator', zeros (2), 'x') B('Scope', [], 'y')];
  matrix.edges = [1 2; 2 3];
  cases{end+1} = add ('matrix rk4', matrix, struct ('solver', 'rk4'), [0.5 1]);
  cases{end+1} = add ('matrix ode45', matrix, struct ('solver', 'ode45'), [0.5 1]);
  single_gain = oscillator; single_gain.blocks(3).value = single (-1);
  cases{end+1} = add ('single derivative rk4', single_gain, struct ('solver', 'rk4'), [0.1 0.2]);

  % Delays (single-hit path with right-limit records), limited integrators
  % with resets (general path), steps, inputs and multirate clocks.
  dde.blocks = [B('Integrator', 1, 'x') B('Transport Delay', [0.3 1], 'Delay') ...
                B('Gain', -1, 'Gain') B('Scope', [], 'Scope')];
  dde.edges = [1 2; 2 3; 3 1; 1 4];
  cases{end+1} = add ('delay rk4', dde, struct ('solver', 'rk4'), [0.1 0.25 0.6 1]);
  cases{end+1} = add ('delay ode45', dde, struct ('solver', 'ode45'), [0.25 0.6]);
  limited.blocks = [B('Constant', 1, 'u') ...
                    B('Limited Integrator', struct ('initial', 0, 'lower', 0, 'upper', 0.3, 'reset', 'rising'), 'x') ...
                    B('Step', [0.4 -1 1], 'reset') B('Scope', [], 'y')];
  limited.edges = [1 1 2 1; 3 1 2 2; 2 1 4 1];
  cases{end+1} = add ('limited rk4', limited, struct ('solver', 'rk4'), [0.2 0.5 0.8]);
  cases{end+1} = add ('limited ode45', limited, struct ('solver', 'ode45'), [0.5 0.8]);
  cases{end+1} = add ('input example', ob_input_example (), struct (), [0.5 1.5]);
  cases{end+1} = add ('multirate', ob_multirate_example (), struct (), [0.25 0.5 1]);
  cases{end+1} = add ('multioutput', ob_multioutput_example (), struct (), [0.5 1]);
  cases{end+1} = add ('algebraic', ob_algebraic_example (), struct (), [0.5 1]);
  cases{end+1} = add ('linear system', ob_linear_system_example (), struct (), [0.5 1]);
  cases{end+1} = add ('zero crossings', ob_control_example (), struct ('zero_crossings', true), [1 2.5]);
  cases{end+1} = add ('zero-crossing primitive', ob_zero_crossing_example (), struct ('zero_crossings', true), [0.5 1]);
  cases{end+1} = add ('conditional', ob_conditional_example (), struct ('solver', 'rk4'), [0.5 1.5 2.5]);
  cases{end+1} = add ('enabled continuous', ob_enabled_continuous_example (), struct (), [0.5 1.5 2.5]);
  for index = 1:numel (cases)
    item = cases{index};
    fast = ob_runtime_init (item.model, 0, item.options);
    assert (isfield (fast.model.runtime_info, 'plan'), item.name);
    general = without_plan (fast);
    for time = item.times
      fast = ob_runtime_step (fast, time);
      general = ob_runtime_step (general, time);
      assert (isequaln (ob_runtime_outputs (fast), ob_runtime_outputs (general)), item.name);
      assert (isequaln (without_plan (fast), without_plan (general)), item.name);
    endfor
  endfor

  % Only a same-version cache's plan is trusted.  A cache of another kind
  % takes the general paths even when it carries a 'plan' field (of another
  % layout, or a real plan beside stripped parameters).  A same-version plan
  % is self-contained, so stripping the other cache fields leaves it usable.
  kinds = {'foreign plan', 'unknown kind without parameters', 'stripped fields'};
  checked = {'delay rk4', 'delay ode45', 'limited rk4', 'limited ode45', 'algebraic', ...
             'zero crossings', 'conditional', 'enabled continuous', 'multirate'};
  for index = 1:numel (cases)
    item = cases{index};
    if (! any (strcmp (item.name, checked))), continue; endif
    reference = ob_runtime_init (item.model, 0, item.options);
    variants = cell (1, numel (kinds));
    for kind = 1:numel (kinds)
      variants{kind} = change_cache (reference, kinds{kind});
    endfor
    for time = item.times
      reference = ob_runtime_step (reference, time);
      for kind = 1:numel (kinds)
        label = [item.name ', ' kinds{kind}];
        variants{kind} = ob_runtime_step (variants{kind}, time);
        assert (isequaln (ob_runtime_outputs (variants{kind}), ob_runtime_outputs (reference)), label);
        assert (isequaln (without_cache (variants{kind}), without_cache (reference)), label);
      endfor
    endfor
  endfor

  % Fast paths keep the general paths' errors.
  failing = {};
  wrong_shape = matrix; wrong_shape.blocks(1).value = [1 2];
  failing{end+1} = {wrong_shape, struct('solver', 'rk4'), 'match its state shape'};
  failing{end+1} = {wrong_shape, struct('solver', 'ode45'), 'match its state shape'};
  blowup = oscillator; blowup.blocks(3).type = 'Function'; blowup.blocks(3).name = 'log';
  blowup.blocks(1).value = 0;
  failing{end+1} = {blowup, struct('solver', 'rk4'), 'derivative must be finite'};
  failing{end+1} = {blowup, struct('solver', 'ode45'), 'derivative must be finite'};
  for index = 1:numel (failing)
    [model, options, fragment] = failing{index}{:};
    messages = cell (1, 3);
    for variant = 1:3
      try
        context = ob_runtime_init (model, 0, options);
        if (variant == 2), context = without_plan (context); endif
        if (variant == 3), context = change_cache (context, 'foreign plan'); endif
        context = ob_runtime_step (context, 0.1);
      catch err
        messages{variant} = err.message;
      end_try_catch
    endfor
    assert (! isempty (strfind (messages{1}, fragment)), messages{1});
    assert (strcmp (messages{1}, messages{2}) && strcmp (messages{1}, messages{3}));
  endfor

  % The evaluation program (plan.program, ob_program_eval) exists exactly for
  % models without algebraic loops, conditional bodies or Rate Transitions.
  % A plan without it, as in contexts saved before it existed, takes the
  % plan's dispatch loop and gives identical contexts.
  with_program = {'oscillator rk4', 'oscillator ode45', 'oscillator ode15s', 'matrix rk4', ...
                  'matrix ode45', 'single derivative rk4', 'delay rk4', 'delay ode45', ...
                  'limited rk4', 'limited ode45', 'input example', 'multioutput', ...
                  'linear system', 'zero crossings', 'zero-crossing primitive'};
  for index = 1:numel (cases)
    item = cases{index};
    reference = ob_runtime_init (item.model, 0, item.options);
    programmed = isfield (reference.model.runtime_info.plan, 'program');
    assert (programmed == any (strcmp (item.name, with_program)), item.name);
    if (! programmed), continue; endif
    previous = without_program (reference);
    for time = item.times
      reference = ob_runtime_step (reference, time);
      previous = ob_runtime_step (previous, time);
      assert (isequaln (ob_runtime_outputs (previous), ob_runtime_outputs (reference)), item.name);
      assert (isequaln (without_plan (previous), without_plan (reference)), item.name);
    endfor
  endfor

  % The program's inline control outputs report ob_control_output's errors:
  % a Dead Zone output that overflows after a Step, with and without zero
  % crossings (where the guard snapshot's scalar branch checks it too).
  overflow.blocks = [B('Step', [0.05 0 -realmax], 's') B('Dead Zone', [1e300 2e300], 'dz') ...
                     B('Scope', [], 'y')];
  overflow.edges = [1 2; 2 3];
  for options = {struct('solver', 'rk4'), struct('solver', 'rk4', 'zero_crossings', true)}
    messages = cell (1, 3);
    for variant = 1:3
      context = ob_runtime_init (overflow, 0, options{1});
      if (variant == 2), context = without_plan (context); endif
      if (variant == 3), context = without_program (context); endif
      try
        ob_runtime_step (context, 0.1);
      catch err
        messages{variant} = err.message;
      end_try_catch
    endfor
    assert (! isempty (strfind (messages{1}, 'Dead Zone block 2 produced nonfinite output')), messages{1});
    assert (strcmp (messages{1}, messages{2}) && strcmp (messages{1}, messages{3}));
  endfor

  % Scalar control inputs skip conversion only when already finite full
  % doubles; other inputs keep conversion and the first-port error.
  switch_block = struct ('type', 'Switch', 'value', 0);
  output = ob_control_output (switch_block, {1, sparse(1), int8(3)}, 4);
  assert (isequal (output, 1) && isa (output, 'double') && ! issparse (output));
  assert (isequal (ob_control_output (switch_block, {1, -1, 3}, 4), 3));
  assert_error (@() ob_control_output (switch_block, {1, NaN, 3}, 4), 'block 4 input 2 must be');
  assert_error (@() ob_control_output (switch_block, {1, 1, complex(3, 1)}, 4), 'block 4 input 3 must be');
  assert_error (@() ob_control_output (switch_block, {[1 2], 1, 3}, 4), 'identical shapes');

  % A complete input record and its struct form normalize identically,
  % including the wrapped error for an invalid record.
  driven.blocks = [B('Inport', 1, 'u') B('Scope', [], 'y')];
  driven.edges = [1 2];
  record = ob_input_signal ([0 1], [2; 3]);
  driven.inputs = {record};
  assert (isequal (ob_model_inputs (driven, true), {record}));
  partial = rmfield (record, 'shape'); driven.inputs = {partial};
  assert (isequal (ob_model_inputs (driven, true), {record}));
  record.t = [1; 0]; driven.inputs = {record};
  assert_error (@() ob_model_inputs (driven, true), 'root Inport 1: ob_input_signal: times must be strictly increasing');
  disp ('Octave Blocks runtime fast-path tests passed');
endfunction

function cases = golden_cases ()
  % Models for the golden fingerprints.  'portable' cases use RK4 with only
  % element-wise IEEE arithmetic, so their results do not depend on the
  % platform.  The others depend on the Octave version's ode45 (libm pow in
  % its step-size control) or on BLAS matrix products, so they are compared
  % only in the environment that recorded them.
  B = @(type, value, name) struct ('type', type, 'value', value, 'name', name, 'x', 0, 'y', 0);
  add = @(name, model, t, options, portable) struct ('name', name, 'model', model, 't', t, ...
                                                     'options', options, 'portable', portable);
  rk4 = struct ('solver', 'rk4');
  ode45 = struct ('solver', 'ode45');
  rk4_zc = struct ('solver', 'rk4', 'zero_crossings', true);
  ode45_zc = struct ('solver', 'ode45', 'zero_crossings', true);
  t = linspace (0, 2, 41);
  oscillator = ob_oscillator ();
  matrix.blocks = [B('Constant', [1 2; 3 4], 'u') B('Integrator', zeros (2), 'x') B('Scope', [], 'y')];
  matrix.edges = [1 2; 2 3];
  single_gain = oscillator; single_gain.blocks(3).value = single (-1);
  dde.blocks = [B('Integrator', 1, 'x') B('Transport Delay', [0.3 1], 'Delay') ...
                B('Gain', -1, 'Gain') B('Scope', [], 'Scope')];
  dde.edges = [1 2; 2 3; 3 1; 1 4];
  limited.blocks = [B('Constant', 1, 'u') ...
                    B('Limited Integrator', struct ('initial', 0, 'lower', 0, 'upper', 0.3, 'reset', 'rising'), 'x') ...
                    B('Step', [0.4 -1 1], 'reset') B('Scope', [], 'y')];
  limited.edges = [1 1 2 1; 3 1 2 2; 2 1 4 1];
  cases = {add('oscillator rk4', oscillator, t, rk4, true), ...
           add('matrix rk4', matrix, t, rk4, true), ...
           add('single derivative rk4', single_gain, t, rk4, true), ...
           add('delay rk4', dde, t, rk4, true), ...
           add('limited rk4', limited, t, rk4, true), ...
           add('zero-crossing primitive rk4', ob_zero_crossing_example (), t, rk4_zc, true), ...
           add('zero crossings rk4', ob_control_example (), linspace (0, 4, 41), rk4_zc, true), ...
           add('input example rk4', ob_input_example (), t, rk4, true), ...
           add('conditional rk4', ob_conditional_example (), linspace (0, 4, 41), rk4, true), ...
           add('oscillator ode45', oscillator, t, ode45, false), ...
           add('matrix ode45', matrix, t, ode45, false), ...
           add('delay ode45', dde, t, ode45, false), ...
           add('limited ode45', limited, t, ode45, false), ...
           add('zero-crossing primitive ode45', ob_zero_crossing_example (), t, ode45_zc, false), ...
           add('zero crossings ode45', ob_control_example (), linspace (0, 4, 41), ode45_zc, false), ...
           add('linear system rk4', ob_linear_system_example (), linspace (0, 4, 41), rk4, false), ...
           add('multirate ode45', ob_multirate_example (), t, ode45, false)};
endfunction

function [table, environment] = golden_table ()
  % Recorded 2026-11-21 by test_ob_runtime_fast_paths ('record') with the
  % pre-change engine (before the fast paths) first on the path.
  % Columns: case, md5 of the fingerprint, number of fingerprinted values.
  % ob_control_example has no continuous states, so its two solvers agree.
  environment = '11.3.0|x86_64-w64-mingw32|OpenBLAS (config: OpenBLAS 0.3.31 NO_LAPACK NO_LAPACKE DYNAMIC_ARCH NO_AFFINITY Haswell MAX_THREADS=24)';
  table = {
    'oscillator rk4', '1ebdf8854ffba743de0123096a4a292f', 206
    'matrix rk4', '53f3516227a0da3bb2380f06fc53b308', 534
    'single derivative rk4', '9554785f56f73b0ecf87ac079a8cb659', 206
    'delay rk4', 'b9cde4c8435ccdbdb3b4bd303d13fe25', 206
    'limited rk4', '700914dd6640f17b063978c78eb04bca', 206
    'zero-crossing primitive rk4', 'da6b8a7f80ec04e2aa05596194d8e14d', 289
    'zero crossings rk4', '0b943cb705fbc2824f98a06a22d1e723', 333
    'input example rk4', 'fda0514988cd2b6cd1daf41f5640eacc', 165
    'conditional rk4', 'e9e566a6241c24e1caff0e1bcfab79a4', 206
    'oscillator ode45', '217f83e639f9b2114c4850ac91b408a6', 206
    'matrix ode45', 'fd89ca72e3eed48c743648f1bcad2c8e', 534
    'delay ode45', 'ccc432aea7d83ed329ba7fb0c108ee3c', 206
    'limited ode45', '09d26617bc177d833a3bc1a273829263', 206
    'zero-crossing primitive ode45', '2285a44f15927ab263c18a42769d1dc6', 289
    'zero crossings ode45', '0b943cb705fbc2824f98a06a22d1e723', 333
    'linear system rk4', '0e1f6e2d1d8b3f7db4c9d67bfc22e373', 575
    'multirate ode45', 'a3e8d469ba1915454ba07bffb260ca65', 206
  };
endfunction

function [digest, count] = fingerprint (result)
  % Output times, every numeric cell of flat_values (column-major, i.e.
  % signal by signal in output-time order), the integration-step count and
  % event times.  Struct cells (conditional state snapshots) are left out:
  % the numeric signals downstream of a conditional subsystem carry its
  % results, while its snapshot layout belongs to the conditional code.
  parts = {result.t(:)};
  for item = 1:numel (result.flat_values)
    value = result.flat_values{item};
    if (isnumeric (value) || islogical (value))
      parts{end+1} = full (double (value(:)));
    endif
  endfor
  event_times = zeros (0, 1);
  if (! isempty (result.events)), event_times = [result.events.time]'; endif
  values = [vertcat(parts{:}); result.integration_steps; event_times];
  count = numel (values);
  digest = hash ('md5', char (typecast (values', 'uint8')));
endfunction

function key = environment_key ()
  key = sprintf ('%s|%s|%s', OCTAVE_VERSION, computer (), version ('-blas'));
endfunction

function record_goldens ()
  cases = golden_cases ();
  printf ('  environment = ''%s'';\n  table = {\n', environment_key ());
  for index = 1:numel (cases)
    item = cases{index};
    [digest, count] = fingerprint (ob_run (item.model, item.t, item.options));
    printf ('    ''%s'', ''%s'', %d\n', item.name, digest, count);
  endfor
  printf ('  };\n');
endfunction

function check_goldens ()
  [table, environment] = golden_table ();
  cases = golden_cases ();
  assert (rows (table) == numel (cases));
  same_environment = strcmp (environment, environment_key ());
  for index = 1:numel (cases)
    item = cases{index};
    assert (strcmp (table{index, 1}, item.name));
    if (! item.portable && ! same_environment), continue; endif
    [digest, count] = fingerprint (ob_run (item.model, item.t, item.options));
    assert (count == table{index, 3}, '%s: %d fingerprinted values, golden %d', ...
            item.name, count, table{index, 3});
    assert (strcmp (digest, table{index, 2}), '%s: fingerprint differs from the pre-change engine', ...
            item.name);
  endfor
endfunction

function check_packed_stages ()
  % Flat models of scalar double Integrators use packed solver vectors.  A
  % Limited Integrator with infinite limits and no reset evaluates the same
  % arithmetic through the general cell path (its limits are never reached
  % and its output min (max (x, -Inf), Inf) is x), so both runs must agree
  % bit for bit.
  B = @(type, value, name) struct ('type', type, 'value', value, 'name', name, 'x', 0, 'y', 0);
  free = @(initial) struct ('initial', initial, 'lower', -Inf, 'upper', Inf, 'reset', 'none');
  oscillator = ob_oscillator ();
  free_oscillator = oscillator;
  free_oscillator.blocks(1).type = 'Limited Integrator'; free_oscillator.blocks(1).value = free (1);
  free_oscillator.blocks(2).type = 'Limited Integrator'; free_oscillator.blocks(2).value = free (0);
  dde.blocks = [B('Integrator', 1, 'x') B('Transport Delay', [0.3 1], 'Delay') ...
                B('Gain', -1, 'Gain') B('Scope', [], 'Scope')];
  dde.edges = [1 2; 2 3; 3 1; 1 4];
  free_dde = dde; free_dde.blocks(1).type = 'Limited Integrator'; free_dde.blocks(1).value = free (1);
  switched = ob_zero_crossing_example ();
  free_switched = switched;
  free_switched.blocks(5).type = 'Limited Integrator'; free_switched.blocks(5).value = free (0);
  pairs = {{'oscillator', oscillator, free_oscillator}, {'delay', dde, free_dde}, ...
           {'switched', switched, free_switched}};
  t = linspace (0, 2, 21);
  for index = 1:numel (pairs)
    [name, packed, general] = pairs{index}{:};
    for solver = {'rk4', 'ode45'}
      options = struct ('solver', solver{1});
      a = ob_run (packed, t, options);
      b = ob_run (general, t, options);
      label = [name ' ' solver{1}];
      assert (isequal (a.t, b.t) && a.integration_steps == b.integration_steps, label);
      assert (isequaln (a.flat_values, b.flat_values), label);
    endfor
  endfor
endfunction

function value = change_cache (value, kind)
  % Alter every runtime cache, recursively, as the named variant.
  if (isstruct (value))
    if (isfield (value, 'runtime_info') && isstruct (value.runtime_info))
      for item = 1:numel (value)
        info = value(item).runtime_info;
        switch (kind)
          case 'foreign plan'
            info.kind = 'future-runtime-info';
            info.plan = struct ('kind', 'future-plan');
          case 'unknown kind without parameters'
            info.kind = 'future-runtime-info';
            info.parameters = {};
          case 'stripped fields'
            names = fieldnames (info);
            strip = strcmp (names, 'sources') | strcmp (names, 'loop_at') ...
                    | strcmp (names, 'parameters') | ! cellfun ('isempty', regexp (names, '_ids$'));
            info = rmfield (info, names(strip));
        endswitch
        value(item).runtime_info = info;
      endfor
    endif
    names = fieldnames (value);
    for item = 1:numel (value)
      for name = names'
        if (strcmp (name{1}, 'runtime_info')), continue; endif
        value(item).(name{1}) = change_cache (value(item).(name{1}), kind);
      endfor
    endfor
  elseif (iscell (value))
    for item = 1:numel (value), value{item} = change_cache (value{item}, kind); endfor
  endif
endfunction

function value = without_cache (value)
  % Remove every runtime cache, recursively.
  if (isstruct (value))
    if (isfield (value, 'runtime_info')), value = rmfield (value, 'runtime_info'); endif
    names = fieldnames (value);
    for item = 1:numel (value)
      for name = names'
        value(item).(name{1}) = without_cache (value(item).(name{1}));
      endfor
    endfor
  elseif (iscell (value))
    for item = 1:numel (value), value{item} = without_cache (value{item}); endfor
  endif
endfunction

function value = without_plan (value)
  % Remove the evaluation plan from every runtime cache, recursively.
  if (isstruct (value))
    if (isfield (value, 'runtime_info') && isstruct (value.runtime_info) ...
        && isfield (value.runtime_info, 'plan'))
      for item = 1:numel (value)
        value(item).runtime_info = rmfield (value(item).runtime_info, 'plan');
      endfor
    endif
    names = fieldnames (value);
    for item = 1:numel (value)
      for name = names'
        value(item).(name{1}) = without_plan (value(item).(name{1}));
      endfor
    endfor
  elseif (iscell (value))
    for item = 1:numel (value), value{item} = without_plan (value{item}); endfor
  endif
endfunction

function value = without_program (value)
  % A context as saved before plans carried an evaluation program.
  if (isstruct (value))
    if (isfield (value, 'runtime_info') && isstruct (value.runtime_info) ...
        && isfield (value.runtime_info, 'plan') && isfield (value.runtime_info.plan, 'program'))
      for item = 1:numel (value)
        value(item).runtime_info.plan = rmfield (value(item).runtime_info.plan, 'program');
      endfor
    endif
    names = fieldnames (value);
    for item = 1:numel (value)
      for name = names'
        value(item).(name{1}) = without_program (value(item).(name{1}));
      endfor
    endfor
  elseif (iscell (value))
    for item = 1:numel (value), value{item} = without_program (value{item}); endfor
  endif
endfunction

function assert_error (callback, fragment)
  caught = false;
  try
    callback ();
  catch err
    caught = ! isempty (strfind (err.message, fragment));
  end_try_catch
  assert (caught, fragment);
endfunction
