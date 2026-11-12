function measurements = benchmark_ob_editor_ui (counts = [10 40], clicks = 8)
  % Measure the actual editor selection/mouse-up callbacks on hidden Qt figures.
  if (!any(strcmp(available_graphics_toolkits(),'qt')))
    error ('benchmark_ob_editor_ui: run this benchmark in the Octave GUI runtime with Qt available');
  endif
  graphics_toolkit ('qt');
  previous = get (0, 'defaultfigurevisible');
  set (0, 'defaultfigurevisible', 'off');
  measurements = struct ('blocks', {}, 'clicks', {}, 'seconds', {}, 'per_click', {});
  unwind_protect
    for count = counts
      model = editor_chain (count);
      fig = octave_blocks (model);
      unwind_protect
        drawnow ();
        elapsed = tic ();
        for k = 1:clicks
          state = guidata (fig);
          patches = findall (state.axes, 'type', 'patch');
          callbacks = get (patches, 'buttondownfcn');
          if (!iscell(callbacks)), callbacks = {callbacks}; endif
          selectable = find (!cellfun(@isempty,callbacks));
          selected = selectable(1 + mod(k-1,numel(selectable)));
          feval (callbacks{selected}, patches(selected), []);
          feval (get(fig,'windowbuttonupfcn'), fig, []);
          drawnow ();
        endfor
        seconds = toc (elapsed);
        measurements(end+1) = struct ('blocks',count,'clicks',clicks, ...
            'seconds',seconds,'per_click',seconds/clicks);
        fprintf ('%d blocks: %d clicks %.6f seconds, %.6f seconds/click\n',count,clicks,seconds,seconds/clicks);
      unwind_protect_cleanup
        if (isgraphics(fig)), delete(fig); endif
      end_unwind_protect
    endfor
  unwind_protect_cleanup
    set (0, 'defaultfigurevisible', previous);
  end_unwind_protect
endfunction

function model = editor_chain (count)
  model = ob_example ();
  model.blocks = repmat (model.blocks(2),1,count);
  model.blocks(1).type = 'Constant'; model.blocks(1).value = 1;
  model.blocks(end).type = 'Scope'; model.blocks(end).value = [];
  for id = 1:count
    model.blocks(id).x = .12 + .19 * mod(id-1,5);
    model.blocks(id).y = .9 - .12 * floor((id-1)/5);
  endfor
  model.edges = [(1:count-1)' (2:count)'];
endfunction
