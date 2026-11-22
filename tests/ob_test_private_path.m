function cleanup = ob_test_private_path ()
  % Put src/private on the path for a test that calls private functions
  % directly (Octave reaches private/ only from functions in src/).  Keep
  % the returned onCleanup object for the duration of the test: deleting it
  % removes the folder from the path again, unless it was already there.
  folder = fullfile (fileparts (fileparts (mfilename ('fullpath'))), 'src', 'private');
  entries = strrep (strsplit (path (), pathsep ()), '\', '/');
  if (any (strcmpi (entries, strrep (folder, '\', '/'))))
    cleanup = onCleanup (@() []);
  else
    addpath (folder);
    cleanup = onCleanup (@() rmpath (folder));
  endif
endfunction
