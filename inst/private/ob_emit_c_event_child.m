function lines = ob_emit_c_event_child (u)
  % Accepted gate lifecycle and discrete samples share the root clock frame.
  % Pure flow evaluations retain its frozen primitive modes, without samples.
  lines = {};
  p = u.prefix; t = [p 'model'];
  enabled = strcmp(u.options.mode,'enabled');
  combined=ob_is_combined_mode(u.options.mode);
  extra='';if(combined),extra=',double enable';endif
  continuous_control = strcmp(u.options.control,'continuous');
  delayed = reshape(find(strcmp(u.types,'Unit Delay') | strcmp(u.types,'Discrete Integrator')),1,[]);
  emit_suspend ();
  add(sprintf('static int %sevent_process(%s *m,double time,const double *input,int major,double interval,const ob_clock_frame *frame){',p,t), ...
      '  (void)major;(void)interval;(void)input;', ...
      '  if(!frame)return OB_BAD_ARGUMENT;');
  for id = delayed
    o=u.state_offsets(id); n=u.sizes(id); source=u.sources{id};
    if (u.clock_ids(id)==0)
      add('  if(major&&interval>0.0&&!frame->reconcile){');
      if (strcmp(u.types{id},'Unit Delay'))
        add(sprintf('    memcpy(m->pending+%d,m->major_value+%d,%d*sizeof(double));',o,u.offsets(source),n));
      else
        add(sprintf('    for(size_t i=0;i<%d;++i)m->pending[%d+i]=m->state[%d+i]+interval*m->major_value[%d+i];',n,o,o,u.offsets(source)));
      endif
      add(sprintf('    for(size_t i=0;i<%d;++i)if(!isfinite(m->pending[%d+i]))return OB_NONFINITE;',n,o), ...
          sprintf('    m->pending_valid[%d]=1;}',id-1));
      due='major';
    else
      due=sprintf('frame->due[%d]',u.clock_ids(id)-1);
    endif
    add(sprintf('  if(!frame->reconcile&&(%s)&&m->pending_valid[%d]){memcpy(m->state+%d,m->pending+%d,%d*sizeof(double));m->pending_valid[%d]=0;}',due,id-1,o,o,n,id-1));
  endfor
  add(sprintf('  unsigned char hit[%d]={0};',max(1,u.n)));
  for id = reshape(find(strcmp(u.types,'Rate Transition') | strcmp(u.types,'Conditional Subsystem')),1,[])
    if (u.clock_ids(id)>0)
      condition=sprintf('frame->due[%d]',u.clock_ids(id)-1);
    else
      condition='major'; child=u.children{id};
      if (!isempty(child) && strcmp(child.options.mode,'enabled') && strcmp(child.options.control,'sampled'))
        condition=['(' condition ')||(' clock_test(child.all_clocks) ')'];
      endif
    endif
    add(sprintf('  hit[%d]=!frame->reconcile&&(%s);',id-1,condition));
  endfor
  add(sprintf('  int status=%seval(m,time,m->state,m->value,0,input,hit,m,interval,major?OB_INTERVAL_INHERITED:OB_INTERVAL_ELAPSED,frame);',p), ...
      '  if(status!=OB_OK)return status;');
  for id = delayed(u.clock_ids(delayed)>0)
    source=u.sources{id}; o=u.state_offsets(id); n=u.sizes(id);
    add(sprintf('  if(!frame->reconcile&&frame->due[%d]){',u.clock_ids(id)-1));
    if (strcmp(u.types{id},'Unit Delay'))
      add(sprintf('    memcpy(m->pending+%d,m->value+%d,%d*sizeof(double));',o,u.offsets(source),n));
    else
      add(sprintf('    for(size_t i=0;i<%d;++i)m->pending[%d+i]=m->state[%d+i]+%s*m->value[%d+i];',n,o,o,num(u.flat.sample_times(id,1)),u.offsets(source)));
    endif
    add(sprintf('    for(size_t i=0;i<%d;++i)if(!isfinite(m->pending[%d+i]))return OB_NONFINITE;',n,o), ...
        sprintf('    m->pending_valid[%d]=1;}',id-1));
  endfor
  for id = reshape(find(u.clock_ids>0),1,[])
    add(sprintf('  if(!frame->reconcile)m->tick[%d]=frame->tick[%d]+frame->due[%d];',id-1,u.clock_ids(id)-1,u.clock_ids(id)-1));
  endfor
  add('  if(major&&!frame->reconcile)memcpy(m->major_value,m->value,sizeof(m->value));', ...
      '  m->time=time;return OB_OK;}', ...
      sprintf('static int %sevent_init(%s *m,double time,const double *input,int major,const ob_clock_frame *frame){',p,t), ...
      '  memset(m->state,0,sizeof(m->state));memset(m->pending,0,sizeof(m->pending));', ...
      '  memset(m->pending_valid,0,sizeof(m->pending_valid));memset(m->value,0,sizeof(m->value));');
  for id = reshape(find(u.numeric_state),1,[])
    add(sprintf('  memcpy(m->state+%d,%sp%d,%d*sizeof(double));',u.state_offsets(id),p,id,u.sizes(id)));
  endfor
  for id = 1:u.n
    child=u.children{id};
    if (!isempty(child)), add(sprintf('  %sancestor_reset(&m->child_%d,time);',child.prefix,id)); endif
  endfor
  % Blocks sharing an Outport's buffer start from its held value.
  add (ob_conditional_c_gate (u, 'init', '!frame->reconcile&&'){:});
  add('  m->time=time;m->start_time=frame->origin;m->initialized=1;', ...
      sprintf('  int status=%sevent_process(m,time,input,major,0.0,frame);',p), ...
      '  if(status==OB_OK){memcpy(m->major_value,m->value,sizeof(m->value));}return status;}', ...
      sprintf('static int %sevent(%s *m,double time,const double *input,double control%s,double inherited_interval,ob_interval_kind interval_kind,int major,const ob_clock_frame *frame){',p,t,extra), ...
      '  (void)input;(void)inherited_interval;(void)interval_kind;(void)major;', ...
      '  if(!frame||!frame->accepted)return OB_OK;', ...
      '  if(!isfinite(time)||!isfinite(control))return OB_NONFINITE;', ...
      '  int active=0,reset=0;');
  if (enabled)
    add('  int entering=0;');
    if (continuous_control), lifecycle='1'; else lifecycle='major&&!frame->reconcile'; endif
    add(sprintf('  if(%s){',lifecycle), ...
        '    const int previous=m->was_enabled;active=control>0.0;entering=active&&!previous;', ...
        '    m->control_sign=(control>0.0)-(control<0.0);');
    if (continuous_control)
      add('    if(previous&&!active){', ...
          '      if(m->active_since_valid)m->continuous_elapsed+=fmax(0.0,time-m->active_since);', ...
          '      m->active_since_valid=0;', ...
          sprintf('      if(m->initialized)%ssuspend(m,time);}',p), ...
          '    else if(active&&(!previous||!m->active_since_valid)){m->active_since=time;m->active_since_valid=1;}');
    else
      add('    if(m->last_executed){', ...
          '      const double elapsed=time-m->last_sample;', ...
          '      if(interval_kind==OB_INTERVAL_PERIOD)m->advance_interval=inherited_interval;', ...
          '      else if(interval_kind==OB_INTERVAL_INHERITED)m->advance_interval=inherited_interval;', ...
          '      else m->advance_interval=elapsed;');
      if (u.clocked)
        add('      if(interval_kind==OB_INTERVAL_INHERITED&&inherited_interval>0.0)m->advance_interval=fmin(inherited_interval,elapsed);');
      endif
      add('    }',sprintf('    if(previous&&!active&&m->initialized)%ssuspend(m,time);',p));
    endif
    if (strcmp(u.options.states,'reset'))
      add('    reset=active&&!previous;', ...
          '    if(reset){m->continuous_elapsed=0.0;m->advance_interval=0.0;}');
    endif
    disable = ob_conditional_c_gate (u, 'disable');
    if (!isempty(disable)), add('    if(previous&&!active&&m->initialized){', disable{:}, '    }'); endif
    enable = ob_conditional_c_gate (u, 'enable');
    if (!isempty(enable)), add('    if(active){', enable{:}, '    }'); endif
    add('    m->was_enabled=active;');
    add('  }else active=m->was_enabled;', ...
        '  if(major&&!frame->reconcile){m->last_sample=time;m->last_executed=0;}');
    if (continuous_control)
      add('  if(active&&major&&!frame->reconcile){', ...
          '    m->advance_interval=m->continuous_elapsed;', ...
          '    if(m->active_since_valid)m->advance_interval+=fmax(0.0,time-m->active_since);', ...
          '    m->continuous_elapsed=0.0;m->active_since=time;m->active_since_valid=1;}');
    endif
    % OutputWhenDisabled 'reset': a port fed by inner clocks resets at one of
    % their hits while disabled, any other port at once (idempotent here).
    add('  if(!active){', ob_conditional_c_gate (u, 'reset', '!frame->reconcile&&'){:}, '    return OB_OK;}');
  else
    if (continuous_control), lifecycle='1'; else lifecycle='major&&!frame->reconcile'; endif
    add(sprintf('  if(!(%s))return OB_OK;',lifecycle));
    if(combined)
      add('  if(!isfinite(enable))return OB_NONFINITE;', ...
          '  const int enabled=enable>0.0;');
      if(strcmp(u.options.states,'reset')),add('  if(enabled&&!m->was_enabled)m->reset_pending=1;');endif
      add(sprintf('  if(!enabled&&m->was_enabled&&m->initialized)%ssuspend(m,time);',p), ...
          '  m->was_enabled=enabled;m->enable_sign=(enable>0.0)-(enable<0.0);');
      reset_lines = ob_conditional_c_gate (u, 'reset');
      if (!isempty(reset_lines)), add('  if(!enabled){', reset_lines{:}, '  }'); endif
    endif
    add('  const int sign=(control>0.0)-(control<0.0);');
    % A combined context's first evaluation records the sample without an
    % edge, as does a trigger-only one with initial_control 'compatibility'.
    if (combined || ischar(u.options.initial_control))
      add('  if(!m->trigger_seen){m->previous_sign=sign;m->last_rising=0;m->last_falling=0;m->trigger_seen=1;}');
    endif
    add( ...
        '  const int rising=(m->previous_sign<0&&sign>=0)||(m->previous_sign==0&&sign>0);', ...
        '  const int falling=(m->previous_sign>0&&sign<=0)||(m->previous_sign==0&&sign<0);');
    if (any(strcmp(u.options.mode,{'rising','enabled_rising','reset_rising'}))), active='rising&&!m->last_rising';
    elseif (any(strcmp(u.options.mode,{'falling','enabled_falling','reset_falling'}))), active='falling&&!m->last_falling';
    else active='(rising&&!m->last_rising)||(falling&&!m->last_falling)'; endif
    add(['  active=' active ';']);
    if (continuous_control)
      add('  if(sign!=m->previous_sign&&(rising||falling)){m->last_rising=rising;m->last_falling=falling;}');
    else
      add('  m->last_rising=rising;m->last_falling=falling;');
    endif
    add('  m->previous_sign=sign;m->control_sign=sign;');
    if(ob_is_resettable_mode(u.options.mode))
      add('  reset=active;active=1;', ...
          '  m->advance_interval=interval_kind==OB_INTERVAL_ELAPSED?time-m->last_sample:inherited_interval;');
    endif
    if(combined),add('  active=active&&enabled;reset=m->reset_pending;');endif
    add( ...
        '  if(!active)return OB_OK;', ...
        '  ob_clock_frame triggered=*frame;triggered.reconcile=0;frame=&triggered;', ...
        '  major=1;m->last_sample=time;m->last_executed=0;');
  endif
  if (u.input_count>0)
    add(sprintf('  for(size_t i=0;i<%d;++i)if(!isfinite(input[i]))return OB_NONFINITE;',u.input_count));
  endif
  if (enabled||ob_is_resettable_mode(u.options.mode)), interval='m->advance_interval'; else interval='time-m->time'; endif
  add('  int status;',sprintf('  if(!m->initialized||reset)status=%sevent_init(m,time,input,major&&!frame->reconcile,frame);',p));
  if (enabled && !u.needs_flow)
    % A body without flow executes only at its hits, as in ob_runtime_eval:
    % a reconcile between them (an input or Step boundary, a located
    % crossing, an accepted control change) keeps its held outputs, so it
    % does not follow an input that changed since its last hit.
    add(sprintf('  else if(major||(%s))status=%sevent_process(m,time,input,major,%s,frame);',clock_test(u.all_clocks),p,interval), ...
        '  else return OB_OK;');
  else
    add(sprintf('  else status=%sevent_process(m,time,input,major&&!frame->reconcile,%s,frame);',p,interval));
  endif
  add('  if(status!=OB_OK)return status;');
  if(combined),add('  m->reset_pending=0;');endif
  add (ob_conditional_c_gate (u, 'held', '!frame->reconcile&&'){:});
  add('  if(major&&!frame->reconcile)m->last_executed=1;');
  if (enabled)
    add(sprintf('  if(entering||(!frame->reconcile&&(major||(%s)))){++m->executions;}',clock_test(u.all_clocks)));
  else
    add('  ++m->executions;');
  endif
  add('  return OB_OK;}', ...
      sprintf('static int %sflow(%s *m,double time,const double *input,int left,const ob_clock_frame *frame){',p,t), ...
      '  (void)m;(void)time;(void)input;(void)left;(void)frame;');
  if (enabled && u.needs_flow)
    add('  if(!m->initialized||!m->was_enabled)return OB_OK;', ...
        '  ob_clock_frame frozen;const ob_clock_frame *flow_frame=frame;', ...
        '  if(frame){frozen=*frame;frozen.accepted=0;flow_frame=&frozen;}', ...
        sprintf('  int status=%seval(m,time,m->state,m->value,left,input,NULL,m,0.0,OB_INTERVAL_ELAPSED,flow_frame);',p), ...
        '  if(status!=OB_OK)return status;');
    add (ob_conditional_c_gate (u, 'flow'){:});
    add('  m->time=time;');
  endif
  add('  return OB_OK;}');

  function add (varargin), lines=[lines varargin]; endfunction

  function emit_suspend ()
    add(sprintf('static inline void %ssuspend(%s *m,double time){',p,t), '  (void)m;(void)time;');
    for id=1:u.n
      child=u.children{id};
      if (isempty(child)), continue; endif
      if (!(strcmp(child.options.mode,'enabled')||ob_is_combined_mode(child.options.mode)))
        add(sprintf('  if(m->child_%d.initialized)%ssuspend(&m->child_%d,time);',id,child.prefix,id));
        continue;
      endif
      access=sprintf('m->child_%d.',id);
      add(sprintf('  if(%sinitialized&&%swas_enabled){',access,access), ...
          sprintf('    if(%slast_executed){',access));
      if (u.flat.sample_times(id,1)>0)
        add(sprintf('      %sadvance_interval=%s;',access,num(u.flat.sample_times(id,1))));
      else
        add(sprintf('      const double interval=time-%slast_sample;',access), ...
            sprintf('      if(isfinite(interval)&&interval>0.0)%sadvance_interval=interval;',access));
      endif
      add(sprintf('      %slast_executed=0;}',access), ...
          sprintf('    if(%sactive_since_valid){%scontinuous_elapsed+=fmax(0.0,time-%sactive_since);%sactive_since_valid=0;}',access,access,access,access), ...
          sprintf('    %ssuspend(&m->child_%d,time);%swas_enabled=0;}',child.prefix,id,access));
    endfor
    add('}');
  endfunction
endfunction

function expression=clock_test(ids)
  terms=arrayfun(@(id)sprintf('frame->due[%d]',id-1),ids,'uniformoutput',false);
  if (isempty(terms)), expression='0'; else expression=strjoin(terms,'||'); endif
endfunction

function value=num(x), value=ob_c_number_list(x); endfunction
