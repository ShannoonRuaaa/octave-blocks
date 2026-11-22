function reference_ob_matlab_numeric (file)
  % Generate native MATLAB results, independently of Octave or generated C.
  if exist ('OCTAVE_VERSION','builtin')
    error ('reference_ob_matlab_numeric: run this producer in MATLAB');
  end
  unary = {'sin','cos','tan','asin','acos','atan','sinh','cosh','tanh','exp', ...
           'log','log10','sqrt','abs','floor','ceil','round','sign','uminus'};
  binary = {'power','atan2','hypot','plus','times','minus','rdivide'};
  a = [0.1 0.2;0.3 0.4]; b = [1.5;2.5];
  records = struct ('name',{},'arity',{},'shape',{},'values',{});
  for name = [unary binary]
    arity = 1 + any(strcmp(name{1},binary));
    if arity == 1, value = feval(name{1},a); else, value = feval(name{1},a,b); end
    records(end+1) = struct ('name',name{1},'arity',arity,'shape',size(value),'values',value(:)');
  end
  evidence = struct ('matlab_version',version,'producer','reference_ob_matlab_numeric.m', ...
      'input_a',a(:)','input_a_shape',size(a),'input_b',b(:)','input_b_shape',size(b), ...
      'records',records,'atan2_negative_zero',atan2(-0.0,-1.0), ...
      'round_ties',round([-1.5 -0.5 0.5 1.5]));
  inputs = {[3 8 -1;3 2 -1],[-3 -3 -1 -1],[-5;7;7],-0.0,[0 -0.0;-0.0 0]};
  multi = struct ('name',{},'input_shape',{},'input_values',{},'input_negative_zero',{}, ...
      'first_shape',{},'first_values',{},'first_negative_zero',{}, ...
      'second_shape',{},'second_values',{});
  for name = {'size','max','min'}
    for sample = 1:numel(inputs)
      value = inputs{sample};
      [first,second] = feval(name{1},value);
      negative_zero = first == 0 & (1./first) < 0;
      multi(end+1) = struct ('name',name{1},'input_shape',size(value),'input_values',value(:)', ...
          'input_negative_zero',((value(:)' == 0) & (1./value(:)') < 0), ...
          'first_shape',size(first),'first_values',first(:)','first_negative_zero',negative_zero(:)', ...
          'second_shape',size(second),'second_values',second(:)');
    end
  end
  evidence.multi_records = multi;
  fid = fopen(file,'w');
  if fid < 0, error ('Cannot write numeric reference'); end
  cleanup = onCleanup (@() fclose(fid));
  fprintf(fid,'%s\n',jsonencode(evidence));
  fprintf('Recorded %d single-output and %d two-output MATLAB cases, signed zero, and rounding ties.\n',numel(records),numel(multi));
end
