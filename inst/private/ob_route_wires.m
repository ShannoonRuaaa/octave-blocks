function routes = ob_route_wires (centers, edges, inputs, outputs, routes, subset)
  % Orthogonal editor wire routes that keep different signals apart.
  %
  % ROUTES = ob_route_wires (CENTERS, EDGES, INPUTS, OUTPUTS)
  % CENTERS is an N-by-2 matrix of block centers, EDGES the canonical
  % [source source_port target target_port] connections, and INPUTS/OUTPUTS
  % the drawn port counts of each block. ROUTES is a column cell array of
  % K-by-2 polylines from each source port to its target port, made only of
  % horizontal and vertical segments.
  %
  % ROUTES = ob_route_wires (..., ROUTES, SUBSET) reroutes only the wires in
  % SUBSET around the other, unchanged routes. The editor uses this while a
  % block is dragged and routes the whole diagram again when it is dropped.
  %
  % Wires are routed one at a time in a fixed order: direct wires first,
  % then detours, each group from the shortest horizontal extent so nested
  % feedback loops keep their inner lanes. Each wire takes the cheapest
  % candidate route, scored by length and bends plus penalties for passing
  % through a block, running on or next to a segment of another signal, and
  % crossing one. Parallel segments therefore move into separate lanes, and
  % backward (feedback) wires go around blocks through free channels.
  % Branches of one output port may share their common trunk. The result
  % depends only on the arguments, so it is deterministic. Routes are
  % display geometry only and are never stored in a model.
  count = rows (edges);
  partial = nargin > 4;
  if (! partial), routes = cell (count, 1); subset = 1:count; endif
  routes = routes(:);
  if (count == 0 || isempty (subset)), return; endif
  g = geometry ();
  rect = [centers(:,1)-g.hw centers(:,1)+g.hw centers(:,2)-g.hh centers(:,2)+g.hh];
  net = edges(:,1)*(max (edges(:,2))+1) + edges(:,2);  % one id per output port
  inputs = inputs(:); outputs = outputs(:);
  start = [centers(edges(:,1),1)+g.hw ...
           centers(edges(:,1),2)+offsets(edges(:,2),outputs(edges(:,1)))];
  finish = [centers(edges(:,3),1)-g.hw ...
            centers(edges(:,3),2)+offsets(edges(:,4),inputs(edges(:,3)))];
  gap = finish(:,1) - start(:,1);
  [unused, order] = sort ((gap < 2*g.min_stub)*1e3 + abs (gap));
  wanted = false (count, 1); wanted(subset) = true;
  order = order(wanted(order))';
  % Placed segments, one row [orientation position low high signal] each
  % (orientation 0 is horizontal). The run in front of every port is
  % reserved from the start, so a lane or channel chosen for an earlier wire
  % does not block the way into or out of a later wire's port.
  used = [zeros(2*count,1) [start(:,2) start(:,1) start(:,1)+g.stub net; ...
                            finish(:,2) finish(:,1)-g.stub finish(:,1) net]];
  if (partial)
    fixed = find (! wanted);
    if (! isempty (fixed))
      % Label every point with its route (a run-length expansion).
      lengths = cellfun ("size", routes(fixed), 1);
      owner = zeros (sum (lengths), 1);
      owner(cumsum ([1; lengths(1:end-1)])) = 1;
      placed = segments (vertcat (routes{fixed}), fixed(cumsum (owner)));
      placed(:,5) = net(placed(:,5));
      used = [used; placed];
    endif
  endif
  % Block faces in the frame of a horizontal segment (row 1: across is y,
  % along is x) and of a vertical one (row 2).
  c = struct ('rect',rect,'g',g, ...
              'across',[rect(:,3)'; rect(:,1)'],'across_end',[rect(:,4)'; rect(:,2)'], ...
              'along',[rect(:,1)'; rect(:,3)'],'along_end',[rect(:,2)'; rect(:,4)']);
  for k = order
    c.used = used(used(:,5) != net(k),1:4);
    routes{k} = route_one (start(k,:), finish(k,:), c);
    placed = segments (routes{k}, k*ones (rows (routes{k}), 1));
    placed(:,5) = net(k);
    used = [used; placed];
  endfor
endfunction

function g = geometry ()
  g = struct ('hw',.105,'hh',.052, ...        % block half width and height
              'stub',.02,'min_stub',.012, ... % horizontal run at a port
              'px',.012,'py',.024, ...        % lane pitch in x and y
              'clear_y',.024, ...             % channel clearance from blocks
              'low',.01,'high',.99, ...       % channel limits inside the axes
              'lanes',6,'joint',4, ...        % candidate lanes per choice
              'length_weight',10,'bend_weight',.25,'cross_penalty',1, ...
              'near_penalty',2,'overlap_penalty',50,'block_penalty',40);
endfunction

function offset = offsets (port, count)
  % The editor's port placement (port_offset in octave_blocks.m).
  offset = zeros (size (port));
  many = count > 1;
  offset(many) = .036 - .072 * (port(many) - 1) ./ (count(many) - 1);
endfunction

function points = route_one (s, f, c)
  % The first route shape without any penalty wins; otherwise the cheapest.
  g = c.g; best = Inf; points = [s; f];
  if (f(1) - s(1) >= 2*g.min_stub || (abs (f(2)-s(2)) < 1e-12 && f(1) > s(1)))
    % Only obstacles near the box between the ports matter for these shapes.
    near = prune (c, [s(1) f(1)], [min(s(2),f(2)) max(s(2),f(2))]);
    if (abs (f(2)-s(2)) < 1e-12)
      [best, penalty] = score (s, f, zeros (0, 1), 1, near);
      if (penalty == 0), return; endif
    else
      % One vertical lane between the ports. Lanes spread out from the
      % middle of the gap, and the first candidate wins ties.
      steps = [0 reshape([-1:-1:-g.lanes; 1:g.lanes], 1, [])];
      xm = (s(1)+f(1))/2 + steps*g.px;
      xm = xm(xm >= s(1)+g.min_stub-1e-12 & xm <= f(1)-g.min_stub+1e-12)';
      [cost, penalty] = score (s, f, xm, 2, near);
      [best, at] = min (cost);
      points = [s; xm(at) s(2); xm(at) f(2); f];
      if (penalty(at) == 0), return; endif
    endif
  endif
  [cost, route] = detour (s, f, c);
  if (cost < best), points = route; endif
endfunction

function [best, points] = detour (s, f, c)
  % Five segments: out of the source, along a free channel, into the target.
  g = c.g;
  x1 = s(1) + g.stub + (0:g.lanes-1)'*g.px;
  x2 = f(1) - g.stub - (0:g.lanes-1)'*g.px;
  c = prune (c, [min(x2(end),s(1)) max(x1(end),f(1))], [-Inf Inf]);
  yc = channels (min (x1(1), x2(1)), max (x1(1), x2(1)), c);
  % The shortest exit and entry lanes first, along every channel lane.
  e = ones (numel (yc), 1);
  [cost, penalty] = score (s, f, [x1(e) x2(e) yc], 3, c);
  [best, at] = min (cost);
  choice = [x1(1) x2(1) yc(at)];
  if (penalty(at) > 0)
    % Otherwise every combination of the nearest lanes and the cheapest
    % channel lanes, in one evaluation.
    [unused, ranked] = sort (cost);
    yc = yc(ranked(1:min (g.joint, end)));
    index = (0:g.joint^2*numel (yc)-1)';
    candidates = [x1(mod (index, g.joint)+1) x2(mod (floor (index/g.joint), g.joint)+1) ...
                  yc(floor (index/g.joint^2)+1)];
    [cost, at] = min (score (s, f, candidates, 3, c));
    if (cost < best), best = cost; choice = candidates(at,:); endif
  endif
  points = [s; choice(1) s(2); choice(1:2:3); choice(2:3); choice(2) f(2); f];
endfunction

function c = prune (c, x, y)
  % Keep the blocks and segments that can touch the box X by Y (with one
  % lane pitch of margin, for the closeness penalty).
  x = [x(1)-c.g.px x(2)+c.g.px]; y = [y(1)-c.g.py y(2)+c.g.py];
  r = c.rect;
  keep = r(:,2) > x(1) & r(:,1) < x(2) & r(:,4) > y(1) & r(:,3) < y(2);
  c.rect = r(keep,:);
  c.across = c.across(:,keep); c.across_end = c.across_end(:,keep);
  c.along = c.along(:,keep); c.along_end = c.along_end(:,keep);
  u = c.used; horizontal = u(:,1) == 0;
  % Horizontal rows: position is y, extent is x; vertical rows the reverse.
  lo_x = u(:,2); hi_x = u(:,2); lo_y = u(:,3); hi_y = u(:,4);
  lo_x(horizontal) = u(horizontal,3); hi_x(horizontal) = u(horizontal,4);
  lo_y(horizontal) = u(horizontal,2); hi_y(horizontal) = u(horizontal,2);
  c.used = u(hi_x > x(1) & lo_x < x(2) & hi_y > y(1) & lo_y < y(2),:);
endfunction

function yc = channels (left, right, c)
  % Lanes in the block-free horizontal bands across [left, right]: upward
  % from above the blocks, downward from below them, and spreading from the
  % middle of every interior gap that is wide enough for a lane.
  g = c.g; r = c.rect;
  inside = r(:,2) > left - 1e-9 & r(:,1) < right + 1e-9;
  bands = [r(inside,3)-g.clear_y r(inside,4)+g.clear_y];
  if (isempty (bands)), yc = (g.low+g.high)/2; return; endif
  [unused, ranked] = sort (bands(:,1)); bands = bands(ranked,:);
  % Merge overlapping bands: a band starts a new group when it begins above
  % the highest top of every band before it.
  tops = cummax (bands(:,2));
  first = [true; bands(2:end,1) > tops(1:end-1)];
  last = [first(2:end); true];
  merged = [bands(first,1) tops(last)];
  lanes = (0:g.lanes-1)'*g.py;
  above = merged(end,2) + lanes; below = merged(1,1) - lanes;
  yc = [above(above <= g.high); below(below >= g.low)];
  for k = 1:rows (merged)-1
    low = merged(k,2); high = merged(k+1,1);
    half = min (g.lanes, floor ((high-low)/(2*g.py)));
    steps = [0 reshape([-1:-1:-half; 1:half], 1, [])]';
    yc = [yc; (low+high)/2 + steps*g.py];
  endfor
  if (isempty (yc))
    % No free band inside the axes: run along the nearest limit.
    yc = [min(g.high, merged(end,2)); max(g.low, merged(1,1))];
  endif
endfunction

function [cost, penalty] = score (s, f, p, shape, c)
  % Costs of candidate routes of one SHAPE (1 straight, 2 one vertical lane,
  % 3 detour); P has one row of lane coordinates per candidate. Segment
  % rows [orientation position low high] are stacked by place in the
  % route: all first segments, then all second segments, and so on.
  g = c.g;
  switch (shape)
    case 1
      n = 1; seg = [0 s(2) s(1) f(1)];
    case 2
      n = rows (p); e = ones (n, 1); z = zeros (n, 1);
      seg = [z s(2)*e min(s(1),p) max(s(1),p); ...
             e p min(s(2),f(2))*e max(s(2),f(2))*e; ...
             z f(2)*e min(p,f(1)) max(p,f(1))];
    case 3
      n = rows (p); e = ones (n, 1); z = zeros (n, 1);
      x1 = p(:,1); x2 = p(:,2); yc = p(:,3);
      seg = [z s(2)*e min(s(1),x1) max(s(1),x1); ...
             e x1 min(s(2),yc) max(s(2),yc); ...
             z yc min(x1,x2) max(x1,x2); ...
             e x2 min(yc,f(2)) max(yc,f(2)); ...
             z f(2)*e min(x2,f(1)) max(x2,f(1))];
  endswitch
  penalty = sum (reshape (segment_penalty (seg, c), n, []), 2);
  len = sum (reshape (seg(:,4)-seg(:,3), n, []), 2);
  cost = penalty + g.length_weight*len + g.bend_weight*(2*shape-2);
endfunction

function penalty = segment_penalty (seg, c)
  % Penalties of candidate segments [orientation position low high] for
  % blocks they pass through and for placed segments of other signals they
  % run on, run close beside, or cross.
  g = c.g; tol = 1e-9;
  o = seg(:,1); pos = seg(:,2); lo = seg(:,3); hi = seg(:,4);
  penalty = zeros (rows (seg), 1);
  if (! isempty (c.rect))
    side = o + 1;
    penalty += g.block_penalty * sum (pos > c.across(side,:)+tol & pos < c.across_end(side,:)-tol ...
                                      & lo < c.along_end(side,:)-tol & hi > c.along(side,:)+tol, 2);
  endif
  u = c.used;
  if (! isempty (u))
    parallel = o == u(:,1)';
    upos = u(:,2)'; ulo = u(:,3)'; uhi = u(:,4)';
    distance = abs (pos - upos);
    shared = parallel & min (hi, uhi) - max (lo, ulo) > tol;
    overlap = shared & distance < tol;
    pitch = g.py + (g.px-g.py)*o;
    near = shared & ! overlap & distance < pitch*(1-1e-6);
    crossing = ! parallel & upos > lo+tol & upos < hi-tol & pos > ulo+tol & pos < uhi-tol;
    penalty += g.overlap_penalty*sum (overlap, 2) + g.cross_penalty*sum (crossing, 2) ...
             + g.near_penalty*sum (near .* (1 - distance./pitch), 2);
  endif
endfunction

function seg = segments (points, owner)
  % Rows [orientation position low high owner] of the segments of one or
  % more stacked routes. OWNER labels every point with its route, and only
  % consecutive points of one route form a segment.
  a = points(1:end-1,:); b = points(2:end,:);
  same = owner(1:end-1) == owner(2:end); owner = owner(1:end-1);
  dx = abs (a(:,1)-b(:,1)) > 1e-12; dy = abs (a(:,2)-b(:,2)) > 1e-12;
  across = same & ! dy & dx; up = same & dy & ! dx;
  seg = [zeros(sum (across), 1) a(across,2) min(a(across,1),b(across,1)) ...
         max(a(across,1),b(across,1)) owner(across,1); ...
         ones(sum (up), 1) a(up,1) min(a(up,2),b(up,2)) max(a(up,2),b(up,2)) owner(up,1)];
endfunction
