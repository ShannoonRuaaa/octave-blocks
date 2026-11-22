function test_ob_simulink_extended (directory = '', pattern = '', verbose = false)
  % Compare Octave Blocks with recorded Simulink 26.2 traces for continuous
  % (zero-crossing) conditional controls and primitive crossings under
  % ode45/ode15s, subsystems and functions with several outputs, and
  % enabled bodies with inner clocks.  MATLAB is not needed at test time; the
  % references are written by
  %   reference_ob_simulink_continuous    simulink-continuous-reference.json
  %   reference_ob_simulink_multioutput   simulink-multioutput-reference.json
  %   reference_ob_simulink_inner_clocks  simulink-inner-clocks-reference.json
  %   reference_ob_conditional_outputs    simulink-conditional-outputs-reference.json
  % Each case rebuilds the recorded Simulink model in Octave Blocks, runs it
  % on the Simulink output times and compares every output column.
  %
  % Agreeing cases are asserted.  Every known discrepancy is listed in
  % pending_table () with its diagnosis and the tag 'pending': it is still
  % run and its error printed, but not asserted.  Each pending diagnosis
  % must be verified: an alternate Octave model that reproduces the
  % Simulink trace, a confinement mask outside which everything agrees (a
  % mask hiding a whole column also needs a check), or a diagnosis check on
  % the Simulink columns.  A pending entry that starts to agree is reported,
  % not failed.
  %
  % Optional arguments: the folder holding the JSON files (default: the
  % project's reference folder), a regular expression selecting case ids,
  % and verbose (print time, Simulink and Octave columns for every case
  % that differs).
  % The full run takes about a quarter of an hour, almost all of it in the
  % continuous ode45/ode15s cases; for example '^(enabled_|euler|delays)'
  % selects the quick discrete ones.
  if (isempty (directory)), directory = ob_test_reference (); endif
  pending = pending_table ();
  files = {'simulink-continuous-reference.json', @continuous_case; ...
           'simulink-multioutput-reference.json', @multioutput_case; ...
           'simulink-inner-clocks-reference.json', @inner_clock_case; ...
           'simulink-conditional-outputs-reference.json', @output_case};
  failures = {}; rows_out = {};
  matched = 0; listed = 0;
  for f = 1:rows (files)
    ref = jsondecode (fileread (fullfile (directory, files{f, 1})));
    ids = fieldnames (ref.cases);
    for k = 1:numel (ids)
      id = ids{k}; c = ref.cases.(id);
      if (! isempty (pattern) && isempty (regexp (id, pattern, 'once'))), continue; endif
      if (! c.ok)
        failures{end+1} = sprintf ('%s: the Simulink reference run failed: %s', id, c.error);
        continue;
      endif
      t = c.t(:);
      sl = c.y;
      if (rows (sl) != numel (t)), sl = sl.'; endif
      started = tic;
      try
        out = files{f, 2} (id, c);
      catch err
        out = outcome (0); out.note = ['Octave error: ' err.message];
      end_try_catch
      seconds = toc (started);
      [value, column] = compare (sl, out);
      if (verbose && value > out.tol)
        % Columns: time, Simulink outputs, then Octave outputs.
        printf ('%s (%s)\n', id, out.note);
        if (isequal (size (out.y), size (sl))), disp ([t sl out.y]); endif
      endif
      entry = find (strcmp (id, {pending.id}));
      if (isempty (entry))
        if (value <= out.tol)
          matched++; status = 'agrees';
          if (! isempty (out.note)), printf ('note    %-38s %s\n', id, out.note); endif
        else
          status = 'FAILS';
          failures{end+1} = sprintf ('%s: max error %.3g in column %d (tolerance %.3g) %s', ...
                                     id, value, column, out.tol, out.note);
        endif
      else
        listed++;
        status = 'pending';
        printf ('pending %-38s max error %-10.3g %s: %s\n', id, value, ...
                pending(entry).category, pending(entry).diagnosis);
        if (value <= out.tol)
          printf ('        %s now agrees (%.3g <= %.3g): remove it from pending_table\n', id, value, out.tol);
        endif
        if (! isempty (out.alternate))
          alternate = out; alternate.y = out.alternate;
          alt = compare (sl, alternate);
          if (alt <= out.tol)
            printf ('        alternate model reproduces Simulink (max error %.3g)\n', alt);
          else
            failures{end+1} = sprintf ('%s: the diagnosed alternate model does not reproduce Simulink (%.3g)', ...
                                       id, alt);
          endif
        endif
        if (! isempty (out.confined))
          % The diagnosis names the entries that may differ; everything
          % else must still agree.
          outside = out; outside.skip = out.confined;
          if (! isempty (out.skip)), outside.skip |= out.skip; endif
          rest = compare (sl, outside);
          if (rest <= out.tol)
            printf ('        difference confined to the diagnosed entries (elsewhere %.3g)\n', rest);
          else
            failures{end+1} = sprintf ('%s: differs outside the diagnosed entries (%.3g)', id, rest);
          endif
          if (any (all (out.confined, 1)) && isempty (out.check))
            % A mask hiding a whole column proves nothing about that column.
            failures{end+1} = sprintf ('%s: a confinement mask hides a whole column without a diagnosis check', id);
          endif
        endif
        if (! isempty (out.check))
          violation = out.check (sl);
          if (violation <= out.tol)
            printf ('        diagnosis check holds (largest violation %.3g)\n', violation);
          else
            failures{end+1} = sprintf ('%s: the diagnosis check fails (%.3g)', id, violation);
          endif
        endif
        if (isempty (out.alternate) && isempty (out.confined) && isempty (out.check))
          failures{end+1} = sprintf ('%s: the pending diagnosis is not verified', id);
        endif
      endif
      rows_out(end+1, :) = {id, value, out.tol, seconds, status};
    endfor
  endfor
  for entry = pending
    if (! isempty (pattern)), break; endif
    if (! any (strcmp (entry.id, rows_out(:, 1))))
      failures{end+1} = sprintf ('pending entry %s matches no recorded case', entry.id);
    endif
  endfor
  printf ('\n%-40s %12s %10s %8s  %s\n', 'case', 'max error', 'tolerance', 'seconds', 'status');
  for k = 1:rows (rows_out)
    printf ('%-40s %12.3g %10.3g %8.2f  %s\n', rows_out{k, :});
  endfor
  if (! isempty (failures))
    error ('test_ob_simulink_extended: %d failures\n  %s', numel (failures), strjoin (failures, "\n  "));
  endif
  printf ('Simulink extended references: %d cases agree, %d pending discrepancies\n', matched, listed);
endfunction

function [value, column] = compare (sl, out)
  % Largest absolute difference over the compared entries, and its column.
  value = Inf; column = 0;
  if (isempty (out.y) || ! isequal (size (out.y), size (sl))), return; endif
  difference = abs (out.y - sl);
  difference(isnan (out.y) & isnan (sl)) = 0;
  difference(isnan (difference)) = Inf;
  if (! isempty (out.skip)), difference(out.skip) = 0; endif
  cc = out.crossing_column;
  if (cc > 0)
    % Recorder columns compare the sets of located crossing times.  A
    % crossing that falls on an output time may be reported on either side
    % of it by a rounding-level difference, which would shift the sampled
    % column by one sample without any physical disagreement.
    difference(:, cc) = 0;
    expected = crossing_set (sl(:, cc));
    actual = crossing_set (out.y(:, cc));
    if (numel (expected) == numel (actual))
      difference(1, cc) = max ([0; abs(expected(:) - actual(:))]);
    else
      difference(1, cc) = Inf;
    endif
  endif
  [per_column, ~] = max (difference, [], 1);
  [value, column] = max (per_column);
endfunction

function times = crossing_set (column)
  % Distinct recorded crossing times (-1 means none yet), merging values
  % within 1e-9 of each other.
  times = sort (column(column > -1));
  if (isempty (times)), return; endif
  times = times([true; diff(times) > 1e-9]);
endfunction

function table = pending_table ()
  % Known discrepancies, each with its diagnosis and category
  % (octave-blocks-bug, undocumented-difference, documented-difference or
  % harness-artifact).  Each diagnosis is verified by an alternate model, a
  % confinement mask or a diagnosis check.  Per-port OutputWhenDisabled
  % (enabled_three_mixed*), the scalar InitialOutput expansion
  % (enabled_vector), the inner-clock Outport timing (euler_two_rates_reset,
  % delays_rate_transition_hold) and the Outport buffers shared by clocked
  % blocks (gating_*) now agree and are asserted.
  table = struct ('id', {}, 'category', {}, 'diagnosis', {});
  table(end+1) = struct ('id', 'delays_rate_transition_deterministic', 'category', 'documented-difference', ...
                         'diagnosis', ['the default Rate Transition (Integrity and Deterministic on) makes ' ...
                                       'the slow-to-fast output the previous slow sample, updated only at ' ...
                                       'slow hits and one slow period late from its initial condition; ' ...
                                       'Octave Blocks'' Rate Transition is a plain sample-and-hold ' ...
                                       '(MULTIRATE.md); a slow Unit Delay and a slow hold reproduce Simulink']);
  hold = ['Rate Transition with Integrity and Deterministic off: the value seen by the continuous ' ...
          'Integrator is updated at every major solver step (each ode4 step adds h*t_n: 0.475 at t = 1), ' ...
          'while the logged Outport is sampled at the declared 0.25 s; Octave Blocks holds both at ' ...
          '0.25 s (0.375, as the deterministic case does)'];
  table(end+1) = struct ('id', 'root_rate_transition_hold_ode4', 'category', 'documented-difference', ...
                         'diagnosis', [hold '; a Rate Transition at the 0.05 s step reproduces the integral']);
  table(end+1) = struct ('id', 'root_rate_transition_hold_ode45', 'category', 'documented-difference', ...
                         'diagnosis', [hold '; the integral lies between the 0.25 s hold and t^2/2']);
endfunction

% --- Continuous controls and primitive crossings ---------------------------

function out = continuous_case (id, c)
  p = c.parameters;
  times = row (c.output_times);
  options = struct ('solver', c.solver, 'zero_crossings', true, 'maxstep', c.maxstep, ...
                    'reltol', c.reltol, 'abstol', c.abstol);
  out = outcome (1e-6);
  switch (c.model)
    case 'enabled_integrator'
      child = make_model ({'Inport', 1; 'Integrator', p.initial_state; 'Outport', 1}, [1 1 2 1; 2 1 3 1]);
      child.execution = continuous_execution ('enabled', {p.initial_output});
      child.execution.states = p.states; child.execution.outputs = p.outputs;
      model = pulse_root (p, block ('Constant', p.data, 'Data'), child, 1);
      result = ob_run (model, times, options);
      out = with_recorder (out, scopes (result, 8), result, times, 'Conditional Subsystem', 7);
    case 'enabled_feedthrough'
      child = make_model ({'Inport', 1; 'Gain', 1; 'Outport', 1}, [1 1 2 1; 2 1 3 1]);
      child.execution = continuous_execution ('enabled', {p.initial_output});
      child.execution.outputs = p.outputs;
      model = pulse_root (p, block ('Time', [], 'Data'), child, 1);
      model.blocks(9) = block ('Integrator', 0, 'Integral');
      model.blocks(10) = block ('Scope', [], 'Integral scope');
      model.edges = [model.edges; 7 1 9 1; 9 1 10 1];
      result = ob_run (model, times, options);
      out = with_recorder (out, scopes (result, [8 10]), result, times, 'Conditional Subsystem', 7);
    case 'enabled_switch'
      child = make_model ({'Inport', 1; 'Integrator', 0; 'Outport', 1}, [1 1 2 1; 2 1 3 1]);
      child.execution = continuous_execution ('enabled', {p.initial_output});
      model = make_model ({'Constant', 1; 'Time', []; 'Constant', p.high; 'Constant', p.low; ...
                           'Switch', p.threshold; 'Subsystem', child; 'Scope', []}, ...
                          [3 1 5 1; 2 1 5 2; 4 1 5 3; 1 1 6 1; 5 1 6 2; 6 1 7 1]);
      result = ob_run (model, times, options);
      % The recorder watched the Switch output that drives the enable.
      out = with_recorder (out, scopes (result, 7), result, times, {'Switch', 'Conditional Subsystem'}, [5 6]);
    case 'enabled_inner_clock'
      child = make_model ({'Inport', 1; 'Unit Delay', p.delay_initial; 'Outport', 1; ...
                           'Constant', 1; 'Integrator', 0; 'Outport', 2}, ...
                          [1 1 2 1; 2 1 3 1; 4 1 5 1; 5 1 6 1]);
      child.sample_times = zeros (6, 2); child.sample_times(2, :) = [p.delay_period 0];
      child.execution = continuous_execution ('enabled', {p.initial_output, p.initial_output});
      model = pulse_root (p, block ('Time', [], 'Data'), child, 2);
      result = ob_run (model, times, options);
      out = with_recorder (out, scopes (result, [8 9]), result, times, 'Conditional Subsystem', 7);
    case {'triggered_clock', 'triggered_delay'}
      if (strcmp (c.model, 'triggered_clock'))
        child = make_model ({'Inport', 1; 'Outport', 1}, [1 1 2 1]);
      else
        child = make_model ({'Inport', 1; 'Unit Delay', p.delay_initial; 'Outport', 1}, [1 1 2 1; 2 1 3 1]);
      endif
      child.execution = continuous_execution (p.trigger, {p.initial_output});
      child.execution.initial_control = initial_control (p.initial_trigger);
      model = pulse_root (p, block ('Time', [], 'Data'), child, 1);
      out.y = scopes (ob_run (model, times, options), 8);
    case 'switch_time'
      model = make_model ({'Constant', p.high; 'Time', []; 'Constant', p.low; 'Switch', p.threshold; ...
                           'Integrator', p.initial_state; 'Scope', []}, ...
                          [1 1 4 1; 2 1 4 2; 3 1 4 3; 4 1 5 1; 5 1 6 1]);
      result = ob_run (model, times, options);
      out = with_recorder (out, scopes (result, 6), result, times, 'Switch', 4);
    case 'switch_state'
      model = make_model ({'Constant', p.high; 'Integrator', p.initial_state; 'Time', []; 'Function', []; ...
                           'Switch', p.threshold; 'Scope', []}, ...
                          [1 1 5 1; 2 1 5 2; 3 1 4 1; 4 1 5 3; 5 1 2 1; 2 1 6 1]);
      model.blocks(4).name = 'cos';
      result = ob_run (model, times, options);
      out = with_recorder (out, scopes (result, 6), result, times, 'Switch', 5);
    case {'saturation_integrator', 'deadzone_integrator'}
      kind = 'Saturation';
      if (strcmp (c.model, 'deadzone_integrator')), kind = 'Dead Zone'; endif
      model = make_model ({'Time', []; 'Gain', p.gain; 'Function', []; kind, [p.lower p.upper]; ...
                           'Integrator', p.initial_state; 'Scope', []}, ...
                          [1 1 2 1; 2 1 3 1; 3 1 4 1; 4 1 5 1; 5 1 6 1]);
      model.blocks(3).name = 'sin';
      out.y = scopes (ob_run (model, times, options), 6);
    otherwise
      error ('unknown continuous reference model %s', c.model);
  endswitch
  % An enable that reaches zero exactly at a stop keeps one record there
  % (ob_integrate_events, origin departures): no repeated records.
  if (any (strcmp (id, {'en_int_ongrid_ode45', 'en_int_ongrid_ode15s'})) && ! isempty (out.note))
    error ('%s: %s', id, out.note);
  endif
endfunction

function model = pulse_root (p, data, child, outputs)
  % Data, Time, offset, Sum, Gain, sin -> Subsystem (block 7) -> Scopes 8...:
  % the control is sin(gain * (t + offset)), built as in the producer.
  model = make_model ({'Constant', []; 'Time', []; 'Constant', p.offset; 'Sum', []; 'Gain', p.gain; ...
                       'Function', []; 'Subsystem', child}, ...
                      [2 1 4 1; 3 1 4 2; 4 1 5 1; 5 1 6 1; 1 1 7 1; 6 1 7 2]);
  model.blocks(1) = data;
  model.blocks(6).name = 'sin';
  for port = 1:outputs
    model.blocks(7+port) = block ('Scope', [], sprintf ('Output %d', port));
    model.edges(end+1, :) = [7 port 7+port 1];
  endfor
endfunction

function execution = continuous_execution (mode, initial_outputs)
  execution = struct ('mode', mode, 'control', 'continuous', 'initial_outputs', {initial_outputs});
endfunction

function value = initial_control (name)
  switch (name)
    case 'positive', value = 1;
    case 'negative', value = -1;
    case 'compatibility', value = 'compatibility';
    otherwise, value = 0;  % 'zero'
  endswitch
endfunction

function out = with_recorder (out, values, result, times, types, paths)
  % Append the Octave counterpart of the producer's Simulink-only recorder:
  % the most recent located event of the given type(s) and root block
  % path(s) at or before each output time, -1 before the first.  Records of
  % one crossing repeated within 1e-9 s are noted.
  if (ischar (types)), types = {types}; endif
  events = result.events;
  keep = false (1, numel (events));
  for k = 1:numel (events)
    keep(k) = any (strcmp (events(k).type, types)) && isscalar (events(k).path) ...
              && any (events(k).path == paths);
  endfor
  located = sort ([events(keep).time]);
  column = -ones (numel (times), 1);
  for k = 1:numel (times)
    before = located(located <= times(k) + 1e-9);
    if (! isempty (before)), column(k) = max (before); endif
  endfor
  repeated = located([false, diff(located) <= 1e-9]);
  if (! isempty (repeated))
    out.note = sprintf ('%d repeated event record(s) near t = %s', numel (repeated), mat2str (repeated, 6));
  endif
  out.y = [values, column];
  out.crossing_column = columns (out.y);
endfunction

% --- Multiple outputs ------------------------------------------------------

function out = multioutput_case (id, c)
  p = c.parameters;
  times = row (c.t);
  out = outcome (1e-12);
  switch (c.model)
    case 'virtual_three'
      child = make_model ({'Inport', 1; 'Gain', p.gain; 'Function', []; 'Integrator', p.initial_state; ...
                           'Outport', 1; 'Outport', 2; 'Outport', 3}, ...
                          [1 1 2 1; 2 1 5 1; 1 1 3 1; 3 1 6 1; 1 1 4 1; 4 1 7 1]);
      child.blocks(3).name = 'sin';
      model = make_model ({'Time', []; 'Subsystem', child; 'Sum', []; 'Product', []; 'Scope', []; ...
                           'Scope', []; 'Scope', []; 'Scope', []; 'Scope', []}, ...
                          [1 1 2 1; 2 1 3 1; 2 3 3 2; 2 2 4 1; 2 2 4 2; ...
                           2 1 5 1; 2 2 6 1; 2 3 7 1; 3 1 8 1; 4 1 9 1]);
      out.y = scopes (ob_run (model, times, struct ('solver', 'rk4')), 5:9);
    case 'enabled_three'
      % OutputWhenDisabled per Outport: execution.outputs takes one policy
      % per numbered Outport.
      model = enabled_three (p, reshape (p.outputs, 1, []));
      out.y = scopes (ob_run (model, times), 4:6);
    case 'triggered_three'
      child = make_model ({'Inport', 1; 'Unit Delay', p.delay_initial; 'Gain', p.gain; ...
                           'Outport', 1; 'Outport', 2; 'Outport', 3}, ...
                          [1 1 4 1; 1 1 2 1; 2 1 5 1; 1 1 3 1; 3 1 6 1]);
      child.execution = struct ('mode', p.trigger_type, 'initial_outputs', {num2cell(row (p.initial_outputs))}, ...
                                'initial_control', initial_control (p.initial_trigger));
      model = make_model ({'Time', []; 'Inport', 1; 'Subsystem', child; 'Scope', []; 'Scope', []; 'Scope', []}, ...
                          [1 1 3 1; 2 1 3 2; 3 1 4 1; 3 2 5 1; 3 3 6 1]);
      model.inputs = {ob_input_signal(p.trigger.times(:), p.trigger.values(:))};
      out.y = scopes (ob_run (model, times), 4:6);
    case 'enabled_vector'
      % The scalar InitialOutput -4 of the 2-element port is expanded to
      % [-4 -4] before the first execution, as in Simulink.
      initial = cellfun (@row, p.initial_outputs, 'UniformOutput', false)';
      out.y = scopes (ob_run (enabled_vector (p, initial), times), 5:6);
    case 'function_vector'
      count = 2;
      if (! strcmp (p.octave_function, 'max')), count = 3; endif
      blocks = {'Time', []; 'Gain', row(p.gain); 'Constant', row(p.bias); 'Sum', []; 'Function', []};
      edges = [1 1 2 1; 2 1 4 1; 3 1 4 2; 4 1 5 1];
      for k = 1:count
        blocks(end+1, :) = {'Scope', []};
        edges(end+1, :) = [5 k 5+k 1];
      endfor
      model = make_model (blocks, edges);
      [model.blocks.outputs] = deal ([]);
      model.blocks(5).name = p.octave_function; model.blocks(5).outputs = count;
      out.y = scopes (ob_run (model, times, struct ('solver', 'rk4')), 5 + (1:count));
    otherwise
      error ('unknown multioutput reference model %s', c.model);
  endswitch
endfunction

function model = enabled_three (p, policy)
  child = make_model ({'Inport', 1; 'Unit Delay', p.delay_initial; 'Gain', p.gain; ...
                       'Discrete Integrator', p.euler_initial; 'Outport', 1; 'Outport', 2; 'Outport', 3}, ...
                      [1 1 2 1; 2 1 5 1; 1 1 3 1; 3 1 6 1; 1 1 4 1; 4 1 7 1]);
  child.execution = struct ('mode', 'enabled', 'states', p.states, 'outputs', {policy}, ...
                            'initial_outputs', {num2cell(row (p.initial_outputs))});
  model = make_model ({'Time', []; 'Inport', 1; 'Subsystem', child; 'Scope', []; 'Scope', []; 'Scope', []}, ...
                      [1 1 3 1; 2 1 3 2; 3 1 4 1; 3 2 5 1; 3 3 6 1]);
  model.inputs = {ob_input_signal(p.enable.times(:), p.enable.values(:))};
endfunction

function model = enabled_vector (p, initial)
  child = make_model ({'Inport', 1; 'Unit Delay', row(p.delay_initial); 'Outport', 1; 'Outport', 2}, ...
                      [1 1 2 1; 2 1 3 1; 1 1 4 1]);
  child.execution = struct ('mode', 'enabled', 'initial_outputs', {initial});
  model = make_model ({'Time', []; 'Gain', row(p.gain); 'Inport', 1; 'Subsystem', child; 'Scope', []; 'Scope', []}, ...
                      [1 1 2 1; 2 1 4 1; 3 1 4 2; 4 1 5 1; 4 2 6 1]);
  model.inputs = {ob_input_signal(p.enable.times(:), p.enable.values(:))};
endfunction

% --- Inner clocks ----------------------------------------------------------

function out = inner_clock_case (id, c)
  p = c.parameters;
  times = row (c.t);
  out = outcome (1e-12);
  switch (c.model)
    case 'euler_rates'
      child = make_model ({'Inport', 1; 'Discrete Integrator', 0; 'Discrete Integrator', 0; ...
                           'Outport', 1; 'Outport', 2}, [1 1 2 1; 1 1 3 1; 2 1 4 1; 3 1 5 1]);
      child.sample_times = [0 0; p.clocks(1, :); p.clocks(2, :); 0 0; 0 0];
      child.execution = struct ('mode', 'enabled', 'states', p.states, ...
                                'initial_outputs', {num2cell(row (p.initial_outputs))});
      model = make_model ({'Constant', 1; 'Inport', 1; 'Subsystem', child; 'Scope', []; 'Scope', []}, ...
                          [1 1 3 1; 2 1 3 2; 3 1 4 1; 3 2 5 1]);
      model.inputs = {ob_input_signal(p.enable.times(:), p.enable.values(:))};
      model.sample_times = zeros (5, 2);
      % An enable sampled at every logged step is Octave's inherited
      % control: requested outputs plus the inner clock union.
      if (abs (p.enable_sample - c.fixed_step) > 1e-12)
        model.sample_times(3, :) = [p.enable_sample 0];
      endif
      out.y = scopes (ob_run (model, times), 4:5);
    case 'delay_rates'
      model = delay_rates (p, false);
      out.y = scopes (ob_run (model, times), 4:8);
      % Harness artifact: before the first [0.25 0.0625] hit Simulink logs
      % the root Outport's own initial value (0), not the subsystem's.
      out.skip = false (size (out.y)); out.skip(1, 5) = true;
      if (strcmp (p.transfer, 'deterministic'))
        % Deterministic slow-to-fast transfer outputs the previous slow
        % sample and updates only at slow hits (before the first one the
        % Outport sharing its buffer shows -9): a slow Unit Delay (IC = the
        % transition's) and a slow hold reproduce it.
        out.alternate = scopes (ob_run (delay_rates (p, true), times), 4:8);
      endif
    case 'root_transition'
      if (strcmp (c.solver, 'ode4'))
        options = struct ('solver', 'rk4');
      else
        options = struct ('solver', c.solver, 'reltol', c.reltol, 'abstol', c.abstol);
        out.tol = 1e-8;
      endif
      out.y = scopes (ob_run (root_transition (p, p.period), times, options), 4:5);
      if (strcmp (p.transfer, 'hold'))
        if (strcmp (c.solver, 'ode4'))
          % The Integrator sees the Clock held at every major (0.05 s) step,
          % while the logged Outport keeps the declared 0.25 s staircase: a
          % Rate Transition at the solver step reproduces the integral.
          stepped = scopes (ob_run (root_transition (p, c.fixed_step), times, options), 4:5);
          out.alternate = [out.y(:, 1) stepped(:, 2)];
        else
          % ode45 steps are not recorded: the logged staircase must agree,
          % and the integral must lie between the 0.25 s hold and the
          % continuous integral t^2/2 (held more often than 0.25 s).
          out.confined = false (size (out.y)); out.confined(:, 2) = true;
          out.check = @(sl) max ([0; out.y(:, 2) - sl(:, 2); sl(:, 2) - times(:).^2 / 2]);
        endif
      endif
    otherwise
      error ('unknown inner-clock reference model %s', c.model);
  endswitch
endfunction

function model = delay_rates (p, deterministic)
  % Unit Delays at the fast, slow and offset clocks with fast-to-slow and
  % slow-to-fast Rate Transitions; DETERMINISTIC inserts a slow Unit Delay
  % before the slow-to-fast transition and runs that transition at the slow
  % rate.
  child = make_model ({'Inport', 1; 'Unit Delay', p.delay_initials(1); 'Unit Delay', p.delay_initials(2); ...
                       'Unit Delay', p.delay_initials(3); 'Rate Transition', p.transition_initials(1); ...
                       'Rate Transition', p.transition_initials(2); 'Outport', 1; 'Outport', 2; ...
                       'Outport', 3; 'Outport', 4; 'Outport', 5}, ...
                      [1 1 2 1; 1 1 3 1; 1 1 4 1; 2 1 5 1; 3 1 6 1; ...
                       2 1 7 1; 3 1 8 1; 5 1 9 1; 6 1 10 1; 4 1 11 1]);
  child.sample_times = zeros (11, 2);
  child.sample_times(2:6, :) = [p.fast 0; p.slow 0; row(p.offset_clock); p.slow 0; p.fast 0];
  if (deterministic)
    child.blocks(12) = block ('Unit Delay', p.transition_initials(2), 'Previous slow sample');
    child.edges(child.edges(:, 3) == 6, 1) = 12;
    child.edges(end+1, :) = [3 1 12 1];
    child.sample_times(12, :) = [p.slow 0];
    child.sample_times(6, :) = [p.slow 0];
  endif
  child.execution = struct ('mode', 'enabled', 'initial_outputs', {repmat({p.initial_output}, 1, 5)});
  model = make_model ({'Time', []; 'Inport', 1; 'Subsystem', child; 'Scope', []; 'Scope', []; ...
                       'Scope', []; 'Scope', []; 'Scope', []}, ...
                      [1 1 3 1; 2 1 3 2; 3 1 4 1; 3 2 5 1; 3 3 6 1; 3 4 7 1; 3 5 8 1]);
  model.inputs = {ob_input_signal(p.enable.times(:), p.enable.values(:))};
  model.sample_times = zeros (8, 2); model.sample_times(3, :) = [p.enable_sample 0];
endfunction

function model = root_transition (p, period)
  model = make_model ({'Time', []; 'Rate Transition', p.initial; 'Integrator', 0; 'Scope', []; 'Scope', []}, ...
                      [1 1 2 1; 2 1 3 1; 2 1 4 1; 3 1 5 1]);
  model.sample_times = zeros (5, 2); model.sample_times(2, :) = [period 0];
endfunction

% --- Conditional Outport timing and policies ---------------------------------

function out = output_case (id, c)
  % Models from ob_simulink_output_cases (shared with the C fixtures).
  [model, options, ids] = ob_simulink_output_cases (c);
  out = outcome (1e-12);
  out.y = scopes (ob_run (model, row (c.t), options), ids);
endfunction

% --- Helpers ---------------------------------------------------------------

function out = outcome (tol)
  % check: optional diagnosis test, a function of the Simulink columns
  % returning its largest violation (pending entries only).
  out = struct ('y', [], 'tol', tol, 'skip', [], 'alternate', [], 'confined', [], 'note', '', ...
                'crossing_column', 0, 'check', []);
endfunction

function values = scopes (result, ids)
  % Root Scope samples as columns; matrix signals contribute their elements
  % in column-major order, as the producers log them.
  values = [];
  for id = ids
    values = [values, cell2mat(cellfun (@(v) double (v(:)'), result.values(:, id), 'UniformOutput', false))];
  endfor
endfunction

function model = make_model (entries, edges)
  % entries: {type, value} rows; names default to the type.
  model.blocks = struct ('type', {}, 'value', {}, 'name', {}, 'x', {}, 'y', {});
  for k = 1:rows (entries)
    model.blocks(k) = block (entries{k, 1}, entries{k, 2}, entries{k, 1});
  endfor
  model.edges = edges;
endfunction

function b = block (type, value, name)
  b = struct ('type', type, 'value', value, 'name', name, 'x', .5, 'y', .5);
endfunction

function v = row (v)
  v = reshape (v, 1, []);
endfunction
