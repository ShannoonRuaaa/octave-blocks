function source = test_ob_c_number_format (directory)
  test_path_cleanup = ob_test_setup ();
  % Compare the old scalar formatter and independently check C binary values.
  if (! exist (directory, 'dir')), mkdir (directory); endif
  boundary = [0 -0.0 1 -1 2 -2 realmax realmin realmin*eps ...
              1e20 2^63-1024 2^63 2^63+2048 2^64 1e-20];
  saved = rng ();
  unwind_protect
    rng (8917);
    words = bitor (bitshift (uint64 (randi ([0 2^32-1], 1, 4096)), 32), ...
                   uint64 (randi ([0 2^32-1], 1, 4096)));
    random = typecast (words, 'double');
    random = random(isfinite (random));
  unwind_protect_cleanup
    rng (saved);
  end_unwind_protect
  values = [boundary -boundary random];
  expected = cell (1, numel (values));
  for index = 1:numel (values)
    token = sprintf ('%.17g', values(index));
    if (isempty (strfind (token, '.')) && isempty (strfind (lower (token), 'e')))
      token = [token '.0'];
    endif
    expected{index} = token;
  endfor
  reference = strjoin (expected, ',');
  assert (strcmp (ob_c_number_list (values), reference));
  assert (strcmp (ob_c_number_list (values'), reference));
  assert (strcmp (ob_c_number_list ([1 2; 3 4]), '1.0,3.0,2.0,4.0'));
  assert (strcmp (ob_c_number_list ([]), ''));
  assert (strcmp (ob_c_number_list (zeros (0, 3)), ''));
  assert (strcmp (ob_c_number_list (-0.0), '-0.0'));
  assert (strcmp (ob_c_number_list (single (1.25)), '1.25'));
  % Shape cells store dimension vectors, not the arrays of those dimensions.
  shapes = {[2 3], [4 1]};
  assert (isequal (cellfun (@prod, shapes), [6 4]));
  assert (isequal (cellfun ('prodofsize', shapes), [2 2]));
  assert (isequal (cellfun ('size', shapes, 1), [1 1]));
  assert (isequal (cellfun ('size', shapes, 2), [2 2]));
  hex = num2hex (values);
  bits = cell (1, numel (values));
  for index = 1:numel (values)
    bits{index} = ['UINT64_C(0x' hex(index,:) ')'];
  endfor
  source = fullfile (directory, 'c-number-format.c');
  lines = {'#include <stdint.h>', '#include <stdio.h>', '#include <string.h>', ...
    ['static const double values[]={' reference '};'], ...
    ['static const uint64_t bits[]={' strjoin(bits,',') '};'], ...
    ['static const double actual[]={' ob_c_number_list(values) '};'], ...
    'int main(void){', ...
    '  if(sizeof(double)!=sizeof(uint64_t))return 1;', ...
    '  for(size_t i=0;i<sizeof(actual)/sizeof(actual[0]);++i){', ...
    '    uint64_t word;memcpy(&word,&actual[i],sizeof(word));', ...
    '    if(word!=bits[i]||memcmp(&actual[i],&values[i],sizeof(word))){fprintf(stderr,"value %zu differs\n",i);return 2;}', ...
    '  }', ...
    ['  if((' ob_c_number_list(1) ')/(' ob_c_number_list(2) ')!=0.5)return 3;'], ...
    '  puts("C99 numeric constants round-trip exactly");return 0;', '}'};
  fid = fopen (source, 'w');
  assert (fid >= 0);
  unwind_protect
    fprintf (fid, '%s\n', lines{:});
  unwind_protect_cleanup
    fclose (fid);
  end_unwind_protect
  fprintf ('Numeric formatting: %d finite doubles match scalar reference\n', numel(values));
endfunction
