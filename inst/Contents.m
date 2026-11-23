% Octave Blocks
%
% Editor: octave_blocks
% Simulation: ob_run, ob_runtime_init, ob_runtime_step, ob_runtime_outputs
% Signals: ob_scope_data, ob_scope_paths, ob_signal_values
% Models: ob_connect, ob_disconnect, ob_load_model, ob_save_model
% Builders: ob_state_space, ob_transfer_function, ob_subsystem_template
% Export: ob_codegen
% Acceleration: ob_accelerate
% Programmatic models: ob_simulink, ob_simulink_setup
%
% Nonlinear and logic builders:
%   ob_backlash                 - Backlash (mechanical play) subsystem
%   ob_quantizer                - Quantizer subsystem
%   ob_minmax                   - Multi-input MinMax subsystem
%   ob_saturation_dynamic       - Saturation Dynamic subsystem
%   ob_dead_zone_dynamic        - Dead Zone Dynamic subsystem
%   ob_sign                     - Sign (signum) subsystem
%   ob_coulomb_viscous_friction - Coulomb & Viscous Friction subsystem
%   ob_relational_operator      - Relational Operator subsystem
%   ob_logical_operator         - Logical Operator subsystem
% Signal routing and source builders:
%   ob_mux                      - Mux subsystem (signals -> one column vector)
%   ob_demux                    - Demux subsystem (column vector -> signals)
%   ob_multiport_switch         - Multiport Switch subsystem
%   ob_pulse_generator          - Time-based Pulse Generator source
%   ob_chirp                    - Chirp Signal (linear swept sine) source
% Continuous and multirate builders:
%   ob_first_order_filter       - Continuous or discretized first-order filter
%   ob_second_order_integrator  - 'Integrator, Second-Order' subsystem
%   ob_rate_transition          - Rate Transition with Integrity/Deterministic modes
% Analysis:
%   ob_linearize                - Linearize a continuous model about an operating point (linmod)
%   ob_findop                   - Find a steady-state operating point (trim)
%   ob_bode                     - Frequency response and stability margins
%   ob_stepinfo                 - Step-response characteristics of sampled data
%
% Source checkout: call ob_setup() from the project root.
% Installed package: pkg load octave-blocks
% See the package INDEX and doc/README.md for categorized documentation.
