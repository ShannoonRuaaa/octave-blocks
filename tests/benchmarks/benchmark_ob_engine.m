function report = benchmark_ob_engine (sources, varargin)
  % Time the shared engine benchmark set (ob_benchmark_models) for one or
  % more source trees and fingerprint every result.
  %
  %   report = benchmark_ob_engine (SOURCE)
  %   report = benchmark_ob_engine ({BASELINE, CANDIDATE}, 'rounds', 3)
  %
  % One source: optional warm-up, then 'repetitions' timed ob_run calls per
  % case; the median wall time is reported.  Several sources: each round runs
  % the versions in A/B/B/A order (B/A/A/B in even rounds), clearing functions
  % and rebuilding the path before every run, so a loaded machine affects
  % both versions alike.  Each run is preceded by a short warm-up on the
  % first output times of the same case.
  %
  % Options (name/value pairs):
  %   'cases'        cellstr of case names (default: all nine)
  %   'repetitions'  timed runs per case for one source (default 3)
  %   'rounds'       interleaved rounds for several sources (default 1)
  %   'warmup'       'short' (default), 'full' or 'none'
  %   'output'       JSON file receiving the report (default: none)
  %   'ignore_fields' struct field names left out of the fingerprint walk
  %                  (default {'runtime_info', 'options'}; see below)
  %
  % The fingerprint of a run holds every numeric and logical value of
  % result.flat_values (column-major per signal, in output-time order),
  % found by a depth-first walk through struct and cell values such as
  % conditional state snapshots, plus the output times, the integration-step
  % count and the event times.  A signature of the walked structure (classes,
  % sizes, struct field names and char values) is hashed with the values.
  % Leaves of any other class (e.g. function handles) are counted in
  % unhashed_leaves.  Struct fields named in 'ignore_fields' are not walked:
  % by default the prepared runtime cache (runtime_info, rebuilt at every
  % preparation) and normalized solver settings (options) that conditional
  % snapshots carry inside their child contexts.  They are configuration, not
  % results, and differ between versions that add cache or option fields.
  % report.cases(k).identical says whether all versions
  % produced bit-identical fingerprints and signatures;
  % max_relative_difference quantifies any gap in the numeric values.
  % Run from a fresh Octave process; the caller's path is restored on exit.
  if (ischar (sources)), sources = {sources}; endif
  if (! iscellstr (sources) || isempty (sources))
    error ('benchmark_ob_engine: SOURCES must be a directory or a cell array of directories');
  endif
  settings = struct ('cases', {{}}, 'repetitions', 3, 'rounds', 1, ...
                     'warmup', 'short', 'output', '', ...
                     'ignore_fields', {{'runtime_info', 'options'}});
  if (mod (numel (varargin), 2))
    error ('benchmark_ob_engine: options must be name/value pairs');
  endif
  for k = 1:2:numel (varargin)
    name = lower (varargin{k});
    if (! isfield (settings, name))
      error ('benchmark_ob_engine: unknown option ''%s''', varargin{k});
    endif
    settings.(name) = varargin{k+1};
  endfor
  if (! isempty (settings.output))
    % Fail before a long run, not after it, if the report cannot be written.
    % Append mode leaves an existing report intact until the new one is
    % complete; a probe file created here is removed again.
    existed = exist (settings.output, 'file') == 2;
    fid = fopen (settings.output, 'a');
    if (fid < 0), error ('benchmark_ob_engine: cannot write %s', settings.output); endif
    fclose (fid);
    if (! existed), delete (settings.output); endif
  endif
  sources = cellfun (@canonical_directory, sources, 'UniformOutput', false);
  bench_dir = fileparts (mfilename ('fullpath'));
  initial_path = path ();
  restore = onCleanup (@() path (initial_path));

  select_source (sources{1}, sources, initial_path, bench_dir);
  all_cases = ob_benchmark_models ();
  names = {all_cases.name};
  if (isempty (settings.cases)), settings.cases = names; endif
  if (ischar (settings.cases)), settings.cases = {settings.cases}; endif
  missing = setdiff (settings.cases, names);
  if (! isempty (missing))
    error ('benchmark_ob_engine: unknown case ''%s''', missing{1});
  endif

  samples = struct ('case', {}, 'version', {}, 'round', {}, 'wall', {}, 'cpu', {}, ...
                    'steps', {}, 'events', {}, 'md5', {});
  report.sources = sources;
  report.ignore_fields = settings.ignore_fields;
  report.cases = struct ('name', {}, 'median_wall', {}, 'ratio', {}, 'steps', {}, ...
                         'events', {}, 'identical', {}, 'max_relative_difference', {}, ...
                         'hashed_values', {}, 'unhashed_leaves', {}, 'md5', {});
  for name = settings.cases
    fingerprints = cell (1, numel (sources));
    if (numel (sources) == 1)
      schedule = repmat ([1 1], settings.repetitions, 1);
      schedule(:, 2) = (1:settings.repetitions)';
    else
      schedule = zeros (0, 2);
      for round = 1:settings.rounds
        if (mod (round, 2)), order = [1 2 2 1]; else order = [2 1 1 2]; endif
        if (numel (sources) > 2), order = [1:numel(sources) numel(sources):-1:1]; endif
        schedule = [schedule; order(:) repmat(round, numel (order), 1)];
      endfor
    endif
    warmed = false (1, numel (sources));
    for slot = 1:rows (schedule)
      version = schedule(slot, 1);
      select_source (sources{version}, sources, initial_path, bench_dir);
      cases = ob_benchmark_models ();
      entry = cases(strcmp ({cases.name}, name{1}));
      % Several sources reload functions before every run, so each run
      % warms up; one source warms up once.
      if (! strcmp (settings.warmup, 'none') && (numel (sources) > 1 || ! warmed(version)))
        warm_t = entry.t;
        if (strcmp (settings.warmup, 'short'))
          warm_t = warm_t(1:min (numel (warm_t), max (3, ceil (numel (warm_t) / 20))));
        endif
        ob_run (entry.model, warm_t, entry.options);
        warmed(version) = true;
      endif
      cpu = cputime (); clock = tic ();
      result = ob_run (entry.model, entry.t, entry.options);
      wall = toc (clock); cpu = cputime () - cpu;
      print = fingerprint (result, settings.ignore_fields);
      if (isempty (fingerprints{version})), fingerprints{version} = print; endif
      if (! isequal (print.values, fingerprints{version}.values) ...
          || ! strcmp (print.signature, fingerprints{version}.signature))
        warning ('benchmark_ob_engine: %s changed between runs of version %d', name{1}, version);
      endif
      samples(end+1) = struct ('case', name{1}, 'version', version, 'round', schedule(slot, 2), ...
                               'wall', wall, 'cpu', cpu, 'steps', print.steps, ...
                               'events', print.events, 'md5', print.md5);
      printf ('%-18s version %d round %d: %.4f s (steps %d)\n', name{1}, version, ...
              schedule(slot, 2), wall, print.steps);
      fflush (stdout);
    endfor
    mine = samples(strcmp ({samples.case}, name{1}));
    medians = zeros (1, numel (sources));
    for version = 1:numel (sources)
      medians(version) = median ([mine([mine.version] == version).wall]);
    endfor
    identical = true; difference = 0;
    for version = 2:numel (sources)
      [same, gap] = compare_prints (fingerprints{1}, fingerprints{version});
      identical = identical && same; difference = max (difference, gap);
    endfor
    hashes = cellfun (@(p) p.md5, fingerprints, 'UniformOutput', false);
    report.cases(end+1) = struct ('name', name{1}, 'median_wall', medians, ...
        'ratio', medians(1) ./ medians, 'steps', fingerprints{1}.steps, ...
        'events', fingerprints{1}.events, 'identical', identical, ...
        'max_relative_difference', difference, ...
        'hashed_values', numel (fingerprints{1}.values), ...
        'unhashed_leaves', fingerprints{1}.unhashed, ...
        'md5', {hashes});
    if (numel (sources) > 1)
      printf ('%-18s medians %s  speedup %.3f  identical %d  max rel diff %.3g\n', name{1}, ...
              sprintf ('%.4f ', medians), medians(1) / medians(end), identical, difference);
    endif
  endfor
  report.samples = samples;
  ratios = reshape ([report.cases.ratio], numel (sources), []);
  report.geometric_mean_speedup = exp (mean (log (ratios), 2))';
  if (numel (sources) > 1)
    printf ('geometric-mean speedup (version 1 / version k): %s\n', ...
            sprintf ('%.3f ', report.geometric_mean_speedup));
  endif
  if (! isempty (settings.output))
    fid = fopen (settings.output, 'w');
    if (fid < 0), error ('benchmark_ob_engine: cannot write %s', settings.output); endif
    fwrite (fid, jsonencode (report), 'char');
    fclose (fid);
  endif
endfunction

function directory = canonical_directory (directory)
  if (! exist (directory, 'dir'))
    error ('benchmark_ob_engine: source directory %s does not exist', directory);
  endif
  directory = strrep (make_absolute_filename (directory), '\', '/');
  if (directory(end) == '/'), directory(end) = []; endif
endfunction

function select_source (source, sources, initial_path, bench_dir)
  % Clear compiled functions (and their persistent state) and put exactly
  % one source tree, plus this benchmark folder, at the front of the path.
  % A package tree (with ob_setup.m) keeps its library in inst/ and its
  % models in inst/examples/ and is set up by its own ob_setup; a flat tree
  % (before the reorganization) is the library folder itself.
  clear functions;
  path (initial_path);
  state = warning ('off', 'all');
  for other = sources
    for sub = {'', '/tests/benchmarks', '/inst', '/inst/examples', '/inst/simulink', '/tests', '/tools'}
      rmpath ([other{1} sub{1}]);
    endfor
  endfor
  warning (state);
  addpath (source);
  library = source;
  if (exist ([source '/ob_setup.m'], 'file'))
    ob_setup ();
    library = [source '/inst'];
  endif
  addpath (bench_dir);
  found = strrep (which ('ob_run'), '\', '/');
  if (! strcmpi (found, [library '/ob_run.m']))
    error ('benchmark_ob_engine: ob_run resolved to %s instead of %s', found, library);
  endif
endfunction

function print = fingerprint (result, ignore)
  % flat_values is fingerprinted column by column (signal by signal), each
  % in output-time order, as the cell's column-major linear order gives.
  % Each cell is walked on its own, so the cost stays linear in the number
  % of cells (accumulating across all cells would copy ever larger arrays).
  values = result.flat_values;
  parts = cell (1, numel (values) + 2);
  signature = cell (1, numel (values));
  unhashed = 0;
  parts{1} = result.t(:);
  for item = 1:numel (values)
    [parts{item+1}, signature{item}, skipped] = walk (values{item}, ignore);
    unhashed += skipped;
  endfor
  events = result.events;
  event_times = zeros (0, 1);
  if (! isempty (events)), event_times = [events.time]'; endif
  parts{end} = event_times;
  print.values = vertcat (parts{:});
  print.steps = result.integration_steps;
  print.events = numel (events);
  print.unhashed = unhashed;
  print.values(end+1:end+2) = [print.steps; print.events];
  print.signature = [signature{:}];
  print.md5 = hash ('md5', [char(typecast (print.values', 'uint8')) print.signature]);
endfunction

function [values, signature, unhashed] = walk (value, ignore)
  % Depth-first numeric/logical leaves (one double column) and a signature
  % of the walked structure, through struct arrays and cells in linear order.
  shape = sprintf ('%dx', size (value));
  unhashed = 0;
  if (isnumeric (value) || islogical (value))
    kind = class (value);
    if (issparse (value)), kind = ['sparse ' kind]; endif
    if (iscomplex (value))
      kind = ['complex ' kind];
      values = full ([real(double (value(:))); imag(double (value(:)))]);
    else
      values = full (double (value(:)));
    endif
    signature = [kind shape ';'];
  elseif (ischar (value))
    values = zeros (0, 1);
    signature = ['char' shape ':' value(:)' ';'];
  elseif (iscell (value) || isstruct (value))
    if (iscell (value))
      children = value(:)';
      signature = ['cell' shape '{'];
    else
      names = fieldnames (value);
      keep = ! ismember (names, ignore);
      names = names(keep);
      children = struct2cell (value(:));
      children = children(keep, :);
      children = children(:)';
      signature = ['struct' shape '(' strjoin(names', ',') '){'];
    endif
    parts = cell (1, numel (children));
    signatures = cell (1, numel (children));
    for item = 1:numel (children)
      [parts{item}, signatures{item}, skipped] = walk (children{item}, ignore);
      unhashed += skipped;
    endfor
    values = vertcat (zeros (0, 1), parts{:});
    signature = [signature signatures{:} '}'];
  else
    values = zeros (0, 1);
    signature = [class(value) shape ';'];
    unhashed = 1;
  endif
endfunction

function [same, gap] = compare_prints (a, b)
  same = isequal (a.values, b.values) && strcmp (a.signature, b.signature) ...
         && a.unhashed == b.unhashed;
  gap = Inf;
  if (numel (a.values) == numel (b.values))
    scale = max (abs (a.values), realmin ());
    difference = abs (a.values - b.values) ./ scale;
    difference(a.values == b.values) = 0;
    gap = max ([0; difference]);
  endif
endfunction
