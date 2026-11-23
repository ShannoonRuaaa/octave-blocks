function varargout = ob_simulink (command, varargin)
  % OB_SIMULINK  Simulink-style programmatic modelling commands.
  %   Implements new_system, load_system, open_system, save_system,
  %   close_system, bdclose, add_block, delete_block, add_line, delete_line,
  %   set_param, get_param, find_system and sim on top of Octave Blocks
  %   models.  Run ob_simulink_setup () to put the project's simulink folder
  %   on the path and call these commands by their Simulink names, e.g.
  %
  %     ob_simulink_setup ();
  %     new_system ('demo');
  %     add_block ('simulink/Sources/Sine Wave', 'demo/Sine');
  %     add_block ('simulink/Continuous/Integrator', 'demo/Int');
  %     add_block ('simulink/Sinks/Out1', 'demo/Out1');
  %     add_line ('demo', 'Sine/1', 'Int/1'); add_line ('demo', 'Int/1', 'Out1/1');
  %     set_param ('demo', 'StopTime', '5');
  %     out = sim ('demo');  plot (out.tout, out.yout);
  %
  %   With set_param (name, 'SaveFormat', 'Dataset'), out.yout (root
  %   Outports) and out.logsout (Scopes) are Dataset-like structs:
  %     out.yout.numElements, out.yout.getElementNames ()
  %     e = out.yout.getElement (1);    % or getElement ('name'), get (1)
  %     plot (e.Values.Time, e.Values.Data);
  %   Each element has Name, PropagatedName, BlockPath, PortType, PortIndex
  %   and Values (Name, Time, Data, IsTimeFirst, Length).
  %
  %   Systems live in a session registry keyed by name.  See SIMULINK_API.md
  %   for the supported library blocks, parameters and differences.
  persistent systems;
  if (isempty (systems))
    systems = struct ('name', {}, 'model', {}, 'params', {}, 'file', {}, 'dirty', {});
  endif
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
        model = restore_ports (model);
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
      parts = split_path (varargin{1});
      name = root_name (varargin{1});
      index = find_entry (systems, name);
      % A block path only closes that block's window; the system stays loaded.
      if (isempty (index) || numel (parts) > 1), return; endif
      if (numel (varargin) > 1)
        option = varargin{2};
        if (ischar (option) && ! any (strcmpi (option, {'0', '1', 'on', 'off', 'true', 'false'})))
          systems(index) = save_entry (systems(index), option);
        elseif (is_true (option))
          systems(index) = save_entry (systems(index), systems(index).file);
        endif
      elseif (systems(index).dirty)
        % Like Simulink, a modified system is never discarded silently.
        error (['close_system: Unable to close the model ''%s'' because it has been changed. ' ...
                'To save changes, use close_system(''%s'',1). To discard changes, use close_system(''%s'',0).'], ...
               name, name, name);
      endif
      systems(index) = [];
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
      systems = mark_dirty (systems, path);
      if (nargout > 0), varargout{1} = path; endif
    case 'delete_block'
      systems = delete_block (systems, varargin{1});
      systems = mark_dirty (systems, varargin{1});
    case 'add_line'
      systems = edit_line (systems, true, varargin{:});
      systems = mark_dirty (systems, varargin{1});
      if (nargout > 0), varargout{1} = [varargin{1} ':' varargin{2} '->' varargin{3}]; endif
    case 'delete_line'
      systems = edit_line (systems, false, varargin{:});
      systems = mark_dirty (systems, varargin{1});
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
      [varargout{2}, varargout{3}] = run_settings (systems(index).params, varargout{1});
    case 'list'
      varargout{1} = {systems.name};
    case 'dataset'
      % Rebuild a Dataset-like struct (with its access functions) from one
      % whose handles were removed, e.g. to save it in a MAT file.
      ds = varargin{1};
      if (! isstruct (ds) || ! isscalar (ds) || ! all (isfield (ds, {'Name', 'Elements'})))
        error ('ob_simulink: dataset needs a struct with Name and Elements fields');
      endif
      varargout{1} = dataset_struct (ds.Name, ds.Elements);
    case 'dataset_element'
      % Target of a Dataset's getElement/get handles: a public entry point,
      % so the handles still resolve after clear functions or save/load.
      varargout{1} = dataset_lookup (varargin{:});
    otherwise
      error ('ob_simulink: unknown command ''%s''', command);
  endswitch
endfunction

%% ---------------------------------------------------------------- registry

function entry = new_entry (name, model, params, file)
  entry = struct ('name', name, 'model', model, 'params', params, 'file', file, 'dirty', false);
endfunction

function systems = mark_dirty (systems, path)
  % Any modifying command marks its system dirty until save_system.
  if (iscell (path))
    for k = 1:numel (path), systems = mark_dirty (systems, path{k}); endfor
    return;
  endif
  index = find_entry (systems, root_name (path));
  if (! isempty (index)), systems(index).dirty = true; endif
endfunction

function model = empty_model ()
  model.blocks = struct ('type', {}, 'value', {}, 'name', {}, 'x', {}, 'y', {});
  model.edges = zeros (0, 4);
endfunction

function params = default_params ()
  % Simulink configuration defaults; AbsTol, MaxStep and FixedStep 'auto'.
  % SaveFormat defaults to 'Array', as in Octave Blocks 0.2, although
  % Simulink defaults to 'Dataset'; 'Dataset' gives Dataset-like structs
  % (dataset_struct) because Simulink.SimulationData objects do not exist.
  params = struct ('StartTime', '0.0', 'StopTime', '10.0', 'Solver', 'VariableStepAuto', ...
                   'FixedStep', 'auto', 'RelTol', '1e-3', 'AbsTol', 'auto', ...
                   'MaxStep', 'auto', 'ZeroCrossControl', 'UseLocalSettings', ...
                   'SaveFormat', 'Array', 'ReturnWorkspaceOutputs', 'on', 'SimulationMode', 'normal');
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
  % Saved accelerate settings come back as Accelerator mode (Rapid
  % Accelerator runs the same accelerator, so it is not kept apart).
  if (isfield (options, 'accelerate') && ! isequal (options.accelerate, false))
    params.SimulationMode = 'accelerator';
  endif
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
  if (isempty (file)), file = [entry.name '.mat']; endif
  [folder, unused, extension] = fileparts (file);
  if (isempty (extension)), file = [file '.mat'];
  elseif (! strcmpi (extension, '.mat'))
    error ('save_system: only Octave Blocks .mat files can be written');
  endif
  % An InitialOutput naming a variable that is not defined yet does not
  % prevent saving (Simulink evaluates it only when compiling).
  model = realize_model (entry.model, false);
  [config, options] = run_settings (entry.params, model);
  ob_save_model (file, model, config, options);
  entry.file = file;
  entry.dirty = false;
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
        && ! isempty (block.simulink) && ! strcmp (meta_kind (block.simulink), 'SubSystem');
endfunction

%% ---------------------------------------------------------------- library

function meta = library_block (source)
  % Map a Simulink library path to block metadata: the BlockType and
  % MaskType Simulink R2026b reports, the realization Kind and the default
  % dialog parameters (Simulink names and values; see
  % simulink-api-reference.json).  Paths must name a block that exists in
  % Simulink, or be 'built-in/<BlockType>'.  Whitespace runs, including the
  % newlines inside Simulink library names, compare as one space.
  path = regexprep (strtrim (source), '\s+', ' ');
  P = @(varargin) struct (varargin{:});
  block_type = ''; mask_type = '';
  switch (path)
    case {'simulink/Sources/Constant', 'simulink/Commonly Used Blocks/Constant', 'built-in/Constant'}
      kind = 'Constant'; params = P('Value', '1');
    case {'simulink/Sources/Clock', 'built-in/Clock'}
      kind = 'Clock'; params = struct ();
    case {'simulink/Sources/Step', 'built-in/Step'}
      % Before/After remain accepted as aliases (param_aliases).  SampleTime
      % may be 0 or -1; both give the native (continuous-time) Step.
      kind = 'Step'; params = P('Time', '1', 'InitialValue', '0', 'FinalValue', '1', 'SampleTime', '0');
    case {'simulink/Sources/Sine Wave', 'built-in/Sin'}
      kind = 'Sin'; params = P('Amplitude', '1', 'Bias', '0', 'Frequency', '1', 'Phase', '0');
    case 'simulink/Sources/Ramp'
      % A masked subsystem in Simulink, with lowercase parameter names.
      kind = 'Ramp'; block_type = 'SubSystem'; mask_type = 'Ramp';
      params = P('slope', '1', 'start', '0', 'InitialOutput', '0');
    case {'simulink/Sources/Ground', 'simulink/Commonly Used Blocks/Ground', 'built-in/Ground'}
      kind = 'Ground'; params = struct ();
    case {'simulink/Math Operations/Gain', 'simulink/Commonly Used Blocks/Gain', 'built-in/Gain'}
      kind = 'Gain'; params = P('Gain', '1', 'Multiplication', 'Element-wise(K.*u)');
    case {'simulink/Math Operations/Sum', 'simulink/Commonly Used Blocks/Sum'}
      kind = 'Sum'; params = P('Inputs', '|++');
    case {'simulink/Math Operations/Add', 'built-in/Sum'}
      kind = 'Sum'; params = P('Inputs', '++');
    case 'simulink/Math Operations/Subtract'
      kind = 'Sum'; params = P('Inputs', '+-');
    case {'simulink/Math Operations/Product', 'simulink/Commonly Used Blocks/Product', 'built-in/Product'}
      kind = 'Product'; params = P('Inputs', '2', 'Multiplication', 'Element-wise(.*)');
    case 'simulink/Math Operations/Divide'
      kind = 'Product'; params = P('Inputs', '*/', 'Multiplication', 'Element-wise(.*)');
    case {'simulink/Math Operations/Abs', 'built-in/Abs'}
      kind = 'Abs'; params = struct ();
    case {'simulink/Math Operations/Sqrt', 'built-in/Sqrt'}
      kind = 'Sqrt'; params = P('Operator', 'sqrt');
    case {'simulink/Math Operations/Math Function', 'built-in/Math'}
      kind = 'Math'; params = P('Operator', 'exp');
    case {'simulink/Math Operations/Trigonometric Function', 'built-in/Trigonometry'}
      kind = 'Trigonometry'; params = P('Operator', 'sin');
    case {'simulink/User-Defined Functions/MATLAB Fcn', ...
          'simulink/User-Defined Functions/Interpreted MATLAB Function', 'built-in/MATLABFcn'}
      kind = 'MATLABFcn'; params = P('MATLABFcn', 'sin');
    case {'simulink/User-Defined Functions/Fcn', 'built-in/Fcn'}
      % Simulink's default 'sin(u(1)*exp(2.3*(-u(2))))' indexes a second
      % input element, which a Function block cannot express.
      kind = 'Fcn'; params = P('Expr', 'sin(u)');
    case {'simulink/Discrete/Unit Delay', 'built-in/UnitDelay'}
      kind = 'UnitDelay'; params = P('InitialCondition', '0', 'SampleTime', '-1');
    case {'simulink/Discrete/Discrete-Time Integrator', ...
          'simulink/Commonly Used Blocks/Discrete-Time Integrator', 'built-in/DiscreteIntegrator'}
      kind = 'DiscreteIntegrator'; params = P('InitialCondition', '0', 'SampleTime', '-1');
    case {'simulink/Continuous/Integrator', 'simulink/Commonly Used Blocks/Integrator', 'built-in/Integrator'}
      kind = 'Integrator';
      params = P('InitialCondition', '0', 'LimitOutput', 'off', 'UpperSaturationLimit', 'inf', ...
                 'LowerSaturationLimit', '-inf', 'ExternalReset', 'none');
    case 'simulink/Continuous/Integrator Limited'
      kind = 'Integrator';
      params = P('InitialCondition', '0', 'LimitOutput', 'on', 'UpperSaturationLimit', '1', ...
                 'LowerSaturationLimit', '0', 'ExternalReset', 'none');
    case {'simulink/Continuous/Transport Delay', 'built-in/TransportDelay'}
      kind = 'TransportDelay'; params = P('DelayTime', '1', 'InitialOutput', '0');
    case {'simulink/Discontinuities/Saturation', 'simulink/Commonly Used Blocks/Saturation', 'built-in/Saturate'}
      kind = 'Saturate'; params = P('UpperLimit', '0.5', 'LowerLimit', '-0.5');
    case {'simulink/Discontinuities/Dead Zone', 'built-in/DeadZone'}
      kind = 'DeadZone'; params = P('LowerValue', '-0.5', 'UpperValue', '0.5');
    case {'simulink/Signal Routing/Switch', 'simulink/Commonly Used Blocks/Switch'}
      % The library blocks override the BlockType default 'u2 >= Threshold'.
      kind = 'Switch'; params = P('Criteria', 'u2 > Threshold', 'Threshold', '0');
    case 'built-in/Switch'
      kind = 'Switch'; params = P('Criteria', 'u2 >= Threshold', 'Threshold', '0');
    case {'simulink/Signal Attributes/Rate Transition', 'built-in/RateTransition'}
      kind = 'RateTransition'; params = P('OutPortSampleTime', '-1', 'InitialCondition', '0');
    case {'simulink/Sinks/Scope', 'simulink/Commonly Used Blocks/Scope', 'built-in/Scope'}
      kind = 'Scope'; params = struct ();
    case {'simulink/Sinks/Display', 'built-in/Display'}
      kind = 'Display'; params = struct ();
    case {'simulink/Sinks/Terminator', 'simulink/Commonly Used Blocks/Terminator', 'built-in/Terminator'}
      kind = 'Terminator'; params = struct ();
    case {'simulink/Sinks/To Workspace', 'built-in/ToWorkspace'}
      % Simulink's default SaveFormat 'Timeseries' has no Octave equivalent.
      kind = 'ToWorkspace'; params = P('VariableName', 'simout', 'SaveFormat', 'Structure With Time');
    case {'simulink/Sources/In1', 'simulink/Ports & Subsystems/In1', ...
          'simulink/Commonly Used Blocks/In1', 'built-in/Inport'}
      kind = 'Inport'; params = P('Port', '');
    case {'simulink/Sinks/Out1', 'simulink/Ports & Subsystems/Out1', ...
          'simulink/Commonly Used Blocks/Out1', 'built-in/Outport'}
      % OutputWhenDisabled and InitialOutput apply inside conditional
      % subsystems (conditional_outputs); Simulink R2026b defaults.
      kind = 'Outport'; params = P('Port', '', 'OutputWhenDisabled', 'held', 'InitialOutput', '[]');
    case {'simulink/Ports & Subsystems/Subsystem', 'simulink/Commonly Used Blocks/Subsystem'}
      kind = 'SubSystem'; params = P('Mode', 'virtual');
    case 'built-in/SubSystem'
      kind = 'SubSystem'; params = P('Mode', 'empty');      % no ports, like Simulink
    case 'simulink/Ports & Subsystems/Enabled Subsystem'
      kind = 'SubSystem'; params = P('Mode', 'enabled');
    case 'simulink/Ports & Subsystems/Triggered Subsystem'
      kind = 'SubSystem'; params = P('Mode', 'rising');
    case 'simulink/Ports & Subsystems/Enabled and Triggered Subsystem'
      kind = 'SubSystem'; params = P('Mode', 'enabled_rising');
    case 'simulink/Ports & Subsystems/Resettable Subsystem'
      kind = 'SubSystem'; params = P('Mode', 'reset_rising');
    case {'simulink/Ports & Subsystems/Enable', 'built-in/EnablePort'}
      kind = 'EnablePort'; params = P('StatesWhenEnabling', 'held');
    case {'simulink/Ports & Subsystems/Trigger', 'built-in/TriggerPort'}
      kind = 'TriggerPort'; params = P('TriggerType', 'rising', 'InitialTriggerSignalState', compatibility_state ());
    case {'simulink/Ports & Subsystems/Resettable Subsystem/Reset', 'built-in/ResetPort'}
      % Simulink has no 'Ports & Subsystems/Reset' library block.
      kind = 'ResetPort'; params = P('ResetTriggerType', 'rising');
    case {'simulink/Continuous/Transfer Fcn', 'built-in/TransferFcn'}
      kind = 'TransferFcn'; params = P('Numerator', '[1]', 'Denominator', '[1 1]');
    case {'simulink/Continuous/State-Space', 'built-in/StateSpace'}
      kind = 'StateSpace'; params = P('A', '1', 'B', '1', 'C', '1', 'D', '1', 'InitialCondition', '0');
    case {'simulink/Continuous/Zero-Pole', 'built-in/ZeroPole'}
      kind = 'ZeroPole'; params = P('Zeros', '[1]', 'Poles', '[0 -1]', 'Gain', '[1]');
    case {'simulink/Discrete/Discrete Transfer Fcn', 'built-in/DiscreteTransferFcn'}
      kind = 'DiscreteTransferFcn';
      params = P('Numerator', '[1]', 'Denominator', '[1 0.5]', 'SampleTime', '-1');
    case {'simulink/Discrete/Discrete State-Space', 'built-in/DiscreteStateSpace'}
      kind = 'DiscreteStateSpace';
      params = P('A', '1', 'B', '1', 'C', '1', 'D', '1', 'InitialCondition', '0', 'SampleTime', '-1');
    case {'simulink/Continuous/PID Controller', 'simulink/Discrete/Discrete PID Controller'}
      % Linked masked subsystems in Simulink.
      kind = 'PIDController'; block_type = 'SubSystem'; mask_type = 'PID 1dof';
      params = P('P', '1', 'I', '1', 'D', '0', 'N', '100', 'Form', 'Parallel', ...
                 'TimeDomain', 'Continuous-time', 'SampleTime', '-1', ...
                 'LimitOutput', 'off', 'UpperSaturationLimit', 'inf', 'LowerSaturationLimit', '-inf');
      if (strcmp (path, 'simulink/Discrete/Discrete PID Controller'))
        % Simulink defaults to -1 (inherited); the discrete PID builder
        % needs an explicit period.
        params.TimeDomain = 'Discrete-time'; params.SampleTime = '1';
      endif
    case {'simulink/Lookup Tables/1-D Lookup Table', 'built-in/Lookup_n-D'}
      kind = 'Lookup_n-D';
      params = P('BreakpointsForDimension1', '[-5:5]', 'Table', 'tanh([-5:5])', ...
                 'InterpMethod', 'Linear point-slope', 'ExtrapMethod', 'Linear');
    case {'simulink/Lookup Tables/Lookup Table', 'built-in/Lookup'}
      kind = 'Lookup';
      params = P('InputValues', '[-5:5]', 'Table', 'tanh([-5:5])', 'LookUpMeth', 'Interpolation-Extrapolation');
    case {'simulink/Discontinuities/Rate Limiter', 'built-in/RateLimiter'}
      % OctaveSampleTime is an Octave-only extension: the realization is
      % sampled, whatever Simulink's SampleTimeMode says.
      kind = 'RateLimiter';
      params = P('RisingSlewLimit', '1', 'FallingSlewLimit', '-1', 'SampleTimeMode', 'inherited', ...
                 'InitialCondition', '0', 'OctaveSampleTime', '0.1');
    case {'simulink/Discontinuities/Relay', 'built-in/Relay'}
      kind = 'Relay';
      params = P('OnSwitchValue', 'eps', 'OffSwitchValue', 'eps', 'OnOutputValue', '1', ...
                 'OffOutputValue', '0', 'SampleTime', '-1');
    % ---- 0.3.0 builders.  Only the parameters the builders honour are
    % listed; data-type, icon and ZeroCross options are left out (the model's
    % ZeroCrossControl governs zero crossings), except Sign's ZeroCross.
    case {'simulink/Discontinuities/Backlash', 'built-in/Backlash'}
      kind = 'Backlash'; params = P('BacklashWidth', '1', 'InitialOutput', '0', 'SampleTime', '-1');
    case {'simulink/Discontinuities/Quantizer', 'built-in/Quantizer'}
      kind = 'Quantizer'; params = P('QuantizationInterval', '0.5', 'SampleTime', '-1');
    case {'simulink/Math Operations/MinMax', 'built-in/MinMax'}
      kind = 'MinMax'; params = P('Function', 'min', 'Inputs', '1', 'SampleTime', '-1');
    case 'simulink/Discontinuities/Saturation Dynamic'
      % Masked subsystem; its only dialog parameters are data-type ones.
      kind = 'SaturationDynamic'; block_type = 'SubSystem'; mask_type = 'Saturation Dynamic'; params = struct ();
    case 'simulink/Discontinuities/Dead Zone Dynamic'
      kind = 'DeadZoneDynamic'; block_type = 'SubSystem'; mask_type = 'Dead Zone Dynamic'; params = struct ();
    case {'simulink/Math Operations/Sign', 'built-in/Signum'}
      kind = 'Signum'; params = P('ZeroCross', 'on', 'SampleTime', '-1');
    case 'simulink/Discontinuities/Coulomb & Viscous Friction'
      kind = 'CoulombViscousFriction'; block_type = 'SubSystem'; mask_type = 'Coulombic and Viscous Friction';
      params = P('offset', '[1 3 2 0]', 'gain', '1');
    case {'simulink/Logic and Bit Operations/Relational Operator', ...
          'simulink/Commonly Used Blocks/Relational Operator', 'built-in/RelationalOperator'}
      kind = 'RelationalOperator'; params = P('Operator', '<=', 'SampleTime', '-1');
    case {'simulink/Logic and Bit Operations/Logical Operator', ...
          'simulink/Commonly Used Blocks/Logical Operator', 'built-in/Logic'}
      kind = 'Logic'; params = P('Operator', 'AND', 'Inputs', '2', 'SampleTime', '-1');
    case {'simulink/Signal Routing/Multiport Switch', 'built-in/MultiPortSwitch'}
      kind = 'MultiPortSwitch';
      params = P('DataPortOrder', 'One-based contiguous', 'Inputs', '3', 'DataPortForDefault', 'Last data port', ...
                 'DiagnosticForDefault', 'Error', 'SampleTime', '-1');
    case {'simulink/Sources/Pulse Generator', 'built-in/DiscretePulseGenerator'}
      % SampleTime applies to 'Sample based' pulses only, as in Simulink.
      kind = 'DiscretePulseGenerator';
      params = P('PulseType', 'Time based', 'TimeSource', 'Use simulation time', 'Amplitude', '1', ...
                 'Period', '10', 'PulseWidth', '5', 'PhaseDelay', '0', 'SampleTime', '1');
    case 'simulink/Sources/Chirp Signal'
      kind = 'Chirp'; block_type = 'SubSystem'; mask_type = 'chirp'; params = P('f1', '0.1', 'T', '100', 'f2', '1');
    case {'simulink/Signal Routing/Mux', 'simulink/Commonly Used Blocks/Mux', 'built-in/Mux'}
      kind = 'Mux'; params = P('Inputs', '2', 'DisplayOption', 'bar');
    case {'simulink/Signal Routing/Demux', 'simulink/Commonly Used Blocks/Demux', 'built-in/Demux'}
      kind = 'Demux'; params = P('Outputs', '2', 'DisplayOption', 'bar');
    case {'simulink/Continuous/Integrator, Second-Order', 'built-in/SecondOrderIntegrator'}
      % The other options (limits, wrapping, external reset, external
      % initial conditions, one output) are rejected unless at these values.
      kind = 'SecondOrderIntegrator';
      params = P('ICSourceX', 'internal', 'ICX', '0.0', 'LimitX', 'off', 'WrapX', 'off', ...
                 'ICSourceDXDT', 'internal', 'ICDXDT', '0.0', 'LimitDXDT', 'off', ...
                 'ExternalReset', 'none', 'ShowOutput', 'both');
    otherwise
      if (any (strcmp (path, unsupported_library_paths ())))
        error ('add_block: library block ''%s'' is not supported by Octave Blocks', source);
      endif
      error ('add_block: There is no block named ''%s'' (see SIMULINK_API.md for the supported library paths)', ...
             source);
  endswitch
  if (strncmp (path, 'built-in/', 9)), params = builtin_defaults (path, params); endif
  if (isempty (block_type)), block_type = kind; endif
  meta = struct ('BlockType', block_type, 'MaskType', mask_type, 'Kind', kind, 'Params', params);
endfunction

function params = builtin_defaults (path, params)
  % Simulink R2026b gives some built-in/<BlockType> blocks different
  % defaults from the library blocks above (recorded in
  % simulink-api-reference.json by reference_ob_simulink_api.m).
  % built-in/Lookup_n-D is the exception: its default is a multi-dimensional
  % table, and only the 1-D configuration is supported, so it keeps the
  % 1-D Lookup Table defaults (documented in SIMULINK_API.md).
  switch (path)
    case {'built-in/UnitDelay', 'built-in/DiscreteIntegrator', 'built-in/DiscreteStateSpace'}
      params.SampleTime = '1';
    case 'built-in/Step'
      params.SampleTime = '-1';
    case 'built-in/TransferFcn'
      params.Denominator = '[1 2 1]';
    case 'built-in/StateSpace'
      params.InitialCondition = '0.0';
    case 'built-in/ZeroPole'
      params.Poles = '[0 1]';
    case 'built-in/ToWorkspace'
      params.VariableName = 'simulink_output'; params.SaveFormat = 'Array';
    case 'built-in/Lookup'
      params.InputValues = '[-4:5]'; params.Table = ' rand(1,10)-0.5';
    case 'built-in/RateLimiter'
      params.SampleTimeMode = 'continuous';
    case 'built-in/RelationalOperator'
      params.Operator = '>=';
    case 'built-in/DiscretePulseGenerator'
      params.PulseType = 'Sample based'; params.Period = '2'; params.PulseWidth = '1';
    case 'built-in/Mux'
      params.Inputs = '4'; params.DisplayOption = 'none';
    case 'built-in/Demux'
      params.Outputs = '4';
  endswitch
endfunction

function paths = unsupported_library_paths ()
  % Simulink R2026b library blocks that Octave Blocks cannot realize.
  paths = {'simulink/Sources/Signal Builder', 'simulink/Sources/Signal Editor', ...
           'simulink/Sources/From Workspace', ...
           'simulink/Sources/Repeating Sequence', 'simulink/Sources/Signal Generator', ...
           'simulink/Sources/Random Number', ...
           'simulink/Sources/Digital Clock', 'simulink/Sinks/To File', 'simulink/Sinks/Stop Simulation', ...
           'simulink/Sinks/Floating Scope', 'simulink/Sinks/XY Graph', ...
           'simulink/Signal Routing/Bus Creator', 'simulink/Signal Routing/Bus Selector', ...
           'simulink/Signal Routing/Merge', ...
           'simulink/Signal Routing/Selector', 'simulink/Signal Routing/Goto', 'simulink/Signal Routing/From', ...
           'simulink/Commonly Used Blocks/Bus Creator', 'simulink/Commonly Used Blocks/Bus Selector', ...
           'simulink/Commonly Used Blocks/Delay', 'simulink/Commonly Used Blocks/Data Type Conversion', ...
           'simulink/Discrete/Delay', 'simulink/Discrete/Memory', 'simulink/Discrete/Zero-Order Hold', ...
           'simulink/Discrete/Discrete Filter', 'simulink/Discrete/Discrete Zero-Pole', ...
           'simulink/Discrete/Transfer Fcn First Order', 'simulink/Discrete/Transfer Fcn Lead or Lag', ...
           'simulink/Discrete/Transfer Fcn Real Zero', ...
           'simulink/Continuous/Derivative', 'simulink/Continuous/Variable Transport Delay', ...
           'simulink/Continuous/PID Controller (2DOF)', 'simulink/Continuous/Integrator, Second-Order Limited', ...
           'simulink/Discontinuities/Hit Crossing', ...
           'simulink/Math Operations/Bias', 'simulink/Math Operations/Unary Minus', ...
           'simulink/Math Operations/Rounding Function', 'simulink/Math Operations/Polynomial', ...
           'simulink/Lookup Tables/2-D Lookup Table', 'simulink/Lookup Tables/n-D Lookup Table', ...
           'simulink/Ports & Subsystems/Atomic Subsystem', 'simulink/Ports & Subsystems/Function-Call Subsystem', ...
           'simulink/Ports & Subsystems/If', 'simulink/Ports & Subsystems/If Action Subsystem', ...
           'simulink/Ports & Subsystems/Switch Case', 'simulink/Ports & Subsystems/For Each Subsystem', ...
           'simulink/Ports & Subsystems/Model', 'simulink/Ports & Subsystems/Variant Subsystem', ...
           'simulink/User-Defined Functions/MATLAB Function', 'simulink/User-Defined Functions/S-Function'};
endfunction

function kind = meta_kind (meta)
  % Realization key; metadata saved before Kind existed used the BlockType.
  if (isfield (meta, 'Kind')), kind = meta.Kind; else kind = meta.BlockType; endif
endfunction

function aliases = param_aliases (kind)
  % Hidden Simulink parameter aliases accepted by get_param and set_param.
  aliases = struct ();
  if (strcmp (kind, 'Step')), aliases = struct ('Before', 'InitialValue', 'After', 'FinalValue'); endif
endfunction

function field = param_field (meta, name)
  % Case-insensitive dialog parameter name (or alias) to its stored field.
  field = '';
  aliases = param_aliases (meta_kind (meta));
  names = fieldnames (aliases);
  alias = find (strcmpi (names, name), 1);
  if (! isempty (alias)), name = aliases.(names{alias}); endif
  fields = fieldnames (meta.Params);
  match = find (strcmpi (fields, name), 1);
  if (! isempty (match)), field = fields{match}; endif
endfunction

function meta = upgrade_meta (meta)
  % Bring metadata saved before the Simulink R2026b names (no Kind or
  % MaskType, Step Before/After, Ramp Slope/Start, Rate Limiter SampleTime)
  % up to date, so older .mat models keep loading with unchanged behaviour.
  if (isfield (meta, 'Kind')), return; endif
  kind = meta.BlockType; p = meta.Params; mask_type = '';
  rename = @(p, old, new) setfield (rmfield (p, old), new, p.(old));
  switch (kind)
    case 'Step'
      if (isfield (p, 'Before')), p = rename (p, 'Before', 'InitialValue'); endif
      if (isfield (p, 'After')), p = rename (p, 'After', 'FinalValue'); endif
      if (! isfield (p, 'SampleTime')), p.SampleTime = '0'; endif
    case 'Ramp'
      meta.BlockType = 'SubSystem'; mask_type = 'Ramp';
      if (isfield (p, 'Slope')), p = rename (p, 'Slope', 'slope'); endif
      if (isfield (p, 'Start')), p = rename (p, 'Start', 'start'); endif
    case 'PIDController'
      meta.BlockType = 'SubSystem'; mask_type = 'PID 1dof';
    case 'Gain'
      % Gains used to multiply as matrices.
      if (! isfield (p, 'Multiplication')), p.Multiplication = 'Matrix(K*u)'; endif
    case 'Lookup_n-D'
      if (! isfield (p, 'InterpMethod')), p.InterpMethod = 'Linear point-slope'; endif
    case 'RateLimiter'
      if (isfield (p, 'SampleTime')), p = rename (p, 'SampleTime', 'OctaveSampleTime'); endif
      if (! isfield (p, 'SampleTimeMode')), p.SampleTimeMode = 'inherited'; endif
    case 'ToWorkspace'
      if (! isfield (p, 'SaveFormat')), p.SaveFormat = 'Structure With Time'; endif
  endswitch
  meta.Params = p; meta.MaskType = mask_type; meta.Kind = kind;
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
  p = meta.Params; bt = meta_kind (meta);
  E = @(field) evaluate (p.(field), bt, field);
  extra = struct ();
  switch (bt)
    case 'Constant', type = 'Constant'; value = E('Value');
    case 'Clock', type = 'Time'; value = [];
    case 'Ground', type = 'Constant'; value = 0;
    case 'Step'
      if (isfield (p, 'SampleTime'))
        ts = E('SampleTime');
        if (! (isequal (ts, 0) || isequal (ts, -1)))
          error (['ob_simulink: Step SampleTime must be 0 (continuous) or -1 (inherited); ' ...
                  'a discrete Step is not supported']);
        endif
      endif
      type = 'Step'; value = [E('Time') E('InitialValue') E('FinalValue')];
    case 'Sin'
      % y = Amplitude*sin(Frequency*t + Phase) + Bias from native blocks.
      type = 'Subsystem';
      value = sine_subsystem (E('Amplitude'), E('Bias'), E('Frequency'), E('Phase'));
    case 'Ramp'
      % y = InitialOutput + slope*(t - start) for t >= start.
      type = 'Subsystem';
      value = ramp_subsystem (E('slope'), E('start'), E('InitialOutput'));
    case 'Gain'
      gain = E('Gain');
      multiplication = strrep (p.Multiplication, ' ', '');
      if (! any (strcmp (multiplication, {'Element-wise(K.*u)', 'Matrix(K*u)', 'Matrix(u*K)', 'Matrix(K*u)(uvector)'})))
        error (['ob_simulink: Gain Multiplication must be Element-wise(K.*u), Matrix(K*u), ' ...
                'Matrix(u*K) or Matrix(K*u) (u vector)']);
      endif
      if (isscalar (gain) || strcmp (multiplication, 'Matrix(K*u)'))
        type = 'Gain'; value = gain;        % the native Gain computes K*u
      else
        type = 'Subsystem'; value = gain_subsystem (gain, multiplication);
      endif
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
      if (! any (strcmp (reset, {'none', 'rising', 'falling', 'either', 'level', 'level hold'})))
        error ('ob_simulink: Integrator ExternalReset must be none, rising, falling, either, level or level hold');
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
      switch (strrep (p.Criteria, ' ', ''))
        case 'u2>=Threshold', type = 'Switch'; value = E('Threshold');
        case 'u2>Threshold', type = 'Subsystem'; value = switch_subsystem ('greater', E('Threshold'));
        case 'u2~=0', type = 'Subsystem'; value = switch_subsystem ('nonzero', 0);
        otherwise
          error ('ob_simulink: Switch Criteria must be ''u2 >= Threshold'', ''u2 > Threshold'' or ''u2 ~= 0''');
      endswitch
    case 'RateTransition'
      type = 'Rate Transition'; value = E('InitialCondition'); extra.rate = sample_rate (E('OutPortSampleTime'));
    case {'Scope', 'Display', 'Terminator'}, type = 'Scope'; value = [];
    case 'ToWorkspace'
      save_format (p.SaveFormat);
      type = 'Scope'; value = [];
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
      % Both linear interpolation methods give the same piecewise-linear table.
      if (! any (strcmpi (p.InterpMethod, {'Linear point-slope', 'Linear Lagrange', 'Linear'})))
        error ('ob_simulink: 1-D Lookup Table InterpMethod must be Linear point-slope or Linear Lagrange');
      endif
      method = lower (p.ExtrapMethod);
      if (! any (strcmp (method, {'clip', 'linear'})))
        error ('ob_simulink: 1-D Lookup Table ExtrapMethod must be Clip or Linear');
      endif
      type = 'Subsystem'; value = ob_lookup_table_1d (E('BreakpointsForDimension1'), E('Table'), method);
    case 'Lookup'
      % Legacy Lookup Table block.
      switch (p.LookUpMeth)
        case 'Interpolation-Extrapolation', method = 'linear';
        case 'Interpolation-Use End Values', method = 'clip';
        otherwise
          error (['ob_simulink: Lookup Table LookUpMeth must be Interpolation-Extrapolation ' ...
                  'or Interpolation-Use End Values']);
      endswitch
      type = 'Subsystem'; value = ob_lookup_table_1d (E('InputValues'), E('Table'), method);
    case 'RateLimiter'
      if (! any (strcmpi (p.SampleTimeMode, {'inherited', 'continuous'})))
        error ('ob_simulink: Rate Limiter SampleTimeMode must be inherited or continuous');
      endif
      [period, offset] = discrete_rate (E('OctaveSampleTime'));
      type = 'Subsystem';
      value = ob_rate_limiter (E('RisingSlewLimit'), E('FallingSlewLimit'), period, E('InitialCondition'), offset);
    case 'Relay'
      [period, offset] = discrete_rate (E('SampleTime'));
      type = 'Subsystem';
      value = ob_relay (E('OnSwitchValue'), E('OffSwitchValue'), E('OnOutputValue'), E('OffOutputValue'), period, offset);
    % ---- 0.3.0 builders (see SIMULINK_API.md for the mapping and limits).
    case 'Backlash'
      [period, offset] = discrete_rate (E('SampleTime'));
      type = 'Subsystem'; value = ob_backlash (E('BacklashWidth'), E('InitialOutput'), period, offset);
    case 'Quantizer'
      [period, offset] = discrete_rate (E('SampleTime'));
      type = 'Subsystem'; value = ob_quantizer (E('QuantizationInterval'), period, offset);
    case 'MinMax'
      inherited_rate (E('SampleTime'), 'MinMax');
      count = E('Inputs');
      if (! any (strcmpi (p.Function, {'min', 'max'})))
        error ('ob_simulink: MinMax Function must be min or max');
      endif
      type = 'Subsystem';
      if (isequal (count, 1))
        % Simulink's default: reduce the elements of one input (Octave only).
        value = reduction_subsystem (lower (p.Function));
      else
        value = ob_minmax (p.Function, count);
      endif
    case 'SaturationDynamic', type = 'Subsystem'; value = ob_saturation_dynamic ();
    case 'DeadZoneDynamic', type = 'Subsystem'; value = ob_dead_zone_dynamic ();
    case 'Signum'
      inherited_rate (E('SampleTime'), 'Sign');
      if (is_true (p.ZeroCross)), type = 'Subsystem'; value = ob_sign ();
      else type = 'Function'; value = []; extra.name = 'sign';     % no zero-crossing guard
      endif
    case 'CoulombViscousFriction'
      type = 'Subsystem'; value = ob_coulomb_viscous_friction (E('offset'), E('gain'));
    case 'RelationalOperator'
      inherited_rate (E('SampleTime'), 'Relational Operator');
      type = 'Subsystem'; value = ob_relational_operator (p.Operator);
    case 'Logic'
      inherited_rate (E('SampleTime'), 'Logical Operator');
      type = 'Subsystem';
      % With NOT, Simulink keeps Inputs (default 2) but shows one port.
      if (strcmpi (strtrim (p.Operator), 'NOT')), value = ob_logical_operator ('NOT');
      else value = ob_logical_operator (p.Operator, E('Inputs')); endif
    case 'MultiPortSwitch'
      inherited_rate (E('SampleTime'), 'Multiport Switch');
      if (! any (strcmpi (p.DiagnosticForDefault, {'None', 'Warning', 'Error'})))
        error ('ob_simulink: Multiport Switch DiagnosticForDefault must be None, Warning or Error');
      endif
      type = 'Subsystem'; value = ob_multiport_switch (E('Inputs'), p.DataPortOrder, p.DataPortForDefault);
    case 'DiscretePulseGenerator'
      if (! strcmpi (p.TimeSource, 'Use simulation time'))
        error ('ob_simulink: Pulse Generator TimeSource must be ''Use simulation time''');
      endif
      amplitude = E('Amplitude'); period = E('Period'); width = E('PulseWidth'); delay = E('PhaseDelay');
      switch (lower (p.PulseType))
        case 'time based'
          value = ob_pulse_generator (amplitude, period, width, delay);
        case 'sample based'
          % Period, PulseWidth and PhaseDelay count samples of SampleTime;
          % the held output equals the time-based pulse with those edges.
          ts = E('SampleTime');
          if (! isnumeric (ts) || ! isscalar (ts) || ! isreal (ts) || ! (ts > 0) || ! isfinite (ts))
            error ('ob_simulink: a sample-based Pulse Generator needs a SampleTime T > 0');
          endif
          sample_count (period, 'Period'); sample_count (width, 'PulseWidth'); sample_count (delay, 'PhaseDelay');
          if (! (period > 0)), error ('ob_simulink: sample-based Pulse Generator Period must be positive'); endif
          % Simulink refuses PulseWidth 0 and PulseWidth > Period; with
          % PulseWidth = Period the output stays at Amplitude (recorded in
          % scenarios.followup), realized as a pulse that falls half a
          % sample before the next rise, which no sample hit sees.
          if (! (width >= 1))
            error ('ob_simulink: sample-based Pulse Generator PulseWidth (%g) must be a positive number of samples', ...
                   width);
          elseif (width > period)
            error (['ob_simulink: sample-based Pulse Generator PulseWidth (%g samples) must be less than ' ...
                    'or equal to Period (%g samples)'], width, period);
          endif
          duty = 100 * min (width, period - 0.5) / period;
          value = ob_pulse_generator (amplitude, period * ts, duty, delay * ts);
          % Sampled and held at [Ts 0], so the block has Simulink's discrete
          % rate: it counts for FixedStep 'auto' and inherited (-1) blocks
          % downstream run at Ts.  The edges fall on sample hits.
          outport = find (strcmp ({value.blocks.type}, 'Outport'), 1);
          value = ob_hold_builder_output (value, outport, zeros (size (amplitude)), [ts 0]);
        otherwise
          error ('ob_simulink: Pulse Generator PulseType must be ''Time based'' or ''Sample based''');
      endswitch
      type = 'Subsystem';
    case 'Chirp', type = 'Subsystem'; value = ob_chirp (E('f1'), E('T'), E('f2'));
    case 'Mux', type = 'Subsystem'; value = ob_mux (E('Inputs'));
    case 'Demux', type = 'Subsystem'; value = ob_demux (E('Outputs'));
    case 'SecondOrderIntegrator'
      fixed = {'ICSourceX', 'internal'; 'ICSourceDXDT', 'internal'; 'LimitX', 'off'; 'LimitDXDT', 'off'; ...
               'WrapX', 'off'; 'ExternalReset', 'none'; 'ShowOutput', 'both'};
      for k = 1:rows (fixed)
        if (! strcmpi (p.(fixed{k, 1}), fixed{k, 2}))
          error (['ob_simulink: Integrator, Second-Order supports only %s = ''%s''; ' ...
                  'set the initial conditions with ICX and ICDXDT'], fixed{k, 1}, fixed{k, 2});
        endif
      endfor
      type = 'Subsystem'; value = ob_second_order_integrator (E('ICX'), E('ICDXDT'));
    otherwise
      error ('ob_simulink: block %s has unsupported BlockType %s', name, meta.BlockType);
  endswitch
endfunction

function inherited_rate (value, label)
  % The 0.3.0 builders without a sample-time argument run at the rate of
  % their inputs: only Simulink's inherited -1 (or continuous 0, the same
  % thing for these algebraic blocks) is accepted.
  if (! any (cellfun (@(v) isequal (value, v), {-1, 0, [-1 0], [0 0]})))
    error ('ob_simulink: %s SampleTime must be -1 (inherited) or 0; a discrete sample time is not supported', label);
  endif
endfunction

function sample_count (value, label)
  if (! isnumeric (value) || ! isscalar (value) || ! isreal (value) || ! isfinite (value) || value != fix (value))
    error ('ob_simulink: sample-based Pulse Generator %s must be an integer number of samples', label);
  endif
endfunction

function model = reduction_subsystem (operation)
  % MinMax with Inputs = 1: the minimum or maximum over every element of
  % one input (Simulink's CollapseMode 'All dimensions').  The Function
  % blocks 'vec' and 'min'/'max' run in Octave but are not exported by
  % ob_codegen, which has no C reduction.
  model = empty_model ();
  model.blocks = [leaf('Inport', 1, 'u', 0.1, 0.5) leaf('Function', [], 'vec', 0.35, 0.5) ...
                  leaf('Function', [], operation, 0.6, 0.5) leaf('Outport', 1, 'y', 0.9, 0.5)];
  model.edges = [1 1 2 1; 2 1 3 1; 3 1 4 1];
endfunction

function format = save_format (text)
  % To Workspace SaveFormat; Simulink's default Timeseries is not available.
  format = text;
  if (! any (strcmp (format, {'Structure With Time', 'Structure', 'Array'})))
    error (['ob_simulink: To Workspace SaveFormat must be ''Structure With Time'', ''Structure'' ' ...
            'or ''Array'' (Simulink''s Timeseries is not supported)']);
  endif
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

function model = gain_subsystem (gain, multiplication)
  % Non-scalar Gain modes from native blocks: K.*u is a 'times' Function
  % of a Constant K (exportable to C), u*K a Product, and K*u(:) a Gain
  % after a 'vec' Function (Octave only).
  model = empty_model ();
  switch (multiplication)
    case 'Element-wise(K.*u)'
      model.blocks = [leaf('Inport', 1, 'u', 0.1, 0.4) leaf('Constant', gain, 'K', 0.1, 0.7) ...
                      leaf('Function', [], 'times', 0.5, 0.5) leaf('Outport', 1, 'Out1', 0.9, 0.5)];
      model.edges = [2 1 3 1; 1 1 3 2; 3 1 4 1];
    case 'Matrix(u*K)'
      model.blocks = [leaf('Inport', 1, 'u', 0.1, 0.4) leaf('Constant', gain, 'K', 0.1, 0.7) ...
                      leaf('Product', [], 'uK', 0.5, 0.5) leaf('Outport', 1, 'Out1', 0.9, 0.5)];
      model.edges = [1 1 3 1; 2 1 3 2; 3 1 4 1];
    otherwise                                % 'Matrix(K*u) (u vector)'
      model.blocks = [leaf('Inport', 1, 'u', 0.1, 0.5) leaf('Function', [], 'vec', 0.35, 0.5) ...
                      leaf('Gain', gain, 'K', 0.6, 0.5) leaf('Outport', 1, 'Out1', 0.9, 0.5)];
      model.edges = [1 1 2 1; 2 1 3 1; 3 1 4 1];
  endswitch
endfunction

function model = switch_subsystem (criterion, threshold)
  % The native Switch passes u1 when u2 >= Threshold.  Since
  % u2 > T == !(-u2 >= -T) and u2 ~= 0 == !(-|u2| >= 0), the other
  % criteria negate the control (after abs) and swap the data inputs,
  % which keeps the realization exportable to C.
  model = empty_model ();
  model.blocks = [leaf('Inport', 1, 'u1', 0.1, 0.8) leaf('Inport', 2, 'u2', 0.1, 0.5) ...
                  leaf('Inport', 3, 'u3', 0.1, 0.2)];
  control = 2;
  if (strcmp (criterion, 'nonzero'))
    model.blocks(end+1) = leaf ('Function', [], 'abs', 0.3, 0.5);
    model.edges(end+1, :) = [control 1 numel(model.blocks) 1];
    control = numel (model.blocks);
  endif
  model.blocks(end+1) = leaf ('Gain', -1, 'Negate', 0.45, 0.5);
  model.edges(end+1, :) = [control 1 numel(model.blocks) 1];
  control = numel (model.blocks);
  model.blocks(end+1) = leaf ('Switch', 0 - threshold, 'Switch', 0.65, 0.5);   % +0, not -0
  id = numel (model.blocks);
  model.edges(end+1:end+3, :) = [3 1 id 1; control 1 id 2; 1 1 id 3];
  model.blocks(end+1) = leaf ('Outport', 1, 'Out1', 0.9, 0.5);
  model.edges(end+1, :) = [id 1 numel(model.blocks) 1];
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
    if (! unique_name)
      error ('add_block: A new block named ''%s'' cannot be added: a block with that name already exists', ...
             destination);
    endif
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
    meta = library_block (source);
  endif
  kind = meta_kind (meta);
  if (any (strcmp (kind, {'EnablePort', 'TriggerPort', 'ResetPort'})))
    if (isempty (levels)), error ('add_block: %s blocks belong inside a subsystem', meta.BlockType); endif
    systems(index).model = add_control_port (model, levels, name, meta, options);
    return;
  endif
  for k = 1:2:numel (options)
    meta = set_block_param (meta, options{k}, options{k+1}, name);
  endfor
  count = numel (diagram.blocks);
  x = 0.12 + 0.16 * mod (count, 6); y = 0.85 - 0.2 * mod (floor (count / 6), 5);
  block = leaf ('Constant', 0, name, x, y);
  block.simulink = meta;
  if (strcmp (kind, 'SubSystem'))
    child = empty_model ();
    mode = meta.Params.Mode;
    if (strcmp (mode, 'empty'))
      mode = 'virtual';                  % built-in/SubSystem starts without ports
    else
      child.blocks = [leaf('Inport', 1, 'In1', 0.2, 0.5) leaf('Outport', 1, 'Out1', 0.8, 0.5)];
      child.edges = [1 1 2 1];
      child.blocks = ob_store_meta (child.blocks, 1, port_meta ('Inport'));
      child.blocks = ob_store_meta (child.blocks, 2, port_meta ('Outport'));
    endif
    % Library conditional subsystems contain their Enable/Trigger/Reset block.
    ports = struct ('name', {}, 'BlockType', {}, 'Params', {});
    if (strcmp (mode, 'enabled') || strncmp (mode, 'enabled_', 8))
      ports(end+1) = struct ('name', 'Enable', 'BlockType', 'EnablePort', 'Params', struct ('StatesWhenEnabling', 'held'));
    endif
    if (any (strcmp (mode, {'rising', 'enabled_rising'})))
      ports(end+1) = struct ('name', 'Trigger', 'BlockType', 'TriggerPort', 'Params', ...
                             struct ('TriggerType', 'rising', 'InitialTriggerSignalState', compatibility_state ()));
    endif
    if (strcmp (mode, 'reset_rising'))
      ports(end+1) = struct ('name', 'Reset', 'BlockType', 'ResetPort', 'Params', struct ('ResetTriggerType', 'rising'));
    endif
    if (! isempty (ports)), child.simulink_ports = ports; endif
    child = set_mode (child, control_mode (ports), ports);
    meta.Params = struct ();
    block.simulink = meta;
    block.type = 'Subsystem'; block.value = child;
  elseif (any (strcmp (kind, {'Inport', 'Outport'})) && isempty (meta.Params.Port))
    meta.Params.Port = num2str (sum (strcmp ({diagram.blocks.type}, kind)) + 1);
    block.simulink = meta;
  endif
  diagram.blocks = ob_store_meta_block (diagram.blocks, count + 1, block);
  if (isfield (diagram, 'sample_times')), diagram.sample_times(end+1, :) = [0 0]; endif
  diagram = realize_block (diagram, count + 1);
  if (strcmp (kind, 'Outport') && isfield (diagram, 'execution') ...
      && isfield (diagram.execution, 'initial_outputs'))
    diagram.execution.initial_outputs{end+1} = 0;
    % A per-port OutputWhenDisabled list grows with the Outports.
    if (isfield (diagram.execution, 'outputs') && iscell (diagram.execution.outputs))
      diagram.execution.outputs{end+1} = 'held';
    endif
  endif
  systems(index).model = ob_set_model_at (model, levels, diagram);
endfunction

function meta = port_meta (kind)
  params = struct ('Port', '1');
  if (strcmp (kind, 'Outport')), params.OutputWhenDisabled = 'held'; params.InitialOutput = '[]'; endif
  meta = struct ('BlockType', kind, 'MaskType', '', 'Kind', kind, 'Params', params);
endfunction

function meta = block_meta (block)
  meta = [];
  if (isfield (block, 'simulink') && isstruct (block.simulink) && ! isempty (block.simulink))
    meta = upgrade_meta (block.simulink);
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
  if (strcmp (meta_kind (meta), 'SubSystem')), return; endif
  block.simulink = meta;
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

function model = realize_model (model, strict = true)
  % Re-evaluate every Simulink parameter (workspace variables may change).
  for id = 1:numel (model.blocks)
    meta = block_meta (model.blocks(id));
    if (strcmp (model.blocks(id).type, 'Subsystem') && (isempty (meta) || strcmp (meta_kind (meta), 'SubSystem')))
      model.blocks(id).value = realize_model (model.blocks(id).value, strict);
    elseif (! isempty (meta))
      model = realize_block (model, id);
    endif
  endfor
  if (isfield (model, 'simulink_ports')), model = rmfield (model, 'simulink_ports'); endif
  model = conditional_outputs (model, strict);
endfunction

function model = conditional_outputs (model, strict = true)
  % Outport OutputWhenDisabled and InitialOutput (add_block metadata) set a
  % conditional diagram's execution.outputs (one policy, or one per port)
  % and execution.initial_outputs.  InitialOutput is evaluated here, at
  % sim/save time, as Simulink evaluates it at compile time (set_param
  % accepts an undefined variable).  '[]', Simulink's default, means 0.
  % Outports without these parameters keep the execution's values.
  if (! isfield (model, 'execution') || strcmp (ob_execution_mode (model), 'virtual')), return; endif
  ids = find (strcmp ({model.blocks.type}, 'Outport'));
  count = numel (ids);
  execution = model.execution;
  policies = repmat ({'held'}, 1, count);
  if (isfield (execution, 'outputs'))
    if (ischar (execution.outputs)), policies(:) = {execution.outputs};
    elseif (iscell (execution.outputs) && numel (execution.outputs) == count)
      policies = reshape (execution.outputs, 1, []);
    endif
  endif
  initial = repmat ({0}, 1, count);
  if (isfield (execution, 'initial_outputs') && iscell (execution.initial_outputs) ...
      && numel (execution.initial_outputs) == count)
    initial = reshape (execution.initial_outputs, 1, []);
  endif
  touched = false;
  for id = ids
    meta = block_meta (model.blocks(id));
    port = model.blocks(id).value;
    if (isempty (meta) || ! isnumeric (port) || ! isscalar (port) || port < 1 || port > count), continue; endif
    if (isfield (meta.Params, 'OutputWhenDisabled'))
      policies{port} = meta.Params.OutputWhenDisabled; touched = true;
    endif
    if (isfield (meta.Params, 'InitialOutput'))
      text = meta.Params.InitialOutput;
      if (ischar (text) && strcmp (strtrim (text), '[]')), initial{port} = 0;
      else
        % Not STRICT (saving): an expression that cannot be evaluated yet
        % keeps the execution's current value.
        try
          initial{port} = evaluate (text, 'Outport', 'InitialOutput');
        catch err
          if (strict), rethrow (err); endif
        end_try_catch
      endif
      touched = true;
    endif
  endfor
  if (! touched), return; endif
  mode = ob_execution_mode (model);
  if (! strcmp (mode, 'enabled') && ! ob_is_combined_mode (mode))
    % A Triggered (or Resettable) Subsystem keeps its outputs held whatever
    % OutputWhenDisabled says (recorded: triggered_reset_port).
    policies(:) = {'held'};
  endif
  if (all (strcmp (policies, policies{1}))), execution.outputs = policies{1};
  else execution.outputs = policies; endif
  execution.initial_outputs = initial;
  model.execution = execution;
endfunction

function meta = outport_view (diagram, id, meta)
  % An Outport without OutputWhenDisabled/InitialOutput metadata (native
  % blocks, or models saved before these parameters) shows the values its
  % conditional diagram's execution holds.
  block = diagram.blocks(id);
  if (! strcmp (block.type, 'Outport') || isfield (meta.Params, 'OutputWhenDisabled')), return; endif
  policy = 'held'; text = '[]';
  port = block.value;
  if (isfield (diagram, 'execution') && isstruct (diagram.execution))
    execution = diagram.execution;
    if (isfield (execution, 'outputs'))
      if (ischar (execution.outputs)), policy = execution.outputs;
      elseif (iscell (execution.outputs) && port <= numel (execution.outputs)), policy = execution.outputs{port}; endif
    endif
    if (isfield (execution, 'initial_outputs') && iscell (execution.initial_outputs) ...
        && port <= numel (execution.initial_outputs))
      value = execution.initial_outputs{port};
      if (! isequal (value, 0)), text = mat2str (value, 17); endif
    endif
  endif
  meta.Params.OutputWhenDisabled = policy;
  meta.Params.InitialOutput = text;
endfunction

function child = set_mode (child, mode, ports)
  if (strcmp (mode, 'virtual'))
    if (isfield (child, 'execution')), child = rmfield (child, 'execution'); endif
  else
    count = sum (strcmp ({child.blocks.type}, 'Outport'));
    execution = struct ('mode', mode);
    if (isfield (child, 'execution')), execution = child.execution; execution.mode = mode; endif
    if (! isfield (execution, 'initial_outputs')), execution.initial_outputs = repmat ({0}, 1, count); endif
    % The Trigger block's InitialTriggerSignalState owns initial_control.
    trigger = ports(strcmp ({ports.BlockType}, 'TriggerPort'));
    if (! isempty (trigger))
      execution.initial_control = initial_control (trigger.Params.InitialTriggerSignalState);
    elseif (isempty (trigger) && isfield (execution, 'initial_control') && ischar (execution.initial_control))
      execution = rmfield (execution, 'initial_control');
    endif
    % The Enable block's StatesWhenEnabling owns states; without an Enable
    % block the subsystem keeps held states, the only triggered policy.
    enable = ports(strcmp ({ports.BlockType}, 'EnablePort'));
    if (! isempty (enable) && isfield (enable.Params, 'StatesWhenEnabling'))
      execution.states = enable.Params.StatesWhenEnabling;
    elseif (isempty (enable) && isfield (execution, 'states'))
      execution.states = 'held';
    endif
    if (isempty (enable) && ! ob_is_combined_mode (mode) && isfield (execution, 'outputs'))
      execution.outputs = 'held';
    endif
    child.execution = execution;
  endif
  ob_execution_mode (child);
endfunction

function text = compatibility_state ()
  % Simulink's default InitialTriggerSignalState.
  text = 'compatibility (no trigger on first evaluation)';
endfunction

function value = initial_control (state)
  % InitialTriggerSignalState as Octave Blocks' initial_control.
  switch (state)
    case 'zero', value = 0;
    case 'positive', value = 1;
    case 'negative', value = -1;
    otherwise, value = 'compatibility';
  endswitch
endfunction

function text = trigger_state (value, block_type, label)
  % A set_param value for InitialTriggerSignalState, case-insensitive like
  % Simulink, which also accepts plain 'compatibility' (R2026b probes).
  states = {compatibility_state(), 'zero', 'positive', 'negative'};
  match = find (strcmpi (states, value), 1);
  if (isempty (match) && strcmpi (value, 'compatibility')), match = 1; endif
  if (isempty (match))
    error ('set_param: Invalid setting in %s block ''%s'' for parameter ''InitialTriggerSignalState'': ''%s'' is not one of %s', ...
           block_type, label, value, strjoin (states, ', '));
  endif
  text = states{match};
endfunction

function model = restore_ports (model)
  % Saved models keep each conditional subsystem's execution but not its
  % Enable/Trigger/Reset blocks; rebuild them, with Simulink's default
  % names, so get_param/set_param reach them after load_system.
  for id = 1:numel (model.blocks)
    if (! strcmp (model.blocks(id).type, 'Subsystem') || is_masked (model.blocks(id))), continue; endif
    child = restore_ports (model.blocks(id).value);
    mode = ob_execution_mode (child);
    if (! isfield (child, 'simulink_ports') && ! strcmp (mode, 'virtual'))
      ports = struct ('name', {}, 'BlockType', {}, 'Params', {});
      if (strncmp (mode, 'enabled', 7))
        states = ob_execution_options (child, false).states;
        ports(end+1) = struct ('name', 'Enable', 'BlockType', 'EnablePort', 'Params', ...
                               struct ('StatesWhenEnabling', states));
      endif
      edge = regexprep (mode, '^enabled_?', '');
      if (strncmp (mode, 'reset_', 6))
        ports(end+1) = struct ('name', 'Reset', 'BlockType', 'ResetPort', ...
                               'Params', struct ('ResetTriggerType', mode(7:end)));
      elseif (! isempty (edge))
        value = ob_execution_options (child, false).initial_control;
        if (ischar (value)), state = compatibility_state ();
        elseif (value > 0), state = 'positive';
        elseif (value < 0), state = 'negative';
        else state = 'zero'; endif
        ports(end+1) = struct ('name', 'Trigger', 'BlockType', 'TriggerPort', 'Params', ...
                               struct ('TriggerType', edge, 'InitialTriggerSignalState', state));
      endif
      child.simulink_ports = ports;
    endif
    model.blocks(id).value = child;
  endfor
endfunction

function model = add_control_port (model, levels, name, meta, options)
  child = ob_model_at (model, levels);
  ports = struct ('name', {}, 'BlockType', {}, 'Params', {});
  if (isfield (child, 'simulink_ports')), ports = child.simulink_ports; endif
  if (any (strcmp ({ports.BlockType}, meta.BlockType)))
    error ('add_block: the subsystem already has a %s block', meta.BlockType);
  endif
  for k = 1:2:numel (options)
    meta = set_block_param (meta, options{k}, options{k+1}, name);
  endfor
  had_trigger = any (strcmp ({ports.BlockType}, 'TriggerPort'));
  ports(end+1) = struct ('name', name, 'BlockType', meta.BlockType, 'Params', meta.Params);
  child.simulink_ports = ports;
  child = set_mode (child, control_mode (ports), ports);
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
    diagram = set_mode (diagram, control_mode (ports), ports);
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
      if (isfield (diagram.execution, 'outputs') && iscell (diagram.execution.outputs) ...
          && number <= numel (diagram.execution.outputs))
        diagram.execution.outputs(number) = [];
      endif
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

function meta = set_block_param (meta, name, value, label = '')
  if (strcmp (name, 'Name') || strcmp (name, 'Position')), meta.(['Pending' name]) = value; return; endif
  field = param_field (meta, name);
  if (isempty (field))
    error ('set_param: %s block does not have a parameter named ''%s'' (supported: %s)', meta.BlockType, ...
           name, strjoin (fieldnames (meta.Params)', ', '));
  endif
  meta.Params.(field) = as_text (value);
  if (strcmp (meta.BlockType, 'TriggerPort') && strcmp (field, 'InitialTriggerSignalState'))
    meta.Params.(field) = trigger_state (meta.Params.(field), meta.BlockType, label);
  elseif ((strcmp (meta.BlockType, 'Outport') && strcmp (field, 'OutputWhenDisabled')) ...
          || (strcmp (meta.BlockType, 'EnablePort') && strcmp (field, 'StatesWhenEnabling')))
    % held/reset, case-insensitive like Simulink, stored in lower case
    % (recorded in simulink-conditional-outputs-reference.json).
    match = find (strcmpi ({'held', 'reset'}, meta.Params.(field)), 1);
    if (isempty (match))
      error ('set_param: Invalid setting in %s block ''%s'' for parameter ''%s'': ''%s'' is not held or reset', ...
             meta.BlockType, label, field, meta.Params.(field));
    endif
    meta.Params.(field) = {'held', 'reset'}{match};
  else
    meta.Params.(field) = canonical_enum (meta_kind (meta), field, meta.Params.(field));
  endif
endfunction

function value = canonical_enum (kind, field, value)
  % Enumerated parameters of the 0.3.0 blocks are case-insensitive and
  % stored with Simulink's own spelling (recorded in
  % simulink-api-reference.json, scenarios.followup.enum): MinMax 'MAX' is
  % stored as 'max', Logical Operator 'nxor' as 'NXOR'.  Other values are
  % kept as typed and rejected when the block is realized.
  on_off = {'on', 'off'};
  switch (kind)
    case 'MinMax', table = struct ('Function', {{'min', 'max'}});
    case 'Logic', table = struct ('Operator', {{'AND', 'OR', 'NAND', 'NOR', 'XOR', 'NXOR', 'NOT'}});
    case 'RelationalOperator'
      table = struct ('Operator', {{'==', '~=', '<', '<=', '>=', '>', 'isInf', 'isNaN', 'isFinite'}});
    case 'DiscretePulseGenerator'
      table = struct ('PulseType', {{'Time based', 'Sample based'}}, ...
                      'TimeSource', {{'Use simulation time', 'Use external signal'}});
    case 'MultiPortSwitch'
      table = struct ('DataPortOrder', {{'One-based contiguous', 'Zero-based contiguous', 'Specify indices'}}, ...
                      'DataPortForDefault', {{'Last data port', 'Additional data port'}}, ...
                      'DiagnosticForDefault', {{'None', 'Warning', 'Error'}});
    case 'Signum', table = struct ('ZeroCross', {on_off});
    case {'Mux', 'Demux'}, table = struct ('DisplayOption', {{'none', 'signals', 'bar'}});
    case 'SecondOrderIntegrator'
      table = struct ('ICSourceX', {{'internal', 'external'}}, 'ICSourceDXDT', {{'internal', 'external'}}, ...
                      'LimitX', {on_off}, 'WrapX', {on_off}, 'LimitDXDT', {on_off}, ...
                      'ExternalReset', {{'none', 'rising', 'falling', 'either', 'level'}}, ...
                      'ShowOutput', {{'both', 'x', 'dxdt'}});
    otherwise, return;
  endswitch
  if (! isfield (table, field) || ! ischar (value)), return; endif
  match = find (strcmpi (table.(field), strtrim (value)), 1);
  if (! isempty (match)), value = table.(field){match}; endif
endfunction

function systems = set_param (systems, path, varargin)
  if (mod (numel (varargin), 2) || isempty (varargin))
    error ('set_param: use set_param(object, ''Parameter'', value, ...)');
  endif
  parts = split_path (path);
  index = require_entry (systems, parts{1});
  if (numel (parts) == 1)
    params = systems(index).params;
    dirty = systems(index).dirty; changed = false;
    for k = 1:2:numel (varargin)
      if (strcmpi (varargin{k}, 'Dirty'))
        dirty = is_true (varargin{k+1});
        continue;
      endif
      fields = fieldnames (params);
      match = find (strcmpi (fields, varargin{k}), 1);
      if (isempty (match))
        error ('set_param: unsupported model parameter ''%s'' (supported: %s)', varargin{k}, strjoin (fields', ', '));
      endif
      params.(fields{match}) = as_text (varargin{k+1});
      if (strcmp (fields{match}, 'SimulationMode')), params.SimulationMode = simulation_mode (params.SimulationMode); endif
      changed = true;
    endfor
    run_settings (params);           % validate before committing
    systems(index).params = params;
    systems(index).dirty = dirty || changed;
    return;
  endif
  [index, levels, id] = resolve_port_or_block (systems, path);
  model = systems(index).model;
  diagram = ob_model_at (model, levels);
  if (ischar (id))
    ports = diagram.simulink_ports;
    k = find (strcmp ({ports.name}, id));
    meta = struct ('BlockType', ports(k).BlockType, 'Params', ports(k).Params);
    for j = 1:2:numel (varargin), meta = set_block_param (meta, varargin{j}, varargin{j+1}, id); endfor
    ports(k).Params = meta.Params;
    diagram.simulink_ports = ports;
    diagram = set_mode (diagram, control_mode (ports), ports);
    systems(index).model = ob_set_model_at (model, levels, diagram);
    systems(index).dirty = true;
    return;
  endif
  block = diagram.blocks(id);
  meta = block_meta (block);
  if (! isempty (meta)), meta = outport_view (diagram, id, meta); endif
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
    elseif (strcmp (meta_kind (meta), 'SubSystem') && strcmpi (name, 'Mode'))
      error ('set_param: add Enable, Trigger or Reset blocks to change a subsystem''s execution');
    else
      meta = set_block_param (meta, name, value, display_names (diagram){id});
    endif
  endfor
  if (! isempty (meta)), block.simulink = meta; endif
  previous = diagram;
  diagram.blocks = ob_store_meta_block (diagram.blocks, id, block);
  diagram = realize_block (diagram, id);       % errors leave the system unchanged
  if (any (strcmp (block.type, {'Inport', 'Outport'})) && ! isequal (previous.blocks(id).value, diagram.blocks(id).value))
    diagram = renumber_ports (diagram, id, previous.blocks(id).value);
    ob_validate_model (realize_model (diagram, false));
  endif
  systems(index).model = ob_set_model_at (model, levels, diagram);
  systems(index).dirty = true;
endfunction

function diagram = renumber_ports (diagram, id, old)
  % Moving one In1/Out1 to another number shifts the ports in between by
  % one, as Simulink does.  The parent's lines stay on their port numbers.
  type = diagram.blocks(id).type; new = diagram.blocks(id).value;
  ports = find (strcmp ({diagram.blocks.type}, type));
  if (! isnumeric (new) || ! isscalar (new) || new != fix (new) || new < 1 || new > numel (ports))
    error ('set_param: %s Port must be an integer from 1 to %d', type, numel (ports));
  endif
  before = [diagram.blocks(ports).value]; before(ports == id) = old;
  after = before;
  if (old < new), shift = before > old & before <= new; after(shift) -= 1;
  else shift = before >= new & before < old; after(shift) += 1; endif
  after(ports == id) = new;
  for k = find (after != before)
    diagram.blocks(ports(k)).value = after(k);
    if (! isempty (block_meta (diagram.blocks(ports(k)))))
      diagram.blocks(ports(k)).simulink.Params.Port = num2str (after(k));
    endif
  endfor
  if (strcmp (type, 'Outport') && isfield (diagram, 'execution') ...
      && isfield (diagram.execution, 'initial_outputs'))
    % Initial outputs belong to the Outport blocks, so they move with them.
    initial = diagram.execution.initial_outputs;
    diagram.execution.initial_outputs(after) = initial(before);
    if (isfield (diagram.execution, 'outputs') && iscell (diagram.execution.outputs) ...
        && numel (diagram.execution.outputs) == numel (initial))
      policies = diagram.execution.outputs;
      diagram.execution.outputs(after) = policies(before);
    endif
  endif
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
      case 'Dirty', value = on_off (systems(index).dirty);
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
    meta = struct ('BlockType', port.BlockType, 'MaskType', '', 'Kind', port.BlockType, 'Params', port.Params);
    x = 0.5; y = 0.95; display = id;
  else
    block = diagram.blocks(id);
    meta = block_meta (block);
    if (isempty (meta)), meta = native_meta (block); endif
    meta = outport_view (diagram, id, meta);
    x = block.x; y = block.y; display = display_names (diagram){id};
  endif
  switch (name)
    case 'BlockType', value = meta.BlockType;
    case 'MaskType', value = meta.MaskType;
    case 'Mask', value = on_off (! isempty (meta.MaskType));
    case 'Name', value = display;
    case 'Parent', value = parent;
    case 'Type', value = 'block';
    case 'Position', value = xy_to_position (x, y);
    case {'DialogParameters', 'ObjectParameters'}, value = meta.Params;
    case 'Ports'
      value = zeros (1, 10);
      if (! ischar (id)), value = port_counts (diagram, id); endif
    otherwise
      field = param_field (meta, name);
      if (isempty (field))
        error ('get_param: %s block does not have a parameter named ''%s''', meta.BlockType, name);
      endif
      value = meta.Params.(field);
  endswitch
endfunction

function value = port_counts (diagram, id)
  % Simulink's Ports vector [in out enable trigger state lconn rconn
  % ifaction reset event]; 'in' counts data inputs only.
  block = diagram.blocks(id);
  [inputs, outputs] = ob_block_ports (block);
  if (isinf (inputs))
    % Function blocks take as many inputs as are wired (at least one).
    edges = ob_edges (diagram);
    inputs = max ([1; edges(edges(:, 3) == id, 4)]);
  endif
  % Octave Blocks gives sinks a pass-through value; Simulink sinks have no output port.
  if (any (strcmp (block.type, {'Scope', 'Outport'}))), outputs = 0; endif
  value = zeros (1, 10); value(2) = outputs;
  if (strcmp (block.type, 'Subsystem'))
    mode = ob_execution_mode (block.value);
    value(3) = strcmp (mode, 'enabled') || ob_is_combined_mode (mode);
    value(4) = any (strcmp (mode, {'rising', 'falling', 'either'})) || ob_is_combined_mode (mode);
    value(9) = ob_is_resettable_mode (mode);
    inputs -= sum (value([3 4 9]));
  endif
  value(1) = inputs;
endfunction

function text = on_off (flag)
  if (flag), text = 'on'; else text = 'off'; endif
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
  meta = struct ('BlockType', block_type, 'MaskType', '', 'Kind', block_type, 'Params', params);
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

function [config, options] = run_settings (params, model)
  % MODEL (realized) resolves FixedStep 'auto'; without it only the
  % parameters are validated.
  E = @(name) numeric_param (params.(name), name);
  start = E('StartTime'); stop = E('StopTime');
  solver = params.Solver;
  % ode23, ode113, ode23s, ode23t and ode23tb run on the nearest solver
  % Octave Blocks has; SimulationMetadata.ModelInfo keeps the Simulink name.
  map = struct ('ode4', 'rk4', 'ode45', 'ode45', 'ode15s', 'ode15s', 'ode23', 'ode45', ...
                'ode113', 'ode45', 'ode23s', 'ode15s', 'ode23t', 'ode15s', 'ode23tb', 'ode15s', ...
                'VariableStepAuto', 'ode45', 'FixedStepAuto', 'rk4');
  if (! isfield (map, solver))
    error (['ob_simulink: Solver ''%s'' is not supported (ode4, ode45, ode15s, ode23, ode113, ' ...
            'ode23s, ode23t, ode23tb, VariableStepAuto, FixedStepAuto)'], solver);
  endif
  options = struct ('solver', map.(solver));
  span = stop - start;
  maxstep = Inf;
  if (! strcmpi (params.MaxStep, 'auto')), maxstep = E('MaxStep'); options.maxstep = maxstep; endif
  if (strcmpi (params.FixedStep, 'auto'))
    % Simulink uses the fundamental sample time (GCD of the discrete periods
    % and offsets) for a model without continuous states, and otherwise
    % (stop - start) / 50 bounded by MaxStep.
    step = [];
    if (nargin > 1 && ! ob_has_continuous (model)), step = fundamental_step (model); endif
    if (isempty (step)), step = min (span / 50, maxstep); endif
  else
    step = E('FixedStep');
  endif
  options.reltol = E('RelTol');
  if (strcmpi (params.AbsTol, 'auto')), options.abstol = 1e-6;
  else options.abstol = E('AbsTol'); endif
  options.zero_crossings = strcmpi (params.ZeroCrossControl, 'EnableAll');
  % Accelerator and Rapid Accelerator run the compiled C accelerator
  % (ob_accelerate); models outside its subset fall back to interpretation.
  if (! strcmp (simulation_mode (params.SimulationMode), 'normal')), options.accelerate = 'auto'; endif
  if (! any (strcmp (params.SaveFormat, {'Array', 'Structure', 'StructureWithTime', 'Dataset'})))
    error ('ob_simulink: SaveFormat must be Array, Structure, StructureWithTime or Dataset');
  endif
  if (! any (strcmpi (params.ReturnWorkspaceOutputs, {'on', 'off'})))
    error ('ob_simulink: ReturnWorkspaceOutputs must be on or off');
  endif
  config = ob_validate_config ([start stop step]);
  options = ob_solver_options (options);
endfunction

function step = fundamental_step (model)
  % GCD of every explicit discrete period and offset, including those
  % inside library-built subsystems; [] when the model has none.
  values = discrete_times (model);
  step = [];
  if (isempty (values)), return; endif
  step = values(1);
  for value = values(2:end), step = float_gcd (step, value); endfor
  step = str2double (sprintf ('%.15g', step));      % drop rounding residue
endfunction

function values = discrete_times (model)
  values = [];
  if (isfield (model, 'sample_times') && ! isempty (model.sample_times))
    rates = model.sample_times;
    values = [rates(rates(:, 1) > 0, 1); rates(rates(:, 2) > 0, 2)]';
  endif
  for id = find (strcmp ({model.blocks.type}, 'Subsystem'))
    % A Rate Limiter is inherited or continuous in Simulink, so its
    % Octave-only OctaveSampleTime is not a model rate.
    meta = block_meta (model.blocks(id));
    if (! isempty (meta) && strcmp (meta_kind (meta), 'RateLimiter')), continue; endif
    values = [values discrete_times(model.blocks(id).value)];
  endfor
endfunction

function a = float_gcd (a, b)
  tolerance = 1e-9 * max (a, b);
  while (b > tolerance)
    r = rem (a, b);
    if (b - r <= tolerance), r = 0; endif
    a = b; b = r;
  endwhile
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
  overrides = struct ();
  if (! isempty (rest) && isstruct (rest{1})), overrides = rest{1}; rest(1) = []; endif
  % sim(model, Name, Value) always returns one SimulationOutput in Simulink.
  name_value = ! isempty (rest);
  for field = fieldnames (overrides)'
    rest(end+1:end+2) = {field{1}, overrides.(field{1})};
  endfor
  if (mod (numel (rest), 2)), error ('sim: options must be name/value pairs'); endif
  fields = fieldnames (params);
  for k = 1:2:numel (rest)
    match = find (strcmpi (fields, rest{k}), 1);
    if (isempty (match))
      if (any (strcmpi (rest{k}, {'SaveOutput', 'SaveTime', 'SrcWorkspace'}))), continue; endif
      error ('sim: unsupported parameter ''%s''', rest{k});
    endif
    params.(fields{match}) = as_text (rest{k+1});
    if (strcmp (fields{match}, 'SimulationMode')), params.SimulationMode = simulation_mode (params.SimulationMode); endif
  endfor
  % Like Simulink, [t, x, y] = sim (...) needs ReturnWorkspaceOutputs 'off'
  % and the sim(model[, timespan[, options]]) form.
  legacy = ! name_value && strcmpi (params.ReturnWorkspaceOutputs, 'off');
  if (count > 1 && ! legacy)
    error (['sim: Too many output arguments. Requested %d output(s), but only 1 output(s) available. ' ...
            'The [t, x, y] form needs ReturnWorkspaceOutputs ''off'' and no name/value pairs.'], count);
  endif
  started = clock (); total = tic ();
  model = realize_model (systems(index).model);
  [config, options] = run_settings (params, model);
  if (isempty (times)), times = ob_time_grid (config(1), config(2), config(3)); endif
  execution = tic ();
  routing = routing_blocks (model, [], name);
  try
    [result, accelerated, note] = run_model (model, times, options, params.SimulationMode);
  catch err
    routing_failure (err, routing);
  end_try_catch
  routing_shape_check (routing, result);
  execution_time = toc (execution);
  out = struct ('tout', result.t(:));
  variables = {'tout'};
  % yout: root Outports in port order, in the model's SaveFormat.
  ports = find (strcmp ({model.blocks.type}, 'Outport'));
  [unused, order] = sort ([model.blocks(ports).value]);
  ports = ports(order);
  signals = cell (1, numel (ports)); labels = cell (1, numel (ports));
  names = display_names (systems(index).model);
  for k = 1:numel (ports)
    signals{k} = stack (result.values(:, ports(k)));
    labels{k} = [name '/' names{ports(k)}];
  endfor
  dataset = strcmp (params.SaveFormat, 'Dataset');
  if (dataset)
    % Root Outports log like Simulink's yout elements: the element and its
    % timeseries are named after the signal line (Octave Blocks lines have
    % no names, so ''), BlockPath is the Outport and PortType 'inport'.
    elements = dataset_element_list ();
    for k = 1:numel (ports)
      elements(k) = dataset_signal ('', labels{k}, 'inport', 1, result.t(:), signals{k});
    endfor
    out.yout = dataset_struct ('yout', elements);
  else
    out.yout = output_format (signals, labels, result.t(:), params.SaveFormat);
  endif
  if (! isempty (ports)), variables{end+1} = 'yout'; endif
  % To Workspace variables, and logsout entries for Scope blocks (an
  % Octave Blocks extension), anywhere in the virtual hierarchy.  With
  % SaveFormat 'Dataset', logsout is a Dataset with one element per Scope.
  out.logsout = struct ();
  logged = dataset_element_list ();
  for item = result.signal_map
    if (isempty (item.outputs)), continue; endif
    [block, label, variable, format, shown] = block_at (systems(index).model, item.path);
    if (isempty (block)), continue; endif
    data = stack (result.flat_values(:, item.outputs(1)));
    if (! isempty (variable))
      out.(variable) = workspace_entry (data, result.t(:), [name '/' label], format);
      variables{end+1} = variable;
      continue;
    endif
    if (dataset)
      % Simulink's Scope logging layout (BlockPath the Scope, PortType
      % 'inport', PortIndex 1), named after the Scope, as lines have no names.
      logged(end+1) = dataset_signal (shown, [name '/' label], 'inport', 1, result.t(:), data);
    else
      out.logsout.(valid_name (label)) = workspace_entry (data, result.t(:), [name '/' label], format);
    endif
    if (! any (strcmp (variables, 'logsout'))), variables{end+1} = 'logsout'; endif
  endfor
  if (dataset), out.logsout = dataset_struct ('logsout', logged); endif
  out.who = sort (variables)';
  out.ErrorMessage = '';
  out.SimulationMetadata = metadata (name, params, model, config, options, result, started, ...
                                     execution_time, toc (total));
  out.SimulationMetadata.Accelerated = accelerated;
  diagnostics = struct ('Diagnostic', {});
  if (! isempty (note)), diagnostics(1).Diagnostic = struct ('message', note); endif
  out.SimulationMetadata.ExecutionInfo = struct ('WarningDiagnostics', diagnostics);
  out.result = result;
  if (! legacy)
    varargout{1} = out;
  else
    % Legacy outputs; state trajectories are not exposed, so x is empty.
    varargout = {out.tout, [], out.yout};
    varargout = varargout(1:max (1, count));
  endif
endfunction

function found = routing_blocks (diagram, prefix, label)
  % API Mux and Demux blocks in the virtual hierarchy (their flattened
  % signals are in ob_run's signal_map), with the output shapes their
  % declared Inputs/Outputs imply.  Simulink infers Mux and Demux widths;
  % the builders fix them, so a scalar or row vector where a column of
  % another width is expected must be reported instead of broadcast.
  found = struct ('path', {}, 'label', {}, 'kind', {}, 'expected', {});
  names = display_names (diagram);
  for id = 1:numel (diagram.blocks)
    block = diagram.blocks(id);
    if (! strcmp (block.type, 'Subsystem')), continue; endif
    meta = block_meta (block);
    kind = '';
    if (! isempty (meta)), kind = meta_kind (meta); endif
    here = [label '/' names{id}];
    if (any (strcmp (kind, {'Mux', 'Demux'})))
      inner = block.value.blocks;
      gains = find (strcmp ({inner.type}, 'Gain'));
      if (strcmp (kind, 'Mux'))
        expected = {[rows(inner(gains(1)).value) 1]};
      else
        expected = arrayfun (@(g) [rows(inner(g).value) 1], gains, 'UniformOutput', false);
      endif
      found(end+1) = struct ('path', [prefix id], 'label', here, 'kind', kind, 'expected', {expected});
    elseif ((isempty (meta) || strcmp (kind, 'SubSystem')) && strcmp (ob_execution_mode (block.value), 'virtual'))
      found = [found routing_blocks(block.value, [prefix id], here)];
    endif
  endfor
endfunction

function routing_shape_check (found, result)
  if (isempty (found) || ! isfield (result, 'signal_map') || isempty (result.flat_values)), return; endif
  map = result.signal_map;
  for item = found
    match = find (cellfun (@(p) isequal (p, item.path), {map.path}), 1);
    if (isempty (match)), continue; endif
    outputs = map(match).outputs;
    for k = 1:min (numel (outputs), numel (item.expected))
      value = result.flat_values(1, outputs(k));
      if (iscell (value)), value = value{1}; endif
      want = item.expected{k};
      if (isequal (size (value), want)), continue; endif
      if (strcmp (item.kind, 'Mux'))
        error ('ob_simulink:MuxWidth', ...
               ['ob_simulink: Mux ''%s'' output is %s where a %d-by-1 vector is expected: each input must be ' ...
                'a scalar or a column vector of the width declared in Inputs.  Simulink infers the widths; ' ...
                'Octave Blocks does not, so a count (Inputs ''2'') takes scalar inputs and vector inputs need ' ...
                'their widths, e.g. Inputs ''[2 1]'' with Constant ''[1;2]'''], ...
               item.label, size_text (value), want(1));
      else
        error ('ob_simulink:DemuxWidth', ...
               ['ob_simulink: Demux ''%s'' output %d is %s where %s is expected: the input must be a ' ...
                'column vector of %d elements.  Simulink infers the input width; Octave Blocks takes it ' ...
                'from Outputs (a count N splits an N-element column; give widths, e.g. ''[2 1]'', otherwise)'], ...
               item.label, k, size_text (value), size_text (zeros (want)), sum (cellfun (@(w) w(1), item.expected)));
      endif
    endfor
  endfor
endfunction

function routing_failure (err, found)
  % A dimension error in a model with Mux/Demux blocks most often comes
  % from an input of an undeclared width; say so next to the engine's text.
  if (isempty (found) || isempty (regexp (err.message, 'nonconformant|dimension|state shape', 'once')))
    rethrow (err);
  endif
  error ('ob_simulink:RoutingWidth', ...
         ['%s\n(ob_simulink: this model has Mux/Demux blocks (%s), whose inputs must be scalars or column ' ...
          'vectors of the widths declared in Inputs/Outputs; Simulink infers the widths, Octave Blocks ' ...
          'does not, and a row vector such as Constant ''[1 2]'' must be written as a column ''[1;2]'')'], ...
         err.message, strjoin ({found.label}, ', '));
endfunction

function text = size_text (value)
  text = sprintf ('%dx', size (value)); text(end) = [];
endfunction

function [result, accelerated, note] = run_model (model, times, options, mode)
  % Normal mode interprets.  Accelerator modes run ob_run with
  % accelerate = true first, so that a fallback can be reported, and then,
  % exactly like accelerate = 'auto', interpret a model the accelerator
  % cannot take (outside the C subset, no compiler, or Transport Delay
  % capacity), noting why in SimulationMetadata.ExecutionInfo.
  note = ''; accelerated = false;
  % Scalar Outport InitialOutputs take their port's width from the start,
  % as in Simulink, also before a delayed first execution.
  model = ob_expand_initial_outputs (model);
  if (isequal (options.accelerate, false))
    result = ob_run (model, times, options);
    return;
  endif
  try
    options.accelerate = true;
    result = ob_run (model, times, options);
    accelerated = true;
  catch err
    if (! any (strcmp (err.identifier, {'octave_blocks:accelerate_unsupported', ...
                                        'octave_blocks:accelerate_unavailable', ...
                                        'octave_blocks:accelerate_capacity'})))
      rethrow (err);
    endif
    note = sprintf ('SimulationMode ''%s'' ran in normal (interpreted) mode: %s', mode, err.message);
    options.accelerate = false;
    result = ob_run (model, times, options);
  end_try_catch
endfunction

function text = simulation_mode (value)
  % Simulink's SimulationMode, case-insensitive and stored in lower case
  % (recorded in simulink-conditional-outputs-reference.json).  Both
  % accelerator modes run Octave Blocks' compiled C accelerator.
  modes = {'normal', 'accelerator', 'rapid-accelerator'};
  match = find (strcmpi (modes, value), 1);
  if (isempty (match))
    if (any (strcmpi (value, {'software-in-the-loop (sil)', 'processor-in-the-loop (pil)', 'external'})))
      error ('ob_simulink: SimulationMode ''%s'' is not supported (normal, accelerator, rapid-accelerator)', value);
    endif
    error ('ob_simulink: Invalid setting for block_diagram parameter ''SimulationMode'': ''%s'' (normal, accelerator, rapid-accelerator)', ...
           value);
  endif
  text = modes{match};
endfunction

function yout = output_format (signals, labels, t, format)
  % Simulink's Array, Structure and StructureWithTime yout formats.
  if (isempty (signals)), yout = []; return; endif
  if (strcmp (format, 'Array'))
    if (all (cellfun (@(s) ndims (s) == 2, signals)))
      yout = [signals{:}];
    else
      yout = signals;          % matrix-valued ports cannot share one array
    endif
    return;
  endif
  time = [];
  if (strcmp (format, 'StructureWithTime')), time = t; endif
  dimensions = cellfun (@sample_dimensions, signals, 'UniformOutput', false);
  entries = struct ('values', signals, 'dimensions', dimensions, 'label', '', 'blockName', labels);
  yout = struct ('time', time, 'signals', entries);
endfunction

function entry = workspace_entry (data, t, label, format)
  % To Workspace layouts ('Structure With Time' is Simulink's struct layout).
  if (strcmp (format, 'Array')), entry = data; return; endif
  time = t;
  if (strcmp (format, 'Structure')), time = []; endif
  signals = struct ('values', data, 'dimensions', sample_dimensions (data), 'label', '');
  entry = struct ('time', time, 'signals', signals, 'blockName', label);
endfunction

function elements = dataset_element_list ()
  elements = struct ('Name', {}, 'PropagatedName', {}, 'BlockPath', {}, 'PortType', {}, 'PortIndex', {}, ...
                     'Values', {});
endfunction

function element = dataset_signal (name, block_path, port_type, port_index, t, data)
  % A Simulink.SimulationData.Signal-like struct whose Values field is a
  % timeseries-like struct.  Data keeps Simulink's layout: N-by-1 for a
  % scalar, N-by-n for a vector, r-by-c-by-N (time last) for a matrix.
  values = struct ('Name', name, 'Time', t, 'Data', data, 'IsTimeFirst', ndims (data) < 3, ...
                   'Length', numel (t));
  element = struct ('Name', name, 'PropagatedName', '', 'BlockPath', block_path, 'PortType', port_type, ...
                    'PortIndex', port_index, 'Values', values);
endfunction

function ds = dataset_struct (name, elements)
  % Simulink.SimulationData.Dataset-like struct (see SIMULINK_API.md):
  % Name, numElements, Elements (the element structs) and the access
  % functions getElement (by index or name), get (the same) and
  % getElementNames, called as ds.getElement (k).  The handles call the
  % public ob_simulink ('dataset_element', ...), so they survive clear
  % functions and Octave's text/binary save and load.  MAT files cannot
  % hold function handles: save rmfield (ds, {'getElement', 'get',
  % 'getElementNames'}) and rebuild it with ob_simulink ('dataset', s).
  names = reshape ({elements.Name}, [], 1);
  ds = struct ('Name', name, 'numElements', numel (elements));
  ds.Elements = elements;
  ds.getElement = @(key) ob_simulink ('dataset_element', name, elements, key);
  ds.get = ds.getElement;
  ds.getElementNames = @() names;
endfunction

function value = dataset_lookup (name, elements, key)
  % Simulink's getElement: an index, or a name giving the element, a
  % Dataset of every match when names repeat, or [] (with Simulink's
  % warning) when nothing matches.
  count = numel (elements);
  if (ischar (key) && (rows (key) == 1 || isempty (key)))
    match = find (strcmp ({elements.Name}, key));
    if (isempty (match))
      warning ('ob_simulink:DatasetElementNotFound', 'Did not find any Dataset element using ''%s''.', key);
      value = [];
    elseif (isscalar (match))
      value = elements(match);
    else
      value = dataset_struct (name, elements(match));
    endif
  elseif (isnumeric (key) && isscalar (key) && isreal (key) && key == fix (key) && key >= 1 && key <= count)
    value = elements(key);
  else
    error ('ob_simulink:DatasetIndex', ...
           'To access an element by index, use a scalar numeric integer from 1 to %d.', count);
  endif
endfunction

function dims = sample_dimensions (data)
  % Size of one logged sample: rows hold samples, a third dimension stacks matrices.
  if (ndims (data) == 3), dims = [rows(data) columns(data)];
  else dims = columns (data); endif
endfunction

function info = metadata (name, params, model, config, options, result, started, execution_time, total_time)
  % Keeps the original fields (Solver is the Octave Blocks solver that ran)
  % and adds Simulink's ModelInfo and TimingInfo layout.
  continuous = ob_has_continuous (model);
  solver = params.Solver;
  fixed = any (strcmp (solver, {'ode4', 'FixedStepAuto'}));
  % Like Simulink, a model without continuous states reports the discrete
  % solver whatever solver was chosen (recorded R2026b: ode4 ->
  % FixedStepDiscrete, ode45 -> VariableStepDiscrete).
  if (! continuous && fixed), solver = 'FixedStepDiscrete';
  elseif (! continuous), solver = 'VariableStepDiscrete';
  elseif (strcmp (solver, 'VariableStepAuto')), solver = 'ode45';
  elseif (strcmp (solver, 'FixedStepAuto')), solver = 'ode4'; endif
  if (fixed)
    solver_info = struct ('Type', 'Fixed-Step', 'Solver', solver, 'FixedStepSize', config(3));
  else
    maxstep = (config(2) - config(1)) / 50;
    if (isfield (options, 'maxstep') && isfinite (options.maxstep)), maxstep = options.maxstep; endif
    solver_info = struct ('Type', 'Variable-Step', 'Solver', solver, 'MaxStepSize', maxstep);
  endif
  model_info = struct ('ModelName', name, 'StartTime', config(1), 'StopTime', config(2), ...
                       'SolverInfo', solver_info, 'SimulationMode', params.SimulationMode);
  timing = struct ('WallClockTimestampStart', datestr (started, 'yyyy-mm-dd HH:MM:SS.FFF'), ...
                   'WallClockTimestampStop', datestr (clock (), 'yyyy-mm-dd HH:MM:SS.FFF'), ...
                   'InitializationElapsedWallTime', total_time - execution_time, ...
                   'ExecutionElapsedWallTime', execution_time, 'TotalElapsedWallTime', total_time);
  info = struct ('ModelName', name, 'Solver', options.solver, ...
                 'IntegrationSteps', result.integration_steps, 'Events', {result.events}, ...
                 'ModelInfo', model_info, 'TimingInfo', timing, 'UserString', '', 'UserData', []);
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

function [block, label, variable, format, shown] = block_at (model, path)
  % Logged sink at a flattened PATH: To Workspace (VARIABLE and its
  % SaveFormat) or Scope.  Display and Terminator log nothing, like Simulink.
  % SHOWN is the sink's own display name.
  block = []; label = ''; variable = ''; format = 'Structure With Time'; shown = '';
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
  if (! strcmp (current.type, 'Scope')), return; endif
  label = strjoin (names, '/');
  meta = block_meta (current);
  if (isempty (meta))
    block = current;                        % a native Scope
  elseif (strcmp (meta_kind (meta), 'ToWorkspace'))
    variable = evaluate_name (meta.Params.VariableName);
    format = save_format (meta.Params.SaveFormat);
    block = current;
  elseif (strcmp (meta_kind (meta), 'Scope'))
    block = current;
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
