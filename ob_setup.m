function root = ob_setup (varargin)
  % Put Octave Blocks on the Octave path and return the project folder.
  %   ob_setup ()             adds src and examples
  %   ob_setup ('simulink')   also adds the Simulink-named command wrappers
  %                           (opt-in: they shadow names such as sim and
  %                           get_param)
  %   ob_setup ('tests')      also adds tests, benchmarks and tools
  %   ob_setup ('all')        adds every folder above
  %   ob_setup ('remove')     removes the folders ob_setup added
  % Options can be combined, e.g. ob_setup ('simulink', 'tests').  Only
  % folders that are not already on the path are added, so repeated calls
  % leave the path unchanged.  src/private is never added: its functions are
  % reached through src.  If ob_setup's record of what it added was cleared
  % (clear functions), 'remove' removes every project folder on the path.
  persistent added = {};
  root = fileparts (mfilename ('fullpath'));
  groups = struct ('simulink', false, 'tests', false, 'remove', false);
  for k = 1:numel (varargin)
    option = varargin{k};
    if (! ischar (option) || ! isrow (option))
      error ('ob_setup: options must be strings');
    endif
    switch (lower (option))
      case 'simulink'
        groups.simulink = true;
      case 'tests'
        groups.tests = true;
      case 'all'
        groups.simulink = groups.tests = true;
      case 'remove'
        groups.remove = true;
      otherwise
        error ('ob_setup: unknown option ''%s'' (use simulink, tests, all or remove)', option);
    endswitch
  endfor
  every = cellfun (@(name) fullfile (root, name), ...
                   {'src', 'examples', 'simulink', 'tests', 'benchmarks', 'tools'}, ...
                   'UniformOutput', false);
  if (groups.remove)
    if (isempty (added))
      folders = every;
    else
      folders = added;
    endif
    for k = 1:numel (folders)
      if (on_path (folders{k}))
        rmpath (folders{k});
      endif
    endfor
    added = {};
    return;
  endif
  names = {'src', 'examples'};
  if (groups.tests)
    names = [names, {'tests', 'benchmarks', 'tools'}];
  endif
  if (groups.simulink)
    names{end+1} = 'simulink';
  endif
  % addpath puts each folder first, so add in reverse to keep src in front
  % of the optional folders (the Simulink wrappers end up first of all).
  for k = numel (names):-1:1
    folder = fullfile (root, names{k});
    if (! on_path (folder))
      addpath (folder);
      added{end+1} = folder;
    endif
  endfor
  if (groups.simulink)
    folder = fullfile (root, 'simulink');
    entries = strsplit (path (), pathsep ());
    if (! same_folder (entries{1}, folder))
      % The wrappers must win over same-named functions on the path.
      rmpath (folder);
      addpath (folder);
    endif
  endif
endfunction

function yes = on_path (folder)
  yes = any (same_folder (strsplit (path (), pathsep ()), folder));
endfunction

function same = same_folder (a, b)
  a = strrep (a, '\', '/');
  b = strrep (b, '\', '/');
  if (ispc ())
    same = strcmpi (a, b);
  else
    same = strcmp (a, b);
  endif
endfunction

%!test
%! saved = path ();
%! normal = @(p) strrep (p, '\', '/');
%! on = @(d) any (strcmpi (normal (strsplit (path (), pathsep ())), normal (d)));
%! unwind_protect
%!   root = ob_setup ('remove');
%!   assert (isfolder (fullfile (root, 'src', 'private')));
%!   clean = path ();
%!   for name = {'src', 'examples', 'simulink', 'tests', 'benchmarks', 'tools'}
%!     assert (! on (fullfile (root, name{1})));
%!   endfor
%!   assert (strcmp (ob_setup (), root));
%!   assert (on (fullfile (root, 'src')) && on (fullfile (root, 'examples')));
%!   assert (! on (fullfile (root, 'src', 'private')));
%!   assert (! on (fullfile (root, 'simulink')) && ! on (fullfile (root, 'tests')));
%!   assert (strcmpi (normal (which ('ob_run')), normal (fullfile (root, 'src', 'ob_run.m'))));
%!   assert (strcmpi (normal (which ('ob_oscillator')), ...
%!                    normal (fullfile (root, 'examples', 'ob_oscillator.m'))));
%!   once = path ();
%!   ob_setup ();
%!   assert (strcmp (path (), once));
%!   ob_setup ('tests');
%!   for name = {'tests', 'benchmarks', 'tools'}
%!     assert (on (fullfile (root, name{1})));
%!   endfor
%!   assert (! on (fullfile (root, 'simulink')));
%!   twice = path ();
%!   ob_setup ('tests');
%!   assert (strcmp (path (), twice));
%!   ob_setup ('simulink');
%!   assert (on (fullfile (root, 'simulink')));
%!   assert (! on (fullfile (root, 'src', 'private')));
%!   ob_setup ('remove');
%!   assert (strcmp (path (), clean));
%!   ob_setup ('all');
%!   for name = {'src', 'examples', 'simulink', 'tests', 'benchmarks', 'tools'}
%!     assert (on (fullfile (root, name{1})));
%!   endfor
%!   ob_setup ('remove');
%!   assert (strcmp (path (), clean));
%! unwind_protect_cleanup
%!   path (saved);
%! end_unwind_protect
%!error <unknown option 'bogus'> ob_setup ('bogus')
%!error <options must be strings> ob_setup (1)
