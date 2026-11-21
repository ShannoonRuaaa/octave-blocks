function varargout = ob_simulink (command, varargin)
  % OB_SIMULINK  Simulink-style programmatic modelling commands.
  %   Implements new_system, load_system, open_system, save_system,
  %   close_system, bdclose, add_block, delete_block, add_line, delete_line,
  %   set_param, get_param, find_system and sim on top of Octave Blocks
  %   models.  Add the 'simulink' subfolder to the path to call these
  %   commands by their Simulink names, e.g.
  %
  %     addpath (fullfile (fileparts (which ('ob_simulink')), 'simulink'));
  %     new_system ('demo');
  %     add_block ('simulink/Sources/Sine Wave', 'demo/Sine');
  %     add_block ('simulink/Continuous/Integrator', 'demo/Int');
  %     add_block ('simulink/Sinks/Out1', 'demo/Out1');
  %     add_line ('demo', 'Sine/1', 'Int/1'); add_line ('demo', 'Int/1', 'Out1/1');
  %     set_param ('demo', 'StopTime', '5');
  %     out = sim ('demo');  plot (out.tout, out.yout);
  %
  %   Systems live in a session registry keyed by name.  See SIMULINK_API.md
  %   for the supported library blocks, parameters and differences.
  persistent systems;
  if (isempty (systems)), systems = struct ('name', {}, 'model', {}, 'params', {}, 'file', {}); endif
  if (! ischar (command)), error ('ob_simulink: command must be a name'); endif
  varargout = {};
  switch (command)
    case 'new_system'
      name = system_name (varargin{1});
      if (! isempty (find_entry (systems, name)))
        error ('new_system: a system named ''%s'' is already loaded', name);
      endif
      systems(end+1) = new_entry (name, empty_model (), default_params (), '');
      if (nargout > 0), varargout{1} = name; endif
    case 'load_system'
      file = varargin{1};
      [folder, name, extension] = fileparts (file);
      if (isempty (extension)), file = [file '.mat']; extension = '.mat'; endif
      if (any (strcmpi (extension, {'.slx', '.mdl'})))
        error ('load_system: Simulink .slx/.mdl files are not supported; use an Octave Blocks .mat model');
      endif
      index = find_entry (systems, name);
      if (isempty (index))
        if (! exist (file, 'file')) && exist ([name '.mat'], 'file'), file = [name '.mat']; endif
        [model, config, options] = ob_load_model (file);
        params = params_from_settings (default_params (), config, options);
        systems(end+1) = new_entry (name, model, params, file);
      endif
      if (nargout > 0), varargout{1} = name; endif
    case 'open_system'
      index = require_entry (systems, varargin{1});
      model = realize_model (systems(index).model);
      varargout{1} = octave_blocks (model);
      if (nargout == 0), varargout = {}; endif
    case 'close_system'
      if (isempty (varargin)), error ('close_system: name the system to close'); endif
      name = root_name (varargin{1});
      index = find_entry (systems, name);
      if (numel (varargin) > 1 && ! isempty (index) && is_true (varargin{2}))
        systems(index) = save_entry (systems(index), systems(index).file);
      endif
      if (! isempty (index)), systems(index) = []; endif
    case 'bdclose'
      if (isempty (varargin) || strcmp (varargin{1}, 'all'))
        systems = systems([]);
      else
        index = find_entry (systems, root_name (varargin{1}));
        if (! isempty (index)), systems(index) = []; endif
      endif
    case 'save_system'
      index = require_entry (systems, varargin{1});
      file = systems(index).file;
      if (numel (varargin) > 1), file = varargin{2}; endif
      if (isempty (file)), file = [systems(index).name '.mat']; endif
      systems(index) = save_entry (systems(index), file);
      if (nargout > 0), varargout{1} = file; endif
    case 'bdIsLoaded'
      varargout{1} = ! isempty (find_entry (systems, system_name (varargin{1})));
    case 'add_block'
      [systems, path] = add_block (systems, varargin{:});
      if (nargout > 0), varargout{1} = path; endif
    case 'delete_block'
      systems = delete_block (systems, varargin{1});
    case 'add_line'
      systems = edit_line (systems, true, varargin{:});
      if (nargout > 0), varargout{1} = [varargin{1} ':' varargin{2} '->' varargin{3}]; endif
    case 'delete_line'
      systems = edit_line (systems, false, varargin{:});
    case 'set_param'
      systems = set_param (systems, varargin{:});
    case 'get_param'
      varargout{1} = get_param (systems, varargin{:});
    case 'find_system'
      varargout{1} = find_system (systems, varargin{:});
    case 'sim'
      [varargout{1:max(1, nargout)}] = simulate (systems, nargout, varargin{:});
    case 'get_model'
      % Octave Blocks model and run settings behind a loaded system.
      index = require_entry (systems, varargin{1});
      varargout{1} = realize_model (systems(index).model);
      [varargout{2}, varargout{3}] = run_settings (systems(index).params);
    case 'list'
      varargout{1} = {systems.name};
    otherwise
      error ('ob_simulink: unknown command ''%s''', command);
  endswitch
endfunction

%% ---------------------------------------------------------------- registry

function entry = new_entry (name, model, params, file)
  entry = struct ('name', name, 'model', model, 'params', params, 'file', file);
endfunction

function model = empty_model ()
  model.blocks = struct ('type', {}, 'value', {}, 'name', {}, 'x', {}, 'y', {});
  model.edges = zeros (0, 4);
endfunction

function params = default_params ()
  % Simulink configuration defaults; AbsTol, MaxStep and FixedStep 'auto'.
  params = struct ('StartTime', '0.0', 'StopTime', '10.0', 'Solver', 'VariableStepAuto', ...
                   'FixedStep', 'auto', 'RelTol', '1e-3', 'AbsTol', 'auto', ...
                   'MaxStep', 'auto', 'ZeroCrossControl', 'UseLocalSettings');
endfunction

function params = params_from_settings (params, config, options)
  params.StartTime = num2str (config(1), 17); params.StopTime = num2str (config(2), 17);
  params.FixedStep = num2str (config(3), 17);
  solvers = struct ('rk4', 'ode4', 'ode45', 'ode45', 'ode15s', 'ode15s');
  params.Solver = solvers.(options.solver);
  params.RelTol = num2str (options.reltol, 17); params.AbsTol = num2str (options.abstol, 17);
  if (isfinite (options.maxstep)), params.MaxStep = num2str (options.maxstep, 17); endif
  if (options.zero_crossings), params.ZeroCrossControl = 'EnableAll';
  else params.ZeroCrossControl = 'DisableAll'; endif
endfunction

function index = find_entry (systems, name)
  index = find (strcmp ({systems.name}, name), 1);
endfunction

function index = require_entry (systems, name)
  name = root_name (name);
  index = find_entry (systems, name);
  if (isempty (index))
    error ('ob_simulink: system ''%s'' is not loaded; use new_system or load_system', name);
  endif
endfunction

function name = system_name (name)
  if (! ischar (name) || isempty (name) || rows (name) != 1 || ! isvarname (name))
    error ('ob_simulink: system names must be valid identifiers');
  endif
endfunction

function name = root_name (path)
  if (! ischar (path) || isempty (path)), error ('ob_simulink: expected a system or block path'); endif
  parts = split_path (path); name = parts{1};
endfunction

function entry = save_entry (entry, file)
  [folder, unused, extension] = fileparts (file);
  if (isempty (extension)), file = [file '.mat'];
  elseif (! strcmpi (extension, '.mat'))
    error ('save_system: only Octave Blocks .mat files can be written');
  endif
  [config, options] = run_settings (entry.params);
  ob_save_model (file, realize_model (entry.model), config, options);
  entry.file = file;
endfunction

%% ---------------------------------------------------------------- paths

function parts = split_path (path)
  % Simulink escapes a literal slash in a name as '//'.
  marker = char (1);
  parts = strsplit (strrep (path, '//', marker), '/');
  parts = strrep (parts, marker, '/');
endfunction

function [index, levels, id] = resolve (systems, path)
  % levels: numeric subsystem path of the diagram holding the block;
  % id: block index, or [] when PATH names a system or subsystem diagram.
  parts = split_path (path);
  index = require_entry (systems, parts{1});
  model = systems(index).model;
  levels = []; id = [];
  for k = 2:numel (parts)
    diagram = ob_model_at (model, levels);
    found = find (strcmp (display_names (diagram), parts{k}), 1);
    if (isempty (found))
      error ('ob_simulink: block ''%s'' does not exist', path);
    endif
    if (k < numel (parts))
      if (! strcmp (diagram.blocks(found).type, 'Subsystem') || is_masked (diagram.blocks(found)))
        error ('ob_simulink: ''%s'' is not an editable subsystem', strjoin (parts(1:k), '/'));
      endif
      levels(end+1) = found;
    else
      id = found;
    endif
  endfor
endfunction

function [index, levels] = resolve_diagram (systems, path)
  [index, levels, id] = resolve (systems, path);
  if (! isempty (id))
    model = ob_model_at (systems(index).model, levels);
    if (! strcmp (model.blocks(id).type, 'Subsystem') || is_masked (model.blocks(id)))
      error ('ob_simulink: ''%s'' is not a system or editable subsystem', path);
    endif
    levels(end+1) = id;
  endif
endfunction

function yes = is_masked (block)
  % Subsystems realized from a library block (Transfer Fcn, PID, ...) are
  % opaque, like masked Simulink blocks.
  yes = isfield (block, 'simulink') && isstruct (block.simulink) ...
        && ! isempty (block.simulink) && ! strcmp (block.simulink.BlockType, 'SubSystem');
endfunction

%% ---------------------------------------------------------------- library

function [block_type, params] = library_block (source)
  % Map a library path (e.g. 'simulink/Math Operations/Gain' or
  % 'built-in/Gain') to a BlockType and its default dialog parameters.
  parts = split_path (source);
  key = lower (strtrim (parts{end}));
  P = @(varargin) struct (varargin{:});
  switch (key)
    case 'constant',            block_type = 'Constant';   params = P('Value', '1');
    case 'clock',               block_type = 'Clock';      params = struct ();
    case 'step',                block_type = 'Step';       params = P('Time', '1', 'Before', '0', 'After', '1');
    case {'sine wave', 'sin'},  block_type = 'Sin';        params = P('Amplitude', '1', 'Bias', '0', 'Frequency', '1', 'Phase', '0');
    case 'ramp',                block_type = 'Ramp';       params = P('Slope', '1', 'Start', '0', 'InitialOutput', '0');
    case 'ground',              block_type = 'Ground';     params = struct ();
    case 'gain',                block_type = 'Gain';       params = P('Gain', '1');
    case {'sum', 'add'},        block_type = 'Sum';        params = P('Inputs', '++');
    case 'subtract',            block_type = 'Sum';        params = P('Inputs', '+-');
    case 'product',             block_type = 'Product';    params = P('Inputs', '2', 'Multiplication', 'Element-wise(.*)');
    case 'divide',              block_type = 'Product';    params = P('Inputs', '*/', 'Multiplication', 'Element-wise(.*)');
    case 'abs',                 block_type = 'Abs';        params = struct ();
    case 'sqrt',                block_type = 'Sqrt';       params = P('Operator', 'sqrt');
    case 'math function',       block_type = 'Math';       params = P('Operator', 'exp');
    case 'trigonometric function', block_type = 'Trigonometry'; params = P('Operator', 'sin');
    case {'matlab fcn', 'interpreted matlab function'}
      block_type = 'MATLABFcn'; params = P('MATLABFcn', 'sin');
    case 'fcn',                 block_type = 'Fcn';        params = P('Expr', 'sin(u)');
    case 'unit delay',          block_type = 'UnitDelay';  params = P('InitialCondition', '0', 'SampleTime', '-1');
    case 'discrete-time integrator'
      block_type = 'DiscreteIntegrator'; params = P('InitialCondition', '0', 'SampleTime', '-1');
    case 'integrator'
      block_type = 'Integrator';
      params = P('InitialCondition', '0', 'LimitOutput', 'off', 'UpperSaturationLimit', 'inf', ...
                 'LowerSaturationLimit', '-inf', 'ExternalReset', 'none');
    case 'transport delay',     block_type = 'TransportDelay'; params = P('DelayTime', '1', 'InitialOutput', '0');
    case 'saturation',          block_type = 'Saturate';   params = P('UpperLimit', '0.5', 'LowerLimit', '-0.5');
    case 'dead zone',           block_type = 'DeadZone';   params = P('LowerValue', '-0.5', 'UpperValue', '0.5');
    case 'switch',              block_type = 'Switch';     params = P('Threshold', '0', 'Criteria', 'u2 >= Threshold');
    case 'rate transition',     block_type = 'RateTransition'; params = P('OutPortSampleTime', '-1', 'InitialCondition', '0');
    case {'scope', 'display', 'terminator'}
      block_type = 'Scope'; params = struct ();
    case 'to workspace',        block_type = 'ToWorkspace'; params = P('VariableName', 'simout');
    case {'in1', 'inport'},     block_type = 'Inport';     params = P('Port', '');
    case {'out1', 'outport'},   block_type = 'Outport';    params = P('Port', '');
    case 'subsystem',           block_type = 'SubSystem';  params = P('Mode', 'virtual');
    case 'enabled subsystem',   block_type = 'SubSystem';  params = P('Mode', 'enabled');
    case 'triggered subsystem', block_type = 'SubSystem';  params = P('Mode', 'rising');
    case 'enabled and triggered subsystem', block_type = 'SubSystem'; params = P('Mode', 'enabled_rising');
    case 'resettable subsystem', block_type = 'SubSystem'; params = P('Mode', 'reset_rising');
    case 'enable',              block_type = 'EnablePort'; params = struct ();
    case 'trigger',             block_type = 'TriggerPort'; params = P('TriggerType', 'rising');
    case 'reset',               block_type = 'ResetPort';  params = P('ResetTriggerType', 'rising');
    case 'transfer fcn',        block_type = 'TransferFcn'; params = P('Numerator', '[1]', 'Denominator', '[1 1]');
    case 'state-space'
      block_type = 'StateSpace'; params = P('A', '1', 'B', '1', 'C', '1', 'D', '1', 'InitialCondition', '0');
    case 'zero-pole',           block_type = 'ZeroPole';   params = P('Zeros', '[1]', 'Poles', '[0 -1]', 'Gain', '[1]');
    case 'discrete transfer fcn'
      block_type = 'DiscreteTransferFcn'; params = P('Numerator', '[1]', 'Denominator', '[1 0.5]', 'SampleTime', '1');
    case 'discrete state-space'
      block_type = 'DiscreteStateSpace';
      params = P('A', '1', 'B', '1', 'C', '1', 'D', '1', 'InitialCondition', '0', 'SampleTime', '1');
    case {'pid controller', 'discrete pid controller'}
      block_type = 'PIDController';
      params = P('P', '1', 'I', '1', 'D', '0', 'N', '100', 'Form', 'Parallel', ...
                 'TimeDomain', 'Continuous-time', 'SampleTime', '-1', ...
                 'LimitOutput', 'off', 'UpperSaturationLimit', 'inf', 'LowerSaturationLimit', '-inf');
      if (strcmp (key, 'discrete pid controller'))
        params.TimeDomain = 'Discrete-time'; params.SampleTime = '1';
      endif
    case {'1-d lookup table', 'lookup table', '1-d lookup'}
      block_type = 'Lookup_n-D'; params = P('BreakpointsForDimension1', '[-5:5]', 'Table', 'tanh([-5:5])', ...
                                         'ExtrapMethod', 'Clip');
    case 'rate limiter'
      block_type = 'RateLimiter'; params = P('RisingSlewLimit', '1', 'FallingSlewLimit', '-1', ...
                                           'SampleTime', '0.1', 'InitialCondition', '0');
    case 'relay'
      block_type = 'Relay'; params = P('OnSwitchValue', 'eps', 'OffSwitchValue', 'eps', ...
                                     'OnOutputValue', '1', 'OffOutputValue', '0', 'SampleTime', '0.1');
    otherwise
      error ('add_block: library block ''%s'' is not supported by Octave Blocks', source);
  endswitch
endfunction

function value = evaluate (text, block_type, name)
  % Dialog parameters are Octave expressions evaluated in the base workspace.
  if (ischar (text))
    try
      value = evalin ('base', text);
    catch err
      error ('ob_simulink: %s parameter %s = ''%s'' cannot be evaluated: %s', ...
             block_type, name, text, err.message);
    end_try_catch
  else
    value = text;
  endif
endfunction

function text = as_text (value)
  if (ischar (value)), text = value;
  elseif (isnumeric (value) || islogical (value)), text = mat2str (value, 17);
  else error ('ob_simulink: parameter values must be text or numeric');
  endif
endfunction

function [type, value, extra] = realize (meta, name)
  % Octave Blocks type/value for a block's Simulink parameters.  EXTRA holds
  % optional 'rate' ([period offset]) and 'outputs' fields.
  p = meta.Params; bt = meta.BlockType;
  E = @(field) evaluate (p.(field), bt, field);
  extra = struct ();
  switch (bt)
    case 'Constant', type = 'Constant'; value = E('Value');
    case 'Clock', type = 'Time'; value = [];
    case 'Ground', type = 'Constant'; value = 0;
    case 'Step', type = 'Step'; value = [E('Time') E('Before') E('After')];
    case 'Sin'
      % y = Amplitude*sin(Frequency*t + Phase) + Bias from native blocks.
      type = 'Subsystem';
      value = sine_subsystem (E('Amplitude'), E('Bias'), E('Frequency'), E('Phase'));
    case 'Ramp'
      % y = InitialOutput + Slope*(t - Start) for t >= Start.
      type = 'Subsystem';
      value = ramp_subsystem (E('Slope'), E('Start'), E('InitialOutput'));
    case 'Gain', type = 'Gain'; value = E('Gain');
    case 'Sum'
      signs = sum_signs (p.Inputs, '+-');
      if (isequal (signs, '++')), type = 'Sum'; value = [];
      else type = 'Subsystem'; value = signed_sum (signs);
      endif
    case 'Product'
      signs = sum_signs (p.Inputs, '*/');
      matrix = strcmp (p.Multiplication, 'Matrix(*)');
      if (matrix && isequal (signs, '**')), type = 'Product'; value = [];
      elseif (matrix), error ('ob_simulink: matrix Product supports only two multiplied inputs');
      else type = 'Subsystem'; value = elementwise_product (signs);
      endif
    case 'Abs', type = 'Function'; value = []; extra.name = 'abs';
    case {'Sqrt', 'Math', 'Trigonometry'}
      operator = p.Operator;
      if (! isvarname (operator)), error ('ob_simulink: unsupported %s operator ''%s''', bt, operator); endif
      type = 'Function'; value = []; extra.name = operator;
    case 'MATLABFcn', type = 'Function'; value = []; extra.name = function_name (p.MATLABFcn, bt);
    case 'Fcn', type = 'Function'; value = []; extra.name = function_name (p.Expr, bt);
    case 'UnitDelay', type = 'Unit Delay'; value = E('InitialCondition'); extra.rate = sample_rate (E('SampleTime'));
    case 'DiscreteIntegrator'
      type = 'Discrete Integrator'; value = E('InitialCondition'); extra.rate = sample_rate (E('SampleTime'));
    case 'Integrator'
      x0 = E('InitialCondition');
      limited = is_true (p.LimitOutput); reset = lower (p.ExternalReset);
      if (strcmp (reset, 'level hold'))
        error ('ob_simulink: Integrator ExternalReset ''level hold'' is not supported');
      endif
      if (! limited && strcmp (reset, 'none')), type = 'Integrator'; value = x0;
      else
        type = 'Limited Integrator';
        value = struct ('initial', x0, 'lower', -Inf, 'upper', Inf, 'reset', reset);
        if (limited)
          value.lower = E('LowerSaturationLimit'); value.upper = E('UpperSaturationLimit');
        endif
      endif
    case 'TransportDelay'
      type = 'Transport Delay'; value = struct ('delay', E('DelayTime'), 'initial', E('InitialOutput'));
    case 'Saturate', type = 'Saturation'; value = [E('LowerLimit') E('UpperLimit')];
    case 'DeadZone', type = 'Dead Zone'; value = [E('LowerValue') E('UpperValue')];
    case 'Switch'
      if (! strcmp (strrep (p.Criteria, ' ', ''), 'u2>=Threshold'))
        error ('ob_simulink: Switch supports only Criteria ''u2 >= Threshold''');
      endif
      type = 'Switch'; value = E('Threshold');
    case 'RateTransition'
      type = 'Rate Transition'; value = E('InitialCondition'); extra.rate = sample_rate (E('OutPortSampleTime'));
    case {'Scope', 'ToWorkspace'}, type = 'Scope'; value = [];
    case {'Inport', 'Outport'}, type = bt; value = E('Port');
    case 'TransferFcn', type = 'Subsystem'; value = ob_transfer_function (E('Numerator'), E('Denominator'));
    case 'StateSpace'
      type = 'Subsystem';
      x0 = E('InitialCondition'); A = E('A');
      if (isscalar (x0)), x0 = x0 * ones (rows (A), 1); endif
      value = ob_state_space (A, E('B'), E('C'), E('D'), x0);
    case 'ZeroPole', type = 'Subsystem'; value = ob_zero_pole (E('Zeros'), E('Poles'), E('Gain'));
    case 'DiscreteTransferFcn'
      [period, offset] = discrete_rate (E('SampleTime'));
      type = 'Subsystem'; value = ob_discrete_transfer_function (E('Numerator'), E('Denominator'), period, [], offset);
    case 'DiscreteStateSpace'
      [period, offset] = discrete_rate (E('SampleTime'));
      x0 = E('InitialCondition'); A = E('A');
      if (isscalar (x0)), x0 = x0 * ones (rows (A), 1); endif
      type = 'Subsystem'; value = ob_discrete_state_space (A, E('B'), E('C'), E('D'), period, x0, offset);
    case 'PIDController'
      options = struct ('form', lower (p.Form));
      if (strcmpi (p.TimeDomain, 'Discrete-time'))
        [period, offset] = discrete_rate (E('SampleTime'));
        if (period == 0), error ('ob_simulink: a discrete PID Controller needs an explicit SampleTime'); endif
        options.domain = 'discrete'; options.Ts = period; options.offset = offset;
      endif
      if (is_true (p.LimitOutput))
        options.limits = [E('LowerSaturationLimit') E('UpperSaturationLimit')];
      endif
      type = 'Subsystem'; value = ob_pid_controller (E('P'), E('I'), E('D'), E('N'), options);
    case 'Lookup_n-D'
      method = lower (p.ExtrapMethod);
      if (! any (strcmp (method, {'clip', 'linear'})))
        error ('ob_simulink: 1-D Lookup Table ExtrapMethod must be Clip or Linear');
      endif
      type = 'Subsystem'; value = ob_lookup_table_1d (E('BreakpointsForDimension1'), E('Table'), method);
    case 'RateLimiter'
      [period, offset] = discrete_rate (E('SampleTime'));
      type = 'Subsystem';
      value = ob_rate_limiter (E('RisingSlewLimit'), E('FallingSlewLimit'), period, E('InitialCondition'), offset);
    case 'Relay'
      [period, offset] = discrete_rate (E('SampleTime'));
      type = 'Subsystem';
      value = ob_relay (E('OnSwitchValue'), E('OffSwitchValue'), E('OnOutputValue'), E('OffOutputValue'), period, offset);
    otherwise
      error ('ob_simulink: block %s has unsupported BlockType %s', name, bt);
  endswitch
endfunction

function signs = sum_signs (inputs, alphabet)
  % '++-' style sign lists, '|' spacers, or an input count.
  if (isnumeric (inputs)), inputs = num2str (inputs); endif
  inputs = strrep (inputs, '|', '');
  count = str2double (inputs);
  if (! isnan (count))
    if (count < 1 || count != fix (count)), error ('ob_simulink: input count must be a positive integer'); endif
    signs = repmat (alphabet(1), 1, count);
  else
    signs = inputs;
  endif
  if (isempty (signs) || any (! ismember (signs, alphabet)))
    error ('ob_simulink: Inputs must use only ''%s'' characters or be a count', alphabet);
  endif
  if (numel (signs) == 1)
    error ('ob_simulink: single-input %s reduction is not supported', alphabet);
  endif
endfunction

function name = function_name (text, block_type)
  % Accept 'name' or 'name(u)', the forms with an Octave function equivalent.
  text = strtrim (text);
  token = regexp (text, '^([A-Za-z]\w*)(\s*\(\s*u\s*\))?$', 'tokens', 'once');
  if (isempty (token))
    error ('ob_simulink: %s expression ''%s'' must be a function name or name(u)', block_type, text);
  endif
  name = token{1};
endfunction

function rate = sample_rate (value)
  [period, offset] = discrete_rate (value);
  rate = [period offset];
endfunction

function [period, offset] = discrete_rate (value)
  % -1 inherits; T or [T offset] is explicit.
  if (! isnumeric (value) || isempty (value) || numel (value) > 2 || ! isreal (value))
    error ('ob_simulink: SampleTime must be -1, T, or [T offset]');
  endif
  if (isequal (value, -1) || isequal (value, 0) || isequal (value, [-1 0]))
    period = 0; offset = 0;
  else
    period = value(1); offset = 0;
    if (numel (value) == 2), offset = value(2); endif
    if (period <= 0 || offset < 0 || offset >= period)
      error ('ob_simulink: SampleTime needs T > 0 and 0 <= offset < T');
    endif
  endif
endfunction

function model = signed_sum (signs)
  % Virtual subsystem: In_k (negated by Gain -1 for '-') chained through Sum.
  n = numel (signs);
  model = empty_model ();
  for k = 1:n
    model.blocks(end+1) = leaf ('Inport', k, sprintf ('In%d', k), 0.1, 1 - k/(n+1));
  endfor
  terms = 1:n;
  for k = 1:n
    if (signs(k) == '-')
      model.blocks(end+1) = leaf ('Gain', -1, sprintf ('Negate%d', k), 0.3, 1 - k/(n+1));
      model.edges(end+1, :) = [k 1 numel(model.blocks) 1];
      terms(k) = numel (model.blocks);
    endif
  endfor
  model = chain (model, terms, @(k) leaf ('Sum', [], sprintf ('Sum%d', k), 0.5 + 0.05*k, 0.5));
endfunction

function model = elementwise_product (signs)
  n = numel (signs);
  if (signs(1) == '/')
    error ('ob_simulink: a Product whose first input divides is not supported');
  endif
  model = empty_model ();
  for k = 1:n
    model.blocks(end+1) = leaf ('Inport', k, sprintf ('In%d', k), 0.1, 1 - k/(n+1));
  endfor
  previous = 1;
  for k = 2:n
    operation = 'times'; if (signs(k) == '/'), operation = 'rdivide'; endif
    block = leaf ('Function', [], operation, 0.4 + 0.05*k, 0.5);
    model.blocks(end+1) = block;
    id = numel (model.blocks);
    model.edges(end+1:end+2, :) = [previous 1 id 1; k 1 id 2];
    previous = id;
  endfor
  model.blocks(end+1) = leaf ('Outport', 1, 'Out1', 0.9, 0.5);
  model.edges(end+1, :) = [previous 1 numel(model.blocks) 1];
endfunction

function model = chain (model, terms, make)
  previous = terms(1);
  for k = 2:numel (terms)
    model.blocks(end+1) = make (k);
    id = numel (model.blocks);
    model.edges(end+1:end+2, :) = [previous 1 id 1; terms(k) 1 id 2];
    previous = id;
  endfor
  model.blocks(end+1) = leaf ('Outport', 1, 'Out1', 0.9, 0.5);
  model.edges(end+1, :) = [previous 1 numel(model.blocks) 1];
endfunction

function model = sine_subsystem (amplitude, bias, frequency, phase)
  model = empty_model ();
  model.blocks = [leaf('Time', [], 'Clock', 0.1, 0.5) leaf('Gain', frequency, 'Frequency', 0.25, 0.5) ...
                  leaf('Constant', phase, 'Phase', 0.25, 0.3) leaf('Sum', [], 'Argument', 0.4, 0.45) ...
                  leaf('Function', [], 'sin', 0.55, 0.45) leaf('Gain', amplitude, 'Amplitude', 0.7, 0.45) ...
                  leaf('Constant', bias, 'Bias', 0.7, 0.25) leaf('Sum', [], 'Offset', 0.82, 0.4) ...
                  leaf('Outport', 1, 'Out1', 0.94, 0.4)];
  model.edges = [1 1 2 1; 2 1 4 1; 3 1 4 2; 4 1 5 1; 5 1 6 1; 6 1 8 1; 7 1 8 2; 8 1 9 1];
endfunction

function model = ramp_subsystem (slope, start, initial)
  model = empty_model ();
  model.blocks = [leaf('Time', [], 'Clock', 0.1, 0.5) leaf('Constant', -start, 'Start', 0.1, 0.3) ...
                  leaf('Sum', [], 'Elapsed', 0.25, 0.45) leaf('Step', [start 0 1], 'Active', 0.25, 0.7) ...
                  leaf('Product', [], 'Gate', 0.4, 0.55) leaf('Gain', slope, 'Slope', 0.55, 0.55) ...
                  leaf('Constant', initial, 'Initial', 0.55, 0.3) leaf('Sum', [], 'Output', 0.75, 0.5) ...
                  leaf('Outport', 1, 'Out1', 0.92, 0.5)];
  model.edges = [1 1 3 1; 2 1 3 2; 4 1 5 1; 3 1 5 2; 5 1 6 1; 6 1 8 1; 7 1 8 2; 8 1 9 1];
endfunction

function block = leaf (type, value, name, x, y)
  block = struct ('type', type, 'value', value, 'name', name, 'x', x, 'y', y);
endfunction

%% ---------------------------------------------------------------- blocks

function [systems, path] = add_block (systems, source, destination, varargin)
  if (! ischar (source) || ! ischar (destination))
    error ('add_block: supply a library source and a destination path');
  endif
  parts = split_path (destination);
  if (numel (parts) < 2), error ('add_block: destination must be system/name'); endif
  options = varargin;
  unique_name = false;
  keep = true (size (options));
  for k = 1:2:numel (options) - 1
    if (strcmpi (options{k}, 'MakeNameUnique'))
      unique_name = is_true (options{k+1}); keep(k:k+1) = false;
    endif
  endfor
  options = options(keep);
  if (mod (numel (options), 2)), error ('add_block: parameters must be name/value pairs'); endif
  parent = strjoin (parts(1:end-1), '/');
  [index, levels] = resolve_diagram (systems, parent);
  name = parts{end};
  model = systems(index).model;
  diagram = ob_model_at (model, levels);
  existing = display_names (diagram);
  if (any (strcmp (existing, name)))
    if (! unique_name), error ('add_block: a block named ''%s'' already exists', destination); endif
    base = regexprep (name, '\d+$', ''); counter = 1;
    while (any (strcmp (existing, sprintf ('%s%d', base, counter)))), counter += 1; endwhile
    name = sprintf ('%s%d', base, counter);
  endif
  path = [parent '/' name];
  % A block can also be copied from another loaded diagram by its path.
  copied = [];
  try
    if (! isempty (find_entry (systems, root_name (source))))
      [source_index, source_levels, source_id] = resolve (systems, source);
      if (! isempty (source_id))
        source_diagram = ob_model_at (systems(source_index).model, source_levels);
        copied = source_diagram.blocks(source_id);
      endif
    endif
  catch
    copied = [];
  end_try_catch
  if (! isempty (copied))
    meta = block_meta (copied);
    if (isempty (meta)), error ('add_block: only blocks created by add_block can be copied'); endif
  else
    [block_type, params] = library_block (source);
    meta = struct ('BlockType', block_type, 'Params', params);
  endif
  if (any (strcmp (meta.BlockType, {'EnablePort', 'TriggerPort', 'ResetPort'})))
    if (isempty (levels)), error ('add_block: %s blocks belong inside a subsystem', meta.BlockType); endif
    systems(index).model = add_control_port (model, levels, name, meta, options);
    return;
  endif
  for k = 1:2:numel (options)
    meta = set_block_param (meta, options{k}, options{k+1});
  endfor
  count = numel (diagram.blocks);
  x = 0.12 + 0.16 * mod (count, 6); y = 0.85 - 0.2 * mod (floor (count / 6), 5);
  block = leaf ('Constant', 0, name, x, y);
  block.simulink = meta;
  if (strcmp (meta.BlockType, 'SubSystem'))
    child = empty_model ();
    child.blocks = [leaf('Inport', 1, 'In1', 0.2, 0.5) leaf('Outport', 1, 'Out1', 0.8, 0.5)];
    child.edges = [1 1 2 1];
    child.blocks = ob_store_meta (child.blocks, 1, struct ('BlockType', 'Inport', 'Params', struct ('Port', '1')));
    child.blocks = ob_store_meta (child.blocks, 2, struct ('BlockType', 'Outport', 'Params', struct ('Port', '1')));
    % Library conditional subsystems contain their Enable/Trigger/Reset block.
    mode = meta.Params.Mode;
    ports = struct ('name', {}, 'BlockType', {}, 'Params', {});
    if (strcmp (mode, 'enabled') || strncmp (mode, 'enabled_', 8))
      ports(end+1) = struct ('name', 'Enable', 'BlockType', 'EnablePort', 'Params', struct ());
    endif
    if (any (strcmp (mode, {'rising', 'enabled_rising'})))
      ports(end+1) = struct ('name', 'Trigger', 'BlockType', 'TriggerPort', 'Params', struct ('TriggerType', 'rising'));
    endif
    if (strcmp (mode, 'reset_rising'))
      ports(end+1) = struct ('name', 'Reset', 'BlockType', 'ResetPort', 'Params', struct ('ResetTriggerType', 'rising'));
    endif
    if (! isempty (ports)), child.simulink_ports = ports; endif
    child = set_mode (child, control_mode (ports));
    meta.Params = struct ();
    block.simulink = meta;
    block.type = 'Subsystem'; block.value = child;
  elseif (any (strcmp (meta.BlockType, {'Inport', 'Outport'})) && isempty (meta.Params.Port))
    meta.Params.Port = num2str (sum (strcmp ({diagram.blocks.type}, meta.BlockType)) + 1);
    block.simulink = meta;
  endif
  diagram.blocks = ob_store_meta_block (diagram.blocks, count + 1, block);
  if (isfield (diagram, 'sample_times')), diagram.sample_times(end+1, :) = [0 0]; endif
  diagram = realize_block (diagram, count + 1);
  if (strcmp (meta.BlockType, 'Outport') && isfield (diagram, 'execution') ...
      && isfield (diagram.execution, 'initial_outputs'))
    diagram.execution.initial_outputs{end+1} = 0;
  endif
  systems(index).model = ob_set_model_at (model, levels, diagram);
endfunction

function meta = block_meta (block)
  meta = [];
  if (isfield (block, 'simulink') && isstruct (block.simulink) && ! isempty (block.simulink))
    meta = block.simulink;
  endif
endfunction

function blocks = ob_store_meta_block (blocks, id, block)
  % Keep a common struct schema while adding the 'simulink' metadata field.
  for name = fieldnames (block)'
    if (! isfield (blocks, name{1}))
      if (isempty (blocks))
        template = cell2struct (cell (numel (fieldnames (blocks)) + 1, 1), [fieldnames(blocks); name], 1);
        blocks = template([]);
      else
        [blocks.(name{1})] = deal ([]);
      endif
    endif
  endfor
  for name = fieldnames (blocks)'
    if (! isfield (block, name{1})), block.(name{1}) = []; endif
  endfor
  block = orderfields (block, fieldnames (blocks));
  if (isempty (blocks)), blocks = block; else blocks(id) = block; endif
endfunction

function blocks = ob_store_meta (blocks, id, meta)
  block = blocks(id); block.simulink = meta;
  blocks = ob_store_meta_block (blocks, id, block);
endfunction

function diagram = realize_block (diagram, id)
  % Recompute one block's Octave Blocks fields from its Simulink parameters.
  block = diagram.blocks(id);
  meta = block_meta (block);
  if (isempty (meta)), return; endif
  if (strcmp (meta.BlockType, 'SubSystem')), return; endif
  [type, value, extra] = realize (meta, block.name);
  old_inputs = []; old_outputs = [];
  try
    [old_inputs, old_outputs] = ob_block_ports (block);
  catch
  end_try_catch
  block.type = type; block.value = value;
  if (strcmp (type, 'Function'))
    % Octave Blocks keys Function blocks by name; keep the display name in
    % the metadata and use the function name for execution.
    if (! isfield (block.simulink, 'DisplayName')), block.simulink.DisplayName = block.name; endif
    if (! any (exist (extra.name) == [2 3 5]))
      error ('ob_simulink: %s function ''%s'' is not on the Octave path', meta.BlockType, extra.name);
    endif
    block.name = extra.name;
  elseif (isfield (block.simulink, 'DisplayName'))
    block.name = block.simulink.DisplayName;
    block.simulink = rmfield (block.simulink, 'DisplayName');
  endif
  diagram.blocks(id) = block;
  rate = [0 0];
  if (isfield (extra, 'rate')), rate = extra.rate; endif
  if (any (rate) || isfield (diagram, 'sample_times'))
    if (! isfield (diagram, 'sample_times')), diagram.sample_times = zeros (numel (diagram.blocks), 2); endif
    diagram.sample_times(id, :) = rate;
  endif
  ob_block_ports (diagram.blocks(id));
  % Drop wires to ports that no longer exist.
  [inputs, outputs] = ob_block_ports (diagram.blocks(id));
  if (! isempty (diagram.edges))
    edges = ob_edges (diagram);
    stale = (edges(:, 3) == id & edges(:, 4) > inputs) | (edges(:, 1) == id & edges(:, 2) > outputs);
    if (any (stale)), edges(stale, :) = []; diagram.edges = edges; endif
  endif
endfunction

function model = realize_model (model)
  % Re-evaluate every Simulink parameter (workspace variables may change).
  for id = 1:numel (model.blocks)
    meta = block_meta (model.blocks(id));
    if (strcmp (model.blocks(id).type, 'Subsystem') && (isempty (meta) || strcmp (meta.BlockType, 'SubSystem')))
      model.blocks(id).value = realize_model (model.blocks(id).value);
    elseif (! isempty (meta))
      model = realize_block (model, id);
    endif
  endfor
  if (isfield (model, 'simulink_ports')), model = rmfield (model, 'simulink_ports'); endif
endfunction

function child = set_mode (child, mode)
  if (strcmp (mode, 'virtual'))
    if (isfield (child, 'execution')), child = rmfield (child, 'execution'); endif
  else
    count = sum (strcmp ({child.blocks.type}, 'Outport'));
    execution = struct ('mode', mode);
    if (isfield (child, 'execution')), execution = child.execution; execution.mode = mode; endif
    if (! isfield (execution, 'initial_outputs')), execution.initial_outputs = repmat ({0}, 1, count); endif
    child.execution = execution;
  endif
  ob_execution_mode (child);
endfunction

function model = add_control_port (model, levels, name, meta, options)
  child = ob_model_at (model, levels);
  ports = struct ('name', {}, 'BlockType', {}, 'Params', {});
  if (isfield (child, 'simulink_ports')), ports = child.simulink_ports; endif
  if (any (strcmp ({ports.BlockType}, meta.BlockType)))
    error ('add_block: the subsystem already has a %s block', meta.BlockType);
  endif
  for k = 1:2:numel (options)
    meta = set_block_param (meta, options{k}, options{k+1});
  endfor
  had_trigger = any (strcmp ({ports.BlockType}, 'TriggerPort'));
  ports(end+1) = struct ('name', name, 'BlockType', meta.BlockType, 'Params', meta.Params);
  child.simulink_ports = ports;
  child = set_mode (child, control_mode (ports));
  model = ob_set_model_at (model, levels, child);
  if (strcmp (meta.BlockType, 'EnablePort') && had_trigger)
    % Enable takes the first control port; an existing trigger wire moves up.
    data_ports = sum (strcmp ({child.blocks.type}, 'Inport'));
    parent = ob_model_at (model, levels(1:end-1));
    edges = ob_edges (parent);
    moved = edges(:, 3) == levels(end) & edges(:, 4) == data_ports + 1;
    edges(moved, 4) = data_ports + 2;
    parent.edges = edges;
    model = ob_set_model_at (model, levels(1:end-1), parent);
  endif
endfunction

function mode = control_mode (ports)
  types = {ports.BlockType};
  enable = any (strcmp (types, 'EnablePort'));
  trigger = find (strcmp (types, 'TriggerPort'));
  reset = find (strcmp (types, 'ResetPort'));
  if (! isempty (reset) && (enable || ! isempty (trigger)))
    error ('ob_simulink: a Reset port cannot be combined with Enable or Trigger ports');
  endif
  if (! isempty (reset))
    mode = ['reset_' edge_type(ports(reset).Params.ResetTriggerType)];
  elseif (! isempty (trigger))
    mode = edge_type (ports(trigger).Params.TriggerType);
    if (enable), mode = ['enabled_' mode]; endif
  elseif (enable)
    mode = 'enabled';
  else
    mode = 'virtual';
  endif
endfunction

function type = edge_type (text)
  type = lower (text);
  if (! any (strcmp (type, {'rising', 'falling', 'either'})))
    error ('ob_simulink: trigger type ''%s'' is not supported (rising, falling, either)', text);
  endif
endfunction

function systems = delete_block (systems, path)
  if (iscell (path))
    for k = 1:numel (path), systems = delete_block (systems, path{k}); endfor
    return;
  endif
  [index, levels, id] = resolve_port_or_block (systems, path);
  model = systems(index).model;
  diagram = ob_model_at (model, levels);
  if (ischar (id))
    % Control port blocks change the parent's execution mode.
    ports = diagram.simulink_ports;
    removed = ports(strcmp ({ports.name}, id));
    data_ports = sum (strcmp ({diagram.blocks.type}, 'Inport'));
    port = data_ports + 1;
    if (strcmp (removed.BlockType, 'TriggerPort') && any (strcmp ({ports.BlockType}, 'EnablePort')))
      port = data_ports + 2;
    endif
    ports(strcmp ({ports.name}, id)) = [];
    diagram.simulink_ports = ports;
    diagram = set_mode (diagram, control_mode (ports));
    model = ob_set_model_at (model, levels, diagram);
    systems(index).model = drop_parent_ports (model, levels, 'input', port, port);
    return;
  endif
  block = diagram.blocks(id);
  edges = ob_edges (diagram);
  edges(edges(:, 1) == id | edges(:, 3) == id, :) = [];
  edges(edges(:, 1) > id, 1) -= 1; edges(edges(:, 3) > id, 3) -= 1;
  diagram.blocks(id) = [];
  diagram.edges = edges;
  if (isfield (diagram, 'sample_times')), diagram.sample_times(id, :) = []; endif
  if (any (strcmp (block.type, {'Inport', 'Outport'})))
    % Renumber the remaining ports and the parent's wires, as Simulink does.
    number = block.value;
    for k = find (strcmp ({diagram.blocks.type}, block.type))
      if (diagram.blocks(k).value > number)
        diagram.blocks(k).value -= 1;
        meta = block_meta (diagram.blocks(k));
        if (! isempty (meta))
          diagram.blocks(k).simulink.Params.Port = num2str (diagram.blocks(k).value);
        endif
      endif
    endfor
    if (strcmp (block.type, 'Outport') && isfield (diagram, 'execution') ...
        && isfield (diagram.execution, 'initial_outputs'))
      diagram.execution.initial_outputs(number) = [];
    endif
    model = ob_set_model_at (model, levels, diagram);
    if (! isempty (levels))
      kind = 'input'; if (strcmp (block.type, 'Outport')), kind = 'output'; endif
      model = drop_parent_ports (model, levels, kind, number, number);
    endif
  else
    model = ob_set_model_at (model, levels, diagram);
  endif
  systems(index).model = model;
endfunction

function model = drop_parent_ports (model, levels, kind, first, last)
  % Remove parent wires on ports FIRST..LAST of the subsystem at LEVELS and
  % shift higher-numbered ports down.
  parent = ob_model_at (model, levels(1:end-1));
  id = levels(end);
  edges = ob_edges (parent);
  removed = last - first + 1;
  if (removed <= 0), return; endif
  if (strcmp (kind, 'input')), block_col = 3; port_col = 4; else block_col = 1; port_col = 2; endif
  mine = edges(:, block_col) == id;
  edges(mine & edges(:, port_col) >= first & edges(:, port_col) <= last, :) = [];
  mine = edges(:, block_col) == id;
  shift = mine & edges(:, port_col) > last;
  edges(shift, port_col) -= removed;
  parent.edges = edges;
  model = ob_set_model_at (model, levels(1:end-1), parent);
endfunction

function [index, levels, id] = resolve_port_or_block (systems, path)
  % Like resolve, but a trailing name may be an Enable/Trigger/Reset block
  % (returned as its name in ID).
  parts = split_path (path);
  try
    [index, levels, id] = resolve (systems, path);
    if (isempty (id)), error ('ob_simulink: ''%s'' is a system, not a block', path); endif
  catch err
    [index, levels] = resolve_diagram (systems, strjoin (parts(1:end-1), '/'));
    diagram = ob_model_at (systems(index).model, levels);
    if (isfield (diagram, 'simulink_ports') && any (strcmp ({diagram.simulink_ports.name}, parts{end})))
      id = parts{end};
    else
      rethrow (err);
    endif
  end_try_catch
endfunction

%% ---------------------------------------------------------------- lines

function systems = edit_line (systems, adding, varargin)
  if (numel (varargin) < 3 || ! ischar (varargin{1}) || ! ischar (varargin{2}) || ! ischar (varargin{3}))
    error ('add_line: use add_line(system, ''Source/port'', ''Destination/port'')');
  endif
  [index, levels] = resolve_diagram (systems, varargin{1});
  model = systems(index).model;
  diagram = ob_model_at (model, levels);
  [source, source_port] = endpoint (diagram, varargin{2}, 'output');
  [target, target_port] = endpoint (diagram, varargin{3}, 'input');
  if (adding)
    diagram = ob_connect (realize_model (diagram), source, target, source_port, target_port);
    edges = diagram.edges;
    diagram = ob_model_at (model, levels); diagram.edges = edges;
  else
    edges = ob_edges (diagram);
    match = edges(:, 1) == source & edges(:, 2) == source_port & edges(:, 3) == target & edges(:, 4) == target_port;
    if (! any (match)), error ('delete_line: no line from %s to %s', varargin{2}, varargin{3}); endif
    edges(match, :) = []; diagram.edges = edges;
  endif
  systems(index).model = ob_set_model_at (model, levels, diagram);
endfunction

function [id, port] = endpoint (diagram, text, direction)
  slash = find (text == '/', 1, 'last');
  if (isempty (slash)), error ('add_line: endpoints are written ''Block/port'''); endif
  name = text(1:slash-1); port_text = text(slash+1:end);
  id = find (strcmp (display_names (diagram), name), 1);
  if (isempty (id)), error ('add_line: block ''%s'' does not exist', name); endif
  port = str2double (port_text);
  if (isnan (port))
    if (! strcmp (direction, 'input') || ! strcmp (diagram.blocks(id).type, 'Subsystem'))
      error ('add_line: port ''%s'' is not valid for %s', port_text, name);
    endif
    child = diagram.blocks(id).value;
    data_ports = sum (strcmp ({child.blocks.type}, 'Inport'));
    mode = ob_execution_mode (child);
    switch (lower (port_text))
      case 'enable'
        if (! (strcmp (mode, 'enabled') || ob_is_combined_mode (mode)))
          error ('add_line: %s has no Enable port', name);
        endif
        port = data_ports + 1;
      case 'trigger'
        if (ob_is_combined_mode (mode)), port = data_ports + 2;
        elseif (any (strcmp (mode, {'rising', 'falling', 'either'}))), port = data_ports + 1;
        else error ('add_line: %s has no Trigger port', name); endif
      case 'reset'
        if (! ob_is_resettable_mode (mode)), error ('add_line: %s has no Reset port', name); endif
        port = data_ports + 1;
      otherwise
        error ('add_line: port ''%s'' is not valid for %s', port_text, name);
    endswitch
  endif
endfunction

function names = display_names (diagram)
  names = {diagram.blocks.name};
  for id = 1:numel (diagram.blocks)
    meta = block_meta (diagram.blocks(id));
    if (! isempty (meta) && isfield (meta, 'DisplayName')), names{id} = meta.DisplayName; endif
  endfor
endfunction

%% ---------------------------------------------------------------- params

function meta = set_block_param (meta, name, value)
  if (strcmp (name, 'Name') || strcmp (name, 'Position')), meta.(['Pending' name]) = value; return; endif
  fields = fieldnames (meta.Params);
  match = find (strcmpi (fields, name), 1);
  if (isempty (match))
    error ('set_param: %s blocks have no parameter ''%s'' (supported: %s)', meta.BlockType, name, ...
           strjoin (fields', ', '));
  endif
  meta.Params.(fields{match}) = as_text (value);
endfunction

function systems = set_param (systems, path, varargin)
  if (mod (numel (varargin), 2) || isempty (varargin))
    error ('set_param: use set_param(object, ''Parameter'', value, ...)');
  endif
  parts = split_path (path);
  index = require_entry (systems, parts{1});
  if (numel (parts) == 1)
    params = systems(index).params;
    for k = 1:2:numel (varargin)
      fields = fieldnames (params);
      match = find (strcmpi (fields, varargin{k}), 1);
      if (isempty (match))
        error ('set_param: unsupported model parameter ''%s'' (supported: %s)', varargin{k}, strjoin (fields', ', '));
      endif
      params.(fields{match}) = as_text (varargin{k+1});
    endfor
    run_settings (params);           % validate before committing
    systems(index).params = params;
    return;
  endif
  [index, levels, id] = resolve_port_or_block (systems, path);
  model = systems(index).model;
  diagram = ob_model_at (model, levels);
  if (ischar (id))
    ports = diagram.simulink_ports;
    k = find (strcmp ({ports.name}, id));
    meta = struct ('BlockType', ports(k).BlockType, 'Params', ports(k).Params);
    for j = 1:2:numel (varargin), meta = set_block_param (meta, varargin{j}, varargin{j+1}); endfor
    ports(k).Params = meta.Params;
    diagram.simulink_ports = ports;
    diagram = set_mode (diagram, control_mode (ports));
    systems(index).model = ob_set_model_at (model, levels, diagram);
    return;
  endif
  block = diagram.blocks(id);
  meta = block_meta (block);
  for k = 1:2:numel (varargin)
    name = varargin{k}; value = varargin{k+1};
    if (strcmp (name, 'Name'))
      if (any (strcmp (display_names (diagram), value))), error ('set_param: name ''%s'' is in use', value); endif
      if (! isempty (meta) && isfield (meta, 'DisplayName')), meta.DisplayName = value;
      else block.name = value; endif
    elseif (strcmp (name, 'Position'))
      [block.x, block.y] = position_to_xy (value);
    elseif (isempty (meta))
      error ('set_param: block ''%s'' was not created by add_block; edit it with the editor', path);
    elseif (strcmp (meta.BlockType, 'SubSystem') && strcmpi (name, 'Mode'))
      error ('set_param: add Enable, Trigger or Reset blocks to change a subsystem''s execution');
    else
      meta = set_block_param (meta, name, value);
    endif
  endfor
  if (! isempty (meta)), block.simulink = meta; endif
  previous = diagram;
  diagram.blocks = ob_store_meta_block (diagram.blocks, id, block);
  diagram = realize_block (diagram, id);       % errors leave the system unchanged
  if (any (strcmp (block.type, {'Inport', 'Outport'})) && ! isequal (previous.blocks(id).value, diagram.blocks(id).value))
    ob_validate_model (realize_model (diagram));
  endif
  systems(index).model = ob_set_model_at (model, levels, diagram);
endfunction

function value = get_param (systems, path, name)
  if (iscell (path))
    value = cellfun (@(item) get_param (systems, item, name), path, 'UniformOutput', false);
    return;
  endif
  parts = split_path (path);
  index = require_entry (systems, parts{1});
  if (numel (parts) == 1)
    params = systems(index).params;
    switch (name)
      case 'Name', value = parts{1};
      case 'FileName', value = systems(index).file;
      case 'ObjectParameters', value = params;
      case 'Type', value = 'block_diagram';
      otherwise
        fields = fieldnames (params);
        match = find (strcmpi (fields, name), 1);
        if (isempty (match)), error ('get_param: unknown model parameter ''%s''', name); endif
        value = params.(fields{match});
    endswitch
    return;
  endif
  [index, levels, id] = resolve_port_or_block (systems, path);
  diagram = ob_model_at (systems(index).model, levels);
  parent = strjoin (parts(1:end-1), '/');
  if (ischar (id))
    port = diagram.simulink_ports(strcmp ({diagram.simulink_ports.name}, id));
    meta = struct ('BlockType', port.BlockType, 'Params', port.Params);
    x = 0.5; y = 0.95; display = id;
  else
    block = diagram.blocks(id);
    meta = block_meta (block);
    if (isempty (meta)), meta = native_meta (block); endif
    x = block.x; y = block.y; display = display_names (diagram){id};
  endif
  switch (name)
    case 'BlockType', value = meta.BlockType;
    case 'Name', value = display;
    case 'Parent', value = parent;
    case 'Type', value = 'block';
    case 'Position', value = xy_to_position (x, y);
    case {'DialogParameters', 'ObjectParameters'}, value = meta.Params;
    case 'Ports'
      if (ischar (id)), value = [0 0];
      else
        [inputs, outputs] = ob_block_ports (diagram.blocks(id));
        value = [inputs outputs];
      endif
    otherwise
      fields = fieldnames (meta.Params);
      match = find (strcmpi (fields, name), 1);
      if (isempty (match))
        error ('get_param: %s blocks have no parameter ''%s''', meta.BlockType, name);
      endif
      value = meta.Params.(fields{match});
  endswitch
endfunction

function meta = native_meta (block)
  % Simulink-style view of a block built without add_block.
  names = struct ('Constant', 'Constant', 'Time', 'Clock', 'Step', 'Step', 'Gain', 'Gain', ...
                  'Sum', 'Sum', 'Product', 'Product', 'Integrator', 'Integrator', ...
                  'Scope', 'Scope', 'Inport', 'Inport', 'Outport', 'Outport', 'Subsystem', 'SubSystem', ...
                  'Function', 'MATLABFcn', 'Saturation', 'Saturate', 'Switch', 'Switch');
  key = strrep (strrep (block.type, ' ', ''), '-', '');
  if (isfield (names, block.type)), block_type = names.(block.type); else block_type = key; endif
  params = struct ();
  if (isnumeric (block.value) && ! isempty (block.value)), params.Value = mat2str (block.value, 17); endif
  meta = struct ('BlockType', block_type, 'Params', params);
endfunction

function position = xy_to_position (x, y)
  cx = round (x * 1000); cy = round ((1 - y) * 600);
  position = [cx - 15, cy - 15, cx + 15, cy + 15];
endfunction

function [x, y] = position_to_xy (position)
  if (! isnumeric (position) || numel (position) != 4)
    error ('set_param: Position must be [left top right bottom]');
  endif
  x = min (max ((position(1) + position(3)) / 2000, 0.02), 0.98);
  y = min (max (1 - (position(2) + position(4)) / 1200, 0.02), 0.98);
endfunction

%% ---------------------------------------------------------------- search

function paths = find_system (systems, varargin)
  if (isempty (varargin))
    paths = {systems.name}'; return;
  endif
  root = varargin{1}; filters = varargin(2:end);
  depth = Inf;
  keep = true (size (filters));
  for k = 1:2:numel (filters) - 1
    if (any (strcmpi (filters{k}, {'SearchDepth'}))), depth = filters{k+1}; keep(k:k+1) = false; endif
    if (any (strcmpi (filters{k}, {'FollowLinks', 'LookUnderMasks', 'MatchFilter', 'Variants', 'IncludeCommented'})))
      keep(k:k+1) = false;
    endif
  endfor
  filters = filters(keep);
  [index, levels] = resolve_diagram (systems, root);
  candidates = [{root}; collect(systems(index).model, levels, root, depth)];
  paths = {};
  for k = 1:numel (candidates)
    ok = true;
    for j = 1:2:numel (filters)
      try
        value = get_param (systems, candidates{k}, filters{j});
        ok = ischar (value) && strcmp (value, filters{j+1});
      catch
        ok = false;
      end_try_catch
      if (! ok), break; endif
    endfor
    if (ok), paths{end+1, 1} = candidates{k}; endif
  endfor
endfunction

function paths = collect (model, levels, prefix, depth)
  paths = {};
  if (depth < 1), return; endif
  diagram = ob_model_at (model, levels);
  names = display_names (diagram);
  for id = 1:numel (diagram.blocks)
    path = [prefix '/' strrep(names{id}, '/', '//')];
    paths{end+1, 1} = path;
    if (strcmp (diagram.blocks(id).type, 'Subsystem') && ! is_masked (diagram.blocks(id)))
      paths = [paths; collect(model, [levels id], path, depth - 1)];
    endif
  endfor
  if (isfield (diagram, 'simulink_ports'))
    for port = diagram.simulink_ports
      paths{end+1, 1} = [prefix '/' port.name];
    endfor
  endif
endfunction

%% ---------------------------------------------------------------- simulation

function [config, options] = run_settings (params)
  E = @(name) numeric_param (params.(name), name);
  start = E('StartTime'); stop = E('StopTime');
  solver = params.Solver;
  map = struct ('ode4', 'rk4', 'ode45', 'ode45', 'ode15s', 'ode15s', 'ode23', 'ode45', ...
                'VariableStepAuto', 'ode45', 'FixedStepAuto', 'rk4', 'ode23t', 'ode15s', 'ode23tb', 'ode15s');
  if (! isfield (map, solver))
    error ('ob_simulink: Solver ''%s'' is not supported (ode4, ode45, ode15s, VariableStepAuto, FixedStepAuto)', solver);
  endif
  options = struct ('solver', map.(solver));
  span = stop - start;
  maxstep = Inf;
  if (! strcmpi (params.MaxStep, 'auto')), maxstep = E('MaxStep'); options.maxstep = maxstep; endif
  if (strcmpi (params.FixedStep, 'auto'))
    % Simulink's automatic step: (stop - start) / 50, bounded by MaxStep.
    step = min (span / 50, maxstep);
  else
    step = E('FixedStep');
  endif
  options.reltol = E('RelTol');
  if (strcmpi (params.AbsTol, 'auto')), options.abstol = 1e-6;
  else options.abstol = E('AbsTol'); endif
  options.zero_crossings = strcmpi (params.ZeroCrossControl, 'EnableAll');
  config = ob_validate_config ([start stop step]);
  options = ob_solver_options (options);
endfunction

function value = numeric_param (text, name)
  if (ischar (text)), value = evalin ('base', text); else value = text; endif
  if (! isnumeric (value) || ! isscalar (value) || ! isreal (value))
    error ('ob_simulink: %s must evaluate to a real scalar', name);
  endif
  value = double (value);
endfunction

function varargout = simulate (systems, count, name, varargin)
  index = require_entry (systems, name);
  params = systems(index).params;
  times = [];
  rest = varargin;
  if (! isempty (rest) && isnumeric (rest{1}))
    span = rest{1}; rest(1) = [];
    if (numel (span) == 2), params.StartTime = as_text (span(1)); params.StopTime = as_text (span(2));
    elseif (numel (span) > 2), times = span(:)';
    else params.StopTime = as_text (span); endif
  endif
  if (! isempty (rest) && isstruct (rest{1}))
    overrides = rest{1}; rest(1) = [];
    for field = fieldnames (overrides)'
      rest(end+1:end+2) = {field{1}, overrides.(field{1})};
    endfor
  endif
  if (mod (numel (rest), 2)), error ('sim: options must be name/value pairs'); endif
  fields = fieldnames (params);
  for k = 1:2:numel (rest)
    match = find (strcmpi (fields, rest{k}), 1);
    if (isempty (match))
      if (any (strcmpi (rest{k}, {'ReturnWorkspaceOutputs', 'SaveOutput', 'SaveTime', 'SrcWorkspace'}))), continue; endif
      error ('sim: unsupported parameter ''%s''', rest{k});
    endif
    params.(fields{match}) = as_text (rest{k+1});
  endfor
  [config, options] = run_settings (params);
  if (isempty (times)), times = ob_time_grid (config(1), config(2), config(3)); endif
  model = realize_model (systems(index).model);
  result = ob_run (model, times, options);
  out = struct ('tout', result.t(:));
  % yout: root Outports in port order (Array format when all are scalar).
  diagram = model;
  ports = find (strcmp ({diagram.blocks.type}, 'Outport'));
  [unused, order] = sort ([diagram.blocks(ports).value]);
  ports = ports(order);
  signals = cell (1, numel (ports));
  for k = 1:numel (ports)
    signals{k} = stack (result.values(:, ports(k)));
  endfor
  if (all (cellfun (@(s) columns (s) == 1, signals)) && ! isempty (signals))
    out.yout = [signals{:}];
  else
    out.yout = signals;
  endif
  % Logged sinks: Scope and To Workspace blocks anywhere in virtual hierarchy.
  out.logsout = struct ();
  for item = result.signal_map
    if (isempty (item.outputs)), continue; endif
    [block, label, variable] = block_at (systems(index).model, item.path);
    if (isempty (block) || ! strcmp (block.type, 'Scope')), continue; endif
    data = stack (result.flat_values(:, item.outputs(1)));
    entry = struct ('time', result.t(:), 'signals', struct ('values', data, 'blockName', label));
    if (! isempty (variable)), out.(variable) = entry;
    else out.logsout.(valid_name (label)) = entry; endif
  endfor
  out.ErrorMessage = '';
  out.SimulationMetadata = struct ('ModelName', name, 'Solver', options.solver, ...
                                   'IntegrationSteps', result.integration_steps, 'Events', {result.events});
  out.result = result;
  if (count <= 1)
    varargout{1} = out;
  else
    % Legacy [t, x, y] = sim(...) form; state trajectories are not exposed.
    varargout = {out.tout, [], out.yout};
    varargout = varargout(1:count);
  endif
endfunction

function data = stack (values)
  % Stack per-time samples; scalars and row vectors become rows.
  if (all (cellfun (@(v) isscalar (v), values)))
    data = cell2mat (values(:));
  elseif (all (cellfun (@(v) isvector (v), values)))
    data = cell2mat (cellfun (@(v) v(:)', values(:), 'UniformOutput', false));
  else
    data = cat (3, values{:});
  endif
endfunction

function [block, label, variable] = block_at (model, path)
  block = []; label = ''; variable = '';
  diagram = model; names = {};
  for k = 1:numel (path)
    if (path(k) > numel (diagram.blocks)), block = []; return; endif
    current = diagram.blocks(path(k));
    shown = display_names (diagram){path(k)};
    names{end+1} = shown;
    if (k < numel (path))
      if (! strcmp (current.type, 'Subsystem')), return; endif
      diagram = current.value;
    endif
  endfor
  block = current; label = strjoin (names, '/');
  meta = block_meta (block);
  if (! isempty (meta) && strcmp (meta.BlockType, 'ToWorkspace'))
    variable = evaluate_name (meta.Params.VariableName);
    block.type = 'Scope';
  elseif (! isempty (meta) && ! strcmp (meta.BlockType, 'Scope'))
    block = [];
  endif
endfunction

function name = evaluate_name (text)
  name = strtrim (text);
  if (! isvarname (name)), error ('ob_simulink: To Workspace VariableName must be an identifier'); endif
endfunction

function name = valid_name (text)
  name = regexprep (text, '[^A-Za-z0-9_]', '_');
  if (isempty (name) || ! isletter (name(1))), name = ['x' name]; endif
  name = name(1:min (end, namelengthmax ()));
endfunction

function yes = is_true (value)
  if (ischar (value)), yes = any (strcmpi (value, {'on', 'true', '1', 'yes'}));
  else yes = logical (value); endif
endfunction
