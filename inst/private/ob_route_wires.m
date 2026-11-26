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
  % Branches of one output port may share their common trunk. A wire with a
  % port inside another block (blocks drawn over each other) cannot avoid
  % that block and takes its plain shape without a search. The result
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
  start = [rect(edges(:,1),2) centers(edges(:,1),2)+offsets(edges(:,2),outputs(edges(:,1)))];
  finish = [rect(edges(:,3),1) centers(edges(:,3),2)+offsets(edges(:,4),inputs(edges(:,3)))];
  gap = finish(:,1) - start(:,1);
  [unused, order] = sort ((gap < 2*g.min_stub)*1e3 + abs (gap));
  wanted = false (count, 1); wanted(subset) = true;
  order = order(wanted(order))';
  % Wires with a port strictly inside another block.
  tol = 1e-9; ports = [start(order,:); finish(order,:)];
  buried = false (count, 1);
  inside = any (ports(:,1) > rect(:,1)'+tol & ports(:,1) < rect(:,2)'-tol ...
                & ports(:,2) > rect(:,3)'+tol & ports(:,2) < rect(:,4)'-tol, 2);
  buried(order) = inside(1:numel (order)) | inside(numel (order)+1:end);
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
  % The x-extent of every placed segment, for finding the nearby ones.
  [xlo, xhi] = x_extent (used);
  reach = g.stub + g.lanes*g.px;
  for k = order
    s = start(k,:); f = finish(k,:);
    if (buried(k))
      routes{k} = plain (s, f, g);
    else
      % Only blocks and segments across the widest candidate matter.
      left = min (s(1), f(1)-reach); right = max (f(1), s(1)+reach);
      near = used(:,5) != net(k) & xhi > left & xlo < right;
      inside = rect(:,2) > left & rect(:,1) < right;
      routes{k} = route_one (s, f, rect(inside,:), used(near,1:4)', g, ! partial);
    endif
    placed = segments (routes{k}, net(k)*ones (rows (routes{k}), 1));
    [lo, hi] = x_extent (placed);
    used = [used; placed]; xlo = [xlo; lo]; xhi = [xhi; hi];
  endfor
endfunction

function g = geometry ()
  g = struct ('hw',.105,'hh',.052, ...        % block half width and height
              'stub',.02,'min_stub',.012, ... % horizontal run at a port
              'px',.012,'py',.024, ...        % lane pitch in x and y
              'clear_y',.024, ...             % channel clearance from blocks
              'low',.01,'high',.99, ...       % channel limits inside the axes
              'lanes',6,'joint',4);           % candidate lanes per choice
endfunction

function offset = offsets (port, count)
  % The editor's port placement (port_offset in octave_blocks.m).
  offset = zeros (size (port));
  many = count > 1;
  offset(many) = .036 - .072 * (port(many) - 1) ./ (count(many) - 1);
endfunction

function [lo, hi] = x_extent (seg)
  vertical = seg(:,1) == 1;
  lo = seg(:,3); hi = seg(:,4);
  lo(vertical) = seg(vertical,2); hi(vertical) = seg(vertical,2);
endfunction

function F = faces (r, tol)
  % Block faces, shrunk by TOL, in the frame of a horizontal segment (odd
  % rows: across is y, along is x) and of a vertical one (even rows), in the
  % order across low, across high, along low, along high.
  F = [r(:,3)'+tol; r(:,1)'+tol; r(:,4)'-tol; r(:,2)'-tol; ...
       r(:,1)'+tol; r(:,3)'+tol; r(:,2)'-tol; r(:,4)'-tol];
endfunction

function points = plain (s, f, g)
  % The shape without a lane search: straight, one bend lane in the middle
  % of the gap, or a detour just above both ports' blocks.
  if (abs (f(2)-s(2)) < 1e-12 && f(1) > s(1))
    points = [s; f];
  elseif (f(1) - s(1) >= 2*g.min_stub)
    xm = (s(1)+f(1))/2; points = [s; xm s(2); xm f(2); f];
  else
    x1 = s(1) + g.stub; x2 = f(1) - g.stub; yc = max (s(2), f(2)) + g.hh + g.clear_y;
    points = [s; x1 s(2); x1 yc; x2 yc; x2 f(2); f];
  endif
endfunction

function points = route_one (s, f, R, U, g, thorough)
  % The first route shape without any penalty wins; otherwise the cheapest.
  % R holds the nearby blocks and U the nearby segments of other signals,
  % one column [orientation position low high] each. Without THOROUGH (while
  % a block is dragged) a detour keeps its shortest exit and entry lanes.
  best = Inf; points = [s; f]; F = faces (R, 1e-9);
  if (abs (f(2)-s(2)) < 1e-12 && f(1) > s(1))
    [best, penalty] = score (s, f, zeros (0, 1), 1, F, U);
    if (penalty == 0), return; endif
  elseif (f(1) - s(1) >= 2*g.min_stub)
    % One vertical lane between the ports. Lanes spread out from the middle
    % of the gap, and the first candidate wins ties.
    steps = [0 reshape([-1:-1:-g.lanes; 1:g.lanes], 1, [])];
    xm = (s(1)+f(1))/2 + steps*g.px;
    xm = xm(xm >= s(1)+g.min_stub-1e-12 & xm <= f(1)-g.min_stub+1e-12)';
    [cost, penalty] = score (s, f, xm, 2, F, U);
    [best, at] = min (cost);
    points = [s; xm(at) s(2); xm(at) f(2); f];
    if (penalty(at) == 0), return; endif
  endif
  % Five segments: out of the source, along a free channel, into the target.
  x1 = s(1) + g.stub + (0:g.lanes-1)'*g.px;
  x2 = f(1) - g.stub - (0:g.lanes-1)'*g.px;
  yc = channels (min (x1(1), x2(1)), max (x1(1), x2(1)), R, g);
  % The shortest exit and entry lanes first, along every channel lane.
  e = ones (numel (yc), 1);
  [cost, penalty] = score (s, f, [x1(e) x2(e) yc], 3, F, U);
  [detour, at] = min (cost);
  choice = [x1(1) x2(1) yc(at)];
  if (penalty(at) > 0 && thorough)
    % Otherwise every combination of the nearest lanes and the cheapest
    % channel lanes, in one evaluation, against what lies in their height.
    [unused, ranked] = sort (cost);
    yc = yc(ranked(1:min (g.joint, end)));
    low = min ([yc; s(2); f(2)]) - g.py; high = max ([yc; s(2); f(2)]) + g.py;
    F = F(:,R(:,4) > low & R(:,3) < high);
    U = U(:,(U(1,:) == 0 & U(2,:) > low & U(2,:) < high) | (U(1,:) == 1 & U(4,:) > low & U(3,:) < high));
    index = (0:g.joint^2*numel (yc)-1)';
    candidates = [x1(mod (index, g.joint)+1) x2(mod (floor (index/g.joint), g.joint)+1) ...
                  yc(floor (index/g.joint^2)+1)];
    [cost, at] = min (score (s, f, candidates, 3, F, U));
    if (cost < detour), detour = cost; choice = candidates(at,:); endif
  endif
  if (detour < best)
    points = [s; choice(1) s(2); choice(1:2:3); choice(2:3); choice(2) f(2); f];
  endif
endfunction

function yc = channels (left, right, rect, g)
  % Lanes in the block-free horizontal bands across [left, right]: upward
  % from above the blocks, downward from below them, and spreading from the
  % middle of every interior gap that is wide enough for a lane.
  inside = rect(:,2) > left - 1e-9 & rect(:,1) < right + 1e-9;
  bands = [rect(inside,3)-g.clear_y rect(inside,4)+g.clear_y];
  if (isempty (bands)), yc = (g.low+g.high)/2; return; endif
  [unused, ranked] = sort (bands(:,1)); bands = bands(ranked,:);
  % Merge overlapping bands: a band starts a new group when it begins above
  % the highest top of every band before it.
  tops = cummax (bands(:,2));
  first = [true; bands(2:end,1) > tops(1:end-1)];
  merged = [bands(first,1) tops([first(2:end); true])];
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

function [cost, penalty] = score (s, f, p, shape, F, U)
  % Costs of candidate routes of one SHAPE (1 straight, 2 one vertical lane,
  % 3 detour); P has one row of lane coordinates per candidate. Segment
  % rows [orientation position low high] are stacked by place in the
  % route: all first segments, then all second segments, and so on.
  %
  % Cost: 10 per unit of length and .25 per bend, plus 40 for each block a
  % segment passes through, 50 for running on a segment of another signal,
  % up to 2 for running closer than a lane pitch beside one, and 1 for
  % crossing one.
  switch (shape)
    case 1
      n = 1; seg = [0 s(2) s(1) f(1)];
    case 2
      n = rows (p); e = ones (n, 1); z = zeros (n, 1);
      seg = [z s(2)*e s(1)*e p; e p min(s(2),f(2))*e max(s(2),f(2))*e; z f(2)*e p f(1)*e];
    case 3
      n = rows (p); e = ones (n, 1); z = zeros (n, 1);
      x1 = p(:,1); x2 = p(:,2); yc = p(:,3);
      seg = [z s(2)*e s(1)*e x1; e x1 min(s(2),yc) max(s(2),yc); ...
             z yc min(x1,x2) max(x1,x2); e x2 min(yc,f(2)) max(yc,f(2)); ...
             z f(2)*e x2 f(1)*e];
  endswitch
  o = seg(:,1); pos = seg(:,2); lo = seg(:,3); hi = seg(:,4);
  side = o + 1;
  penalty = 40*sum (pos > F(side,:) & pos < F(side+2,:) & lo < F(side+6,:) & hi > F(side+4,:), 2);
  if (! isempty (U))
    tol = 1e-9;
    parallel = o == U(1,:);
    distance = abs (pos - U(2,:));
    shared = parallel & min (hi, U(4,:)) - max (lo, U(3,:)) > tol;
    pitch = .024 - .012*o;
    close = shared & distance < pitch - tol;
    crossing = ! parallel & U(2,:) > lo+tol & U(2,:) < hi-tol & pos > U(3,:)+tol & pos < U(4,:)-tol;
    penalty += 50*sum (close & distance < tol, 2) + sum (crossing, 2) ...
             + 2*sum (close .* (1 - distance./pitch), 2);
  endif
  penalty = sum (reshape (penalty, n, []), 2);
  cost = penalty + 10*sum (reshape (hi-lo, n, []), 2) + .5*(shape-1);
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
