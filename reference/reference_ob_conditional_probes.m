function reference_ob_conditional_probes (file)
  % Independent Simulink probes for trigger initialization, the first
  % evaluation of Enabled and Triggered subsystems, ancestor resets, the
  % 'compatibility (no trigger on first evaluation)' state of trigger-only
  % subsystems (root, delayed, re-enabled, wrapped, edge flags across an
  % ancestor reset, and continuous triggers under ode45), and the Trigger
  % block's InitialTriggerSignalState values.
  % Run only in MATLAB with Simulink:
  %   reference_ob_conditional_probes ('simulink-conditional-probes-reference.json')
  % test_ob_simulink_conditional compares that file with Octave Blocks.
  % Builds unsaved temporary models and closes them without saving.
  if exist ('OCTAVE_VERSION', 'builtin')
    error ('reference_ob_conditional_probes: run this producer in MATLAB');
  end
  if exist ('load_system', 'file') == 0
    error ('reference_ob_conditional_probes:SimulinkMissing', ...
           'A local Simulink engine is required; no reference traces produced.');
  end
  load_system ('simulink');
  compat = 'compatibility (no trigger on first evaluation)';
  inits = {compat, 'zero', 'positive', 'negative'};
  records = {};

  % Trigger-only root subsystems under every InitialTriggerSignalState.
  % First samples: negative (1, 4), positive (2, 6) and zero (3, 5).
  controls = {[-1 0 1 0 0 1 -1 0 0 1], [1 1 -1 0 0 1], [0 1 0 -1 0 1], [-1 -1 1 1 0 -1], ...
              [0 -1 0 1 1 -1], [1 0 -1 -1 0 1]};
  for k = 1:numel (controls)
    for mode = {'rising', 'falling', 'either'}
      for init = inits
        r = record ('trigger_only', sprintf ('trigger_%s_%s_control%d', mode{1}, init{1}, k));
        r.mode = mode{1}; r.initial_trigger = init{1}; r.trigger = controls{k};
        records{end+1} = run_case (r); %#ok<AGROW>
      end
    end
  end

  % Enabled and Triggered root subsystems (Unit Delay IC 7, InitialOutput -9).
  C = {};
  C{end+1} = combined ('C1_enable_on_with_edge', 'rising', 'zero', [0 1 1 1 1 1], [-1 1 1 -1 1 1]);
  C{end+1} = combined ('C2_steady_enable_edge', 'rising', 'zero', ones (1, 6), [-1 1 1 -1 1 1]);
  for init = inits
    C{end+1} = combined (['C3_falling_' init{1}], 'falling', init{1}, ones (1, 6), [-1 -1 1 0 0 -1]); %#ok<AGROW>
    C{end+1} = combined (['C4_either_' init{1}], 'either', init{1}, ones (1, 6), [1 1 -1 0 0 1]); %#ok<AGROW>
  end
  C{end+1} = combined ('C5_const_enable_negative', 'rising', 'negative', ones (1, 6), [1 1 -1 0 0 1]);
  C{end}.const_enable = true;
  C{end+1} = combined ('C6_first_enable_coincident_edge', 'rising', 'negative', [0 0 1 1 1 1], [-1 -1 1 1 -1 1]);
  C{end+1} = combined ('C7_reenable_coincident_edge', 'rising', 'negative', [1 0 1 1 1 1], [-1 -1 1 1 -1 1]);
  % A zero first trigger sample separates "no event, previous = first sample"
  % (fires at t=1) from "event from the configured state, execution suppressed"
  % (the recorded -1 -> 0 edge would alias the following 0 -> +).
  for init = inits
    C{end+1} = combined (['P1_rising_zero_start_' init{1}], 'rising', init{1}, ones (1, 6), [0 1 1 0 0 1]); %#ok<AGROW>
  end
  C{end+1} = combined ('P2_falling_zero_start_positive', 'falling', 'positive', ones (1, 6), [0 -1 -1 0 0 -1]);
  C{end+1} = combined ('P3_either_zero_start_negative', 'either', 'negative', ones (1, 6), [0 1 1 0 0 1]);
  C{end+1} = combined ('P4_either_zero_start_positive', 'either', 'positive', ones (1, 6), [0 -1 -1 0 0 -1]);
  C{end+1} = combined ('P5_disabled_zero_start_negative', 'rising', 'negative', [0 1 1 1 1 1], [0 1 1 0 0 1]);
  C{end+1} = combined ('P6_disabled_high_start_negative', 'rising', 'negative', [0 1 1 1 1 1], [1 1 -1 1 1 1]);
  for k = 1:numel (C)
    records{end+1} = run_case (C{k}); %#ok<AGROW>
  end

  % Nested children of an Enabled outer (Unit Delay IC 17, InitialOutput -9).
  enable = [1 1 0 0 1 1 0 1];
  N = {};
  for wrapped = [false true]
    for outer = {'held', 'reset'}
      for inner = {'held', 'reset'}
        kind = 'combined'; if wrapped, kind = 'wrapper'; end
        N{end+1} = nested (sprintf ('nested_%s_%s_%s', kind, outer{1}, inner{1}), kind, ...
            outer{1}, inner{1}, enable, [-1 1 -1 -1 -1 1 -1 1]); %#ok<AGROW>
      end
    end
  end
  for outer = {'held', 'reset'}
    N{end+1} = nested (['N1_trigger_direct_' outer{1}], 'trigger_direct', outer{1}, 'held', ...
                       enable, [-1 1 -1 -1 -1 1 -1 1]); %#ok<AGROW>
    N{end+1} = nested (['N2_wrapper_retrigger_' outer{1}], 'wrapper', outer{1}, 'held', ...
                       enable, [-1 1 -1 -1 1 1 -1 1]); %#ok<AGROW>
    N{end+1} = nested (['N3_combined_frozen_low_' outer{1}], 'combined', outer{1}, 'held', ...
                       enable, [-1 -1 1 1 1 1 -1 1]); %#ok<AGROW>
    N{end+1} = nested (['N4_trigger_direct_frozen_low_' outer{1}], 'trigger_direct', outer{1}, 'held', ...
                       enable, [-1 -1 1 1 1 1 -1 1]); %#ok<AGROW>
    % An outer reset either keeps a combined child's trigger history or
    % returns it to the configured state: executed and unexecuted children.
    N{end+1} = nested (['R1_combined_executed_' outer{1}], 'combined', outer{1}, 'held', ...
                       enable, [-1 1 1 1 1 1 -1 1]); %#ok<AGROW>
    N{end+1} = nested (['R2_combined_unexecuted_' outer{1}], 'combined', outer{1}, 'held', ...
                       enable, [1 1 1 1 1 1 -1 1]); %#ok<AGROW>
    % Repeated outer resets before the next trigger: held output persistence.
    N{end+1} = nested (['M1_trigger_direct_double_reset_' outer{1}], 'trigger_direct', outer{1}, 'held', ...
                       [1 1 1 1 0 1 0 1 1 1], [-1 1 -1 1 -1 -1 -1 -1 -1 1]); %#ok<AGROW>
  end
  % The outer is disabled at t=0, so each child's first evaluation is at t=2.
  late = [0 0 1 1 1 1 1 1];
  N{end+1} = nested ('Q1_combined_late_high', 'combined', 'held', 'held', late, [1 1 1 1 -1 1 1 1]);
  N{end+1} = nested ('Q2_combined_late_zero', 'combined', 'held', 'held', late, [1 1 0 1 1 -1 1 1]);
  N{end+1} = nested ('Q3_combined_late_falling', 'combined', 'held', 'held', late, [-1 -1 -1 -1 1 -1 -1 -1]);
  N{end}.mode = 'falling'; N{end}.initial_trigger = 'positive';
  N{end+1} = nested ('Q4_trigger_direct_late_high', 'trigger_direct', 'held', 'held', late, [1 1 1 1 -1 1 1 1]);
  N{end+1} = nested ('Q5_trigger_direct_late_zero', 'trigger_direct', 'held', 'held', late, [1 1 0 1 1 -1 1 1]);
  % Late 'either': the zero first sample at t=2 makes t=3 a falling edge.
  N{end+1} = nested ('Q6_combined_late_either', 'combined', 'held', 'held', late, [1 1 0 -1 -1 1 1 1]);
  N{end}.mode = 'either'; N{end}.initial_trigger = 'positive';
  % A combined grandchild inside a Triggered wrapper (rising at t=1, 3, 5, 7)
  % takes its own trigger from inner_trigger, sampled only when the wrapper
  % fires.  W1: zero first sample, fires at t=3; W2: a high first sample does
  % not fire, and the low/high change between wrapper hits fires at t=5;
  % W3: outer resets at t=4 and t=7; a re-armed first evaluation never fires.
  % W4 ('either', wrapper fires every sample): the grandchild fires at t=3
  % and t=5, then the outer resets at t=7.  A kept history does not fire at
  % t=7 (held 3) and fires at t=8 from the kept state (5); a history restarted
  % from 'positive' would fire at t=7 (5, or 17 with reset states).
  wrapper_trigger = [-1 1 -1 1 -1 1 -1 1];
  N{end+1} = nested ('W1_wrapper_combined_zero_start', 'wrapper_combined', 'held', 'held', ...
                     ones (1, 8), wrapper_trigger);
  N{end}.inner_trigger = [0 0 0 1 1 1 1 1];
  N{end+1} = nested ('W2_wrapper_combined_high_start', 'wrapper_combined', 'held', 'held', ...
                     ones (1, 8), wrapper_trigger);
  N{end}.inner_trigger = [1 1 -1 -1 1 1 1 1];
  N{end+1} = nested ('W3_wrapper_combined_outer_reset', 'wrapper_combined', 'reset', 'held', ...
                     enable, wrapper_trigger);
  N{end}.inner_trigger = [-1 -1 -1 -1 1 1 1 1];
  N{end+1} = nested ('W4_wrapper_combined_reset_executed', 'wrapper_combined', 'reset', 'held', ...
                     [1 1 1 1 1 1 0 1 1 1], [1 -1 1 -1 1 -1 1 -1 1 -1]);
  N{end}.mode = 'either'; N{end}.initial_trigger = 'positive';
  N{end}.inner_trigger = [-1 -1 -1 1 1 -1 -1 -1 1 1];
  % Trigger-only children under 'compatibility'.  K: the outer is disabled
  % at t=0, so the first evaluation is at t=2 and is an edge from zero
  % (K1-K3) or a zero sample that arms the next rise (K4).
  K = {'K1_trigger_direct_late_high_compat', 'rising', [-1 -1 1 1 -1 1 1 1]; ...
       'K2_trigger_direct_late_low_compat', 'falling', [1 1 -1 -1 1 -1 -1 -1]; ...
       'K3_trigger_direct_late_either_compat', 'either', [-1 -1 1 1 -1 -1 1 1]; ...
       'K4_trigger_direct_late_zero_compat', 'rising', [1 1 0 1 1 -1 1 1]};
  for k = 1:size (K, 1)
    N{end+1} = nested (K{k,1}, 'trigger_direct', 'held', 'held', late, K{k,3}); %#ok<AGROW>
    N{end}.mode = K{k,2}; N{end}.initial_trigger = compat;
  end
  % E: the outer re-enables at t=4 and t=7 with 'held' or 'reset' states.
  % The last evaluated sample (t=1, t=5) and the re-enabling sample differ,
  % so a re-armed first evaluation (no execution), a kept history and a
  % history restarted from zero each give a different trace.
  E = {'E1_trigger_direct_reenable_high', 'rising', [-1 -1 -1 1 1 1 -1 1]; ...
       'E2_trigger_direct_reenable_zero', 'rising', [-1 -1 -1 -1 0 1 -1 1]; ...
       'E3_trigger_direct_reenable_low', 'falling', [1 1 1 1 -1 -1 1 -1]; ...
       'E4_trigger_direct_reenable_either', 'either', [-1 -1 1 1 1 -1 -1 1]};
  for outer = {'held', 'reset'}
    for k = 1:size (E, 1)
      N{end+1} = nested ([E{k,1} '_' outer{1}], 'trigger_direct', outer{1}, 'held', enable, E{k,3}); %#ok<AGROW>
      N{end}.mode = E{k,2}; N{end}.initial_trigger = compat;
    end
  end
  % D: two executions before each outer reset (t=5, t=8), so the held output
  % (1) differs from the reset Unit Delay's IC 17 and an execution at the
  % re-enabling sample is visible.  The re-enabling sample is not an edge
  % from the last evaluated sample but is one from the first sample and from
  % zero; 'negative' and 'zero' show the explicit states' restart rule.
  late_reset = [1 1 1 1 0 1 1 0 1 1];
  D = {'D1_trigger_direct_double_reset_compat', 'rising', compat, 'reset', [-1 1 -1 1 1 1 -1 1 1 1]; ...
       'D2_trigger_direct_double_reset_falling_compat', 'falling', compat, 'reset', [1 -1 1 -1 -1 -1 1 -1 -1 -1]; ...
       'D3_trigger_direct_double_reset_negative', 'rising', 'negative', 'reset', [-1 1 -1 1 1 1 -1 1 1 1]; ...
       'D4_trigger_direct_double_reset_zero', 'rising', 'zero', 'reset', [-1 1 -1 1 1 1 -1 1 1 1]; ...
       'D5_trigger_direct_double_held_compat', 'rising', compat, 'held', [-1 1 -1 1 1 1 -1 1 1 1]};
  for k = 1:size (D, 1)
    N{end+1} = nested (D{k,1}, 'trigger_direct', D{k,4}, 'held', late_reset, D{k,5}); %#ok<AGROW>
    N{end}.mode = D{k,2}; N{end}.initial_trigger = D{k,3};
  end
  % V: a trigger-only grandchild inside a Triggered wrapper, both rising
  % with 'compatibility'.  The wrapper fires at t=1, 3, 5, 7, which is the
  % grandchild's first evaluation (V1 high, V2 low, V3 zero).  V4: the outer
  % resets at t=4 and t=7 while the wrapper is idle; the grandchild's next
  % evaluation (t=5) either is a re-armed first evaluation or fires.
  V = {'V1_wrapper_trigger_high_start', 'held', ones(1, 8), [1 1 1 1 -1 -1 1 1]; ...
       'V2_wrapper_trigger_low_start', 'held', ones(1, 8), [-1 -1 -1 1 1 1 1 1]; ...
       'V3_wrapper_trigger_zero_start', 'held', ones(1, 8), [0 0 0 1 1 1 1 1]; ...
       'V4_wrapper_trigger_outer_reset', 'reset', enable, [-1 -1 -1 -1 -1 1 1 1]};
  for k = 1:size (V, 1)
    N{end+1} = nested (V{k,1}, 'wrapper_trigger', V{k,2}, 'held', V{k,3}, wrapper_trigger); %#ok<AGROW>
    N{end}.initial_trigger = compat; N{end}.inner_trigger = V{k,4};
  end
  % F: the last evaluated transition before the outer disable at t=5 is a
  % rise (F1, F4, F5) or fall (F2, F3) into zero at t=4, and the re-enabling
  % sample at t=6 continues it (0 -> +1 or 0 -> -1), so the edge flags alone
  % decide t=6.  Two executions before the disable make the held output (1)
  % differ from the reset Unit Delay's IC 17.  Kept flags: no execution at
  % t=6, and the next edge outputs 17 (states reset at re-enable); cleared
  % flags: 17 at t=6, then 6.  F4 is the explicit 'zero' restart and F5 the
  % 'held' outer.
  zero_reset = [1 1 1 1 1 0 1 1 1 1];
  F = {'F1_trigger_direct_reset_after_rise_to_zero_compat', 'rising', compat, 'reset', [-1 1 -1 -1 0 0 1 -1 1 1]; ...
       'F2_trigger_direct_reset_after_fall_to_zero_compat', 'falling', compat, 'reset', [1 -1 1 1 0 0 -1 1 -1 -1]; ...
       'F3_trigger_direct_reset_after_fall_to_zero_either_compat', 'either', compat, 'reset', [-1 1 1 1 0 0 -1 1 1 -1]; ...
       'F4_trigger_direct_reset_after_rise_to_zero_zero', 'rising', 'zero', 'reset', [-1 1 -1 -1 0 0 1 -1 1 1]; ...
       'F5_trigger_direct_held_after_rise_to_zero_compat', 'rising', compat, 'held', [-1 1 -1 -1 0 0 1 -1 1 1]};
  for k = 1:size (F, 1)
    N{end+1} = nested (F{k,1}, 'trigger_direct', F{k,4}, 'held', zero_reset, F{k,5}); %#ok<AGROW>
    N{end}.mode = F{k,2}; N{end}.initial_trigger = F{k,3};
  end
  % 'compatibility' variants of the trigger-only wrapper records above
  % (nested_wrapper_* and N2_wrapper_retrigger_*, which use 'negative'):
  % a compat Triggered wrapper around an Enabled body under each outer policy.
  for outer = {'held', 'reset'}
    for inner = {'held', 'reset'}
      N{end+1} = nested (sprintf ('nested_compat_wrapper_%s_%s', outer{1}, inner{1}), 'wrapper', ...
          outer{1}, inner{1}, enable, [-1 1 -1 -1 -1 1 -1 1]); %#ok<AGROW>
      N{end}.initial_trigger = compat;
    end
    N{end+1} = nested (['N2_wrapper_retrigger_compat_' outer{1}], 'wrapper', outer{1}, 'held', ...
                       enable, [-1 1 -1 -1 1 1 -1 1]); %#ok<AGROW>
    N{end}.initial_trigger = compat;
  end
  for k = 1:numel (N)
    records{end+1} = run_case (N{k}); %#ok<AGROW>
  end

  % Continuous triggers located as zero crossings by ode45: a cosine that
  % starts high (+) or low (-) and crosses zero near t = 0.2528, 0.8778 and
  % 1.5028.  The pass-through body holds the Clock at each execution.
  waves = {'high', [1, 2*pi*0.8, 0.3 + pi/2, 0]; 'low', [-1, 2*pi*0.8, 0.3 + pi/2, 0]};
  for mode = {'rising', 'falling', 'either'}
    for w = 1:size (waves, 1)
      for init = inits
        r = record ('continuous_trigger', sprintf ('continuous_%s_%s_%s', mode{1}, waves{w,1}, init{1}));
        r.mode = mode{1}; r.initial_trigger = init{1}; r.wave = waves{w,2};
        records{end+1} = run_case (r); %#ok<AGROW>
      end
    end
  end

  evidence = struct ('matlab_version', version, 'simulink_version', ver ('simulink'), ...
      'reference_script', 'reference_ob_conditional_probes.m', ...
      'trigger_port', trigger_port_info (), 'records', {records});
  fid = fopen (file, 'w');
  if fid < 0, error ('Cannot write reference output'); end
  cleanup = onCleanup (@() fclose (fid));
  fprintf (fid, '%s\n', jsonencode (evidence));
end

function r = record (group, name)
  % One field set for every record keeps the decoded JSON a struct array.
  r = struct ('group', group, 'name', name, 'kind', '', 'mode', 'rising', ...
              'initial_trigger', 'negative', 'outer', '', 'inner', 'held', ...
              'enable', [], 'trigger', [], 'inner_trigger', [], 'const_enable', false, ...
              'wave', [], 't', [], 'y', [], 'error', '');
end

function r = combined (name, mode, init, enable, trigger)
  r = record ('combined', name);
  r.mode = mode; r.initial_trigger = init; r.enable = enable; r.trigger = trigger;
end

function r = nested (name, kind, outer, inner, enable, trigger)
  r = record ('nested', name);
  r.kind = kind; r.outer = outer; r.inner = inner; r.enable = enable; r.trigger = trigger;
end

function r = run_case (r)
  try
    switch r.group
      case 'trigger_only', [r.t, r.y] = trigger_only (r);
      case 'combined', [r.t, r.y] = combined_root (r);
      case 'continuous_trigger', [r.t, r.y] = continuous_trigger (r);
      otherwise, [r.t, r.y] = nested_case (r);
    end
  catch err
    r.error = getReport (err, 'extended', 'hyperlinks', 'off');
  end
  fprintf ('%s: %s\n', r.name, mat2str (r.y));
end

function name = start_model (prefix, count)
  [~, suffix] = fileparts (tempname);
  name = [prefix suffix];
  new_system (name);
  set_param (name, 'SolverType', 'Fixed-step', 'Solver', 'FixedStepDiscrete', ...
      'FixedStep', '1', 'StartTime', '0', 'StopTime', num2str (count-1), ...
      'ReturnWorkspaceOutputs', 'on');
  add_block ('simulink/Sources/Digital Clock', [name '/Data'], 'SampleTime', '1');
end

function source (name, label, variable)
  add_block ('simulink/Sources/From Workspace', [name '/' label], 'VariableName', variable, ...
      'Interpolate', 'off', 'OutputAfterFinalValue', 'Holding final value', 'SampleTime', '1');
end

function delay_body (path, initial)
  delete_line (path, 'In1/1', 'Out1/1');
  add_block ('simulink/Discrete/Unit Delay', [path '/Delay'], ...
      'InitialCondition', initial, 'SampleTime', '-1');
  add_line (path, 'In1/1', 'Delay/1');
  add_line (path, 'Delay/1', 'Out1/1');
end

function [t, y] = simulate (name, r)
  add_block ('simulink/Sinks/To Workspace', [name '/Recorded'], ...
      'VariableName', 'reference_output', 'SaveFormat', 'Timeseries');
  input = Simulink.SimulationInput (name);
  times = (0:numel(r.trigger)-1)';
  input = input.setVariable ('trigger_data', [times r.trigger(:)]);
  if ~isempty (r.enable)
    input = input.setVariable ('enable_data', [times r.enable(:)]);
  end
  if ~isempty (r.inner_trigger)
    input = input.setVariable ('inner_trigger_data', [times r.inner_trigger(:)]);
  end
  add_line (name, 'Child/1', 'Recorded/1');
  result = sim (input);
  trace = result.reference_output;
  t = trace.Time(:)'; y = trace.Data(:)';
end

function [t, y] = trigger_only (r)
  name = start_model ('ob_probe_trigger_', numel (r.trigger));
  cleanup = onCleanup (@() close_system (name, 0));
  source (name, 'Trigger', 'trigger_data');
  add_block ('simulink/Ports & Subsystems/Triggered Subsystem', [name '/Child']);
  set_param ([name '/Child/Trigger'], 'TriggerType', r.mode, 'InitialTriggerSignalState', r.initial_trigger);
  delay_body ([name '/Child'], '0');
  set_param ([name '/Child/Out1'], 'InitialOutput', '-1');
  add_line (name, 'Data/1', 'Child/1');
  add_line (name, 'Trigger/1', 'Child/Trigger');
  [t, y] = simulate (name, r);
end

function [t, y] = combined_root (r)
  name = start_model ('ob_probe_combined_', numel (r.trigger));
  cleanup = onCleanup (@() close_system (name, 0));
  if r.const_enable
    add_block ('simulink/Sources/Constant', [name '/Enable'], 'Value', '1');
    r.enable = [];
  else
    source (name, 'Enable', 'enable_data');
  end
  source (name, 'Trigger', 'trigger_data');
  child = [name '/Child'];
  add_block ('simulink/Ports & Subsystems/Enabled and Triggered Subsystem', child);
  set_param ([child '/Enable'], 'StatesWhenEnabling', 'held');
  set_param ([child '/Trigger'], 'TriggerType', r.mode, 'InitialTriggerSignalState', r.initial_trigger);
  delay_body (child, '7');
  set_param ([child '/Out1'], 'InitialOutput', '-9', 'OutputWhenDisabled', 'held');
  add_line (name, 'Data/1', 'Child/1');
  add_line (name, 'Enable/1', 'Child/Enable');
  add_line (name, 'Trigger/1', 'Child/Trigger');
  [t, y] = simulate (name, r);
end

function [t, y] = nested_case (r)
  % Outer: Enabled Subsystem driven by enable_data, with the trigger routed in.
  name = start_model ('ob_probe_nested_', numel (r.trigger));
  cleanup = onCleanup (@() close_system (name, 0));
  source (name, 'Enable', 'enable_data');
  source (name, 'Trigger', 'trigger_data');
  outer = [name '/Child'];
  add_block ('simulink/Ports & Subsystems/Enabled Subsystem', outer);
  set_param ([outer '/Enable'], 'StatesWhenEnabling', r.outer);
  delete_line (outer, 'In1/1', 'Out1/1');
  add_block ('simulink/Sources/In1', [outer '/TriggerIn']);
  set_param ([outer '/Out1'], 'InitialOutput', '-9', 'OutputWhenDisabled', 'held');
  if any (strcmp (r.kind, {'wrapper_combined', 'wrapper_trigger'}))
    % Third outer input (port 3): the grandchild's own trigger signal.
    source (name, 'InnerTrigger', 'inner_trigger_data');
    add_block ('simulink/Sources/In1', [outer '/InnerTriggerIn']);
    add_line (name, 'InnerTrigger/1', 'Child/3');
  end
  switch r.kind
    case 'combined'
      body = [outer '/Inner'];
      add_block ('simulink/Ports & Subsystems/Enabled and Triggered Subsystem', body);
      set_param ([body '/Enable'], 'StatesWhenEnabling', r.inner);
      set_param ([body '/Trigger'], 'TriggerType', r.mode, 'InitialTriggerSignalState', r.initial_trigger);
      add_block ('simulink/Sources/Constant', [outer '/InnerEnable'], 'Value', '1');
      add_line (outer, 'In1/1', 'Inner/1');
      add_line (outer, 'InnerEnable/1', 'Inner/Enable');
      add_line (outer, 'TriggerIn/1', 'Inner/Trigger');
      add_line (outer, 'Inner/1', 'Out1/1');
    case 'trigger_direct'
      body = [outer '/Inner'];
      add_block ('simulink/Ports & Subsystems/Triggered Subsystem', body);
      set_param ([body '/Trigger'], 'TriggerType', r.mode, 'InitialTriggerSignalState', r.initial_trigger);
      add_line (outer, 'In1/1', 'Inner/1');
      add_line (outer, 'TriggerIn/1', 'Inner/Trigger');
      add_line (outer, 'Inner/1', 'Out1/1');
    case 'wrapper'
      wrap = [outer '/Wrapper'];
      add_block ('simulink/Ports & Subsystems/Triggered Subsystem', wrap);
      set_param ([wrap '/Trigger'], 'TriggerType', r.mode, 'InitialTriggerSignalState', r.initial_trigger);
      delete_line (wrap, 'In1/1', 'Out1/1');
      set_param ([wrap '/Out1'], 'InitialOutput', '-9');
      add_block ('simulink/Sources/Constant', [wrap '/InnerEnable'], 'Value', '1');
      body = [wrap '/Inner'];
      add_block ('simulink/Ports & Subsystems/Enabled Subsystem', body);
      set_param ([body '/Enable'], 'StatesWhenEnabling', r.inner);
      add_line (wrap, 'In1/1', 'Inner/1');
      add_line (wrap, 'InnerEnable/1', 'Inner/Enable');
      add_line (wrap, 'Inner/1', 'Out1/1');
      add_line (outer, 'In1/1', 'Wrapper/1');
      add_line (outer, 'TriggerIn/1', 'Wrapper/Trigger');
      add_line (outer, 'Wrapper/1', 'Out1/1');
    case 'wrapper_combined'
      % Triggered wrapper around an Enabled and Triggered grandchild (enable
      % constant 1); both use r.mode and r.initial_trigger.
      wrap = [outer '/Wrapper'];
      add_block ('simulink/Ports & Subsystems/Triggered Subsystem', wrap);
      set_param ([wrap '/Trigger'], 'TriggerType', r.mode, 'InitialTriggerSignalState', r.initial_trigger);
      delete_line (wrap, 'In1/1', 'Out1/1');
      set_param ([wrap '/Out1'], 'InitialOutput', '-9');
      add_block ('simulink/Sources/In1', [wrap '/InnerTriggerIn']);
      add_block ('simulink/Sources/Constant', [wrap '/InnerEnable'], 'Value', '1');
      body = [wrap '/Inner'];
      add_block ('simulink/Ports & Subsystems/Enabled and Triggered Subsystem', body);
      set_param ([body '/Enable'], 'StatesWhenEnabling', r.inner);
      set_param ([body '/Trigger'], 'TriggerType', r.mode, 'InitialTriggerSignalState', r.initial_trigger);
      add_line (wrap, 'In1/1', 'Inner/1');
      add_line (wrap, 'InnerEnable/1', 'Inner/Enable');
      add_line (wrap, 'InnerTriggerIn/1', 'Inner/Trigger');
      add_line (wrap, 'Inner/1', 'Out1/1');
      add_line (outer, 'In1/1', 'Wrapper/1');
      add_line (outer, 'InnerTriggerIn/1', 'Wrapper/2');
      add_line (outer, 'TriggerIn/1', 'Wrapper/Trigger');
      add_line (outer, 'Wrapper/1', 'Out1/1');
    case 'wrapper_trigger'
      % Triggered wrapper around a Triggered grandchild; both use r.mode and
      % r.initial_trigger, and the grandchild's trigger is inner_trigger.
      wrap = [outer '/Wrapper'];
      add_block ('simulink/Ports & Subsystems/Triggered Subsystem', wrap);
      set_param ([wrap '/Trigger'], 'TriggerType', r.mode, 'InitialTriggerSignalState', r.initial_trigger);
      delete_line (wrap, 'In1/1', 'Out1/1');
      set_param ([wrap '/Out1'], 'InitialOutput', '-9');
      add_block ('simulink/Sources/In1', [wrap '/InnerTriggerIn']);
      body = [wrap '/Inner'];
      add_block ('simulink/Ports & Subsystems/Triggered Subsystem', body);
      set_param ([body '/Trigger'], 'TriggerType', r.mode, 'InitialTriggerSignalState', r.initial_trigger);
      add_line (wrap, 'In1/1', 'Inner/1');
      add_line (wrap, 'InnerTriggerIn/1', 'Inner/Trigger');
      add_line (wrap, 'Inner/1', 'Out1/1');
      add_line (outer, 'In1/1', 'Wrapper/1');
      add_line (outer, 'InnerTriggerIn/1', 'Wrapper/2');
      add_line (outer, 'TriggerIn/1', 'Wrapper/Trigger');
      add_line (outer, 'Wrapper/1', 'Out1/1');
  end
  delay_body (body, '17');
  if any (strcmp (r.kind, {'trigger_direct', 'wrapper_trigger'}))
    set_param ([body '/Out1'], 'InitialOutput', '-9');
  else
    set_param ([body '/Out1'], 'InitialOutput', '-9', 'OutputWhenDisabled', 'held');
  end
  add_line (name, 'Data/1', 'Child/1');
  add_line (name, 'Trigger/1', 'Child/2');
  add_line (name, 'Enable/1', 'Child/Enable');
  [t, y] = simulate (name, r);
end

function [t, y] = continuous_trigger (r)
  % Root Triggered Subsystem with a pass-through body (Out1 InitialOutput
  % -1) on a continuous Sine Wave trigger, ode45 with zero-crossing
  % location; the To Workspace block samples the held output every 0.05.
  [~, suffix] = fileparts (tempname);
  name = ['ob_probe_continuous_' suffix];
  new_system (name);
  cleanup = onCleanup (@() close_system (name, 0));
  set_param (name, 'SolverType', 'Variable-step', 'Solver', 'ode45', 'RelTol', '1e-10', ...
      'AbsTol', '1e-12', 'MaxStep', '0.05', 'StartTime', '0', 'StopTime', '2', ...
      'ReturnWorkspaceOutputs', 'on');
  add_block ('simulink/Sources/Clock', [name '/Data']);
  add_block ('simulink/Sources/Sine Wave', [name '/Trigger'], ...
      'Amplitude', num2str (r.wave(1), 17), 'Frequency', num2str (r.wave(2), 17), ...
      'Phase', num2str (r.wave(3), 17), 'Bias', num2str (r.wave(4), 17));
  child = [name '/Child'];
  add_block ('simulink/Ports & Subsystems/Triggered Subsystem', child);
  set_param ([child '/Trigger'], 'TriggerType', r.mode, 'InitialTriggerSignalState', r.initial_trigger);
  set_param ([child '/Out1'], 'InitialOutput', '-1');
  add_block ('simulink/Sinks/To Workspace', [name '/Recorded'], ...
      'VariableName', 'reference_output', 'SaveFormat', 'Timeseries', 'SampleTime', '0.05');
  add_line (name, 'Data/1', 'Child/1');
  add_line (name, 'Trigger/1', 'Child/Trigger');
  add_line (name, 'Child/1', 'Recorded/1');
  result = sim (name);
  trace = result.reference_output;
  t = trace.Time(:)'; y = trace.Data(:)';
end

function info = trigger_port_info ()
  % The Trigger block's InitialTriggerSignalState default, its value list,
  % and which spellings set_param accepts (and what it then reports).
  [~, suffix] = fileparts (tempname);
  name = ['ob_probe_port_' suffix];
  new_system (name);
  cleanup = onCleanup (@() close_system (name, 0));
  add_block ('simulink/Ports & Subsystems/Triggered Subsystem', [name '/Child']);
  port = [name '/Child/Trigger'];
  info = struct ('default', get_param (port, 'InitialTriggerSignalState'), 'values', {{}}, 'error', '');
  try
    parameters = get_param (port, 'DialogParameters');
    info.values = parameters.InitialTriggerSignalState.Enum;
  catch err
    info.error = err.message;
  end
  spellings = {'zero', 'Zero', 'POSITIVE', 'negative', 'compatibility', ...
               'compatibility (no trigger on first evaluation)', 'unknown'};
  attempts = struct ('value', spellings, 'accepted', false, 'result', '', 'message', '');
  for k = 1:numel (attempts)
    try
      set_param (port, 'InitialTriggerSignalState', attempts(k).value);
      attempts(k).accepted = true;
      attempts(k).result = get_param (port, 'InitialTriggerSignalState');
    catch err
      attempts(k).message = err.message;
    end
    set_param (port, 'InitialTriggerSignalState', info.default);
  end
  info.attempts = attempts;
end
