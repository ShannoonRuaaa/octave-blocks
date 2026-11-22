function test_ob_editor_graphics ()
  test_path_cleanup = ob_test_setup ();
  % Exercise real Qt callbacks while retaining the diagram's graphics handles.
  if (!any(strcmp(available_graphics_toolkits(),'qt')))
    error ('test_ob_editor_graphics: run under the Octave GUI runtime with Qt available');
  endif
  graphics_toolkit ('qt');
  previous = get(0,'defaultfigurevisible'); set(0,'defaultfigurevisible','off');
  figures = [];
  unwind_protect
    model = ob_multioutput_example ();
    fig = octave_blocks(model); figures(end+1) = fig; drawnow();
    initial = guidata(fig); handles = sort(findall(initial.axes));
    % Every visible block part owns the same selection target. Port markers
    % and numbers must not pass clicks to the axes; wires must not intercept.
    for id = 1:numel(initial.graphics.blocks)
      for part = initial.graphics.blocks{id}
        assert(getappdata(part,'ob_block_id') == id);
        assert(strcmp(get(part,'hittest'),'on') && strcmp(get(part,'pickableparts'),'all'));
        callback = get(part,'buttondownfcn'); assert(isa(callback,'function_handle'));
        feval(callback,part,[]); selected = guidata(fig);
        assert(selected.selected == id && selected.dragging);
        assert(isequal(sort(findall(selected.axes)),handles));
        feval(get(fig,'windowbuttonupfcn'),fig,[]);
        selected = guidata(fig);
        assert(!selected.dragging && isempty(selected.undo) && isequal(selected.model,model));
        assert(isequal(get(selected.graphics.bodies(id),'facecolor'),[1 .83 .5]));
      endfor
    endfor
    for wire = reshape(initial.graphics.wires,1,[])
      assert(strcmp(get(wire,'hittest'),'off') && strcmp(get(wire,'pickableparts'),'none'));
    endfor
    click_block(fig,2); state = guidata(fig);
    assert(state.selected == 2 && state.dragging);
    assert(isequal(get(state.graphics.bodies(2),'facecolor'),[1 .83 .5]));
    assert(isequal(sort(findall(state.axes)),handles));
    feval(get(fig,'windowbuttonupfcn'),fig,[]);
    state = guidata(fig);
    assert(!state.dragging && isempty(state.undo));
    assert(isequal(sort(findall(state.axes)),handles));
    assert(isequal(state.model,model));

    click_block(fig,2); state = guidata(fig);
    delta = [.08 -.03]; point = get(state.axes,'currentpoint');
    state.drag_origin = point(1,1:2)-delta; guidata(fig,state);
    feval(get(fig,'windowbuttonmotionfcn'),fig,[]);
    moved = guidata(fig);
    assert(isequal(sort(findall(moved.axes)),handles));
    assert(moved.drag_moved && isempty(moved.undo));
    assert(abs(moved.model.blocks(2).x-model.blocks(2).x-delta(1)) < 1e-14);
    assert(abs(moved.model.blocks(2).y-model.blocks(2).y-delta(2)) < 1e-14);
    body_x = get(moved.graphics.bodies(2),'xdata');
    assert(max(abs(body_x(:)' - (model.blocks(2).x+delta(1)+[-.105 .105 .105 -.105]))) < 1e-14);
    input_wire = moved.graphics.wires(1,1);
    x = get(input_wire,'xdata'); y = get(input_wire,'ydata');
    assert(abs(x(end)-(moved.model.blocks(2).x-.105)) < 1e-14);
    assert(abs(y(end)-moved.model.blocks(2).y) < 1e-14);
    upper = get(moved.graphics.wires(2,1),'ydata');
    lower = get(moved.graphics.wires(3,1),'ydata');
    assert(abs(upper(1)-moved.model.blocks(2).y-.036) < 1e-14);
    assert(abs(lower(1)-moved.model.blocks(2).y+.036) < 1e-14);
    expected_moved = moved.model;
    % Crossing to the right of a consumer reroutes the wire through its
    % loopback bend while keeping the same line and arrow objects alive.
    point = get(moved.axes,'currentpoint');
    moved.drag_origin = point(1,1:2)-[.5 delta(2)]; guidata(fig,moved);
    feval(get(fig,'windowbuttonmotionfcn'),fig,[]); loopback = guidata(fig);
    assert(loopback.model.blocks(2).x == .89);
    assert(numel(get(loopback.graphics.wires(2,1),'xdata')) == 6);
    assert(isequal(sort(findall(loopback.axes)),handles));
    loopback.drag_origin = point(1,1:2)-delta; guidata(fig,loopback);
    feval(get(fig,'windowbuttonmotionfcn'),fig,[]); moved = guidata(fig);
    assert(isequal(moved.model,expected_moved));
    assert(numel(get(moved.graphics.wires(2,1),'xdata')) == 2);
    feval(get(fig,'windowbuttonupfcn'),fig,[]);
    moved = guidata(fig);
    assert(!moved.dragging && numel(moved.undo)==1);
    assert(isequal(moved.model,expected_moved));
    assert(isequal(sort(findall(moved.axes)),handles));
    press_button(fig,'Undo'); state = guidata(fig);
    assert(isequal(state.model,model) && isempty(state.undo) && numel(state.redo)==1);
    press_button(fig,'Redo'); state = guidata(fig);
    assert(isequal(state.model,expected_moved));

    % Attribute/interface changes rebuild a complete scene; external graphics
    % removal is also detected instead of leaving a partially drawn diagram.
    old_body = state.graphics.bodies(2);
    state.model.blocks(2).outputs = 3; guidata(fig,state);
    press_button(fig,'Connect'); state = guidata(fig);
    assert(!isgraphics(old_body) && state.graphics.outputs(2)==3);
    delete(state.graphics.bodies(1));
    press_button(fig,'Connect'); state = guidata(fig);
    assert(all(isgraphics(state.graphics.handles)) && numel(state.graphics.bodies)==4);

    % Selection shortcuts must detect external model/settings/saved changes,
    % retain graphics ownership, and never create a content-edit Undo entry.
    extra = octave_blocks(ob_example()); figures(end+1)=extra;
    external=guidata(extra); old_body=external.graphics.bodies(2);
    external.model.blocks(2).value=7; guidata(extra,external);
    click_block(extra,2); external=guidata(extra);
    assert(!isgraphics(old_body) && external.model.blocks(2).value==7);
    assert(isempty(external.undo) && !isempty(strfind(get(extra,'name'),'*')));
    feval(get(extra,'windowbuttonupfcn'),extra,[]);
    external=guidata(extra); external.saved=struct('model',external.model, ...
        'config',external.config,'options',external.options); guidata(extra,external);
    click_block(extra,3); external=guidata(extra);
    assert(isempty(strfind(get(extra,'name'),'*')) && isempty(external.undo));
    feval(get(extra,'windowbuttonupfcn'),extra,[]);
    external=guidata(extra); retained=sort(findall(external.axes));
    external.config=[0 2 .1]; guidata(extra,external); click_block(extra,1);
    external=guidata(extra);
    assert(!isempty(strfind(get(extra,'name'),'*')) && isempty(external.undo));
    assert(isequal(sort(findall(external.axes)),retained));
    feval(get(extra,'windowbuttonupfcn'),extra,[]);
    external=guidata(extra); delete(external.graphics.bodies(3));
    click_block(extra,2); external=guidata(extra);
    assert(all(isgraphics(external.graphics.handles)) && external.selected==2);

    % Moving a branch consumer must leave every unrelated wire unchanged.
    branch=octave_blocks(ob_multioutput_example()); figures(end+1)=branch;
    branching=guidata(branch); other=branching.graphics.wires([1 3],1);
    old_x=get(other,'xdata'); old_y=get(other,'ydata');
    click_block(branch,3); branching=guidata(branch);
    point=get(branching.axes,'currentpoint');
    branching.drag_origin=point(1,1:2)-[.04 .03]; guidata(branch,branching);
    feval(get(branch,'windowbuttonmotionfcn'),branch,[]);
    branching=guidata(branch);
    assert(isequal(get(other,'xdata'),old_x) && isequal(get(other,'ydata'),old_y));
    destination=branching.graphics.edges(:,3)==3;
    moved_wire=branching.graphics.wires(find(destination,1),1);
    moved_x=get(moved_wire,'xdata'); moved_y=get(moved_wire,'ydata');
    assert(abs(moved_x(end)-(branching.model.blocks(3).x-.105))<1e-14);
    assert(abs(moved_y(end)-branching.model.blocks(3).y)<1e-14);
    feval(get(branch,'windowbuttonupfcn'),branch,[]);

    % A trusted callback skips the coordinate-discovery loop. External moves
    % of nonselected blocks invalidate that hint and update every moved block
    % and incident wire, while retaining the existing scene objects.
    probe=octave_blocks(ob_multioutput_example()); figures(end+1)=probe;
    click_block(probe,2); probing=guidata(probe);
    retained=sort(findall(probing.axes));
    assert(getappdata(probe,'ob_state_listener') && !getappdata(probe,'ob_external_state'));
    [scans,checks]=profile_motion(probe,[.02 .01]); assert(scans==0 && checks==0);
    probing=guidata(probe); assert_diagram_geometry(probing);
    probing.model.blocks(1).x += .015;
    probing.model.blocks(3).y -= .025;
    probing.config=[0 3 .05]; probing.options.solver='ode45';
    probing.saved=struct('model',probing.model,'config',probing.config,'options',probing.options);
    external_saved=probing.saved;
    guidata(probe,probing);
    assert(getappdata(probe,'ob_external_state') && !getappdata(branch,'ob_external_state'));
    [scans,checks]=profile_motion(probe,[.04 .02]); assert(scans==1 && checks==1);
    probing=guidata(probe); assert_diagram_geometry(probing);
    assert(isequal(sort(findall(probing.axes)),retained));
    assert(isequal(probing.config,[0 3 .05]) && strcmp(probing.options.solver,'ode45'));
    assert(isequal(probing.saved,external_saved));
    assert(!isempty(strfind(get(probe,'name'),'*')) && isempty(probing.undo));
    % External saved-state updates also apply during geometry-only drawing.
    saved_model=probing.model;
    saved_model.blocks(2).x=probing.drag_position(1)+.05;
    saved_model.blocks(2).y=probing.drag_position(2)+.03;
    probing.saved=struct('model',saved_model,'config',probing.config,'options',probing.options);
    guidata(probe,probing);
    assert(profile_motion(probe,[.05 .03])==0);
    assert(isempty(strfind(get(probe,'name'),'*')));
    assert(!getappdata(probe,'ob_external_state') && !getappdata(probe,'ob_state_guard'));
    feval(get(probe,'windowbuttonupfcn'),probe,[]); probing=guidata(probe);
    assert(numel(probing.undo)==1 && !probing.dragging);
    after_drag=probing.model; press_button(probe,'Undo'); probing=guidata(probe);
    assert(isequal(probing.model,ob_multioutput_example()));
    press_button(probe,'Redo'); probing=guidata(probe);
    assert(isequal(probing.model,after_drag)); assert_diagram_geometry(probing);

    % Attribute, edge-port and deleted-graphics changes cannot take the hint.
    click_block(probe,2); probing=guidata(probe); old_body=probing.graphics.bodies(2);
    probing.model.blocks(2).outputs=3;
    probing.model.edges(2,2)=3; set(probe,'__guidata__',probing);
    assert(getappdata(probe,'ob_external_state'));
    profile_motion(probe,[.02 0]); probing=guidata(probe);
    assert(!isgraphics(old_body) && probing.graphics.outputs(2)==3);
    assert(isequal(probing.graphics.edges,ob_edges(ob_model_at(probing.model,probing.path))));
    assert_diagram_geometry(probing);
    delete(probing.graphics.bodies(1));
    profile_motion(probe,[.03 0]); probing=guidata(probe);
    assert(all(isgraphics(probing.graphics.handles))); assert_diagram_geometry(probing);
    probing.graphics=rmfield(probing.graphics,'diagram'); guidata(probe,probing);
    profile_motion(probe,[.04 0]); probing=guidata(probe);
    assert_diagram_geometry(probing);
    feval(get(probe,'windowbuttonupfcn'),probe,[]);

    % A stale selected block cancels the anchor instead of moving a different
    % block; mouse-up keeps exactly one Undo entry for the completed movement.
    click_block(probe,2); profile_motion(probe,[.01 0]); probing=guidata(probe);
    edited=probing.model; old_undo=numel(probing.undo);
    probing.selected=3; guidata(probe,probing);
    profile_motion(probe,[.08 0]); probing=guidata(probe);
    assert(!probing.dragging && isequal(probing.model,edited));
    assert(numel(probing.undo)==old_undo+1);
    feval(get(probe,'windowbuttonupfcn'),probe,[]); probing=guidata(probe);
    assert(numel(probing.undo)==old_undo+1);

    % Reentrant property listeners must consume only the editor's own write
    % token; a nested external guidata write stays invalid until verified.
    reentrant=@rewrite_state;
    setappdata(probe,'test_rewrite',true);
    addlistener(probe,'__guidata__',reentrant);
    click_block(probe,2); probing=guidata(probe);
    assert(probing.config(2)==4 && !getappdata(probe,'ob_state_guard'));
    dellistener(probe,'__guidata__',reentrant);
    assert(isequal(probing.graphics.draw_key.current.config,probing.config));
    feval(get(probe,'windowbuttonupfcn'),probe,[]);

    % A throwing listener cannot leave an internal-write token behind.
    disp('Checking guard recovery; intentional state-listener error diagnostics below are expected.');
    throwing=@throw_state;
    addlistener(probe,'__guidata__',throwing);
    try
      click_block(probe,2);
    catch err
      assert(!isempty(strfind(err.message,'intentional state-listener failure')));
    end_try_catch
    dellistener(probe,'__guidata__',throwing);
    assert(!getappdata(probe,'ob_state_guard'));
    probing=guidata(probe); probing.config(2)=5; guidata(probe,probing);
    assert(getappdata(probe,'ob_external_state'));
    feval(get(probe,'windowbuttonupfcn'),probe,[]);

    % If provenance observation is unavailable, the full equality check is
    % still required even with an otherwise current scene.
    click_block(probe,2); setappdata(probe,'ob_state_listener',false);
    [scans,checks]=profile_motion(probe,[.01 0]); assert(scans==0 && checks==1);
    setappdata(probe,'ob_state_listener',true);
    feval(get(probe,'windowbuttonupfcn'),probe,[]);

    % Hierarchy navigation must invalidate the old scene even when both
    % diagrams happen to have the same number of blocks.
    nested = ob_subsystem_example ();
    second = octave_blocks(nested); figures(end+1) = second;
    click_block(second,1); state=guidata(second);
    state.path=1; state.selected=1; guidata(second,state);
    profile_motion(second,[.03 .01]); state=guidata(second);
    assert(!state.dragging && isequal(state.model,nested) && isequal(state.path,1));
    assert(isequal(state.graphics.diagram,ob_model_at(nested,1)) && isempty(state.undo));
    press_button(second,'Up');
    click_block(second,1); feval(get(second,'windowbuttonupfcn'),second,[]);
    press_button(second,'Enter'); state = guidata(second);
    assert(isequal(state.path,1) && isequal(state.graphics.diagram,ob_model_at(nested,1)));
    press_button(second,'Up'); state = guidata(second);
    assert(isempty(state.path) && isequal(state.graphics.diagram,nested));
    assert(state.selected==1 && all(isgraphics(state.graphics.handles)));

    % The normal Run callback also solves algebraic feedback and plots both
    % scopes without replacing the retained diagram or its model metadata.
    algebraic = ob_algebraic_example ();
    algebraic.blocks(5).algebraic_initial = 0;
    third = octave_blocks(algebraic); figures(end+1) = third;
    state = guidata(third); state.config = [0 1 .05]; guidata(third,state);
    retained = sort(findall(state.axes)); existing_figures = findall(0,'type','figure');
    assignin('base','ob_last_result',[]);
    press_button(third,'Run');
    created = setdiff(findall(0,'type','figure'),existing_figures);
    figures = [figures reshape(created,1,[])];
    result = evalin('base','ob_last_result');
    assert(isstruct(result) && numel(created)==1);
    expected = 1-exp(-max(result.t-.35,0)/2);
    assert(max(abs(ob_scope_data(result,7)-expected)) < 1e-8);
    assert(numel(findall(created,'type','line','-property','displayname')) >= 2);
    state = guidata(third);
    assert(isequal(state.model,algebraic) && isequal(sort(findall(state.axes)),retained));

    event_model = ob_zero_crossing_example ();
    fourth = octave_blocks(event_model); figures(end+1) = fourth;
    state = guidata(fourth); state.config = [0 1 1];
    state.options.zero_crossings = true; guidata(fourth,state);
    existing_figures = findall(0,'type','figure');
    assignin('base','ob_last_result',[]);
    press_button(fourth,'Run');
    created = setdiff(findall(0,'type','figure'),existing_figures);
    figures = [figures reshape(created,1,[])];
    result = evalin('base','ob_last_result');
    assert(isstruct(result) && numel(created)==1);
    assert(abs(ob_scope_data(result,6)(end)-1.25) < 1e-8);
    assert(numel(result.events)==1 && abs(result.events.time-.35) < 1e-8);
    assert(result.solver_options.zero_crossings && isequal(result.events.path,4));

    [continuous_model, continuous_options] = ob_continuous_control_example ();
    fifth = octave_blocks(continuous_model); figures(end+1) = fifth;
    state = guidata(fifth); state.config = [0 1 1];
    state.options = ob_solver_options(continuous_options); guidata(fifth,state);
    existing_figures = findall(0,'type','figure');
    assignin('base','ob_last_result',[]);
    press_button(fifth,'Run');
    created = setdiff(findall(0,'type','figure'),existing_figures);
    figures = [figures reshape(created,1,[])];
    result = evalin('base','ob_last_result');
    assert(isstruct(result) && numel(created)==1);
    assert(abs(ob_scope_data(result,6)(end)-.5) < 1e-8);
    selected_events = result.events(strcmp({result.events.type},'Conditional Subsystem'));
    assert(!isempty(selected_events) && all(arrayfun(@(item) isequal(item.path,5),selected_events)));
    state = guidata(fifth); assert(isequal(state.model,continuous_model));

    % Run expands a scalar InitialOutput to its port's width first, so a
    % subsystem first evaluated after the start plots one sample shape.
    offset_model = ob_scalar_initial_example ('offset');
    sixth = octave_blocks(offset_model); figures(end+1) = sixth;
    state = guidata(sixth); state.config = [0 2 .25]; guidata(sixth,state);
    existing_figures = findall(0,'type','figure');
    assignin('base','ob_last_result',[]);
    press_button(sixth,'Run');
    created = setdiff(findall(0,'type','figure'),existing_figures);
    figures = [figures reshape(created,1,[])];
    result = evalin('base','ob_last_result');
    assert(isstruct(result) && numel(created)==1);
    assert(isequal(ob_scope_data(result,5),[repmat([-4 -4],3,1); repmat([2.25 4.5],6,1)]));
    state = guidata(sixth); assert(isequal(state.model,offset_model));
  unwind_protect_cleanup
    for fig = figures, if(isgraphics(fig)), delete(fig); endif; endfor
    set(0,'defaultfigurevisible',previous);
  end_unwind_protect
  disp ('Octave Blocks retained editor graphics tests passed');
endfunction

function [scans,checks] = profile_motion (fig,delta)
  state=guidata(fig); point=get(state.axes,'currentpoint');
  point(:,1:2)=repmat(state.drag_origin+delta,2,1);
  set(state.axes,'currentpoint',point);
  assert(isequal(get(state.axes,'currentpoint'),point));
  profile clear; profile on;
  unwind_protect
    feval(get(fig,'windowbuttonmotionfcn'),fig,[]);
  unwind_protect_cleanup
    profile off;
  end_unwind_protect
  info=profile('info'); scans=0; checks=0;
  for entry=info.FunctionTable'
    if (!isempty(strfind(entry.FunctionName,'ob_moved_blocks'))), scans += entry.NumCalls; endif
    if (!isempty(strfind(entry.FunctionName,'ob_motion_coherent'))), checks += entry.NumCalls; endif
  endfor
endfunction

function rewrite_state (fig,evt)
  if (getappdata(fig,'test_rewrite'))
    setappdata(fig,'test_rewrite',false);
    state=guidata(fig); state.config(2)=4; guidata(fig,state);
  endif
endfunction

function throw_state (fig,evt)
  error('intentional state-listener failure');
endfunction

function assert_diagram_geometry (state)
  diagram=ob_model_at(state.model,state.path); cache=state.graphics;
  assert(isequal(cache.diagram,diagram));
  for id=1:numel(diagram.blocks)
    x=get(cache.bodies(id),'xdata'); y=get(cache.bodies(id),'ydata');
    assert(max(abs(x(:)'-(diagram.blocks(id).x+[-.105 .105 .105 -.105])))<1e-14);
    assert(max(abs(y(:)'-(diagram.blocks(id).y+[-.052 -.052 .052 .052])))<1e-14);
  endfor
  for k=1:rows(cache.edges)
    edge=cache.edges(k,:); x=get(cache.wires(k,1),'xdata'); y=get(cache.wires(k,1),'ydata');
    source=diagram.blocks(edge(1)); target=diagram.blocks(edge(3));
    assert(abs(x(1)-source.x-.105)<1e-14 && abs(x(end)-target.x+.105)<1e-14);
    source_offset=0; target_offset=0;
    if(cache.outputs(edge(1))>1), source_offset=.072*((cache.outputs(edge(1))+1)/2-edge(2))/(cache.outputs(edge(1))-1); endif
    if(cache.inputs(edge(3))>1), target_offset=.072*((cache.inputs(edge(3))+1)/2-edge(4))/(cache.inputs(edge(3))-1); endif
    assert(abs(y(1)-source.y-source_offset)<1e-14 && abs(y(end)-target.y-target_offset)<1e-14);
  endfor
endfunction

function click_block (fig,id)
  state = guidata(fig); body = state.graphics.bodies(id);
  feval(get(body,'buttondownfcn'),body,[]);
endfunction

function press_button (fig,label)
  button = findall(fig,'style','pushbutton','string',label);
  assert(numel(button)==1); feval(get(button,'callback'),button,[]);
endfunction
