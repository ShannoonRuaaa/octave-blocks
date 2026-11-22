function cases = ob_simulink_conditional_cases (directory = '')
  % Octave Blocks models for every recorded Simulink conditional reference.
  % The traces come from MATLAB producers, each writing one file:
  %   reference_ob_conditional        simulink-conditional-reference.json
  %   reference_ob_combined           simulink-combined-reference.json
  %   reference_ob_nested_reset       simulink-nested-reset-reference.json
  %   reference_ob_conditional_probes simulink-conditional-probes-reference.json
  % Each case holds the model, output times, run options, Scope block ids and
  % the Simulink trace (rows are samples).  A record that Octave Blocks does
  % not reproduce by design would name its reason in 'differs' and carry an
  % 'alternate' model that must reproduce it; no current record needs one.
  if (isempty (directory)), directory = ob_test_reference (); endif
  cases = struct ('name', {}, 'model', {}, 'times', {}, 'options', {}, ...
                  'scopes', {}, 'expected', {}, 'differs', {}, 'alternate', {});

  for rec = records (directory, 'simulink-conditional-reference.json')
    times = rec.t(:)';
    model = ob_conditional_example ();
    model.inputs = {ob_input_signal(times', rec.control(:))};
    % The harness sets InitialTriggerSignalState 'zero', the Octave default.
    model.blocks(3).value.execution.mode = rec.mode;
    model.blocks(3).value.execution.states = rec.states;
    model.blocks(3).value.execution.outputs = rec.outputs;
    for solver = {'rk4','ode45'}
      options = struct ('solver',solver{1},'reltol',1e-8,'abstol',1e-10);
      add (['conditional/' rec.name '/' solver{1}], model, times, options, 4, rec.y(:));
    endfor
  endfor

  for rec = records (directory, 'simulink-combined-reference.json')
    rec.mode = rec.trigger_type; rec.const_enable = false;
    add (['combined/' rec.name], combined_root (rec), rec.t(:)', struct (), 5, rec.y(:));
  endfor

  nested = ob_nested_reset_cases ();
  for rec = records (directory, 'simulink-nested-reset-reference.json')
    policy = cellstr (rec.policies)';
    expected = rec.y;
    if (isvector (expected)), expected = expected(:); endif
    scopes = 3 + (1:numel(policy));
    label = sprintf ('nested-reset/%s %s', rec.kind, strjoin (policy, '/'));
    if (strcmp (rec.kind, 'discrete'))
      % Exactly one sampled and one continuous-control case per record, so a
      % renamed ob_nested_reset_cases cannot silently drop the comparison.
      matches = nested(cellfun (@(m) isequal (m, policy), policies_of (nested)));
      if (numel (matches) != 2)
        error ('ob_simulink_conditional_cases: %d Octave cases for %s, expected 2', ...
               numel (matches), label);
      endif
      for c = matches
        add ([label ' ' c.name], c.model, rec.t(:)', c.options, scopes, expected);
      endfor
    else
      for solver = {'rk4','ode45'}
        options = struct ('solver',solver{1},'maxstep',.25,'reltol',1e-10,'abstol',1e-12);
        add ([label ' ' solver{1}], integrator_layers (policy), rec.t(:)', options, scopes, expected);
      endfor
    endif
  endfor

  for rec = records (directory, 'simulink-conditional-probes-reference.json')
    times = rec.t(:)'; name = ['probes/' rec.name];
    if (! isempty (rec.error))
      error ('ob_simulink_conditional_cases: Simulink failed for %s', rec.name);
    endif
    switch (rec.group)
      case 'trigger_only'
        model = ob_conditional_example ();
        model.inputs = {ob_input_signal(times', rec.trigger(:))};
        model.blocks(3).value.execution.mode = rec.mode;
        model.blocks(3).value.execution.initial_control = initial_value (rec.initial_trigger);
        add (name, model, times, struct (), 4, rec.y(:));
      case 'continuous_trigger'
        % The held Clock values are the located crossing times.
        options = struct ('solver', 'ode45', 'zero_crossings', true, 'maxstep', .05, ...
                          'reltol', 1e-10, 'abstol', 1e-12);
        add (name, continuous_trigger (rec), times, options, 8, rec.y(:));
      case 'combined'
        add (name, combined_root (rec), times, struct (), 5, rec.y(:));
      case 'nested'
        for event = [false true]
          options = struct ('zero_crossings', event, 'maxstep', .25);
          variant = '/sampled'; if (event), variant = '/continuous'; endif
          add ([name variant], nested_probe (rec, event), times, options, 4, rec.y(:));
        endfor
      otherwise
        error ('ob_simulink_conditional_cases: unknown probe group %s', rec.group);
    endswitch
  endfor

  function add (name, model, times, options, scopes, expected)
    cases(end+1) = struct ('name', name, 'model', model, 'times', times, 'options', options, ...
                           'scopes', scopes, 'expected', expected, 'differs', '', 'alternate', []);
  endfunction
endfunction

function list = records (directory, file)
  evidence = jsondecode (fileread (fullfile (directory, file)));
  list = evidence.records;
  if (iscell (list)), list = [list{:}]; endif
  list = reshape (list, 1, []);
endfunction

function policies = policies_of (nested)
  % ob_nested_reset_cases names its sampled policy cases nested_reset_<k>_<event>.
  table = {{'held','held'}, {'held','reset'}, {'reset','held'}, {'reset','reset'}, ...
           {'reset','reset','held'}, {'held','held','reset'}, {'reset','held','reset'}};
  policies = cell (1, numel (nested));
  for k = 1:numel (nested)
    index = sscanf (nested(k).name, 'nested_reset_%d_');
    if (! isempty (index)), policies{k} = table{index}; endif
  endfor
endfunction

function value = initial_value (name)
  % Simulink's InitialTriggerSignalState as Octave Blocks initial_control.
  switch (name)
    case 'positive', value = 1;
    case 'negative', value = -1;
    case 'zero', value = 0;
    case 'compatibility (no trigger on first evaluation)', value = 'compatibility';
    otherwise, error ('ob_simulink_conditional_cases: unknown trigger state %s', name);
  endswitch
endfunction

function model = continuous_trigger (rec)
  % Root Triggered pass-through (initial output -1) holding the time at
  % each execution; the trigger is wave(1)*sin(wave(2)*t+wave(3))+wave(4).
  child.blocks = [block('Inport',1,'In1'), block('Outport',1,'Out1')];
  child.edges = [1 1 2 1];
  child.execution = struct ('mode', rec.mode, 'control', 'continuous', 'initial_outputs', {{-1}}, ...
                            'initial_control', initial_value (rec.initial_trigger));
  wave = rec.wave;
  model.blocks = [block('Time',[],'Time'), block('Gain',wave(2),'Angular rate'), ...
                  block('Constant',wave(3),'Phase'), block('Sum',[],'Angle'), ...
                  block('Function',[],'sin'), block('Gain',wave(1),'Amplitude'), ...
                  block('Subsystem',child,'Triggered'), block('Scope',[],'Output'), ...
                  block('Constant',wave(4),'Bias'), block('Sum',[],'Trigger')];
  model.edges = [1 1 2 1; 2 1 4 1; 3 1 4 2; 4 1 5 1; 5 1 6 1; 6 1 10 1; 9 1 10 2; ...
                 1 1 7 1; 10 1 7 2; 7 1 8 1];
endfunction

function model = combined_root (rec)
  % Enabled and Triggered delay: Unit Delay IC 7, initial output -9.
  model = ob_combined_control_example ();
  times = (0:numel(rec.trigger)-1)';
  model.inputs = {ob_input_signal(times, rec.enable(:)), ob_input_signal(times, rec.trigger(:))};
  if (rec.const_enable)
    model.blocks(2).type = 'Constant'; model.blocks(2).value = 1;
    model.blocks(3).value = 1;
    model.inputs = {ob_input_signal(times, rec.trigger(:))};
  endif
  states = 'held'; outputs = 'held';
  if (isfield (rec, 'states')), states = rec.states; outputs = rec.outputs; endif
  model.blocks(4).value.blocks(2).value = 7;
  model.blocks(4).value.execution = struct ('mode', ['enabled_' rec.mode], 'states', states, ...
      'outputs', outputs, 'initial_outputs', {{-9}}, ...
      'initial_control', initial_value (rec.initial_trigger));
endfunction

function model = nested_probe (rec, event)
  % Enabled outer (initial output -9) around a combined, trigger-only,
  % trigger-wrapped Enabled or trigger-wrapped combined body; the body is a
  % Unit Delay with IC 17.
  delay = [block('Inport',1,'Data'), block('Unit Delay',17,'State'), block('Outport',1,'Out')];
  body.blocks = delay; body.edges = [1 1 2 1; 2 1 3 1];
  trigger = struct ('mode', rec.mode, 'initial_outputs', {{-9}}, ...
                    'initial_control', initial_value (rec.initial_trigger));
  switch (rec.kind)
    case 'combined'
      body.execution = trigger;
      body.execution.mode = ['enabled_' rec.mode]; body.execution.states = rec.inner;
      outer.blocks = [block('Inport',1,'Data'), block('Inport',2,'Trigger'), ...
                      block('Constant',1,'Inner enable'), block('Subsystem',body,'Inner'), ...
                      block('Outport',1,'Out')];
      outer.edges = [1 1 4 1; 3 1 4 2; 2 1 4 3; 4 1 5 1];
    case 'trigger_direct'
      body.execution = trigger;
      outer.blocks = [block('Inport',1,'Data'), block('Inport',2,'Trigger'), ...
                      block('Subsystem',body,'Inner'), block('Outport',1,'Out')];
      outer.edges = [1 1 3 1; 2 1 3 2; 3 1 4 1];
    case 'wrapper'
      body.execution = struct ('mode','enabled','states',rec.inner,'initial_outputs',{{-9}});
      wrap.blocks = [block('Inport',1,'Data'), block('Constant',1,'Inner enable'), ...
                     block('Subsystem',body,'Enabled'), block('Outport',1,'Out')];
      wrap.edges = [1 1 3 1; 2 1 3 2; 3 1 4 1];
      wrap.execution = trigger;
      outer.blocks = [block('Inport',1,'Data'), block('Inport',2,'Trigger'), ...
                      block('Subsystem',wrap,'Wrapper'), block('Outport',1,'Out')];
      outer.edges = [1 1 3 1; 2 1 3 2; 3 1 4 1];
    case 'wrapper_combined'
      % Trigger-only wrapper around a combined grandchild whose own trigger is
      % the third model input (outer and wrapper data input 2).
      body.execution = trigger;
      body.execution.mode = ['enabled_' rec.mode]; body.execution.states = rec.inner;
      wrap.blocks = [block('Inport',1,'Data'), block('Inport',2,'Inner trigger'), ...
                     block('Constant',1,'Inner enable'), block('Subsystem',body,'Inner'), ...
                     block('Outport',1,'Out')];
      wrap.edges = [1 1 4 1; 3 1 4 2; 2 1 4 3; 4 1 5 1];
      wrap.execution = trigger;
      outer.blocks = [block('Inport',1,'Data'), block('Inport',2,'Trigger'), ...
                      block('Inport',3,'Inner trigger'), block('Subsystem',wrap,'Wrapper'), ...
                      block('Outport',1,'Out')];
      outer.edges = [1 1 4 1; 3 1 4 2; 2 1 4 3; 4 1 5 1];
    case 'wrapper_trigger'
      % Trigger-only wrapper around a trigger-only grandchild whose own
      % trigger is the third model input (outer and wrapper data input 2).
      body.execution = trigger;
      wrap.blocks = [block('Inport',1,'Data'), block('Inport',2,'Inner trigger'), ...
                     block('Subsystem',body,'Inner'), block('Outport',1,'Out')];
      wrap.edges = [1 1 3 1; 2 1 3 2; 3 1 4 1];
      wrap.execution = trigger;
      outer.blocks = [block('Inport',1,'Data'), block('Inport',2,'Trigger'), ...
                      block('Inport',3,'Inner trigger'), block('Subsystem',wrap,'Wrapper'), ...
                      block('Outport',1,'Out')];
      outer.edges = [1 1 4 1; 3 1 4 2; 2 1 4 3; 4 1 5 1];
    otherwise
      error ('ob_simulink_conditional_cases: unknown nested kind %s', rec.kind);
  endswitch
  outer.execution = struct ('mode','enabled','states',rec.outer,'initial_outputs',{{-9}});
  if (event), outer.execution.control = 'continuous'; endif
  model.blocks = [block('Time',[],'Data'), block('Inport',1,'Enable'), ...
                  block('Subsystem',outer,'Outer'), block('Scope',[],'Out'), ...
                  block('Inport',2,'Trigger')];
  model.edges = [1 1 3 1; 5 1 3 2; 2 1 3 3; 3 1 4 1];
  times = (0:numel(rec.enable)-1)';
  model.inputs = {ob_input_signal(times, rec.enable(:)), ob_input_signal(times, rec.trigger(:))};
  if (any (strcmp (rec.kind, {'wrapper_combined', 'wrapper_trigger'})))
    model.blocks(6) = block ('Inport', 3, 'Inner trigger');
    model.edges = [1 1 3 1; 5 1 3 2; 6 1 3 3; 2 1 3 4; 3 1 4 1];
    model.inputs{3} = ob_input_signal (times, rec.inner_trigger(:));
  endif
endfunction

function model = integrator_layers (policy, depth = 1)
  % reference_ob_nested_reset's continuous form: Constant 1 into nested
  % Enabled Integrators (IC 7, 17, ...), one Outport per level (no Mux).
  if (depth == 1)
    model.blocks = [block('Constant',1,'Data'), block('Inport',1,'Enable'), ...
                    block('Subsystem',integrator_layers (policy, 2),'Outer')];
    model.edges = [1 1 3 1; 2 1 3 2];
    model.inputs = {ob_input_signal((0:7)', [1;1;0;0;1;1;0;1])};
    for port = 1:numel (policy)
      model.blocks(3+port) = block ('Scope', [], sprintf ('Level %d', port));
      model.edges(end+1,:) = [3 port 3+port 1];
    endfor
    return;
  endif
  level = depth - 1;
  count = numel (policy) - level + 1;
  model.blocks = [block('Inport',1,'Data'), block('Integrator',7+10*(level-1),'State'), ...
                  block('Outport',1,'Local state')];
  model.edges = [1 1 2 1; 2 1 3 1];
  model.execution = struct ('mode','enabled','states',policy{level}, ...
                            'initial_outputs',{repmat({-9},1,count)});
  if (count == 1), return; endif
  model.blocks(4) = block ('Constant', 1, 'Inner enable');
  model.blocks(5) = block ('Subsystem', integrator_layers (policy, depth+1), 'Inner');
  model.edges = [model.edges; 1 1 5 1; 4 1 5 2];
  for port = 2:count
    model.blocks(4+port) = block ('Outport', port, sprintf ('Level %d', level+port-1));
    model.edges(end+1,:) = [5 port-1 4+port 1];
  endfor
endfunction

function b = block (type, value, name)
  b = struct ('type', type, 'value', value, 'name', name, 'x', .5, 'y', .5);
endfunction
