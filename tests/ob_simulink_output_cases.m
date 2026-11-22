function [model, options, scopes] = ob_simulink_output_cases (c)
  % Octave Blocks model for one case of simulink-conditional-outputs-reference.json
  % (recorded by reference_ob_conditional_outputs.m), with its run options
  % and the root Scope blocks holding the recorded columns, in order.
  % Shared by test_ob_simulink_extended (comparison with Simulink) and the
  % C export fixtures (test_ob_inner_clock_c_cases, which
  % test_ob_event_codegen_cases also runs in event mode).
  p = c.parameters;
  options = struct ('solver', 'rk4');
  switch (c.model)
    case 'gating'
      % Simulink's data source is a 0.125 s Digital Clock (digital_clock).
      child = make_model ({'Inport', 1; 'Unit Delay', p.fast_initial; 'Unit Delay', p.slow_initial; ...
                           'Sum', []; 'Gain', 2; 'Gain', 3; 'Sum', []; 'Constant', p.constant; ...
                           'Discrete Integrator', p.euler_initial; 'Rate Transition', p.transition_initial; ...
                           'Outport', 1; 'Outport', 2; 'Outport', 3; 'Outport', 4; 'Outport', 5; ...
                           'Outport', 6; 'Outport', 7; 'Outport', 8; 'Outport', 9}, ...
                          [1 1 2 1; 1 1 3 1; 2 1 4 1; 3 1 4 2; 4 1 11 1; 3 1 5 1; 5 1 12 1; ...
                           1 1 6 1; 6 1 13 1; 1 1 7 1; 3 1 7 2; 7 1 14 1; 8 1 15 1; 3 1 16 1; ...
                           1 1 9 1; 9 1 17 1; 1 1 10 1; 10 1 18 1; 2 1 19 1]);
      child.sample_times = zeros (19, 2);
      child.sample_times([2 3 10], :) = [p.fast 0; p.slow 0; p.transition_period 0];
      child.execution = struct ('mode', 'enabled', 'states', p.states, 'outputs', {policies(p.outputs)}, ...
                                'initial_outputs', {repmat({p.initial_output}, 1, 9)});
      [model, scopes] = enabled_root (block ('Time', []), child, 9, p.enable, p.enable_sample);
      model = digital_clock (model, p.data_sample);
    case 'gating_continuous'
      child = make_model ({'Inport', 1; 'Integrator', p.integrator_initial; 'Unit Delay', p.slow_initial; ...
                           'Sum', []; 'Outport', 1; 'Outport', 2; 'Outport', 3}, ...
                          [1 1 2 1; 2 1 5 1; 2 1 3 1; 3 1 6 1; 2 1 4 1; 3 1 4 2; 4 1 7 1]);
      child.sample_times = zeros (7, 2); child.sample_times(3, :) = [p.slow 0];
      child.execution = struct ('mode', 'enabled', 'states', p.states, ...
                                'initial_outputs', {repmat({p.initial_output}, 1, 3)});
      [model, scopes] = enabled_root (block ('Constant', p.slope), child, 3, p.enable, p.enable_sample);
    case 'vector_clock'
      child = make_model ({'Inport', 1; 'Unit Delay', row(p.delay_initial); 'Outport', 1; 'Outport', 2}, ...
                          [1 1 2 1; 2 1 3 1; 1 1 4 1]);
      child.sample_times = zeros (4, 2); child.sample_times(2, :) = [p.slow 0];
      initial = cellfun (@row, p.initial_outputs, 'UniformOutput', false)';
      child.execution = struct ('mode', 'enabled', 'outputs', {policies(p.outputs)}, ...
                                'initial_outputs', {initial});
      [model, scopes] = enabled_root (block ('Time', []), child, 2, p.enable, p.enable_sample);
      % Data passes a Gain [1 2] before the subsystem, as in the producer.
      model.blocks(end+1) = block ('Gain', row (p.gain), 'Spread');
      spread = numel (model.blocks);
      model.edges(model.edges(:, 1) == 1 & model.edges(:, 3) == 3, 1) = spread;
      model.edges(end+1, :) = [1 1 spread 1];
      model.sample_times(spread, :) = [0 0];
      model = digital_clock (model, p.data_sample);
    case 'triggered_ports'
      % Simulink keeps a Triggered Subsystem's outputs held whatever
      % OutputWhenDisabled says, so the Octave Blocks model holds them.
      child = make_model ({'Inport', 1; 'Gain', p.gain; 'Outport', 1; 'Outport', 2}, ...
                          [1 1 3 1; 1 1 2 1; 2 1 4 1]);
      child.execution = struct ('mode', p.trigger_type, 'initial_control', initial_control (p.initial_trigger), ...
                                'initial_outputs', {num2cell(row (p.initial_outputs))});
      [model, scopes] = enabled_root (block ('Time', []), child, 2, p.trigger, p.trigger_sample);
      model = digital_clock (model, p.data_sample);
    case 'combined_ports'
      child = make_model ({'Inport', 1; 'Gain', p.gain; 'Outport', 1; 'Outport', 2}, ...
                          [1 1 3 1; 1 1 2 1; 2 1 4 1]);
      child.execution = struct ('mode', ['enabled_' p.trigger_type], 'states', p.states, ...
                                'outputs', {policies(p.outputs)}, ...
                                'initial_control', initial_control (p.initial_trigger), ...
                                'initial_outputs', {num2cell(row (p.initial_outputs))});
      [model, scopes] = enabled_root (block ('Time', []), child, 2, p.enable, p.sample);
      % Enable then trigger: the trigger is a second root input.
      model.blocks(end+1) = block ('Inport', 2, 'Trigger');
      trigger = numel (model.blocks);
      model.edges(end+1, :) = [trigger 1 3 3];
      model.sample_times(trigger, :) = [0 0];
      model.inputs{2} = ob_input_signal (p.trigger.times(:), p.trigger.values(:));
      model = digital_clock (model, p.data_sample);
    otherwise
      error ('ob_simulink_output_cases: unknown model %s', c.model);
  endswitch
endfunction

function [model, scopes] = enabled_root (data, child, outputs, control, sample)
  % Data (block 1), control Inport 1 (block 2), Subsystem (block 3) sampled
  % every SAMPLE seconds, then one Scope per output.
  model = make_model ({'Constant', []; 'Inport', 1; 'Subsystem', child}, [1 1 3 1; 2 1 3 2]);
  model.blocks(1) = data;
  model.blocks(2).name = 'Control';
  scopes = zeros (1, outputs);
  for port = 1:outputs
    model.blocks(end+1) = block ('Scope', [], sprintf ('Output %d', port));
    scopes(port) = numel (model.blocks);
    model.edges(end+1, :) = [3 port scopes(port) 1];
  endfor
  model.sample_times = zeros (numel (model.blocks), 2);
  model.sample_times(3, :) = [sample 0];
  model.inputs = {ob_input_signal(control.times(:), control.values(:))};
endfunction

function value = initial_control (name)
  switch (name)
    case 'positive', value = 1;
    case 'negative', value = -1;
    case 'compatibility', value = 'compatibility';
    otherwise, value = 0;  % 'zero'
  endswitch
endfunction

function model = make_model (entries, edges)
  model.blocks = struct ('type', {}, 'value', {}, 'name', {}, 'x', {}, 'y', {});
  for k = 1:rows (entries)
    model.blocks(k) = block (entries{k, 1}, entries{k, 2}, entries{k, 1});
  endfor
  model.edges = edges;
endfunction

function b = block (type, value, name = type)
  b = struct ('type', type, 'value', value, 'name', name, 'x', .5, 'y', .5);
endfunction

function v = row (v)
  v = reshape (v, 1, []);
endfunction

function list = policies (value)
  % jsondecode gives a cell of strings (or one string for a single port).
  if (ischar (value)), list = {value}; else list = reshape (value, 1, []); endif
endfunction

function model = digital_clock (model, sample)
  % Simulink's Digital Clock: Time (block 1) through a root Rate Transition
  % with period SAMPLE, so the data holds between samples.
  model.blocks(end+1) = block ('Rate Transition', 0, 'Digital Clock');
  clock = numel (model.blocks);
  model.edges(model.edges(:, 1) == 1, 1) = clock;
  model.edges(end+1, :) = [1 1 clock 1];
  model.sample_times(clock, :) = [sample 0];
endfunction
