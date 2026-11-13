function test_ob_editor_graphics ()
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

    % Hierarchy navigation must invalidate the old scene even when both
    % diagrams happen to have the same number of blocks.
    nested = ob_subsystem_example ();
    second = octave_blocks(nested); figures(end+1) = second;
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
  unwind_protect_cleanup
    for fig = figures, if(isgraphics(fig)), delete(fig); endif; endfor
    set(0,'defaultfigurevisible',previous);
  end_unwind_protect
  disp ('Octave Blocks retained editor graphics tests passed');
endfunction

function click_block (fig,id)
  state = guidata(fig); body = state.graphics.bodies(id);
  feval(get(body,'buttondownfcn'),body,[]);
endfunction

function press_button (fig,label)
  button = findall(fig,'style','pushbutton','string',label);
  assert(numel(button)==1); feval(get(button,'callback'),button,[]);
endfunction
