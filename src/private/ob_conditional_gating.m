function gating = ob_conditional_gating (types, rates, edges, out_blocks)
  % When the numbered Outports of an enabled body with inner clocks take new
  % values, and which clocked blocks share an Outport's buffer.  Simulink
  % runs each Outport at the sample time it inherits from its source, so it
  % copies a new value only when a block driving it executes
  % (simulink-conditional-outputs-reference.json,
  % simulink-inner-clocks-reference.json).  A clocked block that drives an
  % Outport directly writes into that Outport's buffer: until the block
  % executes after the body is (re)initialized, and again after the Outport
  % is reset while disabled, every reader sees the Outport's held value
  % (gating_*: fast+slow is -1 + -9 = -10 at the 0.375 activation, and
  % 0.75 + -9 = -8.25 after the slow port was reset at 1.0).  The analysis
  % is shared by the Octave runtime (ob_conditional_buffers,
  % ob_refresh_conditional_outputs) and the C exporters
  % (ob_conditional_c_gate), so both apply the same rule.
  %
  % TYPES, RATES ([period offset] rows) and EDGES describe one compiled
  % body; OUT_BLOCKS(p) is the compiled block whose value numbered Outport p
  % publishes.  Result fields:
  %   clocked      Unit Delays, Discrete Integrators and Rate Transitions
  %                with their own period ("gates");
  %   port_blocks  per port, the gates reached backward from it through
  %                blocks without a period of their own (row vectors);
  %   port_every   per port, true when some path instead ends at a source
  %                that may change at every evaluation of the body (Inport,
  %                Time, Constant, Integrator, inherited state, nested
  %                conditional output, ...); such a port follows the body's
  %                own execution rate;
  %   shared       per port, the gate that drives it directly (through
  %                Outport/Inport copies only), or 0.  A gate driving
  %                several ports shares the lowest-numbered one's buffer;
  %   buffer_port  per block, the port whose buffer the gate shares, or 0.
  n = numel (types);
  rates = double (rates);
  stateful = strcmp (types, 'Unit Delay') | strcmp (types, 'Discrete Integrator');
  transitions = strcmp (types, 'Rate Transition');
  clocked = (stateful | transitions) & reshape (rates(:, 1), 1, []) > 0;
  % Terminal sources: their value does not follow their inputs within one
  % evaluation, or they have no inputs.  An inherited Rate Transition is a
  % sample of its input at the body's rate, so the walk continues through it.
  terminal = (stateful & ! clocked) ...
             | ismember (types, {'Integrator', 'Limited Integrator', 'Transport Delay', ...
                                 'Conditional Subsystem', 'Conditional Output'});
  % EDGES may be full [source port target port] rows or the two-column
  % [source target] rows of ob_execution_order, already in target-port order.
  if (columns (edges) == 4), edges = sortrows (edges, [3 4])(:, [1 3]); endif
  sources = cell (1, n);
  for k = 1:rows (edges)
    sources{edges(k, 2)}(end+1) = edges(k, 1);
  endfor
  memo_blocks = cell (1, n); memo_every = false (1, n); state = zeros (1, n);
  count = numel (out_blocks);
  gating.clocked = clocked;
  gating.port_blocks = cell (1, count);
  gating.port_every = false (1, count);
  gating.shared = zeros (1, count);
  gating.buffer_port = zeros (1, n);
  for p = 1:count
    [gating.port_blocks{p}, gating.port_every(p)] = walk (out_blocks(p));
    % The block that writes this port's buffer: follow plain copies.
    b = out_blocks(p);
    while (any (strcmp (types{b}, {'Outport', 'Inport'})) && isscalar (sources{b}))
      b = sources{b};
    endwhile
    if (clocked(b) && gating.buffer_port(b) == 0)
      gating.shared(p) = b; gating.buffer_port(b) = p;
    endif
  endfor

  function [blocks, every] = walk (b)
    % Gates and the "every evaluation" flag behind block B (memoized; a
    % block met again on the current path contributes nothing, which keeps
    % algebraic loops finite).
    if (state(b) == 2), blocks = memo_blocks{b}; every = memo_every(b); return; endif
    if (state(b) == 1), blocks = zeros (1, 0); every = false; return; endif
    if (clocked(b))
      blocks = b; every = false;
    elseif (terminal(b) || isempty (sources{b}))
      blocks = zeros (1, 0); every = true;
    else
      state(b) = 1;
      blocks = zeros (1, 0); every = false;
      for s = sources{b}
        [more, e] = walk (s);
        blocks = union (blocks, more); every |= e;
      endfor
      blocks = reshape (blocks, 1, []);
    endif
    state(b) = 2; memo_blocks{b} = blocks; memo_every(b) = every;
  endfunction
endfunction
