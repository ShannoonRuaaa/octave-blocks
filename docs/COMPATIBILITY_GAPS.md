# Compatibility status and remaining work

Status: **active and incomplete**, reviewed 2026-11-22. The goal is to extend
Octave Blocks toward full Simulink functionality, including subsystems,
variable-step solvers and code generation. Passing a milestone does not complete
that goal. This ledger describes current scope; dated entries in
[ADVANCED_PLAN.md](ADVANCED_PLAN.md) retain historical evidence.

The published optimization release is merged at `3cbf61c`. The verified event-C
milestone is on `codex/event-c-integration`; its public `ob_codegen` route is
implemented and ready for review. It has not yet been merged into `main`.

## Implemented scope and explicit gaps

| Area | Implemented and tested subset | Remaining compatibility work |
| --- | --- | --- |
| Subsystems | Numbered ports, virtual flattening, nested editing/persistence, multiple outputs; sampled enabled/triggered contexts; continuous enabled states and explicit continuous controls; combined enable-and-trigger modes and child Enable reset precedence; all four Simulink trigger initial states, including `compatibility`; per-port OutputWhenDisabled; scalar InitialOutput expansion, also nested and before a delayed first execution (in Octave by static shape propagation in `ob_expand_initial_outputs`, with ports fed by blocks whose shape is known only by evaluation, such as Function blocks and lookup tables, expanded from their first value at runtime; in C by the conditional exporter's own `ob_c_conditional_unit`); Outports of enabled bodies with inner clocks that update at their sources' rates, with clocked blocks sharing the buffer of the Outport they drive; sampled resettable discrete bodies and per-port structural feedthrough diagnostics. All recorded Simulink traces of these features agree. | Continuous resettable variants and nested conditional reset bodies; live traces for function-call triggers, resettable subsystems, continuous combined controls and continuous controls nested in other conditional subsystems under variable-step solvers; the Outport buffer of an inherited-rate block (e.g. a Gain of a slow delay) read by faster blocks, and of a clocked block that drives no Outport, before it executes (not probed); vector controls; use of feedthrough analysis in atomic scheduling; broader structural editing. |
| Variable-step simulation | Octave `ode45` and `ode15s`, tolerances/max-step settings, explicit source/clock boundaries, shared enabled states and registered guard localization. On Octave 11.3.0 with double settings, `ode45` runs through a bit-identical copy of Octave's Dormand–Prince code without per-call option handling. | Solver-state continuity across output intervals; general reset/event classes; implicit/stiff DAEs; robust multiple/tangential crossing policies. |
| Code generation | Supported static real-double C99 subset, RK4 including registered guard/continuous-control events, hierarchy, root input callbacks, independent clocks, transactional contexts and selected builtin Function mappings; Transport Delay and Limited Integrator on the flat path; adaptive `ode45` for flat models (double tolerances), a port of Octave's algorithm. | `ode15s`, and adaptive solvers for conditional/event exports; user `.m` Functions in standalone C; broader Function/multi-output signatures; configurable namespaces, parameter tuning, deployment targets and integration. Arbitrary Octave translation remains open. |
| Accelerator mode | Cached compiled C (MEX) runs through `ob_run` option `accelerate`, `ob_accelerate` or `SimulationMode`: flat `rk4`/`ode45` models, `rk4` models with conditional subsystems, multiple-output Functions, zero crossings or continuous controls, and user `.m` Functions in flat models (called back into Octave). Results equal interpreted runs field by field; delay histories are enlarged automatically on overflow; `'auto'` falls back to interpretation outside the subset. | `ode15s`; in models that need the typed exporter (conditional subsystems, multiple-output Functions, zero crossings): `ode45`, user Functions, Transport Delays and Limited Integrators; algebraic loops. Nonfinite values from C-mapped blocks fail accelerated runs (also with `'auto'`). No separate Rapid Accelerator or standalone executable packaging (`rapid-accelerator` runs the same accelerator). The MEX gateway is untested on Linux/macOS (POSIX threads path). |
| Scheduling | Explicit periods/offsets, deterministic simultaneous hits, enabled inner clocks, inherited control-clock unions and sample-and-hold Rate Transitions. | Full automatic sample-time propagation; algebraic-block rate propagation (Outports of enabled bodies with inner clocks already follow their sources' rates); Simulink's deterministic (slow-to-fast transfer one slow period late) and integrity-off Rate Transition modes ([MULTIRATE.md](MULTIRATE.md)); asynchronous/multitasking scheduling. |
| Algebraic systems | Smooth fixed-shape real-double components, warm starts, matrix signals, virtual boundaries and finite/residual diagnostics. | Broader loop blocks and atomic hierarchy analysis; sparse/analytic Jacobians and large-loop performance; implicit DAEs. C export rejects algebraic loops. |
| Signals and blocks | Real numeric matrix signals, common math/control primitives, multiple Function outputs, [advanced builders](ADVANCED_EXTENSIONS.md) for PID, linear systems, lookup tables, sampled slew limiting and sampled relay hysteresis, plus Transport Delay and the Limited Integrator (output limits, sampled external reset including level and level hold) in the Octave runtime and flat C export, checked against Simulink 26.2 traces. | Transport Delay and Limited Integrator in zero-crossing runs, conditional bodies and the conditional/event C exporter; event-located integrator resets; zero or per-element Transport Delay times; bus signals and additional data types; broader libraries and diagnostics. |
| Models and ecosystem | Octave Blocks model files and resumable MAT contexts, examples, editor configuration and undo/redo; a [Simulink-style command API](SIMULINK_API.md) (`new_system`, `add_block`, `add_line`, `set_param`, `get_param`, `find_system`, `sim`, ...) accepting the exact Simulink R2026b library paths and `built-in/<BlockType>` forms listed in SIMULINK_API.md, with Simulink's BlockType, parameter names and defaults checked against live Simulink 26.2; `SimulationMode` normal/accelerator/rapid-accelerator. | Dataset/timeseries logging and `Simulink.SimulationOutput` objects; model references, subsystem variants, Simulink `.slx`/`.mdl` import/export, library/toolbox compatibility, Stateflow, Simscape and other product integrations. |

Existing limits are documented in [README.md](../README.md),
[CONDITIONAL.md](CONDITIONAL.md), [CONTINUOUS_CONTROLS.md](CONTINUOUS_CONTROLS.md),
[ZERO_CROSSINGS.md](ZERO_CROSSINGS.md), [ALGEBRAIC.md](ALGEBRAIC.md),
[MULTIRATE.md](MULTIRATE.md) and [CODEGEN.md](CODEGEN.md). These subsets are not
a claim of file, block, solver or generated-code parity with Simulink. The
latest gate results are in [VALIDATION.md](VALIDATION.md).

## Event C evidence (2026-11-14)

On 2026-11-14, the integrated experimental path passed:

- `Test-EventCodegen.ps1 -ExperimentalTyped`: 43 analytical numeric models and
  two API harnesses compiled/executed with `-std=c99 -O2 -Wall -Wextra -Werror`.
  All 392 numeric channels matched Octave; worst scaled error 0.
- `Test-EventCodegenEdges.ps1 -ExperimentalTyped`: six independent numeric
  edge models and one guard-overflow API harness passed the same strict gate.
  All 30 numeric channels matched Octave; worst scaled error 0.

Local logs are `.validation-artifacts/event-c-20261114-integration.log` and
`.validation-artifacts/event-c-20261114-edges.log`. Generated artifacts are in
the corresponding directories without `.log`; they are ignored by Git. These
results preceded activation of the public route. The final registered check
set then passed through public `ob_codegen`: 21 Octave suites, 25 BIST checks,
235 strict C99 cases (219 numerical models, sixteen API harnesses), and expanded
Qt checks. Worst observed numerical scaled error was 0. This includes eleven
nested models/three metadata APIs and two exact editor exports. The main gate's
execution handle became unavailable after Qt callbacks; its completed stages
were retained, and the final Qt/C stage and BIST were rerun with exit 0. See
[VALIDATION.md](VALIDATION.md) for precise logs and verification scope.

## Next acceptance milestones

1. **Event-enabled RK4 C export: implemented and verified.** Public routing,
   active/dormant nested descendants, source jumps, coincidence, plateau/equality,
   metadata, finite failures, instance isolation, rollback/retry and editor export
   have acceptance coverage. Invalid/unsupported exports preserve caller files;
   the ordinary event-off C cases still pass. This closes the named milestone,
   not all event classes, all possible models or live Simulink trace parity.
   [Runtime contract and commands](EVENT_CODEGEN_DEVELOPMENT.md).
2. **Conditional semantic variants and atomic dependencies.** Specify and test
   combined enable/trigger/reset behavior, initialization and nested policy
   precedence. Derive boundary feedthrough per output; accept state-broken
   feedback and reject genuine unsupported loops without adding artificial
   delays. Exercise Octave, C, persistence and editor configuration consistently.
3. **Adaptive execution and emission.** Flat models export with `ode45`, a port
   of Octave's own algorithm with its tolerances, rejection limit and step-failure
   rollback (10 gate models, worst scaled error 3.3e-16). Still open: preserving
   adaptive solver state across output requests without crossing
   source/clock/event boundaries incorrectly; adaptive emission for
   conditional/event exports with event restart contracts; `ode15s` emission.
   DAE constraints require their own initialization/residual acceptance.
4. **Broader libraries, scheduling and tooling.** Implement the open items in
   the table as documented milestones with executable examples, independent
   references, meaningful failure tests, editor/file roundtrips where relevant,
   and explicit supported/unsupported contracts. No ecosystem item is marked
   complete merely because the present regression suite does not exercise it.

## MATLAB, Simulink and REA reference limits

[REFERENCE_EVIDENCE.md](REFERENCE_EVIDENCE.md) records the development probes and
their limits. Simulink 26.2 (MATLAB R2026b Update 1) is installed and licensed:
`reference_ob_environment.m` builds and simulates a model and records the result
in `matlab-environment.json`. An earlier probe that reported no Simulink relied
on a license test alone. Recorded Simulink traces now verify:

- the sampled conditional, combined and nested-reset semantics, including
  Simulink's default `compatibility` trigger state (`test_ob_simulink_conditional`:
  all 304 cases match);
- continuous controls and primitive crossings under ode45/ode15s, multiple
  outputs, inner clocks and Outport timing (`test_ob_simulink_extended`: 75 of 78
  cases agree; the 3 others are the Rate Transition modes in the Scheduling row);
- Transport Delay and Limited Integrator behaviour
  (`test_ob_simulink_delay_integrator`: 22 agree, 29 documented differences);
- the command API (`test_ob_simulink_api_reference`, 158 checks);
- the nine shared benchmark cases (`test_ob_simulink_benchmarks`: 4 agree,
  5 documented differences, interpreted and accelerated).

Recorded MATLAB builtin numeric comparisons cover their named operations only.

The two bounded REA scans observed 237 filesystem entries each, read **zero
file payloads/bytes**, and found no runtime candidates. They provide installation
metadata, not simulation algorithms or observed engine behavior. Further MATLAB
or REA work should answer a specific unresolved compatibility question and retain
reproducible evidence; static inspection cannot substitute for runtime results.

Live traces cover only the recorded scenarios. Features without a recorded
trace (function-call triggers, resettable subsystems, continuous combined
controls and nested continuous controls under variable-step solvers, generated
C against Simulink Coder) remain unproven against Simulink. Regenerate a reference with its `reference_ob_*.m` producer
in MATLAB before making a new claim, and keep those evidence gaps distinct from
missing runtime, editor or code-generation functionality.
