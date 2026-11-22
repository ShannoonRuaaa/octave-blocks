function test_ob_builtin_controls ()
  % Selection must copy values, including signed zeros, rather than combine
  % the two branches arithmetically (0*realmax can conceal such regressions).
  high = [-0.0 realmax(); 7 8]; low = [9 -0.0; -realmax() 10];
  block = struct ('type', 'Switch', 'value', 0);
  output = ob_control_output (block, {high, [0 -1; -1 0], low}, 17);
  assert (isequal (output, [-0.0 -0.0; -realmax() 8]));
  assert (all (signbit (output(1,:))));
  assert (isequal (ob_control_output(block,{high,1,low},17), high));
  assert (isequal (ob_control_output(block,{high,-1,low},17), low));
  assert (isequal (ob_control_output(block,{high,ones(2),low},17,[0 1;1 0]), ...
                   [9 realmax();7 10]));
  assert (isequal (ob_control_output(block,{high,1,low},17,0), low));
  output = ob_control_output (block, {single(zeros(2)), single(ones(2)), sparse(ones(2))}, 17);
  assert (isa (output, 'double') && ! issparse (output));
  assert_error (@() ob_control_output(block,{ones(2),0,1},17), 'identical shapes');
  assert_error (@() ob_control_output(block,{ones(2),[0 1],ones(2)},17), 'scalar or match');
  assert_error (@() ob_control_output(block,{1,1,Inf},17), 'finite real numeric');
  assert_error (@() ob_control_output(block,{1,0},17), 'needs 3 inputs');

  block.type = 'Saturation'; block.value = [0 1];
  assert (signbit (ob_control_output(block,{-0.0},17)));
  assert (isequal (ob_control_output(block,{[-realmax() realmax()]},17), [0 1]));
  assert (isequal (ob_control_output(block,{[-2 3;4 -5]},17,[-1 0;1 -1]),[0 3;1 0]));
  block.type = 'Dead Zone'; block.value = [-realmax() 0];
  % The unused subtraction input-lower overflows at the second sample; only
  % the selected side is needed and the correct output stays finite.
  assert (isequal (ob_control_output(block,{[-realmax() realmax()]},17),[0 realmax()]));
  block.value = [0 0];
  assert (signbit (ob_control_output(block,{-0.0},17,-1)));
  assert (! signbit (ob_control_output(block,{-0.0},17,0)));
  block.value = [-1 2];
  assert (isequal (ob_control_output(block,{[-3 4; 8 -9]},17,[-1 0;1 0]),[-2 0;6 0]));
  block.value = [-realmax() -realmax()];
  assert_error (@() ob_control_output(block,{realmax()},17), 'nonfinite output');
  disp ('Octave Blocks builtin control regression tests passed');
endfunction

function assert_error (callback, fragment)
  caught = false;
  try callback(); catch err, caught = ! isempty (strfind (err.message, fragment)); end_try_catch
  assert (caught);
endfunction
