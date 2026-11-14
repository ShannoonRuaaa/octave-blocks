function edges = ob_edges (model)
  % Canonical edges: [source source_port target target_port].
  raw = model.edges;
  if (! isnumeric (raw) || ! isreal (raw) || ndims (raw) != 2 ...
      || ! any (columns (raw) == [2 4]) || any (! isfinite (raw(:))) ...
      || any (raw(:) < 1) || any (raw(:) != fix (raw(:))))
    error ("ob_edges: connections must be valid block indices/ports in an N-by-2 or N-by-4 matrix");
  endif
  if (columns (raw) == 4)
    edges = raw;
  else
    edges = zeros (rows (raw), 4);
    if (isempty(raw)), return; endif
    edges(:,[1 3]) = raw;
    edges(:,2) = 1;
    % Count each target's incoming wires in original row order. Grouping IDs
    % avoids storage proportional to the largest (possibly invalid) block ID.
    % An explicit row key preserves order without assuming a stable sort.
    [unused,unused,group] = unique (raw(:,2));
    ordinal = (1:rows(raw))';
    [unused,permutation] = sortrows ([group ordinal],[1 2]);
    sorted = group(permutation);
    starts = zeros(rows(raw),1);
    first = [true; diff(sorted)!=0];
    starts(first) = find(first);
    edges(permutation,4) = ordinal-cummax(starts)+1;
  endif
endfunction

%!test
%! raw=[9 5;2 7;8 5;1 5;4 7];
%! assert(ob_edges(struct('edges',raw)),[9 1 5 1;2 1 7 1;8 1 5 2;1 1 5 3;4 1 7 2]);
%! assert(ob_edges(struct('edges',zeros(0,2))),zeros(0,4));

%!test
%! previous=rng();
%! unwind_protect
%!   rng(319,'twister');
%!   for n=0:80
%!     raw=randi(17,n,2); expected=zeros(n,4);
%!     for k=1:n,expected(k,:)=[raw(k,1),1,raw(k,2),1+sum(raw(1:k-1,2)==raw(k,2))];endfor
%!     assert(ob_edges(struct('edges',raw)),expected);
%!   endfor
%! unwind_protect_cleanup
%!   rng(previous);
%! end_unwind_protect

%!test
%! base=uint64(2)^53; raw=[base+1 base+1;base+2 base+3;base+3 base+1];
%! expected=zeros(3,4);
%! for k=1:3,expected(k,:)=[raw(k,1),1,raw(k,2),1+sum(raw(1:k-1,2)==raw(k,2))];endfor
%! actual=ob_edges(struct('edges',raw));assert(isa(actual,'double'));assert(actual,expected);
%! raw=single([1 2;1 2]);actual=ob_edges(struct('edges',raw));
%! assert(isa(actual,'double'));assert(actual,[1 1 2 1;1 1 2 2]);

%!test
%! raw=uint64([1 1 2 1]);assert(isequal(ob_edges(struct('edges',raw)),raw));
%! fail("ob_edges(struct('edges',[1 0]))",'valid block indices');
