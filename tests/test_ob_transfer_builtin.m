function test_ob_transfer_builtin ()
  test_path_cleanup = ob_test_setup ();
  % Independent matrices pin the public derivative-state ordering, including
  % a nonsymmetric coefficient row and a nonzero initial state.
  child = ob_transfer_function ([0 4 10 14 22]', [0 2 6 10 14]', [2;-3;5]);
  assert (isequal (named_value(child,'A'),[0 1 0;0 0 1;-7 -5 -3]));
  assert (isequal (named_value(child,'B'),[0;0;1]));
  assert (isequal (named_value(child,'C'),[-3 -3 -1]));
  assert (isequal (named_value(child,'D'),2));
  assert (isequal (named_value(child,'x'),[2;-3;5]));
  child = ob_transfer_function (1,[2 4]);
  assert (named_value(child,'A') == -2 && named_value(child,'B') == 1);
  assert (named_value(child,'C') == .5);
  constant = ob_transfer_function ([0 4],[0 2]);
  assert (named_value(constant,'D') == 2);
  zero = ob_transfer_function ([0 0],[1 3 2],[2;3]);
  assert (isequal (named_value(zero,'A'),[0 1;-2 -3]));
  assert (isequal (named_value(zero,'x'),[2;3]));
  % Shared pole/zero factors must not cancel or change the meaning of x0.
  child = ob_transfer_function ([1 1],[1 3 2],[2;3]);
  assert (isequal (named_value(child,'A'),[0 1;-2 -3]));
  model.blocks = struct ('type',{'Constant','Subsystem','Scope'}, ...
    'value',{0,child,[]},'name',{'u','System','y'}, ...
    'x',{.1,.5,.9},'y',{.5,.5,.5});
  model.edges = [1 1 2 1;2 1 3 1];
  times = 0:.025:.5;
  result = ob_run (model,times,struct('solver','ode45','reltol',1e-10,'abstol',1e-12));
  % z=7*exp(-t)-5*exp(-2t), y=z+z'=5*exp(-2t).
  assert (max (abs (ob_scope_data(result,3)' - 5*exp(-2*times))) < 1e-8);
  assert_error (@() ob_transfer_function(1,[0 0]), 'zero polynomial');
  assert_error (@() ob_transfer_function([1 2 3],[1 2]), 'proper');
  assert_error (@() ob_transfer_function(1,[1 2 3],[1 2]), 'column');
  assert_error (@() ob_transfer_function(1,[realmin() realmax()]), 'normalized');
  assert_error (@() ob_transfer_function(1,2,1), 'column');
  disp ('Octave Blocks builtin transfer regression tests passed');
endfunction

function value = named_value (model, name)
  index = find (strcmp ({model.blocks.name}, name));
  assert (isscalar (index)); value = model.blocks(index).value;
endfunction

function assert_error (callback, fragment)
  caught = false;
  try callback(); catch err, caught = ! isempty (strfind (err.message, fragment)); end_try_catch
  assert (caught);
endfunction
