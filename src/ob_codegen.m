function info = ob_codegen (model, file, config = [0 10 0.1], options = struct (), build = struct ())
  % Export a validated static real-double model as standalone, allocation-free C99.
  %
  % build is internal (used by ob_accelerate); its optional fields are
  %   record_times  host step times used to size Transport Delay histories
  %                 (default: the config output grid)
  %   standalone    false omits the OB_STANDALONE CSV runner (default true)
  %   count_steps   true adds ob_model.integration_steps, the number of RK4
  %                 segments taken, as ob_run reports it (default false)
  %   capacity_scale  power-of-two factor applied to every Transport Delay
  %                 history capacity (default 1; ob_accelerate doubles it
  %                 after OB_DELAY_OVERFLOW)
  %   external_shapes struct array (id, shape) of flat Function blocks with
  %                 no C mapping, evaluated by the host through
  %                 ob_external_call (ob_accelerate's MEX gateway calls the
  %                 Octave function); the output shape is fixed and the
  %                 source does not compile without that host function
  %
  % options.solver may be rk4 or ode45 (flat models only; see
  % ob_c_ode45_lines); ode15s is rejected.
  config = ob_validate_config (config);
  options = ob_solver_options (options);
  build = build_options (build, config);
  if (strcmp (options.solver, "ode15s"))
    % ode15s is an implicit variable-order method with Jacobian updates;
    % only the explicit fixed-step rk4 and adaptive ode45 have C ports.
    error ("ob_codegen: C export supports rk4 and ode45; ode15s is interpreted only");
  endif
  adaptive = strcmp (options.solver, "ode45");
  if (! ischar (file) || rows (file) != 1 || isempty (file) || any (file == 0))
    error ("ob_codegen: supply a C source file path");
  endif
  [folder, unused, extension] = fileparts (file);
  if (! strcmpi (extension, ".c")), error ("ob_codegen: output must have a .c extension"); endif
  if (isempty (folder)), folder = pwd (); endif
  if (! exist (folder, "dir")), error ("ob_codegen: output directory does not exist"); endif
  if (isstruct (model) && isscalar (model) && isfield (model, 'blocks') ...
      && isstruct (model.blocks) && isfield (model.blocks, 'type'))
    ob_require_runtime_support (model, options, 'ob_codegen');
  endif
  if (options.zero_crossings || ob_has_continuous_control(model))
    reject_typed (model, options);
    info = ob_codegen_conditional (model, file, config, options); return;
  endif
  [flat, signal_map, paths] = ob_compile_model (model);
  [order, edges, stateful] = ob_execution_order (flat);
  types = {flat.blocks.type};
  if (any (ismember (types, {'Conditional Subsystem', 'Multiple Function'})))
    reject_typed (model, options);
    info = ob_codegen_conditional (model, file, config); return;
  endif
  if (adaptive && ! (isa (options.reltol, 'double') && isa (options.abstol, 'double') ...
                     && isa (options.maxstep, 'double')))
    % The C port reproduces ob_run's Dormand-Prince path, which ob_run takes
    % only for double settings (private/ob_runtime_integrate.m lean_ode45);
    % other classes run Octave's ode45 in their own arithmetic.
    error ('ob_codegen: ode45 C export needs double reltol, abstol and maxstep');
  endif
  external = build_externals (build.external_shapes, flat, types);
  stateful |= strcmp (types, 'Rate Transition');
  % A Transport Delay keeps an input history instead of a numeric state;
  % it is stateful only for execution ordering.
  limited = find (strcmp (types, 'Limited Integrator'));
  delays = find (strcmp (types, 'Transport Delay'));
  stateful(delays) = false;
  parameters = cell (1, numel (flat.blocks));
  for id = [limited delays]
    parameters{id} = ob_block_parameters (flat.blocks(id));
  endfor
  resettable = limited(cellfun (@(p) ! strcmp (p.reset, 'none'), parameters(limited)));
  n = numel (flat.blocks);
  if (n == 0), error ("ob_codegen: add at least one block before export"); endif
  sources_by_block = ob_c_adjacency (n, edges);
  [shapes, expressions] = ob_c_shapes (flat, order, edges, paths, sources_by_block, external);
  sizes = cellfun (@prod, shapes);
  offsets = cumsum ([0 sizes(1:end-1)]);
  state_offsets = zeros (1, n); state_size = 0;
  for id = find (stateful)
    state_offsets(id) = state_size; state_size += sizes(id);
  endfor
  if (! isfield (flat, 'sample_times')), flat.sample_times = zeros (n, 2); endif
  rates = flat.sample_times;
  explicit = find (rates(:, 1)' > 0);
  inherited = find ((strcmp (types, 'Unit Delay') | strcmp (types, 'Discrete Integrator')) & rates(:, 1)' == 0);
  continuous = find (strcmp (types, "Integrator") | strcmp (types, 'Limited Integrator'));
  steps = find (strcmp (types, "Step"));
  inputs = {};
  if (isfield (flat, 'inputs')), inputs = flat.inputs; endif
  input_sizes = cellfun (@(signal) prod(signal.shape), inputs);
  input_offsets = cumsum ([0 input_sizes(1:end-1)]);
  if (isempty (inputs)), input_offsets = []; endif
  times = ob_time_grid (config(1), config(2), config(3));
  delay = struct ();
  if (! isempty (delays))
    % ode45 records every accepted interior point as well (several per output
    % interval at tight tolerances), so its histories start four times larger;
    % ob_accelerate doubles them again after OB_DELAY_OVERFLOW.
    delay = delay_info (delays, parameters, shapes, sources_by_block, offsets, flat, ...
                        build.record_times, rates(explicit, 1), steps, inputs, ...
                        ! isempty (continuous), build.count_steps && ! adaptive, ...
                        build.capacity_scale * (1 + 3 * adaptive));
  endif
  lines = {};
  method = 'RK4'; if (adaptive), method = 'adaptive ode45 (Dormand-Prince 5(4))'; endif
  add (['/* Generated by Octave Blocks. C99; real doubles, fixed sizes, ' method '. */'], ...
       '/* Build a CSV runner with: cc -std=c99 -O2 -DOB_STANDALONE model.c -lm -o model */', ...
       '/* Without OB_STANDALONE, include this file in a host translation unit. */');
  if (! isempty (delays))
    add ('/* Transport Delay histories live at the end of ob_model and are rolled back', ...
         '   in place: init and step keep only OB_DELAY_CORE_BYTES (the context', ...
         '   without its histories) and a few value arrays on the stack, never a', ...
         '   copy of ob_model.  The CSV runner keeps its context in static storage. */');
  endif
  add ('#include <math.h>', '#include <stddef.h>', '#include <string.h>', '#include <float.h>', ...
       '#ifdef OB_STANDALONE', '#include <stdio.h>', '#endif', ...
       sprintf ('enum { OB_BLOCK_COUNT = %d, OB_VALUE_COUNT = %d, OB_STATE_COUNT = %d };', n, sum(sizes), state_size), ...
       sprintf ('#define OB_STATE_STORAGE %d', max(1, state_size)), ...
       sprintf ('enum { OB_INPUT_PORT_COUNT = %d, OB_INPUT_VALUE_COUNT = %d };', numel(inputs), sum(input_sizes)), ...
       sprintf ('#define OB_INPUT_STORAGE %d', max(1, sum(input_sizes))), ...
       sprintf ('#define OB_INPUT_PORT_STORAGE %d', max(1, numel(inputs))), ...
       'enum { OB_OK = 0, OB_BAD_ARGUMENT = 1, OB_NONFINITE = 2, OB_INPUT_ERROR = 3 };');
  if (adaptive)
    % ode45 failed to reach a segment end (step size underflow or 5000
    % consecutive rejections), where ob_run raises an error.
    add ('enum { OB_STEP_FAILED = 7 };');
  endif
  if (! isempty (external.ids))
    lines = [lines external_declarations(external, flat, shapes, sources_by_block)];
  endif
  if (! isempty (delays)), lines = [lines ob_c_delay_lines('declarations', delay)]; endif
  if (! isempty (resettable)), add (sprintf ('#define OB_RESET_STORAGE %d', numel (resettable))); endif
  add ('typedef int (*ob_input_provider)(double time, int left, double *values, size_t count, void *user);', ...
       'typedef double (*ob_input_event)(double after, double before, void *user);', ...
       'typedef struct {', '  double state[OB_STATE_STORAGE];', ...
       '  double pending[OB_STATE_STORAGE];', '  unsigned char pending_valid[OB_BLOCK_COUNT];', ...
       '  double tick[OB_BLOCK_COUNT];', '  double start_time;', ...
       '  double value[OB_VALUE_COUNT];', '  double time;', '  int initialized;', ...
       '  ob_input_provider input_provider;', '  ob_input_event input_event;', '  void *input_user;');
  if (! isempty (resettable))
    % Previous sampled reset signal of each resettable Limited Integrator.
    add ('  double reset_memory[OB_RESET_STORAGE];', '  unsigned char reset_valid[OB_RESET_STORAGE];');
  endif
  if (build.count_steps), add ('  double integration_steps;'); endif
  % Delay histories come last: rollback saves everything before delay_t.
  if (! isempty (delays)), lines = [lines ob_c_delay_lines('fields', delay)]; endif
  ode_points = 0;
  if (adaptive && ! isempty (delays) && ! isempty (continuous))
    % Accepted ode45 points of one segment, recorded after it (scratch, zero
    % between calls, after the histories so rollback never copies it).
    ode_points = max (delay.capacity);
    add (sprintf ('  double ode_t[%d];', ode_points), ...
         sprintf ('  double ode_y[%d];', ode_points * sum (sizes(continuous))));
  endif
  add ('} ob_model;', ...
       ['const size_t ob_block_offset[OB_BLOCK_COUNT] = {' integer_list(offsets) '};'], ...
       ['const size_t ob_block_rows[OB_BLOCK_COUNT] = {' integer_list(cellfun(@(s) s(1), shapes)) '};'], ...
       ['const size_t ob_block_cols[OB_BLOCK_COUNT] = {' integer_list(cellfun(@(s) s(2), shapes)) '};']);
  add (['const double ob_sample_period[OB_BLOCK_COUNT] = {' number_list(rates(:, 1)') '};'], ...
       ['const double ob_sample_offset[OB_BLOCK_COUNT] = {' number_list(rates(:, 2)') '};']);
  metadata_offsets = input_offsets;
  metadata_rows = cellfun (@(signal) signal.shape(1), inputs);
  metadata_cols = cellfun (@(signal) signal.shape(2), inputs);
  if (isempty (inputs)), metadata_offsets = metadata_rows = metadata_cols = 0; endif
  add (['const size_t ob_input_offset[OB_INPUT_PORT_STORAGE] = {' integer_list(metadata_offsets) '};'], ...
       ['const size_t ob_input_rows[OB_INPUT_PORT_STORAGE] = {' integer_list(metadata_rows) '};'], ...
       ['const size_t ob_input_cols[OB_INPUT_PORT_STORAGE] = {' integer_list(metadata_cols) '};']);
  labels = cellfun (@(p) strtrim(sprintf('%d ', p)), paths, 'uniformoutput', false);
  path_literals = cellfun (@(p) ['"' strrep(p, ' ', '/') '"'], labels, 'uniformoutput', false);
  add (['const char *const ob_block_path[OB_BLOCK_COUNT] = {' strjoin(path_literals, ',') '};']);
  for id = 1:n
    if (strcmp (types{id}, 'Limited Integrator'))
      % The initial state is the clipped initial condition; limits broadcast
      % to the state shape, with infinite bounds as HUGE_VAL.
      params = parameters{id};
      add (sprintf ('static const double p%d[%d] = {%s};', id, numel(params.initial), number_list(params.initial(:)')), ...
           sprintf ('static const double lo%d[%d] = {%s};', id, numel(params.initial), limit_list(params.lower, params.initial)), ...
           sprintf ('static const double hi%d[%d] = {%s};', id, numel(params.initial), limit_list(params.upper, params.initial)));
    elseif (stateful(id) || any (strcmp (types{id}, {"Constant", "Gain"})))
      add (sprintf ('static const double p%d[%d] = {%s};', id, numel(flat.blocks(id).value), number_list(flat.blocks(id).value(:)')));
    endif
  endfor
  if (any (strcmp (types, "Gain") | strcmp (types, "Product")))
    add ('static void ob_multiply(double *out, const double *a, size_t ar, size_t ac,', ...
         '                        const double *b, size_t br, size_t bc) {', ...
         '  if (ar * ac == 1) {', ...
         '    for (size_t i = 0; i < br * bc; ++i) out[i] = a[0] * b[i];', ...
         '  } else if (br * bc == 1) {', ...
         '    for (size_t i = 0; i < ar * ac; ++i) out[i] = a[i] * b[0];', ...
         '  } else {', '    for (size_t c = 0; c < bc; ++c) {', ...
         '      for (size_t r = 0; r < ar; ++r) {', '        double value = 0.0;', ...
         '        for (size_t k = 0; k < ac; ++k) value += a[r + k*ar] * b[k + c*br];', ...
         '        out[r + c*ar] = value;', '      }', '    }', '  }', '}');
  endif
  % Delay intervals split at input knots even without continuous states.
  lines = [lines ob_c_input_lines(inputs, ! isempty(continuous) || ! isempty(delays))];
  if (! isempty (delays)), lines = [lines ob_c_delay_lines('support', delay)]; endif
  add ('static int ob_eval(const ob_model *model, double time, const double *state, double *v, int left, const unsigned char *hit, double *sampled_state) {', ...
       '  (void)model; (void)time; (void)state; (void)left; (void)hit; (void)sampled_state;');
  if (! isempty (inputs))
    add ('  double input[OB_INPUT_STORAGE];', ...
         '  int input_status = ob_read_inputs(model, time, left, input);', ...
         '  if (input_status != OB_OK) return input_status;');
  endif
  for id = order
    sources = sources_by_block{id};
    o = offsets(id); count = sizes(id); block = flat.blocks(id);
    add (sprintf ('  /* Block %s: %s */', strrep(labels{id}, ' ', '/'), block.type));
    switch (block.type)
      case 'Constant'
        add (sprintf ('  memcpy(v + %d, p%d, %d * sizeof(double));', o, id, count));
      case 'External Input'
        add (sprintf ('  memcpy(v + %d, input + %d, %d * sizeof(double));', o, input_offsets(block.value), count));
      case 'Time'
        add (sprintf ('  v[%d] = time;', o));
      case 'Step'
        p = block.value;
        add (sprintf ('  v[%d] = (time < %s || (left && time == %s)) ? %s : %s;', ...
                      o, c_number(p(1)), c_number(p(1)), c_number(p(2)), c_number(p(3))));
      case 'Rate Transition'
        add (sprintf ('  if (hit && hit[%d]) {', id-1), ...
             sprintf ('    memcpy(sampled_state + %d, v + %d, %d*sizeof(double));', state_offsets(id), offsets(sources(1)), count), ...
             sprintf ('    memcpy(v + %d, v + %d, %d*sizeof(double));', o, offsets(sources(1)), count), ...
             '  } else {', ...
             sprintf ('    memcpy(v + %d, state + %d, %d*sizeof(double));', o, state_offsets(id), count), '  }');
      case {'Unit Delay', 'Integrator', 'Discrete Integrator'}
        add (sprintf ('  memcpy(v + %d, state + %d, %d * sizeof(double));', o, state_offsets(id), count));
      case 'Limited Integrator'
        % Octave min (max (x, lower), upper), including its tie and signed-zero choices.
        add (sprintf ('  for (size_t i = 0; i < %d; ++i) {', count), ...
             sprintf ('    const double clipped = state[%d + i] >= lo%d[i] ? state[%d + i] : lo%d[i];', state_offsets(id), id, state_offsets(id), id), ...
             sprintf ('    v[%d + i] = clipped <= hi%d[i] ? clipped : hi%d[i];', o, id, id), '  }');
      case 'Transport Delay'
        add (sprintf ('  ob_delay_output(model, %d, time, left, v + %d);', find (delays == id) - 1, o));
      case {'Scope', 'Inport', 'Outport'}
        add (sprintf ('  memcpy(v + %d, v + %d, %d * sizeof(double));', o, offsets(sources(1)), count));
      case {'Saturation', 'Dead Zone'}
        lower = c_number (block.value(1)); upper = c_number (block.value(2));
        add (sprintf ('  for (size_t i = 0; i < %d; ++i) {', count), ...
             sprintf ('    const double signal = v[%d + i];', offsets(sources(1))));
        if (strcmp (block.type, 'Saturation'))
          add (sprintf ('    v[%d + i] = signal < %s ? %s : (signal > %s ? %s : signal);', ...
                        o, lower, lower, upper, upper));
        else
          add (sprintf ('    v[%d + i] = signal < %s ? signal - %s : (signal > %s ? signal - %s : 0.0);', ...
                        o, lower, lower, upper, upper));
        endif
        add ('  }');
      case 'Switch'
        control = input_expression (offsets(sources(2)), shapes{sources(2)}, shapes{id});
        add (sprintf ('  for (size_t i = 0; i < %d; ++i)', count), ...
             sprintf ('    v[%d + i] = %s >= %s ? v[%d + i] : v[%d + i];', ...
                      o, control, c_number(block.value), offsets(sources(1)), offsets(sources(3))));
      case {'Gain', 'Product'}
        if (strcmp (block.type, 'Gain'))
          a = sprintf ('p%d', id); ashape = size (block.value); bsource = sources(1);
        else
          a = sprintf ('v + %d', offsets(sources(1))); ashape = shapes{sources(1)}; bsource = sources(2);
        endif
        bshape = shapes{bsource};
        add (sprintf ('  ob_multiply(v + %d, %s, %d, %d, v + %d, %d, %d);', ...
                      o, a, ashape(1), ashape(2), offsets(bsource), bshape(1), bshape(2)));
      case {'Sum', 'Function'}
        host = find (external.ids == id, 1);
        if (! isempty (host))
          % No C mapping: the host evaluates the Octave function (accelerated
          % builds only); it checks the result's class and shape.
          add ('  {', sprintf ('    const double *arguments[%d] = {%s};', numel (sources), ...
                              strjoin (arrayfun (@(s) sprintf ('v + %d', offsets(s)), sources, 'uniformoutput', false), ', ')), ...
               sprintf ('    const int external_status = ob_external_call(%d, arguments, v + %d);', host - 1, o), ...
               '    if (external_status != OB_OK) return external_status;', '  }');
          continue;
        endif
        if (strcmp (block.type, 'Sum')), expression = '(INPUT_A + INPUT_B)';
        else expression = expressions{id}; endif
        add (sprintf ('  for (size_t i = 0; i < %d; ++i) {', count));
        a = input_expression (offsets(sources(1)), shapes{sources(1)}, shapes{id});
        expression = strrep (expression, 'INPUT_A', a);
        if (numel (sources) > 1)
          b = input_expression (offsets(sources(2)), shapes{sources(2)}, shapes{id});
          expression = strrep (expression, 'INPUT_B', b);
        endif
        add (sprintf ('    v[%d + i] = %s;', o, expression), '  }');
    endswitch
  endfor
  add ('  for (size_t i = 0; i < OB_VALUE_COUNT; ++i) if (!isfinite(v[i])) return OB_NONFINITE;', ...
       '  return OB_OK;', '}');
  lines = [lines ob_c_schedule_lines(flat, edges, offsets, state_offsets, sizes, sources_by_block, ...
                                     reset_lines(resettable, parameters, sources_by_block, offsets, state_offsets, sizes, labels, ! adaptive), ...
                                     delay_record_lines(delays))];
  add ('int ob_model_outputs(ob_model *model) {', ...
       '  double values[OB_VALUE_COUNT];', ...
       '  if (!model || !model->initialized || !isfinite(model->time)) return OB_BAD_ARGUMENT;', ...
       '  int status = ob_eval(model, model->time, model->state, values, 0, NULL, NULL);', ...
       '  if (status == OB_OK) memcpy(model->value, values, sizeof(values));', ...
       '  return status;', '}');
  provider_head = {'int ob_model_set_input_provider(ob_model *model, ob_input_provider provider, ob_input_event event, void *user) {', ...
                   '  if (!model || !model->initialized || (!provider && (event || user))) return OB_BAD_ARGUMENT;', ...
                   '  if (OB_INPUT_PORT_COUNT == 0 && provider) return OB_BAD_ARGUMENT;'};
  init_head = {'int ob_model_init_inputs(ob_model *model, double start_time, ob_input_provider provider, ob_input_event event, void *user) {', ...
               '  if (!model || !isfinite(start_time) || (!provider && (event || user))) return OB_BAD_ARGUMENT;', ...
               '  if (OB_INPUT_PORT_COUNT == 0 && provider) return OB_BAD_ARGUMENT;'};
  if (isempty (delays))
    add (provider_head{:}, '  ob_model work = *model;', ...
         '  work.input_provider = provider; work.input_event = event; work.input_user = user;', ...
         '  int status = ob_model_outputs(&work);', ...
         '  if (status == OB_OK) *model = work;', '  return status;', '}', ...
         init_head{:}, '  ob_model work;', '  memset(&work, 0, sizeof(work));');
  else
    % Providers change only the core; initialization resets the histories
    % in place (ob_c_delay_lines rollback helpers) instead of building a
    % second context on the stack.
    add (provider_head{:}, '  unsigned char saved[OB_DELAY_CORE_BYTES];', ...
         '  memcpy(saved, model, sizeof(saved));', ...
         '  model->input_provider = provider; model->input_event = event; model->input_user = user;', ...
         '  int status = ob_model_outputs(model);', ...
         '  if (status != OB_OK) memcpy(model, saved, sizeof(saved));', '  return status;', '}', ...
         'static int ob_delay_init(ob_model *work, double start_time, ob_input_provider provider, ob_input_event event, void *user) {', ...
         '  memset(work, 0, OB_DELAY_CORE_BYTES);');
  endif
  mark = numel (lines);
  add ('  work.input_provider = provider; work.input_event = event; work.input_user = user;', ...
       '  work.time = start_time; work.start_time = start_time; work.initialized = 1;');
  for id = explicit
    add (sprintf ('  if (!isfinite(start_time + ob_sample_period[%d]) || start_time + ob_sample_period[%d] <= start_time) return OB_BAD_ARGUMENT;', id-1, id-1), ...
         sprintf ('  const double first%d = ob_tick_time(&work, %d);', id, id-1), ...
         sprintf ('  if (!isfinite(first%d) || first%d < start_time || (ob_sample_offset[%d] > 0.0 && first%d <= start_time)) return OB_BAD_ARGUMENT;', id, id, id-1, id));
  endfor
  for id = find (stateful)
    add (sprintf ('  memcpy(work.state + %d, p%d, %d * sizeof(double));', state_offsets(id), id, sizes(id)));
  endfor
  if (isempty (delays))
    add ('  int status = ob_process_hits(&work, start_time, 1, 0);', '  if (status == OB_OK) *model = work;', ...
         '  return status;', '}');
  else
    lines(mark+1:end) = in_place (lines(mark+1:end));
    add ('  return ob_process_hits(work, start_time, 1, 0);', '}', init_head{:}, ...
         '  ob_delay_undo undo;', '  ob_delay_begin_init(model, &undo);', ...
         '  const int status = ob_delay_init(model, start_time, provider, event, user);', ...
         '  ob_delay_finish_init(model, &undo, status);', '  return status;', '}');
  endif
  add ('int ob_model_init(ob_model *model, double start_time) {', ...
       '  return ob_model_init_inputs(model, start_time, NULL, NULL, NULL);', '}');
  if (adaptive && ! isempty (continuous))
    lines = [lines ob_c_ode45_lines(ode45_info(continuous, types, parameters, sources_by_block, offsets, ...
                                                   state_offsets, sizes, options, ! isempty (delays), ...
                                                   build.count_steps, ode_points))];
  elseif (! isempty (continuous) && isempty (limited) && isempty (delays))
    add ('static int ob_rhs(const ob_model *model, double time, const double *state, double *dy, int left) {', ...
         '  double v[OB_VALUE_COUNT];', '  int status = ob_eval(model, time, state, v, left, NULL, NULL);', ...
         '  if (status != OB_OK) return status;', '  memset(dy, 0, OB_STATE_STORAGE * sizeof(double));');
    for id = continuous
      source = sources_by_block{id};
      add (sprintf ('  memcpy(dy + %d, v + %d, %d * sizeof(double));', state_offsets(id), offsets(source), sizes(id)));
    endfor
    add ('  return OB_OK;', '}', ...
         'static int ob_integrate(const ob_model *model, double start, double end, double *state) {', ...
         '  double k1[OB_STATE_STORAGE], k2[OB_STATE_STORAGE], k3[OB_STATE_STORAGE], k4[OB_STATE_STORAGE];', ...
         '  double stage[OB_STATE_STORAGE];', '  const double h = end - start;', ...
         '  int status = ob_rhs(model, start, state, k1, 0); if (status != OB_OK) return status;', ...
         '  for (size_t i = 0; i < OB_STATE_COUNT; ++i) stage[i] = state[i] + h/2.0*k1[i];', ...
         '  status = ob_rhs(model, start + h/2.0, stage, k2, 0); if (status != OB_OK) return status;', ...
         '  for (size_t i = 0; i < OB_STATE_COUNT; ++i) stage[i] = state[i] + h/2.0*k2[i];', ...
         '  status = ob_rhs(model, start + h/2.0, stage, k3, 0); if (status != OB_OK) return status;', ...
         '  for (size_t i = 0; i < OB_STATE_COUNT; ++i) stage[i] = state[i] + h*k3[i];', ...
         '  status = ob_rhs(model, end, stage, k4, 1); if (status != OB_OK) return status;', ...
         '  for (size_t i = 0; i < OB_STATE_COUNT; ++i) state[i] += h/6.0*(k1[i] + 2.0*k2[i] + 2.0*k3[i] + k4[i]);', ...
         '  return OB_OK;', '}');
  elseif (! isempty (continuous))
    lines = [lines limited_integrate_lines(continuous, limited, parameters, sources_by_block, offsets, state_offsets, sizes, types)];
  endif
  if (! isempty (delays)), lines = [lines ob_c_delay_lines('interval', delay)]; endif
  step_head = {'int ob_model_step(ob_model *model, double next_time) {', ...
               '  if (!model || !model->initialized || !isfinite(next_time) || next_time <= model->time)', ...
               '    return OB_BAD_ARGUMENT;', ...
               '  const double dt = next_time - model->time;', ...
               '  if (!isfinite(dt)) return OB_BAD_ARGUMENT;'};
  if (isempty (delays)), add (step_head{:}, '  ob_model work = *model;'); endif
  mark = numel (lines);
  add ('  int status = ob_model_outputs(&work);', '  if (status != OB_OK) return status;');
  for id = inherited
    source = sources_by_block{id};
    if (strcmp (types{id}, 'Unit Delay'))
      add (sprintf ('  memcpy(work.pending + %d, work.value + %d, %d*sizeof(double));', state_offsets(id), offsets(source), sizes(id)));
    else
      add (sprintf ('  for (size_t i = 0; i < %d; ++i)', sizes(id)), ...
           sprintf ('    work.pending[%d+i] = work.state[%d+i] + dt*work.value[%d+i];', state_offsets(id), state_offsets(id), offsets(source)));
    endif
    add (sprintf ('  work.pending_valid[%d] = 1;', id-1));
    add (sprintf ('  for (size_t i = 0; i < %d; ++i) if (!isfinite(work.pending[%d+i])) return OB_NONFINITE;', sizes(id), state_offsets(id)));
  endfor
  add ('  double start = work.time;', '  while (start < next_time) {', '    double end = next_time;');
  for id = explicit
    add (sprintf ('    const double tick%d = ob_tick_time(&work, %d);', id, id-1), ...
         sprintf ('    if (!isfinite(tick%d) || tick%d <= start) return OB_BAD_ARGUMENT;', id, id), ...
         sprintf ('    if (tick%d < end && !ob_time_close(tick%d, next_time, work.start_time)) end = tick%d;', id, id, id));
  endfor
  if (! isempty (delays))
    % ob_runtime_integrate fixes all boundaries of a scheduled interval at its
    % start, from the delay histories recorded so far; ob_delay_interval
    % integrates and records the whole interval before the accepted hit.
    add ('    if (!isfinite(end) || end <= start) return OB_BAD_ARGUMENT;', ...
         '    status = ob_delay_interval(&work, start, end);', ...
         '    if (status != OB_OK) return status;', ...
         '    const int output = end == next_time;', ...
         '    status = ob_process_hits(&work, end, output, output);', ...
         '    if (status != OB_OK) return status;', ...
         '    start = end;', '  }');
  else
    add ('    const double scheduled_end = end;');
    if (! isempty (continuous))
      for id = steps
        event = c_number (flat.blocks(id).value(1));
        add (sprintf ('    if (%s > start && %s < end) end = %s;', event, event, event));
      endfor
      if (! isempty (inputs))
        add ('    status = ob_next_input_boundary(&work, start, &end);', ...
             '    if (status != OB_OK) return status;');
      endif
      if (adaptive)
        add ('    {', '      size_t points;', '      double accepted;', ...
             '      status = ob_ode45(&work, start, end, work.state, NULL, NULL, 0, &points, &accepted);', ...
             '      if (status != OB_OK) return status;');
        if (build.count_steps), add ('      work.integration_steps += accepted;'); endif
        add ('    }');
      else
        if (isempty (limited))
          add ('    status = ob_integrate(&work, start, end, work.state);');
        else
          add ('    status = ob_integrate(&work, start, end, work.state, NULL);');
        endif
        add ('    if (status != OB_OK) return status;');
        if (build.count_steps), add ('    work.integration_steps += 1.0;'); endif
      endif
    endif
    add ('    if (!isfinite(end) || end <= start) return OB_BAD_ARGUMENT;', ...
         '    const int output = end == next_time;', ...
         '    if (end == scheduled_end) {', ...
         '      status = ob_process_hits(&work, end, output, output);', ...
         '      if (status != OB_OK) return status;', '    } else { work.time = end; }', ...
         '    start = end;', '  }');
  endif
  if (isempty (delays))
    add ('  *model = work;', '  return OB_OK;', '}');
    runner_model = '  ob_model model;';
  else
    % The step body works on the caller's context in place; ob_delay_finish
    % commits it or restores the state saved by ob_delay_begin.
    body = in_place (lines(mark+1:end));
    lines(mark+1:end) = [];
    add ('static int ob_delay_step(ob_model *work, double next_time, double dt) {', '  (void)dt;', ...
         body{:}, '  return OB_OK;', '}', step_head{:}, ...
         '  ob_delay_undo undo;', '  ob_delay_begin(model, &undo);', ...
         '  const int status = ob_delay_step(model, next_time, dt);', ...
         '  ob_delay_finish(model, &undo, status);', '  return status;', '}');
    % Histories can be large: keep the runner's context off the stack.
    runner_model = '  static ob_model model;';
  endif
  if (build.standalone)
    add ('#ifdef OB_STANDALONE', ['static const double ob_times[] = {' number_list(times) '};'], ...
         'int main(void) {', runner_model, ...
         '  if (ob_model_init(&model, ob_times[0]) != OB_OK) return 1;', ...
         '  printf("time");', ...
         '  for (size_t b = 0; b < OB_BLOCK_COUNT; ++b)', ...
         '    for (size_t e = 0; e < ob_block_rows[b]*ob_block_cols[b]; ++e)', ...
         '      printf(",b%s_e%zu", ob_block_path[b], e + 1);', ...
         '  printf("\n");', ...
         '  for (size_t sample = 0; sample < sizeof(ob_times)/sizeof(ob_times[0]); ++sample) {', ...
         '    if (sample && ob_model_step(&model, ob_times[sample]) != OB_OK) {', ...
         '      fprintf(stderr, "Simulation failed at sample %zu\n", sample); return 2;', '    }', ...
         '    printf("%.17g", model.time);', ...
         '    for (size_t i = 0; i < OB_VALUE_COUNT; ++i) printf(",%.17g", model.value[i]);', ...
         '    printf("\n");', '  }', '  return 0;', '}', '#endif');
  endif
  text = [strjoin(lines, char(10)) char(10)];
  temporary = [tempname(folder) '.c']; fid = -1;
  unwind_protect
    fid = fopen (temporary, 'wb');
    if (fid < 0), error ('ob_codegen: cannot write the output directory'); endif
    written = fwrite (fid, text, 'char'); status = fclose (fid); fid = -1;
    if (written != numel (text) || status != 0), error ('ob_codegen: source write failed'); endif
    [ok, message] = movefile (temporary, file, 'f');
    if (! ok), error ('ob_codegen: %s', message); endif
  unwind_protect_cleanup
    if (fid >= 0), fclose (fid); endif
    if (exist (temporary, 'file')), unlink (temporary); endif
  end_unwind_protect
  % Match the typed exporter: clocks describe blocks, including equal rates.
  clock_unit = struct ('flat',flat,'n',n,'paths',{paths},'children',{cell(1,n)});
  [unused_clock_unit, clocks] = ob_c_clock_inventory (clock_unit);
  info = struct ('source', file, 'paths', {paths}, 'shapes', {shapes}, ...
                 'offsets', offsets, 'value_count', sum(sizes), 'state_count', state_size, ...
                 'signal_map', {signal_map}, 'solver', options.solver, ...
                 'input_shapes', {cellfun(@(signal) signal.shape, inputs, 'uniformoutput', false)}, ...
                 'input_offsets', input_offsets, 'input_value_count', sum(input_sizes), ...
                 'sample_times', rates, ...
                 'continuous_state_count', sum(sizes(continuous)), ...
                 'clock_count', numel(clocks), 'clocks', {clocks}, ...
                 'typed_conditional', false, 'zero_crossings', false, 'event_guard_count', 0);

  function add (varargin)
    lines = [lines varargin];
  endfunction
endfunction

function text = c_number (value)
  text = ob_c_number_list (value);
endfunction

function text = number_list (values)
  text = ob_c_number_list (values);
endfunction

function text = integer_list (values)
  text = sprintf ('%d,', values); text(end) = [];
endfunction

function text = input_expression (offset, shape, output_shape)
  if (isequal (shape, output_shape))
    text = sprintf ('v[%d + i]', offset);
  elseif (prod (shape) == 1)
    text = sprintf ('v[%d]', offset);
  else
    row = '0'; column = '0';
    if (shape(1) != 1), row = sprintf ('(i %% %d)', output_shape(1)); endif
    if (shape(2) != 1), column = sprintf ('(i / %d)', output_shape(1)); endif
    text = sprintf ('v[%d + %s + %s * %d]', offset, row, column, shape(1));
  endif
endfunction

function build = build_options (build, config)
  if (! isstruct (build) || ! isscalar (build))
    error ('ob_codegen: build options must be a scalar struct');
  endif
  defaults = struct ('record_times', [], 'standalone', true, 'count_steps', false, 'capacity_scale', 1, ...
                     'external_shapes', []);
  for name = fieldnames (build)'
    if (! isfield (defaults, name{1}))
      error ('ob_codegen: unknown build option ''%s''', name{1});
    endif
    defaults.(name{1}) = build.(name{1});
  endfor
  build = defaults;
  if (isempty (build.record_times))
    build.record_times = ob_time_grid (config(1), config(2), config(3));
  endif
  if (! isnumeric (build.record_times) || ! isreal (build.record_times) ...
      || any (! isfinite (build.record_times(:))))
    error ('ob_codegen: record_times must be finite real times');
  endif
  build.standalone = logical (build.standalone);
  build.count_steps = logical (build.count_steps);
  scale = build.capacity_scale;
  if (! isnumeric (scale) || ! isscalar (scale) || ! isreal (scale) || ! (scale >= 1) ...
      || ! isfinite (scale) || 2^round (log2 (scale)) != scale)
    error ('ob_codegen: capacity_scale must be a power of two, at least 1');
  endif
  build.capacity_scale = double (scale);
endfunction

function lines = in_place (lines)
  % Turn lines written against a local 'ob_model work' into lines against
  % an 'ob_model *work' parameter (delay exports roll back in place).
  lines = strrep (strrep (lines, '&work', 'work'), 'work.', 'work->');
endfunction

function reject_typed (model, options)
  % The typed conditional/event exporter does not implement Transport Delay
  % or Limited Integrator; report that before it sees an unknown block.
  if (isstruct (model) && isscalar (model) && isfield (model, 'blocks') ...
      && isstruct (model.blocks) && isfield (model.blocks, 'type'))
    ob_require_runtime_support (model, options, 'ob_codegen_conditional');
  endif
  % The adaptive C integrator exists only on the flat path.
  if (! strcmp (options.solver, 'rk4'))
    error (['ob_codegen: the conditional/event C exporter requires rk4; ode45 C export ' ...
            'supports flat models without conditional subsystems, multiple-output Functions ' ...
            'or zero crossings']);
  endif
endfunction

function external = build_externals (shapes, flat, types)
  % Function blocks without a C mapping that the caller (ob_accelerate)
  % implements through ob_external_call: a map from flat block id to the
  % output shape learned from an initialized interpreted run.  Standalone
  % exports pass none and keep rejecting such blocks in ob_c_shapes.
  external = struct ('ids', zeros (1, 0), 'shapes', {{}});
  if (isempty (shapes)), return; endif
  if (! isstruct (shapes) || ! all (isfield (shapes, {'id', 'shape'})))
    error ('ob_codegen: external_shapes must be a struct array with id and shape');
  endif
  for item = reshape (shapes, 1, [])
    if (! isscalar (item.id) || item.id < 1 || item.id > numel (types) || item.id != fix (item.id) ...
        || ! strcmp (types{item.id}, 'Function'))
      error ('ob_codegen: external_shapes entries must name Function blocks');
    endif
    external.ids(end+1) = item.id;
    external.shapes{end+1} = double (item.shape);
  endfor
endfunction

function d = delay_info (delays, parameters, shapes, sources, offsets, flat, ...
                         record_times, periods, steps, inputs, continuous, count_steps, scale)
  % Static description of every Transport Delay for ob_c_delay_lines.
  count = numel (delays);
  d = struct ('ids', delays, 'delay', zeros (1, count), 'width', zeros (1, count), ...
              'input_width', zeros (1, count), 'source_offset', zeros (1, count), ...
              'capacity', zeros (1, count), 'initial', {cell(1, count)}, ...
              'steps', zeros (1, 0), 'inputs', {inputs}, ...
              'continuous', continuous, 'count_steps', count_steps);
  for k = 1:count
    id = delays(k); params = parameters{id}; source = sources{id}(1);
    d.delay(k) = params.delay;
    d.width(k) = prod (shapes{id});
    d.input_width(k) = prod (shapes{source});
    d.source_offset(k) = offsets(source);
    if (isscalar (params.initial))
      d.initial{k} = repmat (params.initial, d.width(k), 1);
    else
      d.initial{k} = params.initial(:);
    endif
  endfor
  for id = steps
    d.steps(end+1) = flat.blocks(id).value(1);
  endfor
  d.capacity = scale * ob_c_delay_capacity (d.delay, record_times, periods, numel (steps), inputs);
  % Samples (time, values, side flag) plus the per-interval jump list.
  bytes = sum (d.capacity .* (8 * d.width + 9) + 8 * (floor (d.capacity / 2) + 1));
  if (bytes > 2^28)
    error ('ob_codegen: Transport Delay histories need %.0f MB for this output grid; use a coarser grid or interpreted simulation', ...
           bytes / 2^20);
  endif
endfunction

function text = limit_list (bound, initial)
  values = bound .* ones (size (initial));
  parts = cell (1, numel (values));
  for k = 1:numel (values)
    if (values(k) == Inf), parts{k} = 'HUGE_VAL';
    elseif (values(k) == -Inf), parts{k} = '-HUGE_VAL';
    else parts{k} = ob_c_number_list (values(k)); endif
  endfor
  text = strjoin (parts, ',');
endfunction

function lines = reset_lines (resettable, parameters, sources, offsets, state_offsets, sizes, labels, fixed_step)
  % Limited Integrator resets sampled at accepted hits, as ob_runtime_engine's
  % apply_integrator_resets: one side-effect-free probe supplies every reset
  % signal, a triggered state returns to its initial value before the
  % committed evaluation, and fixed-step 'level' also fires when the signal
  % has just returned to zero (with ode45 it fires only while the signal is
  % nonzero, as in ob_runtime_engine apply_integrator_resets).
  lines = {};
  if (isempty (resettable)), return; endif
  lines = {'  {', ...
           '    double reset_probe[OB_VALUE_COUNT], reset_scratch[OB_STATE_STORAGE];', ...
           '    const int reset_status = ob_eval(model, time, model->state, reset_probe, 0, hit, reset_scratch);', ...
           '    if (reset_status != OB_OK) return reset_status;'};
  for j = 1:numel (resettable)
    id = resettable(j); params = parameters{id}; source = sources{id}(2);
    k = j - 1;
    lines = [lines {sprintf('    { /* Limited Integrator %s: %s reset */', strrep (labels{id}, ' ', '/'), params.reset), ...
                    sprintf('      const double signal = reset_probe[%d];', offsets(source))}];
    switch (params.reset)
      case 'level'
        fire = 'signal != 0.0';
        if (fixed_step)
          fire = sprintf ('signal != 0.0 || (model->reset_valid[%d] && model->reset_memory[%d] != 0.0)', k, k);
        endif
      case 'level hold'
        fire = 'signal != 0.0';
      otherwise
        rising = sprintf ('(model->reset_memory[%d] < 0.0 && signal >= 0.0) || (model->reset_memory[%d] == 0.0 && signal > 0.0)', k, k);
        falling = sprintf ('(model->reset_memory[%d] > 0.0 && signal <= 0.0) || (model->reset_memory[%d] == 0.0 && signal < 0.0)', k, k);
        switch (params.reset)
          case 'rising', edge = rising;
          case 'falling', edge = falling;
          otherwise, edge = [rising ' || ' falling];
        endswitch
        fire = sprintf ('model->reset_valid[%d] && (%s)', k, edge);
    endswitch
    lines = [lines {sprintf('      if (%s)', fire), ...
                    sprintf('        memcpy(model->state + %d, p%d, %d*sizeof(double));', state_offsets(id), id, sizes(id)), ...
                    sprintf('      model->reset_memory[%d] = signal;', k), ...
                    sprintf('      model->reset_valid[%d] = 1;', k), '    }'}];
  endfor
  lines{end+1} = '  }';
endfunction

function lines = delay_record_lines (delays)
  % Accepted hits record the right limit of each delayed input.
  lines = {};
  if (isempty (delays)), return; endif
  lines = {'  {', ...
           '    const int delay_status = ob_delay_record_all(model, time, model->value, 0);', ...
           '    if (delay_status != OB_OK) return delay_status;', '  }'};
endfunction

function lines = limited_integrate_lines (continuous, limited, parameters, sources, offsets, state_offsets, sizes, types)
  % RK4 with Limited Integrator saturation decided from the step's initial
  % state (ob_runtime_integrate saturation_at): a saturated component stops
  % integrating outward, a nonzero level reset holds the whole state, and
  % the result is clamped.  ob_integrate accepts the values already
  % evaluated at the step start, as the Transport Delay segment loop does.
  lines = {'static void ob_derivatives(const double *v, const unsigned char *saturated, double *dy) {', ...
           '  (void)saturated;', '  memset(dy, 0, OB_STATE_STORAGE * sizeof(double));'};
  for id = continuous
    source = sources{id};
    if (strcmp (types{id}, 'Integrator'))
      lines{end+1} = sprintf ('  memcpy(dy + %d, v + %d, %d * sizeof(double));', state_offsets(id), offsets(source), sizes(id));
      continue;
    endif
    o = state_offsets(id);
    lines = [lines {sprintf('  for (size_t i = 0; i < %d; ++i) {', sizes(id)), ...
                    sprintf('    const double rate = v[%d + i];', offsets(source(1))), ...
                    sprintf('    dy[%d + i] = ((saturated[%d + i] & 1u) && rate > 0.0) || ((saturated[%d + i] & 2u) && rate < 0.0) ? 0.0 : rate;', o, o, o), ...
                    '  }'}];
    if (any (strcmp (parameters{id}.reset, {'level', 'level hold'})))
      lines = [lines {sprintf('  if (v[%d] != 0.0)', offsets(source(2))), ...
                      sprintf('    for (size_t i = 0; i < %d; ++i) dy[%d + i] = 0.0;', sizes(id), o)}];
    endif
  endfor
  lines = [lines {'}', ...
    'static int ob_rhs(const ob_model *model, double time, const double *state, double *dy, int left, const unsigned char *saturated) {', ...
    '  double v[OB_VALUE_COUNT];', '  int status = ob_eval(model, time, state, v, left, NULL, NULL);', ...
    '  if (status != OB_OK) return status;', '  ob_derivatives(v, saturated, dy);', '  return OB_OK;', '}', ...
    'static int ob_integrate(const ob_model *model, double start, double end, double *state, const double *initial) {', ...
    '  double k1[OB_STATE_STORAGE], k2[OB_STATE_STORAGE], k3[OB_STATE_STORAGE], k4[OB_STATE_STORAGE];', ...
    '  double stage[OB_STATE_STORAGE];', '  unsigned char saturated[OB_STATE_STORAGE];', ...
    '  memset(saturated, 0, sizeof(saturated));'}];
  for id = limited
    o = state_offsets(id);
    lines = [lines {sprintf('  for (size_t i = 0; i < %d; ++i)', sizes(id)), ...
                    sprintf('    saturated[%d + i] = (unsigned char)((state[%d + i] >= hi%d[i] ? 1u : 0u) | (state[%d + i] <= lo%d[i] ? 2u : 0u));', o, o, id, o, id)}];
  endfor
  lines = [lines {'  const double h = end - start;', '  int status = OB_OK;', ...
    '  if (initial) ob_derivatives(initial, saturated, k1);', ...
    '  else { status = ob_rhs(model, start, state, k1, 0, saturated); if (status != OB_OK) return status; }', ...
    '  for (size_t i = 0; i < OB_STATE_COUNT; ++i) stage[i] = state[i] + h/2.0*k1[i];', ...
    '  status = ob_rhs(model, start + h/2.0, stage, k2, 0, saturated); if (status != OB_OK) return status;', ...
    '  for (size_t i = 0; i < OB_STATE_COUNT; ++i) stage[i] = state[i] + h/2.0*k2[i];', ...
    '  status = ob_rhs(model, start + h/2.0, stage, k3, 0, saturated); if (status != OB_OK) return status;', ...
    '  for (size_t i = 0; i < OB_STATE_COUNT; ++i) stage[i] = state[i] + h*k3[i];', ...
    '  status = ob_rhs(model, end, stage, k4, 1, saturated); if (status != OB_OK) return status;', ...
    '  for (size_t i = 0; i < OB_STATE_COUNT; ++i) state[i] += h/6.0*(k1[i] + 2.0*k2[i] + 2.0*k3[i] + k4[i]);'}];
  for id = limited
    o = state_offsets(id);
    lines = [lines {sprintf('  for (size_t i = 0; i < %d; ++i) {', sizes(id)), ...
                    sprintf('    const double clipped = state[%d + i] >= lo%d[i] ? state[%d + i] : lo%d[i];', o, id, o, id), ...
                    sprintf('    state[%d + i] = clipped <= hi%d[i] ? clipped : hi%d[i];', o, id, id), '  }'}];
  endfor
  lines = [lines {'  return OB_OK;', '}'}];
endfunction

function lines = external_declarations (external, flat, shapes, sources)
  % Tables and prototype of the host hook for Function blocks without a C
  % mapping.  Row 0 of ob_external_rows/cols is the output shape, rows
  % 1..arity the input shapes.
  count = numel (external.ids);
  arity = cellfun (@numel, sources(external.ids));
  width = max (arity) + 1;
  rows = cols = zeros (count, width);
  names = cell (1, count);
  for k = 1:count
    id = external.ids(k);
    name = flat.blocks(id).name;
    if (! ischar (name) || ! isvarname (name))
      error ('ob_codegen: Function block %d needs a function name', id);
    endif
    names{k} = ['"' name '"'];
    rows(k, 1) = external.shapes{k}(1); cols(k, 1) = external.shapes{k}(2);
    for j = 1:arity(k)
      shape = shapes{sources{id}(j)};
      rows(k, j+1) = shape(1); cols(k, j+1) = shape(2);
    endfor
  endfor
  table = @(m) strjoin (arrayfun (@(k) ['{' integer_list(m(k, :)) '}'], 1:count, 'uniformoutput', false), ',');
  lines = {'/* Function blocks without a C mapping, evaluated by the host (ob_accelerate''s', ...
           '   MEX gateway calls the Octave function): ob_external_call fills output from', ...
           '   the inputs, or returns OB_EXTERNAL_ERROR (the function failed),', ...
           '   OB_EXTERNAL_SHAPE (its result is not a real double matrix of the compiled', ...
           '   shape) or OB_EXTERNAL_NONFINITE (its result has a NaN or Inf element).', ...
           '   Not available in standalone exports. */', ...
           sprintf(['enum { OB_EXTERNAL_COUNT = %d, OB_EXTERNAL_WIDTH = %d, OB_EXTERNAL_ERROR = 8, ' ...
                    'OB_EXTERNAL_SHAPE = 9, OB_EXTERNAL_NONFINITE = 10 };'], count, width), ...
           ['static const char *const ob_external_name[OB_EXTERNAL_COUNT] = {' strjoin(names, ',') '};'], ...
           ['static const size_t ob_external_arity[OB_EXTERNAL_COUNT] = {' integer_list(arity) '};'], ...
           ['static const size_t ob_external_rows[OB_EXTERNAL_COUNT][OB_EXTERNAL_WIDTH] = {' table(rows) '};'], ...
           ['static const size_t ob_external_cols[OB_EXTERNAL_COUNT][OB_EXTERNAL_WIDTH] = {' table(cols) '};'], ...
           'static int ob_external_call(size_t index, const double *const *inputs, double *output);'};
endfunction

function o = ode45_info (continuous, types, parameters, sources, offsets, state_offsets, sizes, ...
                         options, delays, count_steps, points)
  % Continuous states and solver settings for ob_c_ode45_lines.
  entries = struct ('id', {}, 'state', {}, 'size', {}, 'source', {}, 'output', {}, ...
                    'limited', {}, 'level', {}, 'reset', {});
  for id = continuous
    limited = strcmp (types{id}, 'Limited Integrator');
    level = false; reset = 0;
    if (limited)
      level = any (strcmp (parameters{id}.reset, {'level', 'level hold'}));
      if (level), reset = offsets(sources{id}(2)); endif
    endif
    entries(end+1) = struct ('id', id, 'state', state_offsets(id), 'size', sizes(id), ...
                             'source', offsets(sources{id}(1)), 'output', offsets(id), ...
                             'limited', limited, 'level', level, 'reset', reset);
  endfor
  o = struct ('count', sum (sizes(continuous)), 'entries', entries, 'reltol', options.reltol, ...
              'abstol', options.abstol, 'maxstep', options.maxstep, 'delays', delays, ...
              'count_steps', count_steps, 'points', points);
endfunction
