function test_ob_codegen_metadata ()
  test_path_cleanup = ob_test_setup ();
  directory = tempname (); mkdir (directory);
  unwind_protect
    options = struct ('zero_crossings',true);
    legacy = export_model (ob_example());
    event = export_model (ob_example(),options);
    assert (isequal(sort(fieldnames(legacy)),sort(fieldnames(event))));
    assert (!legacy.zero_crossings && event.zero_crossings);
    assert (!legacy.typed_conditional && !event.typed_conditional);
    assert (legacy.event_guard_count==0 && event.event_guard_count==0);
    assert (legacy.continuous_state_count==0 && event.continuous_state_count==0);
    assert (legacy.clock_count==0 && isempty(legacy.clocks));
    assert (isequal(fieldnames(legacy.clocks),{'path';'rate'}));

    matrix = ob_example();
    matrix.blocks(1).type='Constant'; matrix.blocks(1).value=ones(2);
    matrix.blocks(2).type='Integrator'; matrix.blocks(2).value=zeros(2);
    plain = export_model(matrix); events = export_model(matrix,options);
    assert (plain.continuous_state_count==4 && events.continuous_state_count==4);
    assert (plain.state_count==4 && events.state_count==4);

    % Equal clock rates belong to distinct blocks and retain both paths.
    clocks = ob_enabled_multirate_example();
    child = clocks.blocks(3).value;
    child.execution = struct('mode','virtual');
    child.sample_times(2:3,:) = [.25 .125;.25 .125];
    clocks.blocks(3).value=child; clocks.sample_times(3,:)=[0 0];
    clocks.edges(clocks.edges(:,3)==3 & clocks.edges(:,4)==2,:) = [];
    plain = export_model(clocks); events = export_model(clocks,options);
    expected = struct('path',{[3 2],[3 3]},'rate',{[.25 .125],[.25 .125]});
    assert (plain.clock_count==2 && isequal(plain.clocks,expected));
    assert (events.clock_count==2 && isequal(events.clocks,expected));
    assert (!plain.typed_conditional && !events.typed_conditional);

    clocks = ob_enabled_multirate_example();
    clocks.blocks(3).value.sample_times(2:3,:) = [.125 0;.125 0];
    plain = export_model(clocks); events = export_model(clocks,options);
    expected = struct('path',{3,[3 2],[3 3]}, ...
                     'rate',{[.125 0],[.125 0],[.125 0]});
    assert (plain.clock_count==3 && isequal(plain.clocks,expected));
    assert (events.clock_count==3 && isequal(events.clocks,expected));
    assert (plain.typed_conditional && events.typed_conditional);
    assert (plain.event_guard_count==0 && events.event_guard_count==0);

    [continuous, controls] = ob_continuous_control_example();
    continuous = export_model(continuous,controls);
    assert (continuous.typed_conditional && continuous.zero_crossings);
    assert (continuous.continuous_state_count==1 && continuous.event_guard_count==1);
    assert (continuous.clock_count==0 && isempty(continuous.clocks));
    primitive = export_model(ob_control_example(),options);
    assert (primitive.event_guard_count==5 && !primitive.typed_conditional);
    disp ('Octave Blocks codegen metadata tests passed');
  unwind_protect_cleanup
    rmdir (directory,'s');
  end_unwind_protect

  function info = export_model (model, options = struct())
    info = ob_codegen(model,fullfile(directory,'model.c'),[0 1 .5],options);
    assert (info.clock_count==numel(info.clocks));
  endfunction
endfunction
