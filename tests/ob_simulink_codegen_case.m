function entry = ob_simulink_codegen_case (directory, name = 'simulink_api_switch_gain')
  % Build a model with the Simulink-style command API that uses the
  % structural Switch criteria ('u2 > Threshold' with a nonzero threshold,
  % 'u2 ~= 0') and the non-scalar Gain realizations (element-wise K.*u,
  % also into an Integrator, and Matrix(u*K)), export it to C in DIRECTORY
  % and write the Octave reference traces next to it.  ENTRY is a
  % standalone case in the manifest format of test_ob_codegen, so the
  % generated C can be compiled and compared by verify_ob_codegen.
  % ob_simulink is called directly, so the simulink/ wrappers need not be
  % on the path.
  if (ob_simulink ('bdIsLoaded', name)), ob_simulink ('close_system', name, 0); endif
  cleanup = onCleanup (@() ob_simulink ('bdclose', name));
  ob_simulink ('new_system', name);
  A = @(source, block, varargin) ob_simulink ('add_block', source, [name '/' block], varargin{:});
  L = @(from, to) ob_simulink ('add_line', name, from, to);
  A('simulink/Sources/Constant', 'One', 'Value', '1');
  A('simulink/Sources/Constant', 'Three', 'Value', '3');
  A('simulink/Sources/Ramp', 'U2', 'InitialOutput', '-1');
  A('simulink/Sources/Sine Wave', 'Sine', 'Frequency', '3');
  A('simulink/Signal Routing/Switch', 'Sw');                       % u2 > Threshold
  A('built-in/Switch', 'SwB');                                     % u2 >= Threshold
  A('simulink/Commonly Used Blocks/Switch', 'SwN', 'Criteria', 'u2 ~= 0');
  A('simulink/Signal Routing/Switch', 'SwS', 'Threshold', '0.25');
  A('simulink/Sources/Constant', 'U', 'Value', '[1 2]');
  A('simulink/Math Operations/Gain', 'Kv', 'Gain', '[2 3]');
  A('simulink/Math Operations/Gain', 'Km', 'Gain', '[1 2; 3 4]', 'Multiplication', 'Matrix(u*K)');
  A('simulink/Math Operations/Gain', 'Ks', 'Gain', '[2 -1]');
  A('simulink/Continuous/Integrator', 'Int', 'InitialCondition', '[0 0]');
  for k = 1:7, A('simulink/Sinks/Out1', sprintf ('Out%d', k)); endfor
  switches = {'Sw', 'SwB', 'SwN'};
  for k = 1:3
    L('One/1', [switches{k} '/1']); L('U2/1', [switches{k} '/2']); L('Three/1', [switches{k} '/3']);
    L([switches{k} '/1'], sprintf ('Out%d/1', k));
  endfor
  L('U/1', 'Kv/1'); L('Kv/1', 'Out4/1');
  L('U/1', 'Km/1'); L('Km/1', 'Out5/1');
  L('Sine/1', 'Ks/1'); L('Ks/1', 'Int/1'); L('Int/1', 'Out6/1');
  L('One/1', 'SwS/1'); L('Sine/1', 'SwS/2'); L('Three/1', 'SwS/3'); L('SwS/1', 'Out7/1');
  ob_simulink ('set_param', name, 'StopTime', '2', 'Solver', 'ode4', 'FixedStep', '0.05');
  [model, config] = ob_simulink ('get_model', name);
  source = [name '.c']; expected_file = [name '.expected.csv'];
  info = ob_codegen (model, fullfile (directory, source), config);
  % Reference traces in the layout test_ob_codegen writes: time, then every
  % flattened block's value.
  result = ob_run (model, ob_time_grid (config(1), config(2), config(3)));
  expected = result.t;
  for block = 1:numel (result.compiled_model.blocks)
    count = prod (info.shapes{block});
    if (count == 0), continue; endif
    traces = zeros (numel (result.t), count);
    for sample = 1:numel (result.t)
      value = result.flat_values{sample, block};
      assert (isnumeric (value) && isreal (value) && isequal (size (value), info.shapes{block}));
      traces(sample, :) = value(:)';
    endfor
    assert (all (isfinite (traces(:))));
    expected = [expected traces];
  endfor
  dlmwrite (fullfile (directory, expected_file), expected, 'precision', '%.17g');
  entry = struct ('name', name, 'source', source, 'standalone', true, 'expected', expected_file);
endfunction
