function file = ob_test_reference (name)
  % Location of a recorded reference file in the project's reference/
  % folder, e.g. ob_test_reference ('matlab-dde-reference.json').  With no
  % name, the reference/ folder itself (the default directory of the tests
  % that take one).
  file = fullfile (fileparts (fileparts (mfilename ('fullpath'))), 'reference');
  if (nargin > 0)
    file = fullfile (file, name);
  endif
endfunction
