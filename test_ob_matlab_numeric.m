function test_ob_matlab_numeric ()
  file = fullfile (fileparts(mfilename('fullpath')), 'matlab-numeric-reference.json');
  reference = jsondecode (fileread (file));
  assert (! isempty (strfind(reference.matlab_version, 'R2026b')));
  a = reshape (reference.input_a, reference.input_a_shape');
  b = reshape (reference.input_b, reference.input_b_shape');
  unary = {'sin','cos','tan','asin','acos','atan','sinh','cosh','tanh','exp', ...
           'log','log10','sqrt','abs','floor','ceil','round','sign','uminus'};
  binary = {'power','atan2','hypot','plus','times','minus','rdivide'};
  assert (numel(reference.records) == numel(unary) + numel(binary));
  observed = {};
  for k = 1:numel(reference.records)
    record = reference.records(k);
    assert (any(strcmp(record.name,[unary binary])) && ! any(strcmp(record.name,observed)));
    observed{end+1} = record.name;
    model = ob_oscillator ();
    model.blocks(1).type = model.blocks(2).type = 'Constant';
    model.blocks(1).value = a; model.blocks(2).value = b;
    model.blocks(3).type = 'Function'; model.blocks(3).value = []; model.blocks(3).name = record.name;
    model.edges = [1 1 3 1;3 1 4 1];
    if (record.arity == 2), model.edges(end+1,:) = [2 1 3 2]; endif
    expected = reshape (record.values, record.shape');
    result = ob_run (model,0);
    actual = result.values{1,4};
    assert (isequal(size(actual),size(expected)));
    assert (max(abs(actual(:)-expected(:))./max(1,abs(expected(:)))) < 1e-13);
  endfor
  assert (atan2(-0.0,-1.0) == reference.atan2_negative_zero);
  model = ob_example ();
  model.blocks(1).type = 'Constant'; model.blocks(1).value = -0.0;
  model.blocks(2).type = 'Saturation'; model.blocks(2).value = [0 1];
  result = ob_run (model,0);
  assert (atan2(result.values{1,3},-1) == reference.atan2_negative_zero);
  assert (isequal (round([-1.5 -0.5 0.5 1.5]), reference.round_ties'));
  assert (numel(reference.multi_records) == 15);
  for record = reference.multi_records'
    assert (any(strcmp(record.name,{'size','max','min'})));
    model = ob_example ();
    model.blocks(1).type = 'Constant';
    model.blocks(1).value = reshape(record.input_values,record.input_shape');
    model.blocks(1).value(logical(record.input_negative_zero(:))) = -0.0;
    model.blocks(2).type = 'Function'; model.blocks(2).name = record.name; model.blocks(2).outputs = 2;
    model.blocks(4) = model.blocks(3);
    model.edges = [1 1 2 1;2 1 3 1;2 2 4 1];
    result = ob_run (model,0);
    first = result.values{1,3}; second = result.values{1,4};
    assert (isequal(first,reshape(record.first_values,record.first_shape')));
    assert (isequal(second,reshape(record.second_values,record.second_shape')));
    negative_zero = first == 0 & (1./first) < 0;
    % JSON numerical values lose the sign of zero; the producer records it separately.
    assert (isequal(negative_zero(:),logical(record.first_negative_zero(:))));
  endfor
  disp ('Octave Blocks MATLAB numeric reference tests passed');
endfunction
