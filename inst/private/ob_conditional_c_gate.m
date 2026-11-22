function lines = ob_conditional_c_gate (u, part, guard = '')
  % C fragments for the Outports of one exported conditional unit, shared by
  % the sampled (ob_emit_c_conditional) and event-mode (ob_emit_c_event_child)
  % exporters so that both follow ob_refresh_conditional_outputs,
  % ob_conditional_buffers and ob_conditional_disabled_reset.  U.gating is
  % the ob_conditional_gating analysis of an enabled body with inner clocks,
  % or [] (every port then follows the body's rate).  GUARD prefixes clock
  % tests, e.g. '!frame->reconcile&&' in event mode.  PART:
  %   'init'     after the states are initialized, before the first body
  %              evaluation: a clocked block that drives an Outport directly
  %              and does not execute now starts from that Outport's held
  %              value (its real state becomes the pending capture);
  %   'held'     publish ports whose rate executes now;
  %   'flow'     publish, during flow evaluations, ports that follow the
  %              body's rate (clocked ones cannot change between hits);
  %   'disable'  the body has just been disabled: arm clocked reset ports;
  %   'reset'    while disabled: apply OutputWhenDisabled 'reset' (a shared
  %              block shows the initial output again);
  %   'enable'   the body is enabled: drop pending clocked resets.
  lines = {};
  g = u.gating; p = u.prefix;
  mask = ob_conditional_reset_ports (u.options);
  switch (part)
    case 'init'
      if (isempty (g)), return; endif
      for port = find (g.shared > 0)
        due = any_due (g.shared(port), u.clock_ids, guard);
        lines{end+1} = sprintf ('  if(!(%s)){%s}', due, substitute (u, port));
      endfor
    case {'held', 'flow'}
      for port = 1:numel (u.out_ids)
        copy = sprintf ('memcpy(m->held+%d,m->value+%d,%d*sizeof(double));', ...
                        u.out_offsets(port), u.offsets(u.out_ids(port)), u.out_sizes(port));
        if (isempty (g) || g.port_every(port)), lines{end+1} = ['  ' copy]; continue; endif
        if (strcmp (part, 'flow')), continue; endif
        lines{end+1} = sprintf ('  if(%s)%s', any_due (g.port_blocks{port}, u.clock_ids, guard), copy);
      endfor
    case 'disable'
      if (isempty (g)), return; endif
      for port = find (mask & ! g.port_every)
        lines{end+1} = sprintf ('    m->reset_due[%d]=1;', port-1);
      endfor
    case 'enable'
      if (isempty (g) || ! any (mask & ! g.port_every)), return; endif
      lines{end+1} = '    memset(m->reset_due,0,sizeof(m->reset_due));';
    case 'reset'
      for port = find (mask)
        copy = sprintf ('memcpy(m->held+%d,%sinitial+%d,%d*sizeof(double));', ...
                        u.out_offsets(port), p, u.out_offsets(port), u.out_sizes(port));
        if (isempty (g) || g.port_every(port))
          lines{end+1} = ['    ' copy];
        else
          if (g.shared(port) > 0)
            copy = [copy sprintf('if(m->initialized){%s}', substitute (u, port))];
          endif
          lines{end+1} = sprintf ('    if(m->reset_due[%d]&&(%s)){%sm->reset_due[%d]=0;}', ...
                                  port-1, any_due (g.port_blocks{port}, u.clock_ids, guard), copy, port-1);
        endif
      endfor
  endswitch
endfunction

function text = substitute (u, port)
  % The block sharing PORT's buffer shows the port's held value until it
  % next executes; a delay's next hit then outputs its real state.
  gate = u.gating.shared(port);
  o = u.state_offsets(gate); n = u.sizes(gate);
  if (n != u.out_sizes(port))
    error ('ob_codegen: Outport %d must have the shape of the block driving it', port);
  endif
  text = '';
  if (any (strcmp (u.types{gate}, {'Unit Delay', 'Discrete Integrator'})))
    text = sprintf ('if(!m->pending_valid[%d]){memcpy(m->pending+%d,m->state+%d,%d*sizeof(double));m->pending_valid[%d]=1;}', ...
                    gate-1, o, o, n, gate-1);
  endif
  text = [text sprintf('memcpy(m->state+%d,m->held+%d,%d*sizeof(double));', o, u.out_offsets(port), n)];
endfunction

function text = any_due (blocks, clock_ids, guard)
  % C test that one of the listed gates' clocks is due now.
  terms = cell (1, numel (blocks));
  for k = 1:numel (blocks)
    terms{k} = sprintf ('frame->due[%d]', clock_ids(blocks(k))-1);
  endfor
  text = strjoin (terms, '||');
  if (! isempty (guard)), text = [guard '(' text ')']; endif
endfunction
