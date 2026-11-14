function [current, states] = ob_algebraic_solve (model, edges, ids, current, states, time)
  % Solve simultaneous numeric outputs without evaluating lifecycle/state code.
  % Candidate evaluation uses immutable inputs, never a Gauss-Seidel update.
  shapes = cell (1, numel (ids)); counts = zeros (1, numel (ids));
  sources = cell (1, numel (ids));
  cached = isfield(model,'runtime_info') && isstruct(model.runtime_info) ...
           && isscalar(model.runtime_info) && isfield(model.runtime_info,'kind') ...
           && strcmp(model.runtime_info.kind,'octave-blocks-runtime-info-v1') ...
           && isfield(model.runtime_info,'sources') && iscell(model.runtime_info.sources) ...
           && numel(model.runtime_info.sources) == numel(model.blocks);
  for k = 1:numel (ids)
    id = ids(k); guess = states{id};
    shapes{k} = size (guess); counts(k) = numel (guess);
    if (cached), sources{k} = model.runtime_info.sources{id};
    else sources{k} = edges(edges(:, 2) == id, 1)'; endif
  endfor
  offsets = [0 cumsum(counts)];
  initial = zeros (offsets(end), 1);
  for k = 1:numel(ids), initial(offsets(k)+(1:counts(k))) = states{ids(k)}(:); endfor
  settings = optimset ('TolX', 1e-12, 'TolFun', 1e-12, 'MaxIter', 100, ...
      'MaxFunEvals', max (200, 100 * (numel(initial) + 1)), ...
      'Updating', 'off', 'AutoScaling', 'off', 'Jacobian', 'on');
  try
    [solution, unused, status] = fsolve (@residual, initial, settings);
    [error_value, unused] = residual (solution);
  catch err
    error ('ob_run: algebraic loop [%s] at time %.17g: %s', ...
           loop_description(model,ids), time, err.message);
  end_try_catch
  % A small step or trust region is not proof of a solved constraint.
  maximum = max (abs (error_value));
  if (status <= 0 || ! isfinite (maximum) || maximum > 1e-9)
    error ('ob_run: algebraic loop [%s] at time %.17g failed to converge (status %d, maximum residual %.6g)', ...
           loop_description(model,ids), time, status, maximum);
  endif
  for k = 1:numel (ids)
    accepted = reshape (solution(offsets(k) + (1:counts(k))), shapes{k});
    current{ids(k)} = states{ids(k)} = accepted;
  endfor

  function [constraint, jacobian] = residual (candidate)
    constraint = evaluate (candidate);
    if (nargout < 2), return; endif
    jacobian = zeros (numel(candidate));
    for column = 1:numel (candidate)
      perturbed = candidate;
      increment = sqrt (eps) * max (1, abs (candidate(column)));
      perturbed(column) += increment;
      jacobian(:, column) = (evaluate (perturbed) - constraint) / increment;
    endfor
    if (any (! isfinite (jacobian(:))) || rcond (jacobian) <= eps)
      error ('singular algebraic Jacobian; rescale the equations or supply another algebraic_initial');
    endif
  endfunction

  function evaluated = evaluate (candidate)
    values = current;
    for j = 1:numel (ids)
      values{ids(j)} = reshape (candidate(offsets(j) + (1:counts(j))), shapes{j});
    endfor
    evaluated = zeros (numel (candidate), 1);
    for j = 1:numel (ids)
      id = ids(j);
      output = ob_direct_output (model.blocks(id), values(sources{j}), id);
      if (! isa (output, 'double') || ! isreal (output) || issparse (output) ...
          || isempty (output) || any (! isfinite (output(:))))
        error ('block %d output must be a nonempty finite real full double matrix', id);
      endif
      if (! isequal (size (output), shapes{j}))
        error ('block %d output shape must match algebraic_initial (default scalar zero)', id);
      endif
      range = offsets(j) + (1:counts(j));
      evaluated(range) = candidate(range) - output(:);
    endfor
  endfunction
endfunction

function description = loop_description (model, ids)
  labels = cell (1, numel (ids));
  for k = 1:numel (ids)
    label = sprintf ('%d/', model.algebraic_paths{ids(k)});
    labels{k} = label(1:end-1);
  endfor
  description = strjoin (labels, ' ');
endfunction
