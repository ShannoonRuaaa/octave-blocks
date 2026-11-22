function cases = ob_nested_reset_cases ()
  policies = {{'held','held'}, {'held','reset'}, {'reset','held'}, ...
              {'reset','reset'}, {'reset','reset','held'}, ...
              {'held','held','reset'}, {'reset','held','reset'}};
  cases = struct ('name',{},'model',{},'options',{},'expected',{});
  for event = [false true]
    for k = 1:numel (policies)
      policy = policies{k};
      count = numel (policy);
      model.blocks = [block('Time',[],'Data'), block('Inport',1,'Enable'), ...
                      block('Subsystem',layer(policy,1,event),'Outer')];
      model.edges = [1 1 3 1; 2 1 3 2];
      model.inputs = {ob_input_signal(0:7,[1;1;0;0;1;1;0;1])};
      expected = zeros (8,count);
      for port = 1:count
        model.blocks(3+port) = block('Scope',[],sprintf('Level %d',port));
        model.edges(end+1,:) = [3 port 3+port 1];
        initial = 7+10*(port-1);
        expected(:,port) = [initial;0;0;0;1;4;4;5];
        if (strcmp(policy{port},'reset')), expected([5 8],port) = initial; endif
      endfor
      cases(end+1) = struct('name',sprintf('nested_reset_%d_%d',k,event), ...
                            'model',model,'options',struct('zero_crossings',event,'maxstep',.25), ...
                            'expected',expected);
    endfor
    for outer = {'held','reset'}
      for inner = {'held','reset'}
        model = combined_case(outer{1},inner{1},event);
        expected = [-9;17;17;17;17;1;1;1];
        if (strcmp(inner{1},'reset')), expected(6:8) = 17; endif
        cases(end+1) = struct('name',sprintf('nested_trigger_%s_%s_%d',outer{1},inner{1},event), ...
                              'model',model,'options',struct('zero_crossings',event,'maxstep',.25), ...
                              'expected',expected);
        model = combined_case(outer{1},inner{1},event,true);
        if (strcmp(outer{1},'reset'))
          % The outer reset restarts the trigger-only wrapper's history (it
          % fires again at t=7) but keeps its held output at t=4 (Simulink).
          expected([5 8]) = [17;5];
          if (strcmp(inner{1},'reset')), expected(8) = 17; endif
        endif
        cases(end+1) = struct('name',sprintf('nested_wrapper_%s_%s_%d',outer{1},inner{1},event), ...
                              'model',model,'options',struct('zero_crossings',event,'maxstep',.25), ...
                              'expected',expected);
        % With 'compatibility' the outer reset keeps the wrapper's trigger
        % history, so it does not execute at t=7.  These traces were first
        % derived from the ancestor-reset rule (the D, E and V4 probes); the
        % probes' nested_compat_wrapper_<outer>_<inner> records now hold the
        % same traces from Simulink 26.2 for this exact topology.
        model = combined_case(outer{1},inner{1},event,true,'compatibility');
        expected = [-9;17;17;17;17;1;1;1];
        if (strcmp(inner{1},'reset')), expected(6:8) = 17; endif
        cases(end+1) = struct('name',sprintf('nested_compat_wrapper_%s_%s_%d',outer{1},inner{1},event), ...
                              'model',model,'options',struct('zero_crossings',event,'maxstep',.25), ...
                              'expected',expected);
      endfor
    endfor
  endfor
endfunction

function model = combined_case (outer_policy,inner_policy,event,wrapped = false,initial = -1)
  inner = layer({inner_policy},1,false);
  inner.blocks(2).value = 17;
  if (wrapped)
    trigger.blocks = [block('Inport',1,'Data'), block('Constant',1,'Inner enable'), ...
                      block('Subsystem',inner,'Enabled'), block('Outport',1,'State')];
    trigger.edges = [1 1 3 1; 2 1 3 2; 3 1 4 1];
    trigger.execution = struct('mode','rising','initial_control',initial,'initial_outputs',{{-9}});
    inner = trigger;
  else
    inner.execution.mode = 'enabled_rising';
    inner.execution.initial_control = -1;
  endif
  outer.blocks = [block('Inport',1,'Data'), block('Inport',2,'Trigger'), ...
                  block('Constant',1,'Inner enable'), block('Subsystem',inner,'Inner'), ...
                  block('Outport',1,'State')];
  outer.edges = [1 1 4 1; 3 1 4 2; 2 1 4 3; 4 1 5 1];
  if (wrapped), outer.edges = [1 1 4 1; 2 1 4 2; 4 1 5 1]; endif
  outer.execution = struct('mode','enabled','states',outer_policy,'initial_outputs',{{-9}});
  if (event), outer.execution.control = 'continuous'; endif
  model.blocks = [block('Time',[],'Data'), block('Inport',1,'Enable'), ...
                  block('Subsystem',outer,'Outer'), block('Scope',[],'State'), ...
                  block('Inport',2,'Trigger')];
  model.edges = [1 1 3 1; 5 1 3 2; 2 1 3 3; 3 1 4 1];
  model.inputs = {ob_input_signal(0:7,[1;1;0;0;1;1;0;1]), ...
                  ob_input_signal(0:7,[-1;1;-1;-1;-1;1;-1;1])};
endfunction

function model = layer (policy,depth,event)
  model.blocks = [block('Inport',1,'Data'), block('Unit Delay',7+10*(depth-1),'State'), ...
                  block('Outport',1,'Local state')];
  model.edges = [1 1 2 1; 2 1 3 1];
  count = numel(policy)-depth+1;
  model.execution = struct('mode','enabled','states',policy{depth}, ...
                           'initial_outputs',{repmat({-9},1,count)});
  if (event), model.execution.control = 'continuous'; endif
  if (count == 1), return; endif
  model.blocks(4) = block('Constant',1,'Inner enable');
  model.blocks(5) = block('Subsystem',layer(policy,depth+1,event),'Inner');
  model.edges = [model.edges; 1 1 5 1; 4 1 5 2];
  for port = 2:count
    model.blocks(4+port) = block('Outport',port,sprintf('Level %d',depth+port-1));
    model.edges(end+1,:) = [5 port-1 4+port 1];
  endfor
endfunction

function b = block (type,value,name)
  b = struct('type',type,'value',value,'name',name,'x',.5,'y',.5);
endfunction
