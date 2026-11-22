function capture_readme_images (directory = fullfile(fileparts(fileparts(mfilename('fullpath'))),'doc','images'))
  if (!exist(directory,'dir')), mkdir(directory); endif
  ob_setup ();
  graphics_toolkit('qt');
  fig = octave_blocks(ob_oscillator());
  unwind_protect
    drawnow(); pause(.5);
    frame = getframe(fig);
    imwrite(frame.cdata,fullfile(directory,'editor-canvas.png'));
  unwind_protect_cleanup
    delete(fig);
  end_unwind_protect
  model = ob_oscillator();
  result = ob_run(model,0:.02:12);
  fig = figure('visible','off','color','white','position',[100 100 1100 480]);
  unwind_protect
    values = ob_scope_data(result,4);
    plot(result.t,cos(result.t),'--','color',[.55 .62 .72],'linewidth',2); hold on;
    plot(result.t,values,'color',[.05 .40 .62],'linewidth',2);
    grid on; box off;
    xlabel('Time (s)'); ylabel('Position');
    title('Oscillator: simulated position and analytical reference');
    legend({'cos(t) reference','Octave Blocks RK4'},'location','northeast');
    set(gca,'fontsize',12);
    print(fig,fullfile(directory,'oscillator.png'),'-dpng','-r130');
    assert(max(abs(values(:)-cos(result.t(:))))<1e-6);
  unwind_protect_cleanup
    delete(fig);
  end_unwind_protect
endfunction
