function model = ob_scalar_initial_example (kind = 'nested')
  % Enabled subsystems whose 2-element Outport has a scalar InitialOutput,
  % which Simulink expands to [v v] before the first execution.  Data is
  % [1 2]*t through a Gain 3 inside the body.
  %   'offset'  the subsystem runs at [0.5 0.25] (first evaluation after the
  %             start), enabled over [0.6, 1.1): InitialOutput -4 holds
  %             [-4 -4] from t = 0 (the root runtime initialization applies
  %             ob_expand_initial_outputs; the editor and sim also do);
  %   'nested'  an enabled body sampled every 0.25 s (InitialOutput -4,
  %             enabled from 0.5) contains an enabled body at [0.5 0.25]
  %             (InitialOutput -5, enabled from 1): the inner [-5 -5] reaches
  %             the outer port before the inner body first runs.
  B = @(type, value, name) struct ('type', type, 'value', value, 'name', name, 'x', .5, 'y', .5);
  body.blocks = [B('Inport', 1, 'Data') B('Gain', 3, 'Triple') B('Outport', 1, 'Out')];
  body.edges = [1 1 2 1; 2 1 3 1];
  switch (kind)
    case 'offset'
      body.execution = struct ('mode', 'enabled', 'initial_outputs', {{-4}});
      model.blocks = [B('Time', [], 'Time') B('Gain', [1 2], 'Spread') B('Inport', 1, 'Enable') ...
                      B('Subsystem', body, 'Gated') B('Scope', [], 'Out')];
      model.edges = [1 1 2 1; 2 1 4 1; 3 1 4 2; 4 1 5 1];
      model.inputs = {ob_input_signal([0 .6 1.1 2], [0; 1; 0; 0])};
      model.sample_times = zeros (5, 2); model.sample_times(4, :) = [.5 .25];
    case 'nested'
      body.execution = struct ('mode', 'enabled', 'initial_outputs', {{-5}});
      outer.blocks = [B('Inport', 1, 'Data') B('Inport', 2, 'Inner enable') B('Subsystem', body, 'Inner') ...
                      B('Outport', 1, 'Out')];
      outer.edges = [1 1 3 1; 2 1 3 2; 3 1 4 1];
      outer.sample_times = zeros (4, 2); outer.sample_times(3, :) = [.5 .25];
      outer.execution = struct ('mode', 'enabled', 'initial_outputs', {{-4}});
      model.blocks = [B('Time', [], 'Time') B('Gain', [1 2], 'Spread') B('Inport', 1, 'Outer enable') ...
                      B('Inport', 2, 'Inner enable') B('Subsystem', outer, 'Outer') B('Scope', [], 'Out')];
      model.edges = [1 1 2 1; 2 1 5 1; 4 1 5 2; 3 1 5 3; 5 1 6 1];
      model.inputs = {ob_input_signal([0 .5], [0; 1]), ob_input_signal([0 1], [0; 1])};
      model.sample_times = zeros (6, 2); model.sample_times(5, :) = [.25 0];
    otherwise
      error ('ob_scalar_initial_example: kind must be offset or nested');
  endswitch
endfunction
