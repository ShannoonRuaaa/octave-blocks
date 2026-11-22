function [result, info] = ob_accelerate (model, t, options = struct (), retries = 8)
  % Run a model as compiled C, like Simulink's Accelerator mode.
  %
  %   result = ob_accelerate (model, t, options)
  %   [result, info] = ob_accelerate (...)
  %
  % The model is exported with ob_codegen, a MEX gateway is appended, and
  % the source is compiled with mkoctfile --mex into a per-user cache
  % directory, keyed by a hash of the generated source, the gateway, the
  % compiler flags and the Octave version.  Later runs of the same model and
  % settings reuse the compiled file.  The C code advances through the
  % output times t exactly as ob_run does, and result has the same fields
  % and value shapes as an interpreted ob_run result.
  %
  % Covered: flat models with solver rk4 or ode45 (ob_codegen's flat path,
  % including Transport Delay and Limited Integrator), and rk4 models that
  % need the typed recursive exporter (conditional subsystems, multiple-
  % output Functions, zero_crossings=true).  Function blocks whose function
  % has no C mapping (user .m functions) are evaluated by Octave through an
  % ob_external_call hook in flat models.  Everything else (ode15s, ode45
  % with typed models, zero crossings or non-double tolerances, user
  % Functions in typed models, algebraic loops, ...) fails before
  % anything is compiled, with error identifier
  % octave_blocks:accelerate_unsupported; a missing compiler gives
  % octave_blocks:accelerate_unavailable.
  %
  % Transport Delay histories have a fixed compiled capacity
  % (ob_c_delay_capacity).  When a run fills one (OB_DELAY_OVERFLOW, e.g.
  % delayed discontinuities that keep multiplying through feedback), the
  % model is regenerated with doubled capacities and run again, up to
  % 'retries' times (internal argument, default 8) and the export size limit;
  % the enlarged build is remembered for later calls in the session.  If the
  % history still overflows, octave_blocks:accelerate_capacity is raised.
  % A user Function whose result changes class or shape during the run, or
  % has a NaN or Inf element (ob_run keeps those; the compiled model needs
  % finite signals), also raises octave_blocks:accelerate_unsupported.  ob_run
  % with accelerate='auto' falls back to interpretation on these three errors
  % (unsupported, unavailable, capacity).  An export remembered from an
  % earlier call is regenerated once when a user Function's output shape no
  % longer matches it (the function was edited), and the remembered exports
  % are keyed also by how each Function name resolves (a builtin shadowed by
  % a user file is then called in Octave).
  %
  % info reports mex (function name), source, cache, cache_hit, reused_export
  % (the export was reused from this session, skipping regeneration),
  % exporter ('flat' or 'typed'), external_functions (names evaluated by
  % Octave), generate_time (export and hashing), compile_time (mkoctfile, 0
  % when cached), run_time (the compiled simulation), assemble_time (result
  % struct), delay_capacity (history samples per Transport Delay) and
  % capacity_retries (regenerations after OB_DELAY_OVERFLOW in this call).
  %
  % The cache directory is $OB_ACCELERATOR_CACHE when set, otherwise
  % %LOCALAPPDATA%\octave-blocks\accelerator\<version>-<platform> on Windows
  % and $XDG_CACHE_HOME (or ~/.cache)/octave-blocks/accelerator/... elsewhere.
  % It is appended to the Octave path (after every other directory).
  if (nargin < 2)
    print_usage ();
  endif
  if (! isnumeric (retries) || ! isscalar (retries) || ! isreal (retries) ...
      || retries < 0 || retries != fix (retries))
    error ('ob_accelerate: retries must be a nonnegative integer');
  endif
  options = ob_solver_options (options);
  if (! isvector (t) || ! isnumeric (t) || ! isreal (t) || isempty (t) ...
      || any (! isfinite (t(:))) || any (diff (t(:)) <= 0))
    error ('ob_accelerate: t must be a nonempty, strictly increasing numeric vector');
  endif
  t = double (t(:)');
  % Exports already made in this session, keyed by everything the export
  % depends on (model data, solver options, output times, cache folder).
  % A hit skips regeneration and interpreted initialization; the compiled
  % file is still looked up in the cache.
  persistent memo
  if (isempty (memo)), memo = containers.Map (); endif
  cache = cache_directory ();
  info = struct ('mex', '', 'source', '', 'cache', cache, 'cache_hit', false, ...
                 'reused_export', false, 'exporter', '', 'external_functions', {{}}, ...
                 'generate_time', 0, 'compile_time', 0, ...
                 'run_time', 0, 'assemble_time', 0, 'delay_capacity', [], 'capacity_retries', 0);
  clock = tic ();
  fingerprint = export_fingerprint (model, options, t, cache);
  entry = [];
  if (isKey (memo, fingerprint))
    entry = memo(fingerprint);
    if (! exist (entry.binary, 'file')), entry = []; endif
  endif
  if (isempty (entry))
    plan = require_subset (model, options);
    entry = generate (model, options, t, cache, 1, plan, []);
  else
    info.reused_export = true;
  endif
  info.generate_time = toc (clock);

  while (true)
    info.mex = entry.name; info.source = entry.source; info.delay_capacity = entry.delay_capacity;
    info.exporter = entry.plan.exporter; info.external_functions = entry.plan.names;
    clock = tic ();
    cache_hit = exist (entry.binary, 'file') != 0;
    if (! cache_hit)
      compile (entry.source, entry.binary, entry.text, compile_flags ());
    endif
    on_path = strsplit (path (), pathsep ());
    if (! any (same_folder (on_path, cache)))
      addpath (cache, '-end');
    endif
    if (! cache_hit), rehash (); endif
    info.cache_hit = cache_hit;
    info.compile_time += toc (clock);

    clock = tic ();
    inputs = {t};
    % The private helper is reachable from here; the MEX file calls it
    % through this handle.
    if (! isempty (entry.plan.names)), inputs{2} = @ob_accelerate_call; endif
    try
      [values, ticks, status, failed, steps, message, call, event_log] = feval (entry.name, inputs{:});
    catch err
      if (!isempty(regexpi(err.message,'failed to load|invalid mex|access is denied|permission denied','once')))
        unavailable ('cannot load accelerator from %s: %s. Set OB_ACCELERATOR_CACHE to a writable local directory.', cache, err.message);
      endif
      rethrow (err);
    end_try_catch
    info.run_time = toc (clock);
    if (status == 9 && info.reused_export)
      % OB_EXTERNAL_SHAPE with a build from this session: it fixed the user
      % Functions' output shapes when it was generated, and a function may
      % have been edited since.  Regenerate once from a fresh interpreted
      % initialization (a function whose shape changes during the run fails
      % the same way again and is then unsupported).
      remove (memo, fingerprint);
      clock = tic ();
      entry = generate (model, options, t, cache, entry.capacity_scale, ...
                        require_subset (model, options), []);
      info.reused_export = false;
      info.generate_time += toc (clock);
      continue;
    endif
    if (status != 5 || info.capacity_retries >= retries)
      break;
    endif
    % OB_DELAY_OVERFLOW: the capacity heuristic does not bound delayed jumps
    % that multiply through feedback.  Double every history and try again.
    clock = tic ();
    statics = entry.statics;
    try
      entry = generate (model, options, t, cache, 2 * entry.capacity_scale, entry.plan, statics);
    catch err
      if (! strcmp (err.identifier, 'octave_blocks:accelerate_unsupported')), rethrow (err); endif
      capacity_error (t, failed, entry.delay_capacity, info.capacity_retries, ...
                      'cannot be enlarged further (export size limit)');
    end_try_catch
    info.capacity_retries += 1;
    info.generate_time += toc (clock);
  endwhile
  if (status == 5)
    capacity_error (t, failed, entry.delay_capacity, info.capacity_retries, '');
  elseif (status == 9 || status == 10)
    % OB_EXTERNAL_SHAPE, OB_EXTERNAL_NONFINITE: the compiled model cannot
    % hold the new value, but ob_run can; 'auto' falls back to it.
    unsupported ('Function ''%s'' %s (at t = %.17g, sample %d)', entry.plan.names{call}, ...
                 message, t(max (1, failed)), failed);
  elseif (status != 0)
    error ('octave_blocks:accelerate_runtime', ...
           'ob_accelerate: compiled model failed at t = %.17g (sample %d): %s', ...
           t(max (1, failed)), failed, status_text (status, entry, options, message, call));
  endif

  clock = tic ();
  if (isempty (entry.statics))
    entry.statics = statics_of (model, t, options);
  endif
  if (info.capacity_retries > 0 || ! isKey (memo, fingerprint))
    % Remember this (possibly enlarged) build for repeated calls.
    entry.text = '';
    if (memo.Count >= 64 && ! isKey (memo, fingerprint)), remove (memo, keys (memo){1}); endif
    memo(fingerprint) = entry;
  endif
  records = [];
  if (entry.events), records = ob_accelerate_events (event_log, entry.guards); endif
  result = assemble (model, t, options, entry.statics, entry.generated, values, ticks, steps, records);
  info.assemble_time = toc (clock);
endfunction

function statics = statics_of (model, t, options)
  % The static result fields (order, signal map, compiled model, ...) come
  % from an interpreted context that is only initialized, never stepped.
  % Its current values also give the output shapes of user Functions, and
  % its nested clocks (rates and paths only) the inner-clock schedule.
  runtime = ob_runtime_init (model, t(1), options);
  statics = struct ('order', runtime.order, 'signal_map', {runtime.signal_map}, ...
                    'block_paths', {runtime.block_paths}, 'model', {runtime.model}, ...
                    'rates', runtime.rates, 'events', {runtime.events}, ...
                    'inherited', runtime.inherited, 'explicit', runtime.explicit, ...
                    'current', {runtime.current}, 'nested_clocks', {runtime.nested_clocks});
endfunction

function entry = generate (model, options, t, cache, scale, plan, statics)
  % Generate the C source.  The CSV runner is omitted and the delay
  % histories are sized from t (times scale), so the source depends only on
  % the model, its settings and the (power-of-two) history capacity.
  if (! exist (cache, 'dir'))
    [ok, message] = mkdir (cache);
    if (! ok), unavailable ('cannot create the cache directory %s: %s', cache, message); endif
  endif
  build = struct ('record_times', t, 'standalone', false, 'count_steps', true, ...
                  'capacity_scale', scale);
  if (! isempty (plan.ids))
    % Output shapes of user Functions: their values at t(1) in an
    % initialized interpreted context (the C hook checks every later call).
    if (isempty (statics)), statics = statics_of (model, t, options); endif
    build.external_shapes = struct ('id', {}, 'shape', {});
    for id = plan.ids
      value = statics.current{id};
      if (! isa (value, 'double') || ! isreal (value) || issparse (value) || ndims (value) != 2)
        unsupported (['Function ''%s'' returned a %s value at t = %.17g; accelerated builds ' ...
                      'need real double matrices'], statics.model.blocks(id).name, ...
                     value_class (value), t(1));
      endif
      build.external_shapes(end+1) = struct ('id', id, 'shape', size (value));
    endfor
  endif
  scratch = [tempname(cache, 'ob_gen_') '.c'];
  unwind_protect
    try
      % The config only feeds the omitted CSV runner; any valid grid will do.
      span = max (1, abs (t(1)));
      generated = ob_codegen (model, scratch, [t(1) t(1)+span span], options, build);
    catch err
      unsupported ('%s', strrep (err.message, 'ob_codegen: ', ''));
    end_try_catch
    source = fileread (scratch);
  unwind_protect_cleanup
    if (exist (scratch, 'file')), unlink (scratch); endif
  end_unwind_protect
  events = false; guards = [];
  if (strcmp (plan.exporter, 'typed'))
    [source, events] = instrument_typed (source);
    if (events), guards = event_guards (model); endif
  endif
  gateway = ob_accelerate_gateway (! isempty (plan.ids), events);
  key = hash ('sha1', [source gateway compile_flags() OCTAVE_VERSION computer() 'ob-accelerate-v2']);
  name = ['ob_accel_' key(1:32)];
  entry = struct ('name', name, 'source', fullfile (cache, [name '.c']), ...
                  'binary', fullfile (cache, [name '.' mexext()]), 'text', [source gateway], ...
                  'delay_capacity', delay_capacity (source), ...
                  'delay_shortest', delay_shortest (source), 'capacity_scale', scale, ...
                  'generated', struct ('shapes', {generated.shapes}, 'offsets', generated.offsets, ...
                                       'sample_times', generated.sample_times), ...
                  'plan', plan, 'statics', statics, 'events', events, 'guards', guards);
endfunction

function [source, events] = instrument_typed (source)
  % Add what ob_run reports but the typed exporter (ob_emit_c_conditional,
  % ob_emit_c_event_root; see the cross-track proposal in CODEGEN.md) does
  % not keep: an integration step counter in the root context and, with
  % zero crossings, a log of the event records.  Every place that must be
  % instrumented is matched exactly; a source of any other shape is
  % rejected (unsupported) rather than miscounted.
  %
  % Steps: ob_run counts one step per RK4 segment that has continuous
  % states to integrate (none while every enabled body with states is
  % disabled and the root has none) and, with zero crossings, one per
  % accepted event flow (each '*m=candidate;' commit in
  % ob_integrate_events).
  %
  % Events: the C context counts each guard record once per guard and
  % instant (event_count).  Every counting site is instrumented with
  % ob_run's direction and passed to the gateway's ob_accel_event with a kind
  % (1 continuous-control change, 2 plateau departure, 3 located crossing):
  % the ob_event_record calls of the first two (through ob_accel_record,
  % which logs only records that count) and the inline counter of the
  % crossing loop, which already applies ob_run's origin_departures rule
  % (time of the search origin, no second record after an arrival from the
  % other side).  Directions: sign (after - before) of a continuous control,
  % the outgoing regime of a departure, sign (after - before) of a crossing.
  % Each search step (one pass of ob_integrate_events' loop) starts with
  % ob_accel_search, so every record carries its step and
  % ob_accelerate_events can order the records of one step as ob_run does.
  % The C counters themselves are never changed.
  if (! isempty (strfind (source, 'integration_steps')) || ! isempty (strfind (source, 'ob_accel_')))
    unsupported ('the typed export already declares accelerator fields');
  endif
  marker = '} ob_model;';
  if (numel (strfind (source, marker)) != 1)
    unsupported ('the typed export has no unique root context');
  endif
  source = strrep (source, marker, ['  double integration_steps;' char(10) marker]);
  % Activity of the shared continuous states (ob_shared_rhs guards).
  active = '1';
  body = regexp (source, 'static int ob_shared_rhs\(.*?\n  return OB_OK;\}', 'match', 'once');
  if (! isempty (body))
    guards = regexp (body, '\n  if\(([^\n]*?)\)memcpy\(dy\+', 'tokens');
    if (isempty (guards)), active = '0';
    else active = strjoin (cellfun (@(g) ['(' strrep(g{1}, 'm->', 'work.') ')'], guards, 'uniformoutput', false), '||');
    endif
  endif
  call = 'status=ob_integrate_shared(&work,start,end);';
  source = strrep (source, call, ['work.integration_steps+=(' active ')?1.0:0.0;' call]);
  call = 'status=ob_integrate(&work,start,end,work.state);';
  source = strrep (source, call, ['work.integration_steps+=1.0;' call]);
  source = strrep (source, '*m=candidate;', '*m=candidate;m->integration_steps+=1.0;');
  uses = numel (regexp (source, 'ob_integrate(_shared)?\(&work', 'match')) ...
         + numel (strfind (source, '*m=candidate;'));
  if (uses != numel (strfind (source, 'integration_steps+=')))
    unsupported ('the typed export integrates in a way the step counter does not recognize');
  endif
  events = ! isempty (strfind (source, 'static void ob_event_record('));
  if (! events), return; endif
  unknown = 'the typed export records events in a way the accelerator does not recognize';
  record_end = '  if(!m->event_reported[index]){m->event_count++;m->last_event_time=time;m->event_reported[index]=1;}}';
  if (numel (strfind (source, record_end)) != 1), unsupported (unknown); endif
  calls = numel (strfind (source, 'ob_event_record(m,'));
  counters = numel (strfind (source, 'event_count++'));
  search = 'const double begin=m->time;double finish=endpoint;';
  if (numel (strfind (source, search)) != 1), unsupported (unknown); endif
  source = strrep (source, search, [search 'ob_accel_search();']);
  source = strrep (source, record_end, [record_end char(10) ...
    'static void ob_accel_search(void);' char(10) ...
    'static void ob_accel_event(size_t index, double time, int direction, int kind);' char(10) ...
    'static void ob_accel_record(ob_model *m, size_t index, double time, int direction, int kind) {' char(10) ...
    '  const size_t before = m->event_count;' char(10) ...
    '  ob_event_record(m, index, time);' char(10) ...
    '  if (m->event_count != before) ob_accel_event(index, time, direction, kind);' char(10) '}']);
  source = regexprep (source, ['ob_event_sign\(at\.value\[(\d+)\]\)!=m->([A-Za-z0-9_.]+)\)' ...
                               '\{ob_event_record\(m,(\d+),begin\);changed=1;\}'], ...
                      ['ob_event_sign(at.value[$1])!=m->$2){ob_accel_record(m,$3,begin,' ...
                       'ob_event_sign((double)(ob_event_sign(at.value[$1])-m->$2)),1);changed=1;}']);
  source = strrep (source, '!=ob_event_side(i,mode)){ob_event_record(m,i,begin);}', ...
                   '!=ob_event_side(i,mode)){ob_accel_record(m,i,begin,ob_event_side(i,mode),2);}');
  % The crossing loop's counting statement, exactly as ob_emit_c_event_root
  % emits it (last_event_time keeps the latest counted time).
  latest = 'if(m->event_count==1||when>m->last_event_time)m->last_event_time=when;';
  crossing = ['if(!m->event_reported[i]){m->event_count++;' latest 'm->event_reported[i]=1;}'];
  source = strrep (source, crossing, ...
                   [crossing(1:end-1) 'ob_accel_event(i,when,ob_event_sign(sampled.value[i]-at.value[i]),3);}']);
  % Every ob_event_record call site now goes through ob_accel_record (one
  % call remains, inside it), and every inline counter other than the one in
  % ob_event_record logs its record.
  if (numel (strfind (source, 'ob_accel_record(m,')) != calls ...
      || numel (strfind (source, 'ob_event_record(m,')) != 1 ...
      || numel (strfind (source, 'ob_accel_event(i,when,')) != counters - 1)
    unsupported (unknown);
  endif
endfunction

function capacity_error (t, failed, capacity, retries, detail)
  if (! isempty (detail)), detail = [' and ' detail]; endif
  error ('octave_blocks:accelerate_capacity', ...
         ['ob_accelerate: compiled model failed at t = %.17g (sample %d): Transport Delay ' ...
          'history exceeded its compiled capacity of %s samples (OB_DELAY_OVERFLOW) after ' ...
          '%d enlargements%s; delayed discontinuities accumulate faster than the history ' ...
          'allows, so run interpreted (accelerate=''auto'' does so automatically)'], ...
         t(max (1, failed)), failed, capacity_text (capacity), retries, detail);
endfunction

function key = export_fingerprint (model, options, t, cache)
  % Byte-exact digest of the export inputs through Octave's binary format.
  % That format records whether a string was single- or double-quoted, so
  % the normalized solver name is hashed as character codes ('rk4' and the
  % default "rk4" are the same setting).
  options.accelerate = true;
  options.solver = double (options.solver);
  % How each Function name resolves now: whether a builtin is shadowed
  % decides between C math and an Octave call (ob_c_function), so an export
  % made before a user file appeared (or disappeared) is not reused.
  names = reshape (unique (function_names (model)), 1, []);
  resolution = cell (size (names));
  for k = 1:numel (names)
    resolution{k} = {exist(names{k}), function_file(names{k})};
  endfor
  data = struct ('model', model, 'options', options, 't', t, 'cache', cache, ...
                 'functions', {[names; resolution]}, 'version', 'ob-accelerate-v2');
  file = [tempname() '.ob-fingerprint'];
  unwind_protect
    save ('-binary', file, 'data');
    fid = fopen (file, 'rb');
    bytes = fread (fid, Inf, 'uint8=>char')';
    fclose (fid);
  unwind_protect_cleanup
    if (exist (file, 'file')), unlink (file); endif
  end_unwind_protect
  key = hash ('sha1', bytes);
endfunction

function names = function_names (model)
  % Function and Multiple Function names, through every subsystem body.
  names = {};
  if (! isstruct (model) || ! isscalar (model) || ! isfield (model, 'blocks') ...
      || ! isstruct (model.blocks) || ! isfield (model.blocks, 'type'))
    return;
  endif
  for k = 1:numel (model.blocks)
    block = model.blocks(k);
    if (any (strcmp (block.type, {'Function', 'Multiple Function'})))
      if (isfield (block, 'name') && ischar (block.name) && isvarname (block.name))
        names{end+1} = block.name;
      endif
    elseif (isfield (block, 'value') && isstruct (block.value))
      names = [names function_names(block.value)];
    endif
  endfor
endfunction

function file = function_file (name)
  try
    file = functions (str2func (name)).file;
  catch
    file = '';
  end_try_catch
endfunction

function yes = same_folder (folders, folder)
  normalize = @(f) strrep (f, '\', '/');
  if (ispc ())
    yes = strcmpi (cellfun (normalize, folders, 'uniformoutput', false), normalize (folder));
  else
    yes = strcmp (folders, folder);
  endif
endfunction

function plan = require_subset (model, options)
  % Reject what the exporters or this gateway do not cover before
  % generating or compiling anything, and choose the exporter.
  if (! isstruct (model) || ! isscalar (model) || ! isfield (model, 'blocks') ...
      || ! isstruct (model.blocks) || ! isfield (model.blocks, 'type'))
    error ('ob_accelerate: expected a model struct with blocks');
  endif
  if (strcmp (options.solver, 'ode15s'))
    unsupported ('solver ode15s is interpreted only; the C subset uses rk4 or ode45');
  endif
  flat = ob_compile_model (model);
  types = {flat.blocks.type};
  if (isempty (types))
    unsupported ('the model has no blocks');
  endif
  typed = any (ismember (types, {'Conditional Subsystem', 'Multiple Function', 'Function Output'})) ...
          || ob_has_continuous_control (model) || options.zero_crossings;
  plan = struct ('exporter', 'flat', 'ids', zeros (1, 0), 'names', {{}});
  if (typed)
    if (! strcmp (options.solver, 'rk4'))
      unsupported (['solver %s with conditional subsystems, multiple-output Functions or ' ...
                    'zero crossings is interpreted only; their typed C exporter uses rk4'], options.solver);
    endif
    plan.exporter = 'typed';
    return;
  endif
  if (strcmp (options.solver, 'ode45') && ! (isa (options.reltol, 'double') ...
      && isa (options.abstol, 'double') && isa (options.maxstep, 'double')))
    % ob_run takes the Dormand-Prince path that the C port reproduces only
    % for double settings; otherwise Octave's ode45 runs in their class.
    unsupported ('ode45 C export needs double reltol, abstol and maxstep');
  endif
  % Function blocks without a C mapping (ob_c_function) call Octave.
  for id = find (strcmp (types, 'Function'))
    name = flat.blocks(id).name;
    try
      ob_c_function (name);
    catch
      if (! ischar (name) || ! isvarname (name))
        unsupported ('Function block %d has no valid function name', id);
      endif
      plan.ids(end+1) = id;
      plan.names{end+1} = name;
    end_try_catch
  endfor
endfunction

function guards = event_guards (model)
  % The typed exporter's static guard inventory, as ob_codegen_conditional
  % builds it: C record index i (zero-based) is guards(i+1), whose public
  % path, type, channel, side and boundary are those of ob_run's records.
  [unused, guards] = ob_c_event_inventory (ob_c_conditional_unit (model));
endfunction

function text = value_class (value)
  text = class (value);
  if (isnumeric (value) && ! isreal (value)), text = ['complex ' text]; endif
  if (issparse (value)), text = ['sparse ' text]; endif
  if (ndims (value) > 2), text = sprintf ('%d-D %s', ndims (value), text); endif
endfunction

function result = assemble (model, t, options, runtime, generated, values, ticks, steps, records)
  % Mirror ob_run's result fields, field order and value shapes.
  count = numel (t);
  blocks = runtime.model.blocks;
  n = numel (blocks);
  data = values';
  flat_values = cell (count, n);
  cores = false (1, n);
  for id = 1:n
    shape = generated.shapes{id};
    width = prod (shape);
    columns = generated.offsets(id) + (1:width);
    if (any (strcmp (blocks(id).type, {'Conditional Subsystem', 'Multiple Function'})))
      cores(id) = true;
    elseif (width == 1)
      flat_values(:, id) = num2cell (data(:, columns));
    else
      stacked = reshape (data(:, columns)', [shape count]);
      flat_values(:, id) = reshape (num2cell (stacked, [1 2]), count, 1);
    endif
  endfor
  % Typed cores have no numeric channel.  A Multiple Function core is the
  % cell of its outputs, which are exactly its Function Output proxies.  A
  % Conditional Subsystem core is an interpreted child context in ob_run;
  % the compiled child context stays in C, and the accelerated core holds
  % only its held outputs (field 'outputs', equal to the interpreted
  % context's), which are exactly its Conditional Output proxies.
  edges = runtime.model.edges;
  for id = find (cores)
    proxies = edges(edges(:, 1) == id, 3)';
    ports = arrayfun (@(p) blocks(p).value, proxies);
    [unused, order] = sort (ports);
    % One cell row of outputs per sample, built without a per-sample loop
    % (it dominated warm calls of long conditional runs).
    per_sample = num2cell (flat_values(:, proxies(order)), 2);
    if (strcmp (blocks(id).type, 'Multiple Function'))
      flat_values(:, id) = per_sample;
    else
      flat_values(:, id) = num2cell (cell2struct (per_sample', {'outputs'}, 1));
    endif
  endfor
  result = struct ('t', t(:), 'values', {flat_values}, 'order', runtime.order, ...
                   'solver', options.solver, 'solver_options', options, ...
                   'integration_steps', steps);
  result.flat_values = flat_values;
  result.signal_map = runtime.signal_map;
  result.block_paths = runtime.block_paths;
  result.compiled_model = runtime.model;
  result.inputs = runtime.model.inputs;
  result.sample_hits = ob_accelerate_hits (runtime, t, ticks, generated.sample_times);
  result.sample_times = runtime.rates;
  result.events = runtime.events;
  if (! isempty (records)), result.events = [result.events records]; endif
  result.values = cell (count, numel (model.blocks));
  for item = runtime.signal_map
    if (numel (item.path) == 1 && ! isempty (item.outputs))
      result.values(:, item.path) = flat_values(:, item.outputs(1));
    endif
  endfor
endfunction

function capacity = delay_capacity (source)
  capacity = [];
  match = regexp (source, 'const size_t ob_delay_capacity\[OB_DELAY_COUNT\] = \{([0-9,]+)\};', 'tokens', 'once');
  if (! isempty (match)), capacity = str2double (strsplit (match{1}, ',')); endif
endfunction

function shortest = delay_shortest (source)
  shortest = [];
  match = regexp (source, 'static const double ob_delay_shortest = ([^;]+);', 'tokens', 'once');
  if (! isempty (match)), shortest = str2double (match{1}); endif
endfunction

function text = capacity_text (capacity)
  text = strjoin (arrayfun (@num2str, capacity, 'uniformoutput', false), '/');
endfunction

function text = status_text (status, entry, options, message, call)
  switch (status)
    case 1, text = 'invalid time or sample schedule (OB_BAD_ARGUMENT)';
    case 2, text = 'a signal became nonfinite (OB_NONFINITE)';
    case 3, text = 'root input error (OB_INPUT_ERROR)';
    case 4, text = 'nonsettling or chattering event regime, or event limit reached (OB_EVENT_ERROR)';
    case 6
      % The same limit and wording as ob_run (private/ob_runtime_integrate.m).
      text = sprintf (['Transport Delay of %.17g needs more than 1e6 segments per output ' ...
                       'interval (OB_DELAY_SEGMENTS)'], entry.delay_shortest);
    case 7
      % ob_run: "<solver> failed to reach time ... with finite states".
      text = sprintf (['%s failed to reach the end of an integration segment with finite ' ...
                       'states (OB_STEP_FAILED)'], options.solver);
    case 8
      text = sprintf ('Function ''%s'' failed (OB_EXTERNAL_ERROR): %s', entry.plan.names{call}, message);
    case -1, text = 'out of memory or no worker thread';
    otherwise, text = sprintf ('error code %d', status);
  endswitch
endfunction

function flags = compile_flags ()
  % No FMA contraction, so arithmetic rounds as in Octave on any target.
  flags = '-O2 -ffp-contract=off';
  if (! ispc ()), flags = [flags ' -pthread -DOB_ACCEL_PTHREAD']; endif
endfunction

function compile (file, binary, text, flags)
  % Write the source and compile to a private name, then rename, so that
  % concurrent sessions never load a partial file.
  [folder, base] = fileparts (binary);
  temporary = fullfile (folder, sprintf ('%s_%d_%d', base, getpid (), floor (rand () * 1e9)));
  write_file (file, text);
  previous = getenv ('CFLAGS'); previous_ld = getenv ('LDFLAGS');
  previous_directory = pwd ();
  temporary_variables = {'TMPDIR','TMP','TEMP'};
  previous_temporary = cellfun(@getenv,temporary_variables,'uniformoutput',false);
  unwind_protect
    setenv ('CFLAGS', flags);
    if (! ispc ()), setenv ('LDFLAGS', [previous_ld ' -pthread']); endif
    try
      if (ispc ())
        cd (folder);
        for variable = temporary_variables, setenv(variable{1},'.'); endfor
        [unused,source_name,source_extension] = fileparts(file);
        [unused,binary_name] = fileparts(temporary);
        [output, status] = mkoctfile ('--mex', '-o', [binary_name '.' mexext()], [source_name source_extension]);
      else
        [output, status] = mkoctfile ('--mex', '-o', [temporary '.' mexext()], file);
      endif
    catch err
      unavailable ('mkoctfile failed: %s', err.message);
    end_try_catch
    if (status != 0)
      unavailable ('mkoctfile --mex failed for %s:\n%s', file, output);
    endif
    if (! exist (binary, 'file'))
      [ok, message] = movefile ([temporary '.' mexext()], binary);
      if (! ok && ! exist (binary, 'file'))
        unavailable ('cannot store %s: %s', binary, message);
      endif
    endif
  unwind_protect_cleanup
    cd (previous_directory);
    for index = 1:numel(temporary_variables)
      setenv(temporary_variables{index},previous_temporary{index});
    endfor
    setenv ('CFLAGS', previous);
    if (! ispc ()), setenv ('LDFLAGS', previous_ld); endif
    for extension = {['.' mexext()], '.o'}
      if (exist ([temporary extension{1}], 'file')), unlink ([temporary extension{1}]); endif
    endfor
  end_unwind_protect
endfunction

function write_file (file, text)
  temporary = [file '.tmp' sprintf('%d', getpid ())];
  fid = fopen (temporary, 'wb');
  if (fid < 0), unavailable ('cannot write %s', temporary); endif
  unwind_protect
    fwrite (fid, text, 'char');
  unwind_protect_cleanup
    fclose (fid);
  end_unwind_protect
  [ok, message] = movefile (temporary, file, 'f');
  if (! ok), unavailable ('cannot write %s: %s', file, message); endif
endfunction

function folder = cache_directory ()
  folder = getenv ('OB_ACCELERATOR_CACHE');
  if (! isempty (folder))
    if (!cache_writable(folder)), unavailable ('OB_ACCELERATOR_CACHE is not writable: %s',folder); endif
    return;
  endif
  if (ispc ())
    base = getenv ('LOCALAPPDATA');
    if (isempty (base)), base = tempdir (); endif
  else
    base = getenv ('XDG_CACHE_HOME');
    if (isempty (base)), base = fullfile (getenv ('HOME'), '.cache'); endif
  endif
  platform = regexprep (computer (), '[^A-Za-z0-9_.-]', '_');
  folder = fullfile (base, 'octave-blocks', 'accelerator', [OCTAVE_VERSION '-' platform]);
  if (!cache_writable(folder))
    folder = fullfile(tempdir(),'octave-blocks','accelerator',[OCTAVE_VERSION '-' platform]);
    if (!cache_writable(folder)), unavailable ('no writable accelerator cache; set OB_ACCELERATOR_CACHE'); endif
  endif
endfunction

function yes = cache_writable (folder)
  yes = false;
  if (!exist(folder,'dir'))
    try
      [ok,unused] = mkdir(folder);
    catch
      return;
    end_try_catch
    if (!ok), return; endif
  endif
  probe = [tempname(folder) '.probe'];
  fid = fopen(probe,'wb');
  if (fid < 0), return; endif
  fclose(fid); unlink(probe); yes = true;
endfunction

function unsupported (varargin)
  error ('octave_blocks:accelerate_unsupported', '%s', ...
         ['ob_accelerate: model is outside the accelerated C subset: ' sprintf(varargin{:})]);
endfunction

function unavailable (varargin)
  error ('octave_blocks:accelerate_unavailable', '%s', ['ob_accelerate: ' sprintf(varargin{:})]);
endfunction
