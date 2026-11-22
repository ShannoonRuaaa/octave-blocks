function [fig, tracefile] = ob_trace_editor_clicks (model = ob_zero_crossing_example (), tracefile = [tempname() '.mat'])
  % Diagnostic editor: preserve dispatch while recording pointer/callback state.
  if (! ischar (tracefile) || rows (tracefile) != 1 || isempty (tracefile) ...
      || any (tracefile == 0))
    error ('ob_trace_editor_clicks: supply a MAT trace file path');
  endif
  fig = octave_blocks (model);
  set (fig, 'name', 'Octave Blocks - pointer trace');
  original_down = get (fig, 'windowbuttondownfcn');
  original_up = get (fig, 'windowbuttonupfcn');
  records = repmat (capture ('init', 'after'), 1, 0);
  save ('-mat7-binary', tracefile, 'records');
  set (fig, 'windowbuttondownfcn', @(src, evt) dispatch(src,evt,original_down,'down'), ...
            'windowbuttonupfcn', @(src, evt) dispatch(src,evt,original_up,'up'));

  function dispatch (src, evt, callback, kind)
    records(end+1) = capture (kind, 'before');
    unwind_protect
      if (isa (callback, 'function_handle'))
        feval (callback, src, evt);
      elseif (iscell (callback) && ! isempty (callback))
        feval (callback{1}, src, evt, callback{2:end});
      elseif (ischar (callback) && ! isempty (callback))
        evalin ('base', callback);
      endif
    unwind_protect_cleanup
      records(end+1) = capture (kind, 'after');
      save ('-mat7-binary', tracefile, 'records');
    end_unwind_protect
  endfunction

  function entry = capture (kind, stage)
    state = guidata (fig);
    object = get (fig, 'currentobject'); object_type = ''; owner = [];
    if (! isempty (object) && isgraphics (object))
      object_type = get (object, 'type');
      if (isappdata (object, 'ob_block_id')), owner = getappdata (object, 'ob_block_id'); endif
    endif
    diagram = ob_model_at (state.model, state.path);
    xy = [[diagram.blocks.x]' [diagram.blocks.y]'];
    axes_point = get (state.axes, 'currentpoint');
    entry = struct ('kind',kind,'stage',stage,'object',object, ...
        'object_type',object_type,'owner',owner, ...
        'axes_point',axes_point,'figure_point',get(fig,'currentpoint'), ...
        'selected',state.selected,'dragging',state.dragging, ...
        'mode',state.mode,'source',state.source,'path',state.path,'model_xy',xy);
    entry.drag_origin = []; entry.drag_position = [];
    if (isfield (state, 'drag_origin')), entry.drag_origin = state.drag_origin; endif
    if (isfield (state, 'drag_position')), entry.drag_position = state.drag_position; endif
  endfunction
endfunction
