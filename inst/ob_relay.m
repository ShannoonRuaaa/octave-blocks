function model = ob_relay (switch_on = 1, switch_off = -1, out_on = 1, out_off = 0, Ts = 0.1, offset = 0)
% OB_RELAY  Build a Simulink-style Relay (hysteresis switch) subsystem.
%   MODEL = OB_RELAY(ON_PT, OFF_PT, OUT_ON, OUT_OFF[, Ts[, OFFSET]])
%   switches output to OUT_ON when u >= ON_PT and holds it until u < OFF_PT,
%   then switches to OUT_OFF and holds it until u >= ON_PT.
%   Set Ts = 0 for inherited sample time or Ts > 0 for an explicit clock.
%   Built from native primitives (Switch + Unit Delay) for full Octave and
%   strict C99 ob_codegen parity.
%
%   Reference:
%     https://www.mathworks.com/help/simulink/slref/relay.html

  if (nargin > 6)
    error ('ob_relay: at most 6 arguments (switch_on, switch_off, out_on, out_off, Ts, offset)');
  endif
  for value = {switch_on,switch_off,out_on,out_off,Ts,offset}
    validateattributes (value{1}, {'numeric'}, {'scalar','real','finite'});
  endfor
  switch_on = double (switch_on); switch_off = double (switch_off);
  out_on = double (out_on); out_off = double (out_off);
  Ts = double (Ts); offset = double (offset);
  if (switch_off > switch_on)
    error ('ob_relay: switch_off must be <= switch_on');
  endif
  if (Ts < 0 || (Ts > 0 && (offset < 0 || offset >= Ts)) || (Ts == 0 && offset != 0))
    error ('ob_relay: invalid Ts/offset');
  endif

  % State s in {0, 1} stored in Unit Delay (initial state = 0 => off):
  %   If u >= switch_on:  s_next = 1
  %   Else if u >= switch_off: s_next = s_prev
  %   Else: s_next = 0
  %   y = (s_next >= 0.5) ? out_on : out_off
  blocks = struct ( ...
    'type',  {'Inport', 'Constant', 'Constant', 'Unit Delay', 'Switch', 'Switch', 'Constant', 'Constant', 'Switch', 'Outport'}, ...
    'value', {1, 1, 0, 0, switch_off, switch_on, out_on, out_off, 0.5, 1}, ...
    'name',  {'u', 'One', 'Zero', 'State', 'OffCheck', 'OnCheck', 'OutOn', 'OutOff', 'OutMap', 'y'}, ...
    'x',     {0.06, 0.20, 0.20, 0.36, 0.42, 0.58, 0.68, 0.68, 0.80, 0.94}, ...
    'y',     {0.50, 0.85, 0.15, 0.35, 0.35, 0.60, 0.82, 0.22, 0.50, 0.50});
  edges = [4 1 5 1; ... % OffCheck: u >= switch_off ? State : 0
           1 1 5 2; ...
           3 1 5 3; ...
           2 1 6 1; ... % OnCheck:  u >= switch_on  ? 1 : OffCheck
           1 1 6 2; ...
           5 1 6 3; ...
           6 1 4 1; ... % State <- OnCheck
           7 1 9 1; ... % OutMap:   OnCheck >= 0.5 ? OutOn : OutOff
           6 1 9 2; ...
           8 1 9 3; ...
           9 1 10 1];
  model = struct ('blocks', blocks, 'edges', edges, ...
                  'execution', struct ('mode', 'virtual'));
  if (Ts > 0)
    rates = zeros (numel (blocks), 2);
    rates(4, :) = [Ts, offset];
    model.sample_times = rates;
  endif
  model = ob_hold_builder_output (model, 10, out_off, [Ts offset]);
endfunction
