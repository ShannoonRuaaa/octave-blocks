function [sources, proxies] = ob_c_adjacency (count, edges)
  % Index the validated execution edge table without changing its row order.
  % Incoming rows are already in target-port order. Outgoing rows retain the
  % historical proxy order used by typed conditional/multiple-output cores.
  sources = proxies = repmat ({zeros(0,1)}, 1, count);
  if (isempty(edges)), return; endif
  incoming = accumarray (edges(:,2), 1, [count 1]);
  % Execution edges are target ordered. Also support arbitrary input tables:
  % an explicit original-row key preserves order within each target/source.
  permutation = (1:rows(edges))';
  if (!issorted(edges(:,2)))
    [unused, permutation] = sortrows ([edges(:,2) permutation], [1 2]);
  endif
  sources = reshape (mat2cell(edges(permutation,1),incoming,1), 1, []);
  if (nargout > 1)
    outgoing = accumarray (edges(:,1), 1, [count 1]);
    [unused, permutation] = sortrows ([edges(:,1) (1:rows(edges))'], [1 2]);
    proxies = reshape (mat2cell(edges(permutation,2),outgoing,1), 1, []);
  endif
endfunction
