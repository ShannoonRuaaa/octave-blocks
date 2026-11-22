function test_ob_editor_event_export (directory = '', verify = false)
  test_path_cleanup = ob_test_setup ();
  % Exercise the actual Qt Export C callback with scoped file/dialog responses.
  % The emitted sources are compiled by Test-Editor.ps1 and verified here.
  if (verify), verify_exports(directory); return; endif
  if (isempty(directory)), directory = tempname(); endif
  if (!exist(directory,'dir')), mkdir(directory); endif
  directory = canonicalize_file_name(directory);
  mocks = tempname(directory); mkdir(mocks);
  previous_path = path(); previous_visible = get(0,'defaultfigurevisible');
  previous_warning = warning('query','Octave:shadowed-function');
  key = 'ob_test_event_export_dialog';
  had_appdata = isappdata(0,key);
  if (had_appdata), previous_appdata = getappdata(0,key); endif
  had_export = evalin('base',"exist('ob_last_export','var')");
  if (had_export), previous_export = evalin('base','ob_last_export'); endif
  figures = []; manifest = struct('name',{},'source',{},'expected',{});
  unwind_protect
    write_text(fullfile(mocks,'uiputfile.m'), [
      'function [file,folder]=uiputfile(varargin)' char(10) ...
      ' state=getappdata(0,''ob_test_event_export_dialog'');' char(10) ...
      ' state.calls+=1;setappdata(0,''ob_test_event_export_dialog'',state);' char(10) ...
      ' file=state.file;folder=state.folder;' char(10) 'endfunction' char(10)]);
    for dialog = {'msgbox','errordlg'}
      write_text(fullfile(mocks,[dialog{1} '.m']), sprintf([
        'function handle=%s(message,varargin)\n' ...
        ' state=getappdata(0,''ob_test_event_export_dialog'');\n' ...
        ' state.%s{end+1}=message;setappdata(0,''ob_test_event_export_dialog'',state);\n' ...
        ' handle=[];\nendfunction\n'],dialog{1},dialog{1}));
    endfor
    warning('off','Octave:shadowed-function'); addpath(mocks,'-begin');
    clear uiputfile msgbox errordlg;
    set(0,'defaultfigurevisible','off');
    models = {ob_zero_crossing_example()};
    options = {struct('solver','rk4','zero_crossings',true,'maxstep',.1)};
    [models{2},options{2}] = ob_continuous_control_example();
    names = {'editor_primitive_events','editor_continuous_control'};
    for index = 1:2
      model = models{index}; config = [0 1 .2];
      % The complete gate window lies between the coarse output endpoints;
      % its successful integral also checks propagation of maxstep=.1.
      if (index==2), config = [0 1 1]; endif
      fig = octave_blocks(model); figures(end+1) = fig;
      state = guidata(fig); state.config = config;
      state.options = ob_solver_options(options{index}); guidata(fig,state);
      if (index==2)
        % Export remains rooted in the whole model while viewing its body.
        state.selected = 5; guidata(fig,state); press_button(fig,'Enter');
        assert(isequal(guidata(fig).path,5));
      endif
      saved = guidata(fig);
      source = [names{index} '.c']; response = dialog_response(source,directory);
      setappdata(0,key,response); assignin('base','ob_last_export',[]);
      press_button(fig,'Export C');
      response = getappdata(0,key); info = evalin('base','ob_last_export');
      assert(response.calls==1 && numel(response.msgbox)==1 && isempty(response.errordlg), ...
             ['editor export callback failed: ' names{index} ' ' strjoin(response.errordlg,'; ')]);
      assert(isstruct(info) && info.zero_crossings && info.event_guard_count>0);
      assert(strcmp(info.source,fullfile(directory,source)) && strcmp(info.solver,'rk4'));
      after = guidata(fig);
      assert(isequaln(after.model,saved.model) && isequal(after.path,saved.path));
      assert(isequal(after.config,saved.config) && isequaln(after.options,saved.options));
      assert(isequaln(after.undo,saved.undo) && isequaln(after.redo,saved.redo));
      result = ob_run(model,ob_time_grid(config(1),config(2),config(3)),options{index});
      scope = ob_scope_data(result,6);
      if (index==1), wanted=1.25; else wanted=.5; endif
      assert(abs(scope(end)-wanted)<2e-8);
      expected = result.t;
      for block = 1:numel(result.compiled_model.blocks)
        count = prod(info.shapes{block});
        if (count==0), continue; endif
        trace = zeros(numel(result.t),count);
        for sample = 1:numel(result.t)
          value = result.flat_values{sample,block};
          assert(isnumeric(value) && isreal(value) && isequal(size(value),info.shapes{block}));
          trace(sample,:) = value(:)';
        endfor
        assert(all(isfinite(trace(:)))); expected = [expected trace];
      endfor
      expected_file = [names{index} '.expected.csv'];
      dlmwrite(fullfile(directory,expected_file),expected,'precision','%.17g');
      manifest(end+1) = struct('name',names{index},'source',source,'expected',expected_file);

      % Cancelling the picker leaves the export result and editor untouched.
      response = dialog_response(0,directory); setappdata(0,key,response);
      press_button(fig,'Export C'); response = getappdata(0,key);
      assert(response.calls==1 && isempty(response.msgbox) && isempty(response.errordlg));
      assert(isequaln(evalin('base','ob_last_export'),info));
      after = guidata(fig); assert(isequaln(after.model,saved.model));

      % A real unsupported selection reports an error and preserves the file.
      protected = fullfile(directory,[names{index} '.protected.c']);
      sentinel = sprintf('existing source must survive\n'); write_text(protected,sentinel);
      response = dialog_response([names{index} '.protected.c'],directory);
      setappdata(0,key,response); state = guidata(fig); state.options.solver = 'ode45';
      guidata(fig,state); press_button(fig,'Export C'); response = getappdata(0,key);
      assert(response.calls==1 && isempty(response.msgbox) && numel(response.errordlg)==1);
      assert(!isempty(strfind(response.errordlg{1},'rk4')));
      assert(strcmp(fileread(protected),sentinel));
      assert(isequaln(evalin('base','ob_last_export'),info));
    endfor
    write_text(fullfile(directory,'editor-event-manifest.json'),jsonencode(manifest));
  unwind_protect_cleanup
    for fig = figures, if(isgraphics(fig)), delete(fig); endif; endfor
    set(0,'defaultfigurevisible',previous_visible);
    path(previous_path); clear uiputfile msgbox errordlg;
    warning(previous_warning.state,'Octave:shadowed-function');
    if (had_appdata), setappdata(0,key,previous_appdata);
    elseif (isappdata(0,key)), rmappdata(0,key); endif
    if (had_export), assignin('base','ob_last_export',previous_export);
    else evalin('base','clear ob_last_export'); endif
    if (exist(mocks,'dir')), rmdir(mocks,'s'); endif
  end_unwind_protect
  disp('Octave Blocks Qt event export, cancellation and protected-file tests passed');
endfunction

function response = dialog_response (file,folder)
  response = struct('file',file,'folder',folder,'calls',0,'msgbox',{{}},'errordlg',{{}});
endfunction

function press_button (fig,label)
  button = findall(fig,'style','pushbutton','string',label);
  assert(numel(button)==1); feval(get(button,'callback'),button,[]);
endfunction

function verify_exports (directory)
  manifest = jsondecode(fileread(fullfile(directory,'editor-event-manifest.json')));
  worst = 0; channels = 0;
  for item = reshape(manifest,1,[])
    expected = dlmread(fullfile(directory,item.expected),',');
    actual = dlmread(fullfile(directory,[item.name '.csv']),',',1,0);
    assert(isequal(size(actual),size(expected)),['editor export CSV shape: ' item.name]);
    assert(all(isfinite(actual(:))),['editor export nonfinite output: ' item.name]);
    scaled = abs(actual-expected)./max(1,abs(expected));
    difference = max(scaled(:));
    assert(difference<2e-8,sprintf('editor export mismatch %s: %.17g',item.name,difference));
    worst = max(worst,difference); channels += columns(actual)-1;
  endfor
  fprintf('Compared %d exact Qt-exported C models (%d numeric channels); worst scaled error %.3g\n', ...
          numel(manifest),channels,worst);
endfunction

function write_text (file,value)
  stream = fopen(file,'wb'); assert(stream>=0);
  unwind_protect
    assert(fwrite(stream,value,'char')==numel(value));
  unwind_protect_cleanup
    fclose(stream);
  end_unwind_protect
endfunction
