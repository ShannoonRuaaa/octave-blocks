function lines = ob_c_schedule_lines (flat, edges, offsets, state_offsets, sizes)
  % Emit event handling after ob_eval; all scheduling state belongs to instance.
  lines = {};
  types = {flat.blocks.type};
  rates = flat.sample_times;
  explicit = find (rates(:, 1)' > 0);
  discrete = find (strcmp(types, 'Unit Delay') | strcmp(types, 'Discrete Integrator'));
  if (! isempty (explicit))
    add ('static int ob_time_close(double a, double b, double origin) {', ...
         sprintf('  return isfinite(a) && isfinite(b) && fabs(a-b) <= fmin(%.17g,8.0*DBL_EPSILON*fmax(DBL_MIN,fmax(fabs(origin),fmax(fabs(a),fabs(b)))));',min(rates(explicit,1))/16), '}', ...
         'static double ob_tick_time(const ob_model *model, size_t block) {', ...
         '  return model->start_time + ob_sample_offset[block] + model->tick[block]*ob_sample_period[block];', '}');
  endif
  add ('static int ob_process_hits(ob_model *model, double time, int output, int commit_inherited) {', ...
       '  unsigned char hit[OB_BLOCK_COUNT] = {0};', ...
       '  (void)output; (void)commit_inherited;');
  for id = discrete
    if (rates(id, 1) == 0)
      add (sprintf ('  if (commit_inherited && model->pending_valid[%d]) {', id-1), ...
           sprintf ('    memcpy(model->state + %d, model->pending + %d, %d*sizeof(double));', state_offsets(id), state_offsets(id), sizes(id)), ...
           sprintf ('    model->pending_valid[%d] = 0;', id-1), '  }');
    endif
  endfor
  for id = explicit
    add (sprintf ('  if (!(time == model->start_time && ob_sample_offset[%d] > 0.0) && ob_time_close(ob_tick_time(model, %d), time, model->start_time)) {', id-1, id-1), ...
         sprintf ('    hit[%d] = 1;', id-1));
    if (any (id == discrete))
      add (sprintf ('    if (model->pending_valid[%d])', id-1), ...
           sprintf ('      memcpy(model->state + %d, model->pending + %d, %d*sizeof(double));', state_offsets(id), state_offsets(id), sizes(id)));
    endif
    add ('  }');
  endfor
  for id = find (strcmp(types, 'Rate Transition') & rates(:, 1)' == 0)
    add (sprintf ('  if (output) hit[%d] = 1;', id-1));
  endfor
  add ('  int status = ob_eval(model, time, model->state, model->value, 0, hit, model->state);', ...
       '  if (status != OB_OK) return status;');
  for id = explicit
    add (sprintf ('  if (hit[%d]) {', id-1));
    if (any (id == discrete))
      source = edges(edges(:, 2) == id, 1);
      if (strcmp (types{id}, 'Unit Delay'))
        add (sprintf ('    memcpy(model->pending + %d, model->value + %d, %d*sizeof(double));', state_offsets(id), offsets(source), sizes(id)));
      else
        add (sprintf ('    for (size_t i = 0; i < %d; ++i)', sizes(id)), ...
             sprintf ('      model->pending[%d+i] = model->state[%d+i] + ob_sample_period[%d]*model->value[%d+i];', state_offsets(id), state_offsets(id), id-1, offsets(source)));
      endif
      add (sprintf ('    model->pending_valid[%d] = 1;', id-1));
      add (sprintf ('    for (size_t i = 0; i < %d; ++i) if (!isfinite(model->pending[%d+i])) return OB_NONFINITE;', sizes(id), state_offsets(id)));
    endif
    add (sprintf ('    const double previous = ob_tick_time(model, %d);', id-1), ...
         sprintf ('    if (model->tick[%d] >= 9007199254740991.0) return OB_BAD_ARGUMENT;', id-1), ...
         sprintf ('    model->tick[%d] += 1.0;', id-1), ...
         sprintf ('    const double next = ob_tick_time(model, %d);', id-1), ...
         '    if (!isfinite(next) || next <= previous || next <= time) return OB_BAD_ARGUMENT;', '  }');
  endfor
  add ('  model->time = time;', '  return OB_OK;', '}');

  function add (varargin)
    lines = [lines varargin];
  endfunction
endfunction
