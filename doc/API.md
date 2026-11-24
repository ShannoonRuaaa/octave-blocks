# Public API inventory and proposed stability policy

**Development draft: not a 1.0 release or a frozen API contract.** These
changes are not fully tested and will be verified on another machine.
See [proposal review and verification plan](V1_PROPOSAL_REVIEW.md).

The inventory below covers every installed function. A **candidate** is
proposed for stability at a future 1.0 release; it remains a development API
until the roadmap's compatibility and validation gates are satisfied.
**Experimental** functions and example topologies may change.

The proposed 1.x policy is to preserve documented signatures, options and
result fields, and change default numerical results only for documented
bug fixes recorded in [NEWS](../NEWS). Removal would require a major release
after at least one minor release with an identified deprecation warning.
This describes the target policy, not evidence of completed compatibility
verification.

## Installed function inventory

Command wrappers in `inst/simulink/` are available only after
`ob_simulink_setup ()`. Implementation in `inst/private/` is not public.

| Function | Status | Location |
| --- | --- | --- |
| `ob_accelerate` | candidate | `inst/` |
| `ob_atomic_feedthrough` | experimental | `inst/` |
| `ob_backlash` | candidate | `inst/` |
| `ob_bode` | candidate | `inst/` |
| `ob_c2d_state_space` | candidate | `inst/` |
| `ob_chirp` | candidate | `inst/` |
| `ob_codegen` | candidate | `inst/` |
| `ob_connect` | candidate | `inst/` |
| `ob_coulomb_viscous_friction` | candidate | `inst/` |
| `ob_dead_zone_dynamic` | candidate | `inst/` |
| `ob_demux` | candidate | `inst/` |
| `ob_disconnect` | candidate | `inst/` |
| `ob_discrete_state_space` | candidate | `inst/` |
| `ob_discrete_transfer_function` | candidate | `inst/` |
| `ob_edges` | candidate | `inst/` |
| `ob_findop` | candidate | `inst/` |
| `ob_first_order_filter` | candidate | `inst/` |
| `ob_input_signal` | candidate | `inst/` |
| `ob_input_value` | candidate | `inst/` |
| `ob_linearize` | candidate | `inst/` |
| `ob_load_model` | candidate | `inst/` |
| `ob_logical_operator` | candidate | `inst/` |
| `ob_lookup_table_1d` | candidate | `inst/` |
| `ob_minmax` | candidate | `inst/` |
| `ob_model_at` | candidate | `inst/` |
| `ob_multiport_switch` | candidate | `inst/` |
| `ob_mux` | candidate | `inst/` |
| `ob_pid_controller` | candidate | `inst/` |
| `ob_pulse_generator` | candidate | `inst/` |
| `ob_quantizer` | candidate | `inst/` |
| `ob_rate_limiter` | candidate | `inst/` |
| `ob_rate_transition` | candidate | `inst/` |
| `ob_relational_operator` | candidate | `inst/` |
| `ob_relay` | candidate | `inst/` |
| `ob_run` | candidate | `inst/` |
| `ob_runtime_init` | candidate | `inst/` |
| `ob_runtime_outputs` | candidate | `inst/` |
| `ob_runtime_step` | candidate | `inst/` |
| `ob_saturation_dynamic` | candidate | `inst/` |
| `ob_save_model` | candidate | `inst/` |
| `ob_scope_data` | candidate | `inst/` |
| `ob_scope_paths` | candidate | `inst/` |
| `ob_second_order_integrator` | candidate | `inst/` |
| `ob_set_model_at` | candidate | `inst/` |
| `ob_sign` | candidate | `inst/` |
| `ob_signal_values` | candidate | `inst/` |
| `ob_simulink_setup` | candidate | `inst/` |
| `ob_simulink` | candidate | `inst/` |
| `ob_state_space` | candidate | `inst/` |
| `ob_stepinfo` | candidate | `inst/` |
| `ob_subsystem_template` | candidate | `inst/` |
| `ob_transfer_function` | candidate | `inst/` |
| `ob_zero_pole` | candidate | `inst/` |
| `octave_blocks` | candidate | `inst/` |
| `ob_algebraic_example` | experimental | `inst/examples/` |
| `ob_combined_continuous_example` | experimental | `inst/examples/` |
| `ob_combined_control_example` | experimental | `inst/examples/` |
| `ob_combined_enable_wave` | experimental | `inst/examples/` |
| `ob_combined_trigger_wave` | experimental | `inst/examples/` |
| `ob_conditional_example` | experimental | `inst/examples/` |
| `ob_continuous_control_example` | experimental | `inst/examples/` |
| `ob_control_example` | experimental | `inst/examples/` |
| `ob_demo_function` | experimental | `inst/examples/` |
| `ob_demo_multi_function` | experimental | `inst/examples/` |
| `ob_enabled_continuous_example` | experimental | `inst/examples/` |
| `ob_enabled_multirate_example` | experimental | `inst/examples/` |
| `ob_example` | experimental | `inst/examples/` |
| `ob_function_example` | experimental | `inst/examples/` |
| `ob_gated_outputs_example` | experimental | `inst/examples/` |
| `ob_input_example` | experimental | `inst/examples/` |
| `ob_linear_system_example` | experimental | `inst/examples/` |
| `ob_multioutput_example` | experimental | `inst/examples/` |
| `ob_multirate_example` | experimental | `inst/examples/` |
| `ob_oscillator` | experimental | `inst/examples/` |
| `ob_scalar_initial_example` | experimental | `inst/examples/` |
| `ob_staggered_enables_example` | experimental | `inst/examples/` |
| `ob_subsystem_example` | experimental | `inst/examples/` |
| `ob_zero_crossing_example` | experimental | `inst/examples/` |
| `add_block` | candidate | `inst/simulink/` |
| `add_line` | candidate | `inst/simulink/` |
| `bdclose` | candidate | `inst/simulink/` |
| `bdIsLoaded` | candidate | `inst/simulink/` |
| `close_system` | candidate | `inst/simulink/` |
| `delete_block` | candidate | `inst/simulink/` |
| `delete_line` | candidate | `inst/simulink/` |
| `find_system` | candidate | `inst/simulink/` |
| `get_param` | candidate | `inst/simulink/` |
| `load_system` | candidate | `inst/simulink/` |
| `new_system` | candidate | `inst/simulink/` |
| `open_system` | candidate | `inst/simulink/` |
| `save_system` | candidate | `inst/simulink/` |
| `set_param` | candidate | `inst/simulink/` |
| `sim` | candidate | `inst/simulink/` |

## Data returned by the current implementation

- **Model:** scalar struct with `blocks` and `edges`. Blocks contain
  `type`, `value`, `name`, `x`, `y`, and may have `outputs`,
  `algebraic_initial` or command-API metadata. Edges are legacy
  `[source target]` rows or `[source source_port target target_port]`
  rows. Optional fields include `sample_times`, `inputs` and `execution`.
- **`ob_run` result:** `t`, `values`, `flat_values`, `order`,
  `solver`, `solver_options`, `integration_steps`, `signal_map`,
  `block_paths`, `compiled_model`, `inputs`, `sample_hits`,
  `sample_times` and `events`. `t` is a column; `values` is a cell
  array indexed by output time and root block, whereas `flat_values`
  corresponds to the compiled model. A root block's entry in `values`
  represents its first output; use `ob_signal_values` for other ports.
- **`ob_scope_data`:** a numeric matrix with one row per requested output
  time and one column per signal element, flattened in column-major order.
- **`sim` output:** `tout`, `yout`, `logsout`, `who`,
  `ErrorMessage`, `SimulationMetadata`, `result` and any To Workspace
  variables. `SaveFormat` controls the representation of `yout`;
  see [Dataset output](SIMULINK_API.md#dataset-output). Dataset-like structs
  expose `numElements`, `getElement`, `get` and `getElementNames`.
- **Saved model:** [MODEL_FORMAT.md](MODEL_FORMAT.md) defines the version
  marker and legacy normalization. A schema marker alone does not prove
  that all historical model files or future releases remain compatible.

## Selected implemented diagnostic identifiers

| Identifier | Meaning |
| --- | --- |
| `octave_blocks:QtUnavailable` | No Qt toolkit is available in the current build/session. |
| `ob_load_model:InvalidPath` | File path is not a nonempty character row. |
| `ob_load_model:FileNotFound` | The requested file does not exist. |
| `ob_load_model:MissingModel` | The file has no model variable. |
| `ob_load_model:InvalidFormatVersion` | Schema marker is not a positive numeric integer scalar. |
| `ob_load_model:UnsupportedFormatVersion` | Schema marker is newer than the supported version. |
| `ob_save_model:InvalidPath` | Destination path is not a nonempty character row. |
| `ob_save_model:WriteFailed` | Replacing the destination with the temporary save failed. |
| `ob_run:ode15sUnavailable` | Octave was built without the required SUNDIALS IDA backend. |
| `octave_blocks:accelerate_unsupported` | Model or options are outside the accelerator subset. |
| `octave_blocks:accelerate_unavailable` | Compiler, build, cache or MEX loading is unavailable. |
| `octave_blocks:accelerate_capacity` | Compiled delay history exceeded all retried capacities. |
| `octave_blocks:accelerate_runtime` | The compiled model reported a runtime failure. |

This list is not an exhaustive error contract. Some operations still raise
unidentified errors. The proposed `ob_simulink:SolverSubstituted` warning
is not implemented; see [limitations](LIMITATIONS.md). No 1.0 readiness claim
follows from the inventory or the focused contract tests.
