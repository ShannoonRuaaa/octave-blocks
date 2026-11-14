% Run in a fresh Octave process. Callers supply both source paths and output.
if (!exist('baseline_source','var') || !exist('optimized_source','var') ...
    || !exist('output_directory','var'))
  error('Supply baseline_source, optimized_source and output_directory');
endif
if (!exist(baseline_source,'dir') || !exist(optimized_source,'dir'))
  error('Both source directories must exist');
endif
if (!exist(output_directory,'dir')), mkdir(output_directory); endif
audit_initial_path=path();
audit_artifacts=fileparts(mfilename('fullpath'));
audit_sources={baseline_source,optimized_source};
for audit_version=1:2
 clear functions;path(audit_initial_path);addpath(audit_sources{audit_version});benchmark_ob_editor_ui([10 40],12);
endfor
audit_results=struct('version',{},'round',{},'blocks',{},'clicks',{},'seconds',{},'per_click',{});
for audit_round=1:3
 if(mod(audit_round,2)),audit_order=[1 2 2 1];else audit_order=[2 1 1 2];endif
 for audit_version=audit_order
  clear functions;path(audit_initial_path);addpath(audit_sources{audit_version});
  assert(strcmpi(strrep(which('octave_blocks'),'\\','/'),strrep(fullfile(audit_sources{audit_version},'octave_blocks.m'),'\\','/')));
  audit_rows=benchmark_ob_editor_ui([10 40],12);
  for audit_row=audit_rows
   audit_results(end+1)=struct('version',audit_version,'round',audit_round,'blocks',audit_row.blocks,'clicks',audit_row.clicks,'seconds',audit_row.seconds,'per_click',audit_row.per_click);
  endfor
 endfor
endfor
for audit_count=[10 40]
 audit_before=audit_results([audit_results.blocks]==audit_count&[audit_results.version]==1);audit_after=audit_results([audit_results.blocks]==audit_count&[audit_results.version]==2);
 fprintf('INTERLEAVED UI%d before %.6f after %.6f ratio %.3f\n',audit_count,median([audit_before.per_click]),median([audit_after.per_click]),median([audit_after.per_click])/median([audit_before.per_click]));
endfor
audit_fid=fopen(fullfile(output_directory,'interleaved-ui.json'),'wb');assert(audit_fid>=0);fwrite(audit_fid,jsonencode(audit_results),'char');fclose(audit_fid);
