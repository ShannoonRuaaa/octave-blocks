function [overlaps, through] = ob_wire_overlaps (routes, edges, centers)
  % Shared wire-route checks for the editor test suites.
  %
  % OVERLAPS lists [wire wire] pairs whose horizontal or vertical segments
  % share a positive length although they carry different signals (a
  % different source block or output port). Branches of one output port may
  % share their trunk and are not reported. THROUGH lists [wire block] pairs
  % where a segment passes through the interior of a block. Every route
  % must be a polyline of horizontal and vertical segments.
  tol = 1e-9;
  segments = zeros (0, 5);  % [wire horizontal position low high]
  for k = 1:numel (routes)
    p = routes{k};
    a = p(1:end-1,:); b = p(2:end,:);
    across = abs (a(:,2)-b(:,2)) < tol;
    up = abs (a(:,1)-b(:,1)) < tol;
    assert (all (across | up), 'ob_wire_overlaps: wire %d has a diagonal segment', k);
    keep = ! (across & up);   % drop zero-length segments
    position = a(:,2); position(! across) = a(! across,1);
    low = min (a(:,1), b(:,1)); high = max (a(:,1), b(:,1));
    low(! across) = min (a(! across,2), b(! across,2));
    high(! across) = max (a(! across,2), b(! across,2));
    segments = [segments; [k*ones(sum (keep), 1) across(keep) position(keep) low(keep) high(keep)]];
  endfor
  overlaps = zeros (0, 2);
  for i = 1:rows (segments)-1
    j = (i+1:rows (segments))';
    o = segments(j,:); s = segments(i,:);
    different = any (edges(o(:,1),1:2) != edges(s(1),1:2), 2);
    hit = different & o(:,2) == s(2) & abs (o(:,3)-s(3)) < tol ...
          & min (o(:,5), s(5)) - max (o(:,4), s(4)) > tol;
    pairs = sort ([s(1)*ones(sum (hit), 1) o(hit,1)], 2);
    overlaps = [overlaps; pairs];
  endfor
  overlaps = unique (overlaps, 'rows');
  through = zeros (0, 2);
  if (nargin > 2)
    half = [.105 .052];
    for b = 1:rows (centers)
      box = [centers(b,:)-half; centers(b,:)+half];
      for i = 1:rows (segments)
        s = segments(i,:);
        if (s(2)), across = [box(1,2) box(2,2)]; along = [box(1,1) box(2,1)];
        else across = [box(1,1) box(2,1)]; along = [box(1,2) box(2,2)]; endif
        if (s(3) > across(1)+tol && s(3) < across(2)-tol ...
            && s(4) < along(2)-tol && s(5) > along(1)+tol)
          through(end+1,:) = [s(1) b];
        endif
      endfor
    endfor
    through = unique (through, 'rows');
  endif
endfunction
