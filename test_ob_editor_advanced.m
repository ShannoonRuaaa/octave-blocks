function test_ob_editor_advanced ()
  % Drive the Transport Delay and Limited Integrator editor callbacks with
  % scripted dialog answers.  Requires the Qt graphics toolkit.
  if (! any (strcmp (available_graphics_toolkits (), 'qt')))
    error ('test_ob_editor_advanced: run under the Octave GUI runtime with Qt available');
  endif
  graphics_toolkit ('qt');
  global OB_TEST_ANSWERS OB_TEST_ERRORS
  OB_TEST_ANSWERS = {}; OB_TEST_ERRORS = {};
  stubs = fullfile (tempname (), 'dialogs');
  mkdir (stubs);
  write_stub (stubs, 'inputdlg', ...
    {'function answer = inputdlg (varargin)', '  global OB_TEST_ANSWERS', ...
     '  if (isempty (OB_TEST_ANSWERS)), error (''unexpected dialog''); endif', ...
     '  answer = OB_TEST_ANSWERS{1}; OB_TEST_ANSWERS(1) = [];', 'endfunction'});
  write_stub (stubs, 'errordlg', ...
    {'function h = errordlg (message, varargin)', '  global OB_TEST_ERRORS', ...
     '  OB_TEST_ERRORS{end+1} = message; h = [];', 'endfunction'});
  addpath (stubs); rehash ();
  previous = get (0, 'defaultfigurevisible'); set (0, 'defaultfigurevisible', 'off');
  fig = [];
  unwind_protect
    B = @(type, value, name) struct ('type', type, 'value', value, 'name', name, 'x', 0.2, 'y', 0.5);
    model.blocks = [B('Constant', 1, 'One') ...
                    B('Limited Integrator', struct ('initial', 0, 'lower', -1, 'upper', 1, 'reset', 'rising'), 'Limited') ...
                    B('Step', [1 -1 1], 'Reset') B('Scope', [], 'Scope')];
    model.edges = [1 1 2 1; 3 1 2 2; 2 1 4 1];
    fig = octave_blocks (model); drawnow ();

    % Add a Transport Delay with the compact numeric form.
    OB_TEST_ANSWERS = {{'0.5', '2'}};
    press_button (fig, 'Transport Delay');
    state = guidata (fig);
    assert (numel (state.model.blocks) == 5);
    assert (strcmp (state.model.blocks(5).type, 'Transport Delay'));
    assert (isequal (state.model.blocks(5).value, [0.5 2]));
    assert (state.selected == 5);
    assert (! isempty (strfind (get (state.status, 'string'), 'delay 0.5, initial 2')));

    % A matrix initial output is stored as a struct.
    OB_TEST_ANSWERS = {{'0.25', '[1 2]'}};
    press_button (fig, 'Transport Delay');
    state = guidata (fig);
    assert (isequal (state.model.blocks(6).value, struct ('delay', 0.25, 'initial', [1 2])));

    % Invalid parameters are reported and add nothing.
    OB_TEST_ANSWERS = {{'-1', '0'}};
    press_button (fig, 'Transport Delay');
    state = guidata (fig);
    assert (numel (state.model.blocks) == 6);
    assert (! isempty (strfind (OB_TEST_ERRORS{end}, 'positive')));

    % Add a Limited Integrator with a reset port.
    OB_TEST_ANSWERS = {{'0.5', '0', '2', 'either'}};
    press_button (fig, 'Limited Int.');
    state = guidata (fig);
    block = state.model.blocks(7);
    assert (strcmp (block.type, 'Limited Integrator'));
    assert (isequal (block.value, struct ('initial', 0.5, 'lower', 0, 'upper', 2, 'reset', 'either')));
    assert (ob_block_ports (block) == 2);
    assert (numel (state.graphics.blocks) == 7);

    % Editing the wired integrator to reset 'none' removes its reset wire,
    % and undo restores both the parameters and the wire.
    click_block (fig, 2);
    feval (get (fig, 'windowbuttonupfcn'), fig, []);
    OB_TEST_ANSWERS = {{'0', '-1', '1', 'none'}};
    press_button (fig, 'Edit');
    state = guidata (fig);
    assert (strcmp (state.model.blocks(2).value.reset, 'none'));
    edges = ob_edges (state.model);
    assert (! any (edges(:, 3) == 2 & edges(:, 4) == 2));
    assert (any (edges(:, 3) == 2 & edges(:, 4) == 1));
    press_button (fig, 'Undo');
    state = guidata (fig);
    assert (strcmp (state.model.blocks(2).value.reset, 'rising'));
    edges = ob_edges (state.model);
    assert (any (edges(:, 3) == 2 & edges(:, 4) == 2));

    % An invalid edit leaves the block unchanged.
    click_block (fig, 2);
    feval (get (fig, 'windowbuttonupfcn'), fig, []);
    OB_TEST_ANSWERS = {{'0', '1', '-1', 'rising'}};
    press_button (fig, 'Edit');
    state = guidata (fig);
    assert (state.model.blocks(2).value.upper == 1);
    assert (! isempty (strfind (OB_TEST_ERRORS{end}, 'lower <= upper')));
    assert (isempty (OB_TEST_ANSWERS));
  unwind_protect_cleanup
    if (! isempty (fig) && isgraphics (fig)), delete (fig); endif
    set (0, 'defaultfigurevisible', previous);
    rmpath (stubs); rehash ();
    confirm_recursive_rmdir (false, 'local');
    rmdir (fileparts (stubs), 's');
  end_unwind_protect
  disp ('Octave Blocks advanced editor tests passed');
endfunction

function write_stub (folder, name, lines)
  fid = fopen (fullfile (folder, [name '.m']), 'w');
  fprintf (fid, '%s\n', lines{:});
  fclose (fid);
endfunction

function click_block (fig, id)
  state = guidata (fig); body = state.graphics.bodies(id);
  feval (get (body, 'buttondownfcn'), body, []);
endfunction

function press_button (fig, label)
  button = findall (fig, 'style', 'pushbutton', 'string', label);
  assert (numel (button) == 1); feval (get (button, 'callback'), button, []);
endfunction
