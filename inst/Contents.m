## Octave Blocks
##
## Visual editor
##   octave_blocks               - Open the visual block diagram editor
## Simulation
##   ob_run                      - Simulate a model at requested output times
##   ob_runtime_init             - Initialize a resumable simulation context
##   ob_runtime_step             - Advance a simulation context
##   ob_runtime_outputs          - Read a context's current signal values
##   ob_scope_data               - Flatten logged signals into numeric traces
##   ob_scope_paths              - Find Scopes in a model hierarchy
##   ob_signal_values            - Read logged samples with their original shapes
##   ob_accelerate               - Run supported models with cached compiled C
## Programmatic modeling
##   ob_simulink                 - Dispatch Simulink-style modeling commands
##   ob_simulink_setup           - Opt in to Simulink-named command wrappers
## Simulink-style commands (opt in with ob_simulink_setup)
##   new_system                  - Create a model
##   load_system                 - Load a saved model
##   open_system                 - Open a model in the editor
##   close_system                - Close a model, saving or discarding changes
##   save_system                 - Save a model
##   bdIsLoaded                  - Test whether a model is loaded
##   bdclose                     - Discard and close loaded models
##   add_block                   - Add or copy a block
##   delete_block                - Delete a block
##   add_line                    - Connect block ports
##   delete_line                 - Disconnect block ports
##   get_param                   - Read model or block parameters
##   set_param                   - Set model or block parameters
##   find_system                 - Find models and blocks by their parameters
##   sim                         - Simulate a loaded model
## Models and connections
##   ob_connect                  - Connect model block ports
##   ob_disconnect               - Remove a model connection
##   ob_load_model               - Load and validate a saved model
##   ob_save_model               - Validate and save a model
##   ob_model_at                 - Read a subsystem diagram by path
##   ob_set_model_at             - Replace a subsystem diagram by path
##   ob_edges                    - Return canonical port connections
## Subsystem and signal builders
##   ob_subsystem_template       - Build an Inport--Gain--Outport subsystem
##   ob_input_signal             - Create an external input dataset
##   ob_input_value              - Evaluate an external input dataset
##   ob_state_space              - Build a continuous state-space system
##   ob_transfer_function        - Build a continuous transfer function
##   ob_pid_controller           - Build a PID controller
##   ob_zero_pole                - Build a zero-pole-gain system
##   ob_discrete_state_space     - Build a discrete state-space system
##   ob_discrete_transfer_function - Build a discrete transfer function
##   ob_c2d_state_space          - Discretize state-space matrices
##   ob_lookup_table_1d          - Build a one-dimensional lookup table
##   ob_rate_limiter             - Build a sampled slew limiter
##   ob_relay                    - Build a sampled hysteresis relay
##   ob_atomic_feedthrough       - Experimental structural feedthrough diagnostic
##   ob_first_order_filter       - Build a continuous or discrete filter
##   ob_second_order_integrator  - Build a second-order integrator
##   ob_rate_transition          - Build Integrity/Deterministic transfer modes
## Nonlinear and logic builders
##   ob_backlash                 - Build a backlash subsystem
##   ob_quantizer                - Build a quantizer subsystem
##   ob_minmax                   - Build a multiple-input MinMax subsystem
##   ob_saturation_dynamic       - Build a Saturation Dynamic subsystem
##   ob_dead_zone_dynamic        - Build a Dead Zone Dynamic subsystem
##   ob_sign                     - Build a signum subsystem
##   ob_coulomb_viscous_friction  - Build a Coulomb and viscous friction subsystem
##   ob_relational_operator      - Build a relational comparison subsystem
##   ob_logical_operator         - Build a logical operation subsystem
## Signal routing and source builders
##   ob_mux                      - Combine signals into a column vector
##   ob_demux                    - Split a column vector into signals
##   ob_multiport_switch         - Select a signal by an index
##   ob_pulse_generator          - Build a pulse source
##   ob_chirp                    - Build a linear swept sine source
## Analysis
##   ob_linearize                - Linearize a continuous model
##   ob_findop                   - Find a steady-state operating point
##   ob_bode                     - Calculate frequency response and margins
##   ob_stepinfo                 - Measure sampled step-response characteristics
## C export
##   ob_codegen                  - Export the supported model subset as C99
## Examples
##   ob_example                  - Time--Gain--Scope diagram
##   ob_oscillator               - Harmonic oscillator
##   ob_function_example         - Ordinary Octave Function block
##   ob_multioutput_example      - Function with several output ports
##   ob_input_example            - Integrator driven by an external input
##   ob_subsystem_example        - Oscillator with nested states
##   ob_linear_system_example    - Continuous second-order plant
##   ob_control_example          - Clamping, dead zone and switching
##   ob_conditional_example      - Enabled Unit Delay
##   ob_continuous_control_example - Continuously enabled integrator
##   ob_enabled_continuous_example - Sampled enable of a continuous state
##   ob_enabled_multirate_example - Enabled subsystem with inner clocks
##   ob_combined_control_example - Combined enable and trigger controls
##   ob_combined_continuous_example - Independent continuous guards
##   ob_multirate_example        - Sampled hold driving an integrator
##   ob_zero_crossing_example    - Located switching event
##   ob_gated_outputs_example    - Enabled Outports with different source rates
##   ob_scalar_initial_example   - Scalar InitialOutput expansion
##   ob_staggered_enables_example - Independent enable events
##   ob_algebraic_example        - Feedback with an algebraic variable
## Example signal functions
##   ob_demo_function            - Damped sine Function block implementation
##   ob_demo_multi_function      - Function with independently shaped outputs
##   ob_combined_enable_wave     - Enable waveform for combined-control examples
##   ob_combined_trigger_wave    - Trigger waveform for combined-control examples
##
## Source checkout: ob_setup ().  Installed package: pkg load octave-blocks.
## See INDEX for categories and doc/README.md for the documentation index.
