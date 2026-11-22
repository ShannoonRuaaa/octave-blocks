function runtime = ob_restore_reset_children (runtime, previous)
  % An ancestor reset rebuilt this runtime from fresh conditional states.
  % Enabled and combined descendants keep their whole context: their own
  % enable policy applies at the next accepted activation, and a combined
  % trigger history is neither reset nor re-armed for a first evaluation.
  % Other triggered descendants restart states and trigger history (lazily,
  % through reset_seed) but keep their held outputs, as Simulink does.  With
  % initial_control 'compatibility' they keep their trigger history instead,
  % including a pending first evaluation and the edge flags: Simulink 26.2
  % neither re-arms the no-trigger rule nor restarts from zero (the D, E and
  % V4 probes), and a rise into zero before the reset followed by a positive
  % sample after it does not fire again (the F probes).
  ids = reshape(find(strcmp(runtime.types,'Conditional Subsystem')),1,[]);
  history = {'previous_sign','control_sign','last_rising','last_falling','trigger_seen'};
  for id = ids
    old = previous.states{id};
    options = ob_runtime_execution(runtime.model,id).options;
    enabled = strcmp(options.mode,'enabled') || ob_is_combined_mode(options.mode);
    seen = isfield(old,'trigger_seen') && old.trigger_seen;
    if (enabled && (old.initialized || isfield(old,'reset_seed') || seen))
      runtime.states{id} = old;
      continue;
    elseif (old.initialized)
      runtime.states{id}.reset_seed = old.child;
      runtime.states{id} = keep_outputs (runtime.states{id}, old);
    elseif (isfield(old,'reset_seed'))
      runtime.states{id}.reset_seed = old.reset_seed;
      runtime.states{id} = keep_outputs (runtime.states{id}, old);
    endif
    if (!enabled && ischar(options.initial_control))
      for field = history(isfield(old,history))
        runtime.states{id}.(field{1}) = old.(field{1});
      endfor
    endif
  endfor
endfunction

function state = keep_outputs (state, old)
  % Held outputs survive, with any initial output already broadcast to its
  % port's shape (ob_refresh_conditional_outputs).
  state.outputs = old.outputs;
  for field = {'initial_outputs', 'output_shaped', 'shapes_probed'}
    if (isfield (old, field{1})), state.(field{1}) = old.(field{1}); endif
  endfor
endfunction
