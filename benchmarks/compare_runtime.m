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
if (!exist('comparison_cases','var')), comparison_cases={'sampled','continuous','primitive','graph1000','graph10000','input16','input1000','input100000'}; endif
audit_labels=comparison_cases;
audit_results=struct('case',{},'version',{},'round',{},'wall',{},'cpu',{},'checksum',{},'steps',{},'events',{});
for audit_label=audit_labels
 for audit_round=1:3
  if(mod(audit_round,2)),audit_order=[1 2 2 1];else audit_order=[2 1 1 2];endif
  for audit_version=audit_order
   clear functions;
   path(audit_initial_path);addpath(audit_artifacts);addpath(audit_sources{audit_version});
   assert(strcmpi(strrep(which('ob_run'),'\\','/'),strrep(fullfile(audit_sources{audit_version},'ob_run.m'),'\\','/')));
   audit_value=audit_timed_case(audit_label{1});
   audit_results(end+1)=struct('case',audit_label{1},'version',audit_version,'round',audit_round,'wall',audit_value.wall,'cpu',audit_value.cpu,'checksum',audit_value.checksum,'steps',audit_value.steps,'events',audit_value.events);
  endfor
 endfor
 audit_before=audit_results(strcmp({audit_results.case},audit_label{1})&[audit_results.version]==1);audit_after=audit_results(strcmp({audit_results.case},audit_label{1})&[audit_results.version]==2);
 assert(all(abs([audit_before.checksum]-[audit_after.checksum])<1e-8));assert(isequal([audit_before.steps],[audit_after.steps]));assert(isequal([audit_before.events],[audit_after.events]));
 fprintf('INTERLEAVED %s before %.6f after %.6f ratio %.3f; CPU before %.6f after %.6f\n',audit_label{1},median([audit_before.wall]),median([audit_after.wall]),median([audit_after.wall])/median([audit_before.wall]),median([audit_before.cpu]),median([audit_after.cpu]));
endfor
audit_fid=fopen(fullfile(output_directory,'interleaved-runtime.json'),'wb');assert(audit_fid>=0);fwrite(audit_fid,jsonencode(audit_results),'char');fclose(audit_fid);
