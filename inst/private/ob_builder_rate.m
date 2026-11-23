function [Ts, offset] = ob_builder_rate (caller, Ts, offset)
% OB_BUILDER_RATE  Validate a builder's [Ts offset] sample-time pair.
%   [TS, OFFSET] = OB_BUILDER_RATE (CALLER, TS, OFFSET) accepts Ts = 0 (or
%   Simulink's -1) for an inherited rate, which needs OFFSET = 0, and Ts > 0
%   with 0 <= OFFSET < Ts for an explicit clock.  Returns doubles, with -1
%   mapped to 0.  Errors are prefixed with CALLER.

  validateattributes (Ts, {'numeric'}, {'scalar', 'real', 'finite'}, caller, 'Ts');
  validateattributes (offset, {'numeric'}, {'scalar', 'real', 'finite'}, caller, 'offset');
  Ts = double (Ts); offset = double (offset);
  if (Ts == -1), Ts = 0; endif
  if (Ts < 0 || (Ts == 0 && offset != 0) || (Ts > 0 && (offset < 0 || offset >= Ts)))
    error ('%s: Ts must be 0 or -1 (inherited, offset 0) or positive with 0 <= offset < Ts', caller);
  endif
endfunction
