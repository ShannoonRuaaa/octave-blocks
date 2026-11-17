function measurements = benchmark_ob_editor_drag (counts = [10 40], motions = 12, samples = 5)
  % Actual Qt motion callbacks, including paint dispatch. Compare separate
  % baseline/candidate processes with the same counts, motions and samples.
  if (!any(strcmp(available_graphics_toolkits(),'qt')))
    error ('benchmark_ob_editor_drag: the Octave GUI runtime with Qt is required');
  endif
  graphics_toolkit ('qt');
  previous=get(0,'defaultfigurevisible'); set(0,'defaultfigurevisible','off');
  measurements=struct('blocks',{},'motions',{},'per_motion',{},'samples',{});
  unwind_protect
    for count=counts
      model=ob_example(); model.blocks=repmat(model.blocks(2),1,count);
      model.blocks(1).type='Constant'; model.blocks(1).value=1;
      model.blocks(end).type='Scope'; model.blocks(end).value=[];
      for id=1:count
        model.blocks(id).x=.15+.17*mod(id-1,5);
        model.blocks(id).y=.85-.07*mod(floor((id-1)/5),10);
      endfor
      model.edges=[(1:count-1)' (2:count)'];
      fig=octave_blocks(model);
      unwind_protect
        drawnow(); state=guidata(fig); id=ceil(count/2);
        body=state.graphics.bodies(id); feval(get(body,'buttondownfcn'),body,[]);
        elapsed=zeros(1,samples);
        for sample=0:samples
          timer=tic();
          for k=1:motions
            state=guidata(fig); point=get(state.axes,'currentpoint');
            point(:,1:2)=repmat(state.drag_origin+[.012 .008]*(-1)^k,2,1);
            set(state.axes,'currentpoint',point);
            assert(isequal(get(state.axes,'currentpoint'),point));
            feval(get(fig,'windowbuttonmotionfcn'),fig,[]); drawnow();
          endfor
          seconds=toc(timer);
          if(sample>0), elapsed(sample)=seconds/motions; endif
        endfor
        feval(get(fig,'windowbuttonupfcn'),fig,[]);
        measurements(end+1)=struct('blocks',count,'motions',motions, ...
            'per_motion',median(elapsed),'samples',elapsed);
        fprintf('%d blocks, %d motions/sample: median %.6f seconds/motion; samples %s\n', ...
            count,motions,median(elapsed),mat2str(elapsed,6));
      unwind_protect_cleanup
        if(isgraphics(fig)), delete(fig); endif
      end_unwind_protect
    endfor
  unwind_protect_cleanup
    set(0,'defaultfigurevisible',previous);
  end_unwind_protect
endfunction
