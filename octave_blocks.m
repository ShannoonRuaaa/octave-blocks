function fig = octave_blocks (initial_model = ob_example ())
  ob_validate_model (initial_model);
  % Small Simulink-style editor whose execution engine is GNU Octave.
  fig = figure ("name", "Octave Blocks", "numbertitle", "off", ...
                "menubar", "none", "position", [120 100 1100 650], ...
                "closerequestfcn", @(src, evt) ob_close (src), ...
                "windowbuttondownfcn", @ob_pointer_select, ...
                "windowbuttonmotionfcn", @(src, evt) ob_drag (src), ...
                "windowbuttonupfcn", @(src, evt) ob_stop_drag (src));
  ax = axes ("parent", fig, "position", [0.04 0.08 0.92 0.48], ...
             "xlim", [0 1], "ylim", [0 1], "xtick", [], "ytick", []);
  types = {"Constant", "Time", "Step", "Gain", "Sum", "Product", ...
           "Unit Delay", "Integrator", "Discrete Integrator", "Function", "Scope"};
  button_labels = {"Constant", "Time", "Step", "Gain", "Sum", "Product", ...
                   "Delay", "Integrator", "Discrete Int.", "Function", "Scope"};
  for k = 1:numel (types)
    uicontrol (fig, "style", "pushbutton", "string", button_labels{k}, ...
               "units", "normalized", "position", [0.01+(k-1)*0.09 0.92 0.086 0.06], ...
               "callback", @(src, evt) ob_action (src, "add", types{k}));
  endfor
  labels = {"Connect", "Disconnect", "Edit", "Settings", "Run", ...
            "Save", "Load", "Delete", "Oscillator"};
  actions = {"connect", "disconnect", "edit", "settings", "run", ...
             "save", "load", "delete", "example"};
  for k = 1:numel (labels)
    uicontrol (fig, "style", "pushbutton", "string", labels{k}, ...
               "units", "normalized", "position", [0.01+(k-1)*0.109 0.84 0.105 0.06], ...
               "callback", @(src, evt) ob_action (src, actions{k}, ""));
  endfor
  for k = 1:3
    history_labels = {"New", "Undo", "Redo"};
    history_actions = {"new", "undo", "redo"};
    uicontrol (fig, "style", "pushbutton", "string", history_labels{k}, ...
               "units", "normalized", "position", [0.01+(k-1)*0.109 0.76 0.105 0.06], ...
               "callback", @(src, evt) ob_action (src, history_actions{k}, ""));
  endfor
  subsystem_labels = {"Subsystem", "Inport", "Outport", "Enter", "Up", "Nested demo", ...
                      "Export C", "Inputs", "Input demo"};
  subsystem_actions = {"add", "add", "add", "enter", "up", "example_nested", ...
                       "export_c", "inputs", "example_inputs"};
  subsystem_data = {"Subsystem", "Inport", "Outport", "", "", "", "", "", ""};
  for k = 1:numel (subsystem_labels)
    uicontrol (fig, "style", "pushbutton", "string", subsystem_labels{k}, ...
               "units", "normalized", "position", [0.01+(k-1)*0.109 0.68 0.105 0.06], ...
               "callback", @(src, evt) ob_action (src, subsystem_actions{k}, subsystem_data{k}));
  endfor
  rate_labels = {"Rate Transition", "Sample time", "Rate demo", "Saturation", ...
                 "Dead Zone", "Switch", "Control demo"};
  rate_actions = {"add", "sample_time", "example_multirate", "add", "add", "add", "example_control"};
  rate_data = {"Rate Transition", "", "", "Saturation", "Dead Zone", "Switch", ""};
  for k = 1:numel (rate_labels)
    uicontrol (fig, "style", "pushbutton", "string", rate_labels{k}, ...
               "units", "normalized", "position", [0.01+(k-1)*0.14 0.60 0.136 0.06], ...
               "callback", @(src, evt) ob_action (src, rate_actions{k}, rate_data{k}));
  endfor
  status = uicontrol (fig, "style", "text", "units", "normalized", ...
                      "position", [0.35 0.76 0.63 0.055], ...
                      "horizontalalignment", "left");
  state = struct ("model", initial_model, "selected", 0, ...
                  "mode", "select", "source", 0, "axes", ax, ...
                  "dragging", false, "config", [0 10 0.1], "status", status);
  state.undo = {}; state.redo = {};
  state.options = ob_solver_options ();
  state.path = [];
  state.saved = ob_snapshot (state);
  guidata (fig, state);
  ob_draw (fig);
endfunction

function ob_action (src, action, data)
  fig = ancestor (src, "figure");
  state = guidata (fig);
  before = ob_snapshot (state);
  diagram = ob_model_at (state.model, state.path);
  switch (action)
    case "enter"
      if (state.selected < 1 || ! strcmp (diagram.blocks(state.selected).type, "Subsystem"))
        errordlg ("Select a Subsystem block first."); return;
      endif
      state.path(end + 1) = state.selected;
      state.selected = 0; state.mode = "select"; state.source = 0; state.dragging = false;
    case "up"
      if (isempty (state.path)), return; endif
      selected = state.path(end); state.path(end) = [];
      state.selected = selected; state.mode = "select"; state.source = 0; state.dragging = false;
    case "new"
      if (! ob_discard (state)), return; endif
      state.path = [];
      empty_blocks = struct ("type", {}, "value", {}, "name", {}, "x", {}, "y", {});
      state.model = struct ("blocks", empty_blocks, "edges", zeros (0, 2));
      state.selected = 0; state.mode = "select"; state.source = 0;
    case {"undo", "redo"}
      if (isempty (state.(action))), return; endif
      if (strcmp (action, "undo")), other = "redo"; else other = "undo"; endif
      state.(other){end + 1} = before;
      previous = state.(action){end}; state.(action)(end) = [];
      state.model = previous.model; state.config = previous.config;
      state.options = previous.options;
      state.path = [];
      state.selected = 0; state.mode = "select"; state.source = 0;
    case "add"
      block = struct ("type", data, "value", [], "name", data, ...
                      "x", 0.18 + 0.14 * mod (numel (diagram.blocks), 5), ...
                      "y", 0.77 - 0.17 * mod (floor (numel (diagram.blocks) / 5), 5));
      if (strcmp (data, "Subsystem"))
        block.value = ob_subsystem_template ();
      elseif (any (strcmp (data, {"Inport", "Outport"})))
        ids = find (strcmp ({diagram.blocks.type}, data));
        block.value = numel (ids) + 1;
      endif
      if (strcmp (data, "Constant") || strcmp (data, "Gain") ...
          || strcmp (data, "Unit Delay") || strcmp (data, "Integrator") ...
          || strcmp (data, "Discrete Integrator") ...
          || strcmp (data, "Rate Transition") ...
          || any (strcmp (data, {"Saturation", "Dead Zone", "Switch"})) ...
          || strcmp (data, "Step"))
        default_text = "1";
        if (strcmp (data, "Unit Delay") || strcmp (data, "Integrator") ...
            || strcmp (data, "Discrete Integrator"))
          default_text = "0";
        elseif (strcmp (data, "Step"))
          default_text = "[1 0 1]";
        endif
        if (strcmp (data, "Rate Transition")), default_text = "0"; endif
        if (any (strcmp (data, {"Saturation", "Dead Zone"}))), default_text = "[-1 1]"; endif
        if (strcmp (data, "Switch")), default_text = "0"; endif
        prompt_text = sprintf ("Octave expression for %s:", data);
        if (any (strcmp (data, {"Saturation", "Dead Zone", "Switch"})))
          prompt_text = ob_control_prompt (data);
        endif
        prompt = {prompt_text};
        defaults = {default_text};
        answer = inputdlg (prompt, "Block value", 1, defaults);
        if (isempty (answer)), return; endif
        try
          block.value = evalin ("base", answer{1});
          ob_validate_control_parameter (data, block.value);
        catch err
          errordlg (err.message, "Invalid Octave expression"); return;
        end_try_catch
      elseif (strcmp (data, "Function"))
        answer = inputdlg ({"Octave function name on the path:", "Number of outputs (positive integer):"}, ...
                           "Function block", 1, {"sin", "1"});
        if (isempty (answer)), return; endif
        block.name = strtrim (answer{1});
        if (! isvarname (block.name))
          errordlg ("Enter a valid function name."); return;
        endif
        try
          block.outputs = str2double (answer{2});
          block.outputs = ob_function_output_count (block);
        catch err
          errordlg (err.message, "Invalid Function settings"); return;
        end_try_catch
      endif
      diagram.blocks = ob_store_block (diagram.blocks, numel(diagram.blocks) + 1, block);
      if (strcmp (data, 'Outport') && isfield (diagram, 'execution') ...
          && isfield (diagram.execution, 'initial_outputs') && iscell (diagram.execution.initial_outputs))
        diagram.execution.initial_outputs{end + 1} = 0;
      endif
      if (isfield (diagram, "sample_times")), diagram.sample_times(end + 1, :) = [0 0]; endif
      state.selected = numel (diagram.blocks);
    case "select"
      if (! strcmp (state.mode, "select"))
        if (state.source == 0)
          state.source = data;
        else
          try
            ports = ob_choose_ports (diagram, state.source, data, state.mode);
            if (! isempty (ports))
              if (strcmp (state.mode, "connect"))
                diagram = ob_connect (diagram, state.source, data, ports(1), ports(2));
              else
                diagram = ob_disconnect (diagram, state.source, data, ports(1), ports(2));
              endif
            endif
          catch err
            errordlg (err.message, "Connection error");
          end_try_catch
          state.mode = "select";
          state.source = 0;
        endif
      else
        state.dragging = true;
        state.drag_moved = false;
        state.drag_before = before;
        point = get (state.axes, "currentpoint");
        state.drag_origin = point(1, 1:2);
        state.drag_position = [diagram.blocks(data).x, diagram.blocks(data).y];
      endif
      state.selected = data;
    case "connect"
      state.mode = "connect";
      state.source = 0;
      disp ("Octave Blocks: click source, then destination.");
    case "disconnect"
      state.mode = "disconnect";
      state.source = 0;
      disp ("Octave Blocks: click source, then destination to disconnect.");
    case "edit"
      id = state.selected;
      if (isempty (id) || ! isscalar (id) || id < 1 ...
          || id > numel (diagram.blocks))
        return;
      endif
      block = diagram.blocks(id);
      if (strcmp (block.type, "Subsystem"))
        try
          [candidate, accepted] = ob_edit_subsystem (block);
          if (! accepted), return; endif
          if (! strcmp (ob_subsystem_mode(block), "virtual") ...
              && strcmp (ob_subsystem_mode(candidate), "virtual"))
            % Removing the control port removes only its wire and sample rate.
            control_port = 1 + sum (strcmp ({block.value.blocks.type}, "Inport"));
            wires = ob_edges (diagram);
            wires(wires(:, 3) == id & wires(:, 4) == control_port, :) = [];
            diagram.edges = wires;
            if (isfield (diagram, "sample_times")), diagram.sample_times(id, :) = [0 0]; endif
          endif
          execution = ob_execution_options (candidate.value,false);
          if (strcmp(execution.control,'continuous') && isfield(diagram,'sample_times'))
            diagram.sample_times(id,:) = [0 0];
          endif
          diagram.blocks(id) = candidate;
        catch err
          errordlg (err.message, "Invalid subsystem settings"); return;
        end_try_catch
      elseif (strcmp (block.type, "Function"))
        old_count = ob_function_output_count (block);
        count_text = num2str (old_count);
        answer = inputdlg ({"Octave function name:", "Number of outputs (positive integer):"}, "Edit Function", 1, ...
                           {block.name, count_text});
        if (isempty (answer)), return; endif
        name = strtrim (answer{1});
        if (! isvarname (name)), errordlg ("Enter a valid function name."); return; endif
        try
          candidate = block;
          candidate.name = name; candidate.outputs = str2double (answer{2});
          candidate.outputs = ob_function_output_count (candidate);
          if (candidate.outputs < old_count)
            wires = ob_edges (diagram);
            wires(wires(:, 1) == id & wires(:, 2) > candidate.outputs, :) = [];
            diagram.edges = wires;
          endif
          diagram.blocks = ob_store_block (diagram.blocks, id, candidate);
        catch err
          errordlg (err.message, "Invalid Function settings"); return;
        end_try_catch
      elseif (any (strcmp (block.type, {"Constant", "Gain", "Step", ...
                                     "Unit Delay", "Integrator", ...
                                     "Discrete Integrator", "Rate Transition", "Inport", "Outport", ...
                                     "Saturation", "Dead Zone", "Switch"})))
        current_value = block.value;
        prompt = {"Octave expression:"};
        if (any (strcmp (block.type, {"Saturation", "Dead Zone", "Switch"})))
          prompt_text = ob_control_prompt (block.type);
          prompt = {prompt_text};
        endif
        value_text = ob_value_text (current_value);
        defaults = {value_text};
        answer = inputdlg (prompt, "Edit block value", 1, defaults);
        if (isempty (answer)), return; endif
        try
          candidate_value = evalin ("base", answer{1});
          ob_validate_control_parameter (block.type, candidate_value);
          diagram.blocks(id).value = candidate_value;
        catch err
          errordlg (err.message, "Invalid Octave expression"); return;
        end_try_catch
      endif
    case "settings"
      answer = inputdlg ({"Start time", "Stop time", "Output interval / RK4 step", ...
                         "Solver: rk4, ode45, or ode15s", "Relative tolerance", ...
                         "Absolute tolerance", "Adaptive/event maximum step (Inf = no extra limit)", ...
                         "Locate zero crossings (0 or 1)"}, ...
                         "Simulation settings", 1, ...
                         {num2str(state.config(1)), num2str(state.config(2)), ...
                          num2str(state.config(3)), state.options.solver, ...
                          num2str(state.options.reltol), num2str(state.options.abstol), ...
                          num2str(state.options.maxstep), num2str(state.options.zero_crossings)});
      if (isempty (answer)), return; endif
      try
        config = ob_validate_config (cellfun (@str2double, answer(1:3)));
        options = ob_solver_options (struct ("solver", strtrim(answer{4}), ...
                   "reltol", str2double(answer{5}), "abstol", str2double(answer{6}), ...
                   "maxstep", str2double(answer{7}), 'zero_crossings', str2double(answer{8})));
      catch err
        errordlg (err.message, "Invalid simulation settings"); return;
      end_try_catch
      state.config = config; state.options = options;
    case "sample_time"
      id = state.selected;
      if (id < 1 || ! ob_has_sample_time (diagram.blocks(id)))
        errordlg ("Select a Unit Delay, Discrete Integrator, Rate Transition, or conditional Subsystem first."); return;
      endif
      rates = ob_sample_times (diagram);
      answer = inputdlg ({"Period (0 = output schedule)", "Offset from simulation start"}, ...
                         "Block sample time", 1, {num2str(rates(id, 1),17), num2str(rates(id, 2),17)});
      if (isempty (answer)), return; endif
      candidate = diagram;
      rates(id, :) = cellfun (@str2double, answer(:))';
      candidate.sample_times = rates;
      try
        candidate.sample_times = ob_sample_times (candidate);
      catch err
        errordlg (err.message, "Invalid sample time"); return;
      end_try_catch
      diagram = candidate;
    case "inputs"
      [signals, accepted] = ob_edit_root_inputs (state.model);
      if (! accepted), return; endif
      state.model.inputs = signals;
    case {"example", "example_nested", "example_inputs", "example_multirate", "example_control"}
      if (! ob_discard (state)), return; endif
      if (strcmp (action, "example_nested"))
        state.model = ob_subsystem_example ();
      elseif (strcmp (action, "example_inputs"))
        state.model = ob_input_example ();
      elseif (strcmp (action, "example_multirate"))
        state.model = ob_multirate_example ();
        state.config = [0 1 0.1];
      elseif (strcmp (action, "example_control"))
        state.model = ob_control_example ();
        state.config = [0 4 0.1];
      else
        state.model = ob_oscillator ();
      endif
      state.path = [];
      state.selected = 0;
      state.mode = "select";
      state.source = 0;
    case "delete"
      id = state.selected;
      if (id < 1), return; endif
      deleted = diagram.blocks(id);
      if (strcmp (deleted.type, 'Outport') && isfield (diagram, 'execution') ...
          && isfield (diagram.execution, 'initial_outputs') && iscell (diagram.execution.initial_outputs) ...
          && deleted.value == numel (diagram.execution.initial_outputs))
        diagram.execution.initial_outputs(end) = [];
      endif
      if (isempty (state.path) && strcmp (deleted.type, "Inport") ...
          && isfield (diagram, "inputs") && iscell (diagram.inputs) ...
          && isnumeric (deleted.value) && isscalar (deleted.value) ...
          && isreal (deleted.value) && isfinite (deleted.value) ...
          && deleted.value >= 1 && deleted.value == fix (deleted.value) ...
          && deleted.value <= numel (diagram.inputs))
        % Datasets belong to port numbers. Never shift another port's data.
        diagram.inputs{deleted.value} = [];
        while (! isempty (diagram.inputs) && isempty (diagram.inputs{end}))
          diagram.inputs(end) = [];
        endwhile
      endif
      edges = ob_edges (diagram);
      rates = ob_sample_times (diagram);
      diagram.blocks(id) = [];
      if (isfield (diagram, "sample_times"))
        rates(id, :) = []; diagram.sample_times = rates;
      endif
      edges(any (edges(:, [1 3]) == id, 2), :) = [];
      indices = edges(:, [1 3]);
      indices(indices > id) -= 1;
      edges(:, [1 3]) = indices;
      diagram.edges = edges;
      state.selected = 0;
    case "run"
      try
        t = ob_time_grid (state.config(1), state.config(2), state.config(3));
        result = ob_run (state.model, t, state.options);
        scopes = ob_scope_paths (state.model);
        if (isempty (scopes))
          errordlg ("Add and connect a Scope block first."); return;
        endif
        scope_traces = cell (1, numel (scopes));
        for k = 1:numel (scopes)
          try
            scope_traces{k} = ob_scope_data (result, scopes{k});
          catch err
            if (isempty (strfind (err.message, 'conditional child has not executed'))), rethrow (err); endif
          end_try_catch
        endfor
        available = ! cellfun (@isempty, scope_traces);
        if (! any (available))
          assignin ('base', 'ob_last_result', result);
          msgbox ('The conditional children containing these scopes have not executed.', 'No scope samples');
          return;
        endif
        figure ("name", "Octave Blocks scopes", "numbertitle", "off");
        hold on;
        for k = find (available)
          path = scopes{k};
          traces = scope_traces{k};
          path_text = sprintf ("%d/", path); path_text(end) = [];
          handles = plot (result.t, traces);
          for channel = 1:columns (traces)
            if (columns (traces) == 1)
              label = sprintf ("Scope %s", path_text);
            else
              label = sprintf ("Scope %s [%d]", path_text, channel);
            endif
            set (handles(channel), "displayname", label);
          endfor
        endfor
        xlabel ("Time"); ylabel ("Value"); grid on; legend show;
        assignin ("base", "ob_last_result", result);
      catch err
        errordlg (err.message, "Simulation error");
      end_try_catch
    case "export_c"
      [file, folder] = uiputfile ("*.c", "Export standalone C model");
      if (! isequal (file, 0))
        try
          info = ob_codegen (state.model, fullfile(folder, file), state.config, state.options);
          assignin ("base", "ob_last_export", info);
          msgbox (sprintf("C source exported to:\n%s\n\nSee CODEGEN.md for build and API instructions.", ...
                           fullfile(folder, file)), "C export complete");
        catch err
          errordlg (err.message, "C export error"); return;
        end_try_catch
      endif
    case "save"
      [file, folder] = uiputfile ("*.mat", "Save Octave Blocks model");
      if (! isequal (file, 0))
        try
          ob_save_model (fullfile (folder, file), state.model, state.config, state.options);
          state.saved = ob_snapshot (state);
        catch err
          errordlg (err.message, "Save error"); return;
        end_try_catch
      endif
    case "load"
      if (! ob_discard (state)), return; endif
      [file, folder] = uigetfile ("*.mat", "Load Octave Blocks model");
      if (! isequal (file, 0))
        try
          [model, config, options] = ob_load_model (fullfile (folder, file));
        catch err
          errordlg (err.message, "Load error"); return;
        end_try_catch
        state.model = model; state.config = config; state.options = options;
        state.path = [];
        state.selected = 0;
        state.mode = "select";
        state.source = 0;
        state.saved = ob_snapshot (state);
      endif
  endswitch
  if (any (strcmp (action, {"add", "select", "edit", "delete", "sample_time"})))
    state.model = ob_set_model_at (state.model, state.path, diagram);
  endif
  if (! any (strcmp (action, {"undo", "redo"})) ...
      && ! isequal (before, ob_snapshot (state)))
    state = ob_record (state, before);
  endif
  guidata (fig, state);
  ob_draw (fig);
endfunction

function ob_drag (fig)
  state = guidata (fig);
  if (! state.dragging || state.selected < 1), return; endif
  point = get (state.axes, "currentpoint");
  shift = point(1, 1:2) - state.drag_origin;
  if (norm (shift) < 0.002), return; endif
  position = state.drag_position + shift;
  diagram = ob_model_at (state.model, state.path);
  position = [max(0.11,min(0.89,position(1))) max(0.06,min(0.94,position(2)))];
  if (isequal(position,[diagram.blocks(state.selected).x diagram.blocks(state.selected).y])), return; endif
  diagram.blocks(state.selected).x = position(1);
  diagram.blocks(state.selected).y = position(2);
  state.drag_moved = true;
  state.model = ob_set_model_at (state.model, state.path, diagram);
  guidata (fig, state);
  ob_draw (fig, true);
endfunction

function ob_stop_drag (fig)
  ob_drag (fig);
  state = guidata (fig);
  if (! state.dragging), return; endif
  moved = isfield(state,'drag_moved') && state.drag_moved;
  if (moved && isfield (state, "drag_before") ...
      && ! isequal (state.drag_before, ob_snapshot (state)))
    state = ob_record (state, state.drag_before);
  endif
  state.dragging = false;
  guidata (fig, state);
  if (moved), ob_draw (fig); endif
endfunction

function ob_draw (fig, geometry_only = false)
  state = guidata (fig);
  ax = state.axes;
  diagram = ob_model_at (state.model, state.path);
  % Mouse motion already knows content moved. Compare the saved model only
  % after the drag finishes, rather than traversing it for every pointer event.
  dirty = geometry_only || ! isequal (state.saved, ob_snapshot (state));
  title_text = "Octave Blocks";
  if (dirty), title_text = [title_text " *"]; endif
  set (fig, "name", title_text);
  status_text = sprintf ("%d blocks / %d connections / %s / %s", ...
                         numel (diagram.blocks), rows (diagram.edges), ...
                         state.mode, state.options.solver);
  if (state.selected > 0)
    block = diagram.blocks(state.selected);
    status_text = [status_text " / " block.type];
    if (! isempty (block.value) && ! isstruct (block.value)), status_text = [status_text " = " ob_value_text(block.value)]; endif
    if (strcmp (block.type, "Subsystem"))
      mode = ob_subsystem_mode (block);
      status_text = [status_text " / " mode];
      if (! strcmp (mode, "virtual"))
        control_port = 1 + sum (strcmp ({block.value.blocks.type}, "Inport"));
        status_text = [status_text sprintf(" (control input %d)", control_port)];
      endif
    endif
    if (ob_has_sample_time (block))
      rates = ob_sample_times (diagram);
      status_text = [status_text sprintf(" / Ts=%.6g offset=%.6g", rates(state.selected, :))];
    endif
  endif
  breadcrumb = "root";
  if (! isempty (state.path)), breadcrumb = [breadcrumb sprintf("/%d", state.path)]; endif
  set (state.status, "string", [breadcrumb " : " status_text]);
  if (isfield(state,'graphics'))
    cache = state.graphics;
    valid = isequal(cache.path,state.path) && numel(cache.blocks)==numel(diagram.blocks) ...
            && all(isgraphics(cache.handles));
    if (valid && (geometry_only || isequal(cache.diagram,diagram)))
      if (geometry_only)
        moved = [];
        for id = 1:numel(diagram.blocks)
          delta = [diagram.blocks(id).x-cache.diagram.blocks(id).x ...
                   diagram.blocks(id).y-cache.diagram.blocks(id).y];
          if (any(delta != 0))
            moved(end+1) = id;
            for object = cache.blocks{id}
              if (strcmp(get(object,'type'),'text'))
                point = get(object,'position'); point(1:2) += delta;
                set(object,'position',point);
              else
                set(object,'xdata',get(object,'xdata')+delta(1), ...
                           'ydata',get(object,'ydata')+delta(2));
              endif
            endfor
          endif
        endfor
        incident = find(ismember(cache.edges(:,1),moved) | ismember(cache.edges(:,3),moved));
        for k = reshape(incident,1,[])
          edge = cache.edges(k,:);
          [points,corners] = signal_geometry(diagram.blocks(edge(1)),diagram.blocks(edge(3)), ...
              edge(2),cache.outputs(edge(1)),edge(4),cache.inputs(edge(3)));
          set(cache.wires(k,1),'xdata',points(:,1),'ydata',points(:,2));
          set(cache.wires(k,2),'xdata',corners(:,1),'ydata',corners(:,2));
        endfor
      endif
      if (cache.selected != state.selected)
        if (cache.selected > 0), set(cache.bodies(cache.selected),'facecolor',[.86 .91 .99]); endif
        if (state.selected > 0), set(cache.bodies(state.selected),'facecolor',[1 .83 .50]); endif
      endif
      cache.diagram = diagram; cache.selected = state.selected;
      state.graphics = cache; guidata(fig,state);
      return;
    endif
  endif
  cla (ax);
  hold (ax, "on");
  xlim (ax, [0 1]); ylim (ax, [0 1]);
  set (ax, "xtick", [], "ytick", [], "box", "on");
  edges = ob_edges (diagram);
  cache = struct ('path',state.path,'diagram',diagram,'selected',state.selected, ...
                  'blocks',{cell(1,numel(diagram.blocks))},'bodies',zeros(1,numel(diagram.blocks)), ...
                  'wires',zeros(rows(edges),2),'edges',edges,'handles',[], ...
                  'inputs',zeros(1,numel(diagram.blocks)),'outputs',zeros(1,numel(diagram.blocks)));
  for id = 1:numel(diagram.blocks)
    [inputs,outputs] = ob_block_ports(diagram.blocks(id));
    if (isinf(inputs)), inputs = max(1,max([0;edges(edges(:,3)==id,4)])); endif
    cache.inputs(id) = inputs; cache.outputs(id) = outputs;
  endfor
  for k = 1:rows (edges)
    edge = edges(k, :);
    a = diagram.blocks(edge(1)); b = diagram.blocks(edge(3));
    cache.wires(k,:) = draw_signal (ax, a, b, edge(2),cache.outputs(edge(1)),edge(4),cache.inputs(edge(3)));
  endfor
  for id = 1:numel (diagram.blocks)
    block = diagram.blocks(id);
    face = [0.86 0.91 0.99];
    if (state.selected == id), face = [1 0.83 0.50]; endif
    xx = block.x + [-0.105 0.105 0.105 -0.105];
    yy = block.y + [-0.052 -0.052 0.052 0.052];
    body = patch ("parent", ax, "xdata", xx, "ydata", yy, ...
           "facecolor", face, "edgecolor", [0.2 0.3 0.5]);
    label = block.type;
    if (any (strcmp (block.type, {"Function", "Subsystem"}))), label = block.name; endif
    if (strcmp (block.type, "Function"))
      count = ob_function_output_count (block);
      if (count > 1), label = sprintf ("%s\n[%d outputs]", block.name, count); endif
    endif
    if (strcmp (block.type, "Subsystem"))
      mode = ob_subsystem_mode (block);
      if (strcmp (mode, "virtual"))
        label = sprintf ("%s\n[%s]", block.name, mode);
      else
        control_port = 1 + sum (strcmp ({block.value.blocks.type}, "Inport"));
        label = sprintf ("%s\n[%s; control=%d]", block.name, mode, control_port);
      endif
    endif
    if (any (strcmp (block.type, {"Inport", "Outport"})))
      label = sprintf ("%s %d", block.type, block.value);
    endif
    cache.bodies(id) = body; objects = body;
    inputs = cache.inputs(id); outputs = cache.outputs(id);
    for port = 1:inputs
      objects = [objects draw_port(ax,block.x-.105,block.y+port_offset(port,inputs),port,-1)];
    endfor
    for port = 1:outputs
      objects = [objects draw_port(ax,block.x+.105,block.y+port_offset(port,outputs),port,1)];
    endfor
    label_object = text (block.x, block.y, label, "parent", ax, ...
          "horizontalalignment", "center", "fontsize", 10);
    cache.blocks{id} = [objects label_object];
    % A block includes its label, port markers, and port numbers. Give every
    % visible part the same owner/callback instead of relying on click-through
    % from a non-hittable child to another object behind it.
    for object = cache.blocks{id}
      setappdata (object, 'ob_block_id', id);
      set (object, 'buttondownfcn', @ob_select_block, ...
                   'hittest', 'on', 'pickableparts', 'all');
    endfor
  endfor
  hold (ax, "off");
  cache.handles = [cache.wires(:)' cache.blocks{:}];
  state.graphics = cache; guidata(fig,state);
endfunction

function ob_select_block (src, evt)
  ob_action (src, 'select', getappdata(src,'ob_block_id'));
endfunction

function ob_pointer_select (fig, evt)
  % Qt may pick the axes at an antialiased rectangle border. Only provide a
  % geometry fallback for unowned canvas objects: owned parts dispatch their
  % own callback, and dispatching twice would complete Connect on one click.
  state = guidata (fig);
  object = get (fig, 'currentobject');
  if (isempty (state) || isempty (object) || ! isgraphics (object) ...
      || isappdata (object, 'ob_block_id'))
    return;
  endif
  if (object == state.axes)
    object_axes = object;
  else
    object_axes = ancestor (object, 'axes');
  endif
  if (isempty (object_axes) || object_axes != state.axes), return; endif
  point = get (state.axes, 'currentpoint'); point = point(1, 1:2);
  xlimits = sort (get (state.axes, 'xlim'));
  ylimits = sort (get (state.axes, 'ylim'));
  lower = [xlimits(1) ylimits(1)]; upper = [xlimits(2) ylimits(2)];
  if (any (! isfinite (point)) || any (point < lower) || any (point > upper)), return; endif
  pixels = getpixelposition (state.axes, true);
  padding = 5 * (upper-lower) ./ max ([1 1], pixels(3:4));
  diagram = ob_model_at (state.model, state.path);
  for id = numel (diagram.blocks):-1:1
    center = [diagram.blocks(id).x diagram.blocks(id).y];
    first = max (lower, center-[.105 .052]-padding);
    last = min (upper, center+[.105 .052]+padding);
    if (all (point >= first) && all (point <= last))
      ob_action (fig, 'select', id);
      return;
    endif
  endfor
endfunction

function [signals, accepted] = ob_edit_root_inputs (model)
  signals = {}; accepted = false;
  ids = find (strcmp ({model.blocks.type}, "Inport"));
  if (isempty (ids))
    errordlg ("Add an Inport block in the root diagram before configuring Inputs.", ...
              "No root inputs");
    return;
  endif
  numbers = zeros (1, numel (ids));
  for k = 1:numel (ids)
    number = model.blocks(ids(k)).value;
    if (! isnumeric (number) || ! isscalar (number) || ! isreal (number) ...
        || ! isfinite (number) || number < 1 || number != fix (number))
      errordlg ("Root Inports need positive integer port numbers. Use Edit to correct them.", ...
                "Invalid root input ports");
      return;
    endif
    numbers(k) = number;
  endfor
  if (! isequal (sort (numbers), 1:numel (ids)))
    errordlg ("Root Inport numbers must be unique and consecutive from 1. Use Edit to renumber them, then configure Inputs.", ...
              "Invalid root input ports");
    return;
  endif
  staged = cell (1, numel (ids));
  for port = 1:numel (ids)
    times = "[0; 1]"; values = "[0; 0]"; shape = "[1 1]"; method = "zoh";
    if (isfield (model, "inputs") && iscell (model.inputs) ...
        && port <= numel (model.inputs) && ! isempty (model.inputs{port}))
      current = model.inputs{port};
      if (isstruct (current) && isscalar (current))
        if (isfield (current, "t") && isnumeric (current.t)), times = mat2str (current.t, 17); endif
        if (isfield (current, "values") && isnumeric (current.values)), values = mat2str (current.values, 17); endif
        if (isfield (current, "shape") && isnumeric (current.shape)), shape = mat2str (current.shape, 17); endif
        if (isfield (current, "method") && ischar (current.method)), method = current.method; endif
      endif
    endif
    defaults = {times, values, shape, method};
    title_text = sprintf ("Root input %d", port);
    answer = inputdlg ({"Times (Octave expression)", "Sample rows (one row per time)", ...
                       "Signal shape [rows cols]", "Interpolation: zoh or linear"}, ...
                       title_text, 1, defaults);
    if (isempty (answer)), return; endif
    try
      sample_times = evalin ("base", answer{1});
      sample_rows = evalin ("base", answer{2});
      sample_shape = evalin ("base", answer{3});
      staged{port} = ob_input_signal (sample_times, sample_rows, sample_shape, strtrim(answer{4}));
    catch err
      errordlg (err.message, sprintf("Invalid root input %d", port));
      return;
    end_try_catch
  endfor
  % Commit only after every port was accepted and validated. A cancellation
  % or failure above leaves all existing datasets and undo history unchanged.
  signals = staged; accepted = true;
endfunction

function [block, accepted] = ob_edit_subsystem (block)
  accepted = false;
  child = block.value;
  % Read defaults independently of existing execution metadata so settings can
  % repair a draft whose body/interface changed since the last configuration.
  plain = child;
  if (isfield (plain, "execution")), plain = rmfield (plain, "execution"); endif
  options = ob_execution_options (plain);
  if (isfield (child, "execution") && isstruct (child.execution) && isscalar (child.execution))
    for field = {"mode", "states", "outputs", "initial_outputs", "initial_control", "control"}
      if (isfield (child.execution, field{1})), options.(field{1}) = child.execution.(field{1}); endif
    endfor
  endif
  initial_text = ob_cell_expression (options.initial_outputs);
  control_text = num2str (options.initial_control, 17);
  defaults = {block.name, options.mode, options.states, options.outputs, initial_text, control_text, options.control};
  answer = inputdlg ({"Name", "Mode: virtual, enabled, rising, falling, or either", ...
                     "States when re-enabled: held or reset", "Outputs while disabled: held or reset", ...
                     "Initial outputs (Octave cell expression, one per Outport)", ...
                     "Initial trigger control (finite scalar)", "Control timing: sampled or continuous"}, ...
                     "Subsystem settings", 1, defaults);
  if (isempty (answer)), return; endif
  initial_outputs = evalin ("base", answer{5});
  candidate = child;
  candidate.execution = struct ("mode", strtrim(answer{2}), "states", strtrim(answer{3}), ...
                                "outputs", strtrim(answer{4}), "initial_outputs", {initial_outputs}, ...
                                "initial_control", str2double(answer{6}), "control", strtrim(answer{7}));
  candidate.execution = ob_execution_options (candidate);
  ob_validate_model (candidate, false);
  block.name = answer{1}; block.value = candidate;
  accepted = true;
endfunction

function text = ob_cell_expression (values)
  if (! iscell (values)), error ("Initial subsystem outputs must be a cell array."); endif
  elements = cell (1, numel (values));
  for k = 1:numel (values)
    elements{k} = mat2str (values{k}, 17);
  endfor
  text = ["{" strjoin(elements, ", ") "}"];
endfunction

function mode = ob_subsystem_mode (block)
  mode = "virtual";
  if (strcmp (block.type, "Subsystem") && isfield (block.value, "execution") ...
      && isstruct (block.value.execution) && isscalar (block.value.execution) ...
      && isfield (block.value.execution, "mode") && ischar (block.value.execution.mode))
    mode = block.value.execution.mode;
  endif
endfunction

function yes = ob_has_sample_time (block)
  yes = any (strcmp (block.type, {"Unit Delay", "Discrete Integrator", "Rate Transition"}));
  if (strcmp (block.type, "Subsystem"))
    yes = any (strcmp (ob_subsystem_mode(block), {"enabled", "rising", "falling", "either"}));
  endif
endfunction

function prompt = ob_control_prompt (type)
  if (strcmp (type, "Switch"))
    prompt = "Threshold (input 2 >= threshold selects input 1; otherwise input 3):";
  else
    prompt = sprintf ("%s limits [lower upper]:", type);
  endif
endfunction

function ob_validate_control_parameter (type, value)
  if (! any (strcmp (type, {"Saturation", "Dead Zone", "Switch"}))), return; endif
  if (! isnumeric (value) || ! isreal (value) || isempty (value) ...
      || any (! isfinite (value(:))))
    error ("%s needs a finite real numeric parameter.", type);
  endif
  if (strcmp (type, "Switch"))
    if (! isscalar (value)), error ("Switch threshold must be a finite real scalar."); endif
  elseif (! isvector (value) || numel (value) != 2 || value(1) > value(2))
    error ("%s limits must be [lower upper] with lower <= upper.", type);
  endif
endfunction

function snapshot = ob_snapshot (state)
  snapshot = struct ("model", state.model, "config", state.config, "options", state.options);
endfunction

function state = ob_record (state, before)
  state.undo{end + 1} = before;
  if (numel (state.undo) > 50), state.undo(1) = []; endif
  state.redo = {};
endfunction

function yes = ob_discard (state)
  yes = isequal (state.saved, ob_snapshot (state));
  if (! yes)
    answer = questdlg ("Discard unsaved changes? Use Save to keep them.", ...
                       "Unsaved diagram", "Discard", "Cancel", "Cancel");
    yes = strcmp (answer, "Discard");
  endif
endfunction

function ob_close (fig)
  state = guidata (fig);
  if (isempty (state) || ob_discard (state)), delete (fig); endif
endfunction

function handles = draw_signal (ax, source, target, source_port, outputs, target_port, inputs)
  color = [0.28 0.36 0.55];
  [points,corners] = signal_geometry(source,target,source_port,outputs,target_port,inputs);
  wire = line (ax, points(:, 1), points(:, 2), "color", color, "linewidth", 1.6);
  arrow = patch ("parent",ax,"xdata",corners(:,1),"ydata",corners(:,2), ...
                 "facecolor",color,"edgecolor",color);
  handles = [wire arrow];
  % Wires are not selectable in this editor. They must not swallow a click
  % where retained geometry overlaps a block after a drag.
  set (handles, 'hittest', 'off', 'pickableparts', 'none');
endfunction

function [points,corners] = signal_geometry (source, target, source_port, outputs, target_port, inputs)
  start = [source.x + 0.105, source.y + port_offset(source_port, outputs)];
  finish = [target.x - 0.105, target.y + port_offset(target_port, inputs)];
  if (finish(1) > start(1))
    points = [start; finish];
  else
    top = min (0.98, max (source.y, target.y) + 0.1);
    points = [start; start + [0.02 0]; start(1)+0.02 top; ...
              finish(1)-0.02 top; finish - [0.02 0]; finish];
  endif
  start = points(end - 1, :);
  direction = finish - start;
  length = norm (direction);
  if (length > 0.001)
    unit = direction / length;
    perpendicular = [-unit(2), unit(1)];
    base = finish - 0.018 * unit;
    corners = [finish; base + 0.007 * perpendicular; ...
               base - 0.007 * perpendicular];
  else
    corners = NaN(3,2);
  endif
endfunction

function offset = port_offset (port, count)
  if (count <= 1), offset = 0; else offset = 0.036 - 0.072 * (port - 1) / (count - 1); endif
endfunction

function handles = draw_port (ax, x, y, port, side)
  marker = line (ax, x, y, "marker", "o", "markersize", 4, "color", [0.2 0.3 0.5], ...
        "markerfacecolor", "white");
  label = text (x + side * 0.012, y, num2str(port), "parent", ax, ...
        "horizontalalignment", "center", "fontsize", 7);
  handles = [marker label];
endfunction

function ports = ob_choose_ports (diagram, source, target, mode)
  edges = ob_edges (diagram);
  matches = edges(edges(:, 1) == source & edges(:, 3) == target, :);
  if (strcmp (mode, "disconnect") && rows (matches) == 1)
    ports = matches(1, [2 4]); return;
  endif
  [unused, outputs] = ob_block_ports (diagram.blocks(source));
  inputs = ob_block_ports (diagram.blocks(target));
  ports = [1 1];
  while (any (edges(:, 3) == target & edges(:, 4) == ports(2)))
    ports(2) += 1;
  endwhile
  if (strcmp (mode, "disconnect")), ports = [1 1]; endif
  if (outputs > 1 || inputs > 1)
    answer = inputdlg ({"Source output port", "Destination input port"}, "Signal ports", 1, ...
                       {num2str(ports(1)), num2str(ports(2))});
    if (isempty (answer)), ports = []; return; endif
    ports = cellfun (@str2double, answer);
  endif
endfunction

function blocks = ob_store_block (blocks, id, block)
  % Struct arrays share a schema. Preserve every existing extension field
  % while allowing new Function output metadata in legacy five-field models.
  names = fieldnames (blocks);
  supplied = fieldnames (block);
  for k = 1:numel (supplied)
    if (! any (strcmp (names, supplied{k}))), names{end + 1, 1} = supplied{k}; endif
  endfor
  if (isempty (blocks))
    template = struct ();
    for k = 1:numel (names), template.(names{k}) = []; endfor
    blocks = repmat (template, size (blocks));
  else
    for k = 1:numel (names)
      if (! isfield (blocks, names{k}))
        for item = 1:numel (blocks), blocks(item).(names{k}) = []; endfor
      endif
    endfor
  endif
  for k = 1:numel (names)
    if (! isfield (block, names{k})), block.(names{k}) = []; endif
  endfor
  blocks = orderfields (blocks, names);
  block = orderfields (block, names);
  blocks(id) = block;
endfunction
