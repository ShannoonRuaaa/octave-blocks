# Compatibility status and remaining work

Status: **active and incomplete**, reviewed 2026-11-14. The goal is to extend
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
| Subsystems | Numbered ports, virtual flattening, nested editing/persistence, multiple outputs; sampled enabled/triggered contexts; continuous enabled states and explicit continuous controls. | Combined enable-and-trigger/resettable variants; first-evaluation trigger initialization; descendant reset-policy precedence; vector controls; atomic boundary feedthrough analysis; broader structural editing. |
| Variable-step simulation | Octave `ode45` and `ode15s`, tolerances/max-step settings, explicit source/clock boundaries, shared enabled states and registered guard localization. | Solver-state continuity across output intervals; general reset/event classes; implicit/stiff DAEs; robust multiple/tangential crossing policies. |
| Code generation | Supported static real-double C99 subset, RK4 including registered guard/continuous-control events, hierarchy, root input callbacks, independent clocks, transactional contexts and selected builtin Function mappings. | Adaptive C solvers; broader Function/multi-output signatures; configurable namespaces, parameter tuning, deployment targets and integration. Arbitrary Octave translation remains open. |
| Scheduling | Explicit periods/offsets, deterministic simultaneous hits, enabled inner clocks, inherited control-clock unions and supported Rate Transition behavior. | Full automatic sample-time propagation, algebraic-block/Outport rate propagation, target-specific transfer policies, asynchronous/multitasking scheduling and data-integrity policies. |
| Algebraic systems | Smooth fixed-shape real-double components, warm starts, matrix signals, virtual boundaries and finite/residual diagnostics. | Broader loop blocks and atomic hierarchy analysis; sparse/analytic Jacobians and large-loop performance; implicit DAEs. C export rejects algebraic loops. |
| Signals and blocks | Real numeric matrix signals, common math/control primitives, multiple Function outputs, editable state-space and proper SISO transfer-function builders. | Bus signals and additional data types, broader routing/control/system libraries and primitive signatures; broader model diagnostics/debugging. |
| Models and ecosystem | Octave Blocks model files and resumable MAT contexts, examples, editor configuration and undo/redo. | Model references, subsystem variants, Simulink `.slx`/`.mdl` import/export, library/toolbox compatibility, Stateflow, Simscape and other product integrations. |

Existing limits are documented in [README.md](tests/README.md),
[CONDITIONAL.md](CONDITIONAL.md), [CONTINUOUS_CONTROLS.md](CONTINUOUS_CONTROLS.md),
[ZERO_CROSSINGS.md](ZERO_CROSSINGS.md), [ALGEBRAIC.md](ALGEBRAIC.md) and
[CODEGEN.md](CODEGEN.md). These subsets are not a claim of file, block, solver
or generated-code parity with Simulink.

## Current event C evidence

On 2026-11-14, the integrated experimental path passed:

- `tests/Test-EventCodegen.ps1 -ExperimentalTyped`: 43 analytical numeric models and
  two API harnesses compiled/executed with `-std=c99 -O2 -Wall -Wextra -Werror`.
  All 392 numeric channels matched Octave; worst scaled error 0.
- `tests/Test-EventCodegenEdges.ps1 -ExperimentalTyped`: six independent numeric
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
3. **Adaptive execution and emission.** Preserve adaptive solver state across
   output requests without crossing source/clock/event boundaries incorrectly.
   Implement generated adaptive error control with explicit tolerances,
   rejection/retry and event restart contracts; verify analytical nonstiff/stiff
   models, matrices, hierarchy, irregular outputs and transactional failures.
   DAE constraints require their own initialization/residual acceptance.
4. **Broader libraries, scheduling and tooling.** Implement the open items in
   the table as documented milestones with executable examples, independent
   references, meaningful failure tests, editor/file roundtrips where relevant,
   and explicit supported/unsupported contracts. No ecosystem item is marked
   complete merely because the present regression suite does not exercise it.

## MATLAB, Simulink and REA reference limits

[REFERENCE_EVIDENCE.md](REFERENCE_EVIDENCE.md) records the development probes and
their limits. The retained MATLAB R2026b Update 1 probe reported no installed
Simulink and no `load_system`, despite a positive feature-license test. This is
a historical observation, not a new check of the current installation. The
retained conditional comparison harness has not produced a live Simulink trace.
Recorded MATLAB builtin numeric comparisons cover their named operations only.

The two bounded REA scans observed 237 filesystem entries each, read **zero
file payloads/bytes**, and found no runtime candidates. They provide installation
metadata, not simulation algorithms or observed engine behavior. Further MATLAB
or REA work should answer a specific unresolved compatibility question and retain
reproducible evidence; static inspection cannot substitute for runtime results.

Unavailable live Simulink validation does not prevent implementing and testing
runtime milestones against public contracts and analytical references. It does
leave live trace agreement and broader compatibility unproven. Recheck the
environment before making a new claim about availability, then run the relevant
reference harness when possible. Keep those evidence gaps distinct from missing
runtime, editor or code-generation functionality.
