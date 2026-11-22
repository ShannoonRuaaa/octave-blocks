function events = ob_accelerate_events (event_log, guards)
  % ob_run event records from an accelerated typed run's event log.
  %
  %   events = ob_accelerate_events (event_log, guards)
  %
  % event_log has one row per counted C record: one-based guard index, time,
  % direction, kind (1 continuous-control change, 2 plateau departure,
  % 3 located crossing) and the number of the zero-crossing search step that
  % logged it; guards is the typed exporter's inventory
  % (ob_c_event_inventory), whose public path, type, channel, side and
  % boundary complete each record.
  %
  % Within one search step the generated C records continuous-control
  % changes before plateau departures, while ob_run lists the departures
  % first (ob_integrate_events: [departures changes], then returns to
  % reconcile).  Crossings come last in both, and only in a step without
  % changes.  So the records of each step are stably ordered departures,
  % changes, crossings.  Records of different steps keep their order: a
  % change that ends step k comes before a departure found by step k + 1 at
  % the same instant, in ob_run too.
  %
  % Within a step, ob_run lists crossings in time order: a departure from an
  % exact zero at the search origin (time begin) precedes crossings located
  % at the bisected time (ob_integrate_events sorts each batch stably by
  % time).  Departures and changes all carry begin, so the time key only
  % reorders crossings; equal times keep the log (guard) order.
  count = rows (event_log);
  if (count > 1)
    rank = [2 1 3];   % kind 1, 2, 3 -> position within a step
    [unused, order] = sortrows ([event_log(:, 5) rank(event_log(:, 4))' event_log(:, 2) (1:count)']);
    event_log = event_log(order, :);
  endif
  events = struct ('time', {}, 'path', {}, 'type', {}, 'channel', {}, 'side', {}, ...
                   'direction', {}, 'boundary', {});
  for k = 1:count
    g = guards(event_log(k, 1));
    events(end+1) = struct ('time', event_log(k, 2), 'path', g.path, 'type', g.type, ...
                            'channel', g.channel, 'side', g.side, 'direction', event_log(k, 3), ...
                            'boundary', g.boundary);
  endfor
endfunction
