# Advanced functionality goal

Project goal: extend Octave Blocks toward full Simulink functionality, including
subsystems, variable-step solvers, and code generation. This goal supersedes
the first-release stopping point. A completed milestone does not mean full
Simulink compatibility.

Current status: paused at the user's request after the existing agents finished
their assignments. The advanced goal is incomplete.

## Optimization completion (2026-11-13)

The optimization audit is complete. The publication branch
`codex/optimized-release` is based on release `2ae43f3` and contains only the
audited improvements, tests, benchmarks and documentation. Separate experimental
C event-runtime changes remain on the local development branch.

The measured development version passed 21 Octave suites, 25 graph/edge/snapshot
BIST checks, 167 strict C99 cases and the expanded Qt editor gate. All 157
compiled numeric models matched Octave with worst scaled error 0; ten API
harnesses passed. The optimization-only publication branch subsequently passed
the same complete gate. See [OPTIMIZATION_AUDIT.md](OPTIMIZATION_AUDIT.md) for measured
results, reproduction instructions and limits. This task does not resume or
complete the advanced compatibility goal.

## Publication verification (2026-11-11)

The implemented feature set passed a fresh complete gate: eighteen Octave
suites, 167 strict C99 cases, all 157 numeric models with worst scaled error 0,
ten API harnesses, and Qt editor checks. Supplemental inventory/43 analytical
fixtures, two isolated C event-math harnesses and PowerShell parsing also passed.
Native selection, port clicks, dragging, Undo, settings and Run were checked.

The public project uses the MIT license. Local tool caches, generated GUI
exports and raw machine-specific REA bundles are excluded; a sanitized
[reference summary](REFERENCE_EVIDENCE.md) preserves their evidentiary limits.
See [VALIDATION.md](VALIDATION.md) for commands, feature coverage and artifacts.
This verification/publication task does not complete or resume the paused
advanced implementation goal. Event-enabled C integration remains unfinished.
## Pause checkpoint (2026-11-10)

The last complete application gate remains the eighteen Octave suites, 167
strict C99 compilation/API cases, 157 numeric compiled models with worst scaled
error 0, ten C API harnesses, and Qt editor checks recorded below. The new event
export groundwork has only the focused verification described here.

`ob_c_event_inventory.m` now assigns static guard and shared mode IDs across
typed units, preserving public and compiled paths and zero-based numeric
buffer offsets. `test_ob_c_event_inventory()` passed in installed Octave 11.3,
including an independent parent rerun. The inventory includes dormant bodies;
a future runtime must select active guards dynamically.

`test_ob_event_codegen_cases()` passed all analytical Octave assertions for
43 fixtures. Its two API entries are descriptive specifications, not compiled
C harnesses. Window fixtures bound `maxstep` to .1 because a coarse step can
skip two crossings whose interval endpoint signs match. Output grids remain
coarse where intended. No generated C event behavior has been verified.

Neither helper is wired into the production exporter or default full gate.
Continuous-control and zero-crossing C export remain explicitly rejected by
`ob_codegen`; the existing emitter/runtime were not changed for this handoff.

When resumed, continue event-enabled C export through the recursive typed
exporter. Thread frozen regime data through every shared RK4 stage and child
flow, implement active guard collection and accepted-event scheduling, preserve
clock ordering and transactional rollback, then connect the fixtures to strict
C compilation and complete API harnesses. Remove protective export rejections
only after the supported event behavior is implemented and verified. Adaptive
C solvers and the other compatibility gaps remain separate unfinished work.

### Additional agent handoff before pause

After a brief resumption, the user again requested pausing after the agents
finished. No production runtime or exporter changes were started.

`ob_emit_c_event_math.m` adds generated guard metadata, active-mask crossing
checks, and frozen-regime proposal helpers. Populated and empty inventories
passed focused Octave generation and GCC `-std=c99 -O2 -Wall -Wextra -Werror`
harnesses. Both executables also passed an independent parent rerun. Artifacts:
`<TEMP>/ob-event-math-b61cda833d3c48c19494a7eb56175bfc`.
This helper is not connected to the exporter.

`test_ob_event_codegen.m` and `Test-EventCodegen.ps1` now provide a separate
preparation/strict-compilation/full-channel-verification runner for the 43
fixtures and two provider/chatter API harnesses. Octave and PowerShell parsing
passed. All 43 analytical checks passed again before preparation reached the
expected protective export rejection. Synthetic CSV verifier checks accepted
matching data and rejected a mismatch. The event C models and API harnesses
have not been compiled or verified. The proposed event status/summary fields
remain an integration contract rather than an available generated API.

The read-only emitter audit identified required integration work: child flow
and shared RHS currently discard frames; pure feedthrough enabled bodies need
a flow path; frames need valid empty due masks when carrying only modes; and
continuous lifecycle acceptance must precede coincident child clock dispatch
without adding inherited captures. Preserve elapsed active time for inherited
Euler updates, plateau trigger arming, transactional contexts, finite guard
subtractions, canonical root trials, and boundary memory. Stateless models
still need event/source-boundary advancement. These changes remain pending.

## Milestones

- [x] Variable-step simulation: Octave ode45 and ode15s, configurable error
  tolerances and maximum step, matrix state handling, Step discontinuities,
  defined interaction with discrete blocks, GUI settings, saved options, tests.
- [x] Subsystems: explicit input/output ports, nested model validation and
  execution, stateful feedback across boundaries, visual navigation and editing,
  persistence, examples, tests.
- [x] Code generation: generate standalone C for a clearly documented supported
  block subset, reject unsupported models, compile and compare numerical output
  against Octave, expose export in the editor, document toolchain requirements.
- [x] External root inputs: feed controller/plant models from supplied signals
  in Octave and from host C code, with explicit shapes and interpolation/hold
  semantics; expose equivalent GUI data configuration and verify parity.
- [x] Multirate scheduling: independent block sample times, deterministic
  sample hits and rate transitions, mixed continuous/discrete execution, saved
  configuration, generated-code timing, examples and tests.
- [ ] Conditional subsystem execution: enabled/triggered execution, explicit
  state retention/reset and held outputs, hierarchy-aware simulation and C
  generation, editor configuration and behavioral comparisons.
  - [x] Extract resumable Octave execution contexts with independent state,
    hidden sample hits, checkpoints, and atomic failed steps.
  - [x] Sampled enabled/rising/falling/either execution with lazy child contexts,
    retained/reset state, held/reset output, matrices, nesting, clocks, and editor settings.
  - [x] Generate conditional child C contexts and verify compiled timing/rollback.
  - [x] Integrate active enabled continuous child states jointly with the parent
    in Octave, preserving sampled activation, reset/hold, and discrete hit history.
  - [x] Generate shared RK4 stages for continuous enabled C bodies and verify
    compiled coupling, nested timing, input events, and rollback.
  - [x] Schedule globally aligned independent inner rates in enabled Octave
    bodies, including hidden/skipped hits, nested clocks, and checkpoints.
  - [x] Generate globally phased enabled inner clocks in C and verify hidden
    events, pauses/resets, nested clocks, continuous coupling, and rollback.
  - [x] Locate explicitly declared continuous enable/trigger controls in Octave,
    preserving gate-only lifecycle, child clock phase and checkpoint histories.
  - [ ] Verify live Simulink traces and complete nested policy/event variants.
- [ ] Algebraic loops and event handling: identify dependency components,
  solve supported loop systems with convergence diagnostics, detect general
  zero crossings, and verify solver/event behavior against reference models.
  - [x] Solve smooth fixed-shape real-double feedback components, including
    matrix signals, virtual boundaries, continuous stages, and warm starts.
  - [x] Optional computed Switch/Saturation/Dead Zone guard localization under
    RK4/ode45/ode15s, with matrices, active enabled bodies and event histories.
  - [ ] General zero crossings, implicit DAE constraints, and broader loop blocks.
- [ ] Broader block and port coverage: general multi-output functions,
  common control/system blocks, signal routing, parameter tuning, and
  model-level debugging/diagnostics.
  - [x] Nonlinear control primitives: Saturation, Dead Zone, and threshold
    Switch, with matrix shapes, editor controls, and C export.
  - [x] General multiple-output Octave Function calls, numbered routing and
    hierarchy, editor/persistence, and size/max/min C output-pair signatures.
  - [x] Continuous state-space and proper SISO transfer-function builders using
    editable virtual diagrams, with MIMO/autonomous systems and C export.

## Variable-step milestone verification (2026-11-06)

`Launch-Blocks.ps1 -SelfTest` passes engine, persistence/editor-core, and adaptive
solver suites on GNU Octave 11.3.0 on Windows. Adaptive checks compare a
continuous oscillator against cos(t), stiff decay against exp(-1000*t), matrix
integration against its exact solution, aligned/unaligned Step jumps against
their exact integrals, and mixed Unit Delay/continuous integration against the
specified shared output schedule. Tests also reject invalid settings and
derivative shapes and verify new/legacy model-file behavior.

GUI verification: selected ode45 and a 0.5-second output interval in Settings,
undid and redid the settings change, then ran the oscillator and inspected its
Scope plot. Independent sample times were subsequently delivered below.
Remaining solver gaps include general reset/event variants, DAE constraints, and solver-state continuity across
output times (the current implementation restarts each output interval).

## Compatibility gaps to track

Broader multi-output primitive/C Function signatures; full sample-time propagation and target-specific rate transitions;
broader algebraic-loop coverage; reset/combined gate variants and generated event code; stiff
DAEs; subsystem variants and enable/trigger semantics; bus signals and data
types; model reference; Simulink file import/export; library coverage; debugging;
code generation for arbitrary Octave functions; deployment targets; Stateflow,
Simscape, and other product/toolbox integrations.

Use MATLAB behavioral comparisons and the official Reverse Engineer Anything
tools when they can resolve a specific compatibility question. Retain measured
evidence and distinguish static inspection from observed execution. The local
Simulink runtime is currently absent; MATLAB numeric comparisons remain available.

## Continuous controls and runtime optimization (2026-11-10)

Octave simulation now supports `execution.control='continuous'` for scalar
enabled/rising/falling/either controls, with `zero_crossings=true`. Control
timing remains sampled by default. Accepted gate transitions are separate from
child inherited captures. Triggered execution intentionally advances its body;
continuous enabled activation/suspension does not add a discrete sample.
Pure feedthrough enabled bodies refresh from parent solver stages as well as
shared continuous-state bodies. Active-state paths are rebuilt after events.

The integration/scheduler bridge now stops at primitive roots for models with
continuous controls. This fixes downstream enable changes driven by Switch.
Outgoing equality regimes can reconcile at the same physical time without
rebasing clocks, taking hits or committing pending state. At a coincident
descendant clock, accepted activation is reconciled before that clock dispatch;
tests retain child hits `.25,.5,.75` for a positive Switch pulse at equality,
with unchanged peer and inherited clocks. Continuous trigger plateau arming
does not depend on extra output requests. Numeric `initial_control=0` retains
the existing startup falling-edge convention; explicitly prearmed tests cover
startup suppression. See [CONTINUOUS_CONTROLS.md](CONTINUOUS_CONTROLS.md).

Validated runtime metadata caches routing, loop membership and conditional
options/classification. Dynamic input, guard, derivative and output checks stay
live. Cache-free MAT checkpoints reproduce complete future contexts; internal
input-table isolation and value/shape failures retain rollback. Same-version
metadata remains trusted implementation state, not a general corruption-repair
format. See [RUNTIME_PERFORMANCE.md](RUNTIME_PERFORMANCE.md).

Matched local medians changed from `2.938` to `.903` seconds for a sampled enabled
workload and `6.035` to `2.221` seconds for continuous enabled execution. The final
primitive-event rerun measured `.258` versus `.318` seconds; an earlier rerun
was slower, so timing spread and system load remain relevant. Analytical outputs
and step/event counts matched. The optimization reduces repeated normalization;
it does not establish a universal speed guarantee.

The native editor exposes control timing in Subsystem Edit. Changing to continuous
clears that Subsystem's explicit control rate. Native verification inspected
the field and ran the example: the state rises from 0 at .2 to .5 at .7, then
holds. The Qt callback suite also exercises this example.

Continuous-control and event-enabled C export are explicitly rejected before
file replacement. Generated event code, automatic sample-time propagation,
vector controls, combined/resettable variants, nested policy precedence and
general DAE constraints remain gaps. The broader goal remains active.

Final verification: `Launch-Blocks.ps1 -SelfTest` passed all eighteen Octave
suites, 167 strict C99 compilation/API cases, all ten API harnesses, and the
expanded Qt editor suite. All 157 compiled numeric models matched Octave with
worst scaled error 0 in the supported event-off C mode. The new suites verify
continuous-control timing and protected-file rejection independently; this is
not event-enabled C parity. The Qt Run callback produced the expected .5 final
state and public conditional event paths for the new example.

Retained full-gate artifacts:
`<TEMP>/octave-blocks-codegen-16fd2784d58842aaaffeff18368db24e`
and
`<TEMP>/octave-blocks-editor-7c8d5692addd4c83a23e4df6096f4d91`.
The runtime profiling reports are listed in
[RUNTIME_PERFORMANCE.md](RUNTIME_PERFORMANCE.md). Documentation links and
whitespace checks passed. Reference comparison uses official MathWorks
documentation and analytic traces; the installed environment still lacks a
live Simulink runtime.

## Computed zero crossings and reliable block selection (2026-11-09)

`options.zero_crossings = true` enables Switch/Saturation/Dead Zone guard
localization with RK4, ode45, and ode15s. Matrix channels, virtual hierarchy,
active enabled continuous bodies, known source boundaries and independent
sample clocks participate without creating extra discrete or conditional hits.
Incoming piecewise regimes remain frozen during trial integration; retained
event states are reconstructed at their physical timestamps before integration
resumes in the outgoing regimes. Native adaptive segments use local elapsed
time so short intervals at large absolute origins remain solvable.

Accepted events expose public block paths, channel, boundary and direction in
`runtime.events` and `result.events`. Per-context `event_memory` preserves
incoming regimes and reported guards across output/search boundaries, forks,
and MAT checkpoints. Regression-driven fixes cover zero plateaus, initial-zero
departures, returns to zero, decimal step tails, tiny intervals, large origins,
deep feedforward control cascades, and transactional failure. A plateau ending
at a requested stop can be reported on the next successful advance with that
stop's timestamp. See [ZERO_CROSSINGS.md](ZERO_CROSSINGS.md).

The setting is available in the native Settings dialog, defaults off, and is
saved with the model. Event-enabled C export is rejected before file replacement.
Continuous enable/trigger/reset events, broader guard registration, robust
multiple/tangential crossing detection and generated event code remain gaps.
The feature does not establish full Simulink event parity.

The reported unreliable block selection exposed dead areas at port markers
and numbers plus an edge-picking failure. All block graphics now carry explicit
ownership and one selection callback; wires cannot intercept clicks. A five-pixel
canvas fallback handles missed edges while skipping already-owned parts.
Expanded Qt checks cover each part and preserved retained handles. Native mouse
checks covered faces, labels, ports, numbers and edges, plus a traced drag and
Undo. The diagnostic [ob_trace_editor_clicks.m](ob_trace_editor_clicks.m) records
actual picked owners and model positions without replacing the original dispatch.
Existing editor processes retain old callbacks and need a fresh process after
saving work. See [UI_PERFORMANCE.md](UI_PERFORMANCE.md).

Final verification: `Launch-Blocks.ps1 -SelfTest` passed all sixteen Octave
suites, 167 strict C99 compilation/API cases, all ten API harnesses, and the
expanded Qt editor checks. The 157 compiled numeric models matched their
Octave references with worst scaled error 0; these use the existing event-off
C mode. The event suite also verifies protected-file rejection of event-enabled
export. Retained full-gate artifacts:
`<TEMP>/octave-blocks-codegen-89e97552a5cf4a7891acc5b901571277`
and
`<TEMP>/octave-blocks-editor-9310b33a166f46b39d0e94f5a6c2af24`.
The independently rerun expanded Qt gate also passed, with artifacts at
`<TEMP>/octave-blocks-editor-6a72dd371db647e19c3924aadfd7d943`.
Native pointer evidence retained in
`<TEMP>/octave-blocks-pointer-340abde4285f4671ab5b73ee3f5ed592.mat`
identifies owner 2 (Time), its actual down/up axes coordinates, movement of only
that block, and a completed drag state. Subsequent native Undo restored the
diagram and clean title. Official-reference comparisons and analytic numerical
cases support the event behavior; live Simulink remains unavailable locally.
The broader advanced goal remains active.

## Algebraic-loop simulation milestone (2026-11-08)

The runtime now orders strongly connected direct-feedthrough components and
solves supported smooth fixed-shape real-double feedback simultaneously with
Octave `fsolve`. Acyclic order remains unchanged. Numeric candidates use one
immutable signal snapshot; nonlinear iterations never dispatch lifecycle or
sample-state operations. Accepted solutions are per-context warm starts,
preserved by copies/checkpoints. Each continuous solver stage solves its own
constraint without committing trial guesses or trigger history.

Supported cyclic blocks are Gain, Sum, Product, single-output Function, Scope,
Inport, and Outport. Optional `block.algebraic_initial` sets initial values and
matrix shapes for each cyclic signal. Virtual boundaries flatten into the
system; loops inside conditional bodies run when those bodies execute.
Conditional-boundary, Rate Transition, nonsmooth control, and multiple-output
Function cycles remain unsupported. C export continues to reject algebraic
loops, matching the documented MathWorks restriction.

Independent review reproduced false acceptance of an inconsistent equation
with a large guess under a relative-only residual test. The integrated solver
requires positive solver status, absolute maximum residual at most `1e-9`,
finite fixed-shape values, and a nonsingular finite-difference Jacobian.
Singular initial/intermediate/final candidates fail with block-path/time
diagnostics. This numerical guard does not guarantee convergence or uniqueness;
general DAE support, zero crossings, sparse Jacobians, and large-loop
optimization remain gaps. See [ALGEBRAIC.md](ALGEBRAIC.md).

The final `Launch-Blocks.ps1 -SelfTest` passed fifteen Octave suites, 167 strict
C99 compilation/API cases, all ten API harnesses, and Qt editor checks.
All 157 compiled numeric models matched Octave with worst scaled error 0.
Seven focused ordering tests also passed, including a 1,000-node component.
Algebraic regressions cover noncontractive/nonlinear/matrix equations, root
guesses, hierarchy, all three solvers, Step/ZOH discontinuities, hidden clocks,
conditional execution histories, persistence, singularity and failed-step
rollback. The Qt Run callback solved `ob_algebraic_example` and plotted both
Scope outputs while preserving diagram handles and optional metadata.

Retained full-gate artifacts:
`<TEMP>/octave-blocks-codegen-6f4f57b49027490596a7cf54723417da`
and
`<TEMP>/octave-blocks-editor-af6ccd46a78746d0a7c6345a6f4242e6`.
Reference checks used official MathWorks/Octave documentation and analytic
solutions; live Simulink remains unavailable locally. The broader goal stays
active after this milestone.

## Integrated C clocks, linear systems, and editor performance (2026-11-08)

Generated C now owns an explicit root clock inventory across enabled descendants.
Lazy initialization and reset do not reset global phase. Transient clock frames
dispatch major control samples and descendant hits separately, skip inactive
events, and never retain pointers inside a model context. Global ticks and
all nested pending/held state remain transactional. The public API stays stable;
exports add clock metadata and root-owned clock counters for inspection.

Native verification used the updated retained-graphics editor to export
`gui-enabled-inner-clocks-export.c`. That exact source compiled with strict
warnings and matched all 101 default samples and six numeric channels of the
Octave model with worst scaled error 0.

New regressions caught two nested inherited-clock timing errors: nonmajor
ancestor events must not pass a zero inherited interval to a derived child
sample, and a coincident slow ancestor hit must not over-advance a faster
inherited child Euler. Inherited active intervals are now bounded by the
child's elapsed time; explicit configured periods retain their fixed step.
The C emitter expresses these choices with named `ob_interval_kind` constants.
An additional nested-pause regression exposed inherited Euler counting a
disabled ancestor gap. Disabling now freezes each active enabled descendant's
pending interval metadata at that boundary, in Octave and C, without sampling
state or resetting clocks. The resumed inherited Euler matches the explicit
clocked integrators in that trace.

Twenty-eight C inner-clock fixtures cover explicit/inherited controls, offsets,
nonzero/large origins, matrices, pause/reset, nested/virtual contexts, inherited
and explicit Euler, Rate Transition, inactive domain checks, and coupled
continuous dynamics. An additional API harness verifies whole-context rollback
after several successful hidden hits, retry, independent instances, inactive
pause/resume, and output reads without advancing clocks.

`ob_state_space` and `ob_transfer_function` build continuous linear systems from
existing virtual blocks. Their original diagrams support MIMO state-space,
autonomous sources, zero-state feedthrough, proper SISO transfer functions,
nonzero realization state, and zero numerators. Zero D branches are omitted
to preserve state-breaking feedback. Analytical checks cover all three solvers,
and compiled fixtures exercise the supported static-double RK4 subset.
These builders are not a claim of full native Simulink block/file parity.
See [LINEAR_SYSTEMS.md](LINEAR_SYSTEMS.md).

UI investigation measured a complete diagram rebuild twice per ordinary click.
The editor now retains graphics during selection/drag, updates only the moved
block and incident wires, and skips unchanged mouse-up repaints. The 40-block
callback benchmark improved from 2.137 s/click to 0.102–0.112 s/click; an
independent fresh-process run measured 0.085 s/click. Qt regression checks
preserve port routing, loopback wires, Undo/Redo, cache invalidation, and
navigation. Model files/history exclude graphics handles. Initial scene
construction and structural edits still rebuild; simulation Run remains
synchronous. See [UI_PERFORMANCE.md](UI_PERFORMANCE.md).

The final `Launch-Blocks.ps1 -SelfTest` passed fourteen Octave suites, 167
strict C99 compilation/API cases, and the Qt retained-graphics regression suite.
Every numeric channel of 157 compiled models matched Octave with worst scaled
error 0, and ten C API harnesses passed. This includes the deeper nested-pause
correction and autonomous linear systems. Generated sources/traces and Qt logs
are retained in the gate's reported temporary artifact directories.

[REVIEW_GUIDE.md](REVIEW_GUIDE.md) maps execution entrypoints, schema/index
conventions, setup commands, and review invariants. [STYLE_REVIEW.md](STYLE_REVIEW.md)
records concrete maintainability findings and the resolved interval-flag issue.
Full sample-time propagation, nested policy parity, general events/algebraic
loops, broader linear/block types, and live Simulink comparisons remain open.
The full goal remains active.

## Enabled inner-clock scheduling (2026-11-08)

Enabled Octave bodies now support independent clocks for Unit Delay, Euler,
Rate Transition, and nested conditional controls. A root-owned inventory is
compiled without evaluating lazy children. It schedules hidden hits through
sparse output requests and advances phase through disabled intervals, while
inactive children skip execution. Child contexts rebase to the next root-origin
hit on activation/resume. Resetting state does not shift clock phase.

Explicit outer clocks sample the control; active inner clocks can dispatch
between those samples. Inherited enabled controls additionally sample at the
union of their inner hits. Independent Euler clocks use their configured
period; independently clocked nested enabled wrappers supply their own period
to inherited Euler rather than a faster ancestor's interval. Major-hit buffers
remain separate from continuous/output flow snapshots. Continuous parent and
child states share the root solver between discrete hits.

Review reproduced a valid-clock failure at simulation origin 1e16: an absolute
time-scaled comparison merged distinct hits and could skip an entire period.
Clock comparison now caps its floating-point tolerance by the shortest
configured period while preserving decimal-hit coincidence. The Octave scheduler and both C
emitters were corrected. Regressions exercise an 8-second period and 2-second
offset at that origin, including C exports of root and conditional clocks.

`test_ob_enabled_multirate` passes under RK4, ode45, and ode15s. Checks cover
global phase, offsets, decimal periods, nonzero/large origins, matrices,
explicit and derived control hits, hidden Rate Transition/Delay/Euler updates,
pause/resume, resets, nested enabled/virtual contexts, mixed continuous states,
lazy inactive functions, checkpoint forks, and rollback of hidden-hit failures.
The final `Launch-Blocks.ps1 -SelfTest` passed all thirteen Octave suites and
128 strict C99 compilation/API cases. Every numeric channel of 119 supported
compiled models matched Octave with worst scaled error 0; nine C API harnesses
also passed. The C checks include large-origin and decimal-coincidence clock
regressions in both emitters, while enabled inner-clock C export remains open.
The example follows the documented MathWorks discrete timing case: inner
periods .125/.25, enabled on [.375,.875), with the slower block executing at
.5 and .75. This is analytical/documentation evidence, not a live Simulink run.
See [CONDITIONAL.md](CONDITIONAL.md) for the example and reference link.

Native editor verification opened `ob_enabled_multirate_example`, clicked Run,
and inspected both Scope traces reaching .375 and .25 before holding through
t=10. Navigation into the enabled body also displayed its two separately
configured Euler blocks. Runtime rates and saved model schema use the existing
Sample time controls.

C generation of these clocks was subsequently delivered above. Full sample-time propagation to algebraic
blocks/Outports, nested policy parity, general events, combined variants, and
live Simulink execution comparisons remain open. The full goal stays active.

## Continuous enabled C generation (2026-11-08)

The typed C exporter now integrates root and active nested continuous states in
one RK4 solve. Each stage evaluates child graphs with current parent stage
inputs, rather than separately advancing a child with stale inputs. Activation
and reset decisions remain sampled major-hit operations. Inactive ancestors
produce zero child derivatives. Endpoint flow snapshots preserve the output
immediately before disabling; independent major-hit buffers preserve inherited
Unit Delay/Euler input timing through minor stages.

Generated contexts retain static real-double shapes and allocation-free typed
children. Stage and transactional context copies include every child state,
held output, major-hit buffer, and gate history. The public root API remains
unchanged. Typed export metadata adds the total continuous component count;
the existing root numeric state count retains its meaning.

The final `Launch-Blocks.ps1 -SelfTest` passed all twelve Octave suites and
124 compilation/API cases with strict C99 warnings as errors.
All numeric channels of 115 compiled models matched Octave with worst scaled
error 0. New cases cover all enabled state/output policies, explicit offsets
and inherited control hits, matrices, a coupled root/child oscillator, nested
ancestor pauses/resets, buried Step boundaries, an empty active state vector,
mixed inherited Delay/Euler, and inactive domain errors. Nine API harnesses
include the new continuous-child checks for independent instances, whole-tree
rollback on provider/domain/nonfinite errors, successful retry, unchanged
output reads, and a host-supplied discontinuity with its event callback.

Native editor Export C saved `gui-continuous-enabled-export.c`. That exact
source compiled warning-clean and matched all 101 default samples and four
numeric channels of the Octave example, with worst scaled error 0.

Independent inner clocks were subsequently added in Octave simulation; their
C export, general enable zero crossings, nested state-policy
parity, combined execution modes, adaptive C emission, and live Simulink
comparison remain open. The broader goal remains active.

## Continuous enabled simulation verification (2026-11-08)

Active enabled bodies can now contain continuous Integrator states, including
matrix states and nested enabled/virtual children. A recursively packed state
vector places every active child in the same RK4, ode45, or ode15s solve as its
parent. Child flow graphs receive the current parent stage inputs. Activation,
reset policies, trigger histories, and inherited discrete updates remain major-hit
operations; continuous stage evaluations do not execute those operations.
Disabled child states freeze, and their output policies use the endpoint
snapshot immediately before disabling. This also works when all continuous
descendants are inactive and the enclosing body's output is direct feedthrough.

Review found and fixed minor-stage snapshots replacing the inputs needed by
inherited Unit Delay and Euler updates. Continuous children now retain a
separate major-hit input snapshot for those discrete captures. This avoids
advancing a Delay from the current endpoint or using right-endpoint Euler
quadrature. Existing discrete-only contexts retain their prior execution path.

`test_ob_enabled_continuous` passes with all three solvers. Its independent
analytical checks include a coupled parent/child oscillator, pause/resume and
both reset policies, sampled gating between output requests, matrix states,
nested ancestor pauses, inactive invalid functions, nested Step boundaries,
mixed inherited Delay/Euler timing, checkpoint copies, and rollback after
domain/derivative failures. Triggered continuous-child C exports remain invalid
and preserve existing destination files.

The final `Launch-Blocks.ps1 -SelfTest` passed all twelve Octave suites and
107 C compilation/API cases with strict C99 warnings as errors. All numeric
channels of the 99 supported compiled models matched Octave with worst scaled
error 0, and eight C API harnesses passed. These C checks cover the existing
supported subset; they do not claim continuous enabled-body C support.

Native editor verification opened `ob_enabled_continuous_example`, clicked Run,
and inspected its Scope: the ramp reached 1 at t=1, paused until t=2, rose to 2
at t=3, then held through t=10. The existing editor controls required no new
configuration schema. See [CONDITIONAL.md](CONDITIONAL.md) for the example.

The continuous behavior is implemented with sampled enable decisions. General
enable zero crossings,
nested policy parity, and live Simulink comparison remain compatibility work.
The installed MATLAB runtime supplies numeric reference checks; its absent
Simulink engine still prevents a live subsystem trace comparison. This is
progress within the conditional milestone; the full goal remains active.

## Multiple Function output milestone verification (2026-11-07)

Function blocks now call ordinary Octave functions with a saved, explicit
output count. Each evaluation obtains all declared returns in one call;
numbered ports route different shapes through root, virtual, and conditional
models. The editor configures counts, removes only deleted-port wires when a
count shrinks, and restores them with Undo. Legacy models retain one output
without repurposing their existing value field. Failed runtime steps preserve
their previous state, including multiple-output buffers.

The typed C exporter supports exactly two outputs from one-input builtin
size/max/min calls, including default reduction dimensions, first-occurrence
one-based indices, and signed-zero ties. Arbitrary Octave functions continue
to run in simulation; unsupported export signatures and shadowed functions
fail before replacing the destination file. See [MULTIOUTPUT.md](MULTIOUTPUT.md).

The complete `Launch-Blocks.ps1 -SelfTest` gate passed all eleven Octave suites
and 107 strict C99 compilation/API cases. Every numeric channel of 99 compiled
models matched Octave with worst scaled error 0; eight C API harnesses also
passed. Tests cover different return shapes, multiple arguments, branching,
reordered ports, nested execution, checkpoints, rollback, invalid counts,
and export rejection without file replacement.

MATLAB R2026b Update 1 produced 15 additional native two-output cases for
size/max/min. Their dimensions, values, indices, and zero-sign flags match
Octave Blocks alongside the earlier 26 single-output cases. These measured
cases do not establish full MATLAB or Simulink compatibility.

Native editor verification ran the matrix max example and observed values
[3 8 -1] and indices [1 1 1]. Editing two outputs to one removed the second
wire; Undo restored the ports and wires. Adding a Gain and undoing it checked
mixed legacy/new block schemas. The exact GUI-exported source compiled with
warnings as errors and matched all 101 samples and 18 numeric flat channels
with zero observed error. The overall advanced goal remains active.

## External-input milestone verification (2026-11-06)

Root Inports now consume validated, saved scalar/matrix sampled datasets with
explicit component shapes, ZOH or linear interpolation, endpoint holds, and
left-limit integration at jumps. The editor has Inputs configuration and Input
demo controls. Compiled C includes the same default tables and provides
instance-specific host input callbacks and discontinuity-event callbacks.

`test_ob_inputs` verifies exact held/linear integrals with all three solvers,
matrix and nested routing, port order, discrete timing, invalid datasets,
partial diagrams, and model-file persistence. Compiled comparisons and API
harnesses verify default/host inputs, port packing, callbacks, and rollback.
GUI verification changed the demo pulse from `[0;1;0]` to `[0;2;0]` and observed
its integrated plateau change to 1. See [INPUTS.md](INPUTS.md) and
[CODEGEN.md](CODEGEN.md).

## Multirate milestone verification (2026-11-06)

Discrete blocks now have independent periodic clocks, optional offsets, pending
simultaneous state commits, and single-thread sampled hold rate transitions.
Nested diagrams retain their schedules. The engine integrates through hidden
hits independently of output queries, and compiled C preserves the same clocks
and pending updates per instance.

All six Octave suites passed through `Launch-Blocks.ps1 -SelfTest`. Its 40 C
compilation/API cases passed with warnings treated as errors; every channel
from 35 compiled models matched its Octave reference (worst scaled error 0 on
the verified Windows/GCC toolchain). Tests cover collisions, offsets, negative
origins, tiny offsets, legacy clocks, matrices, nested clocks, continuous held
integrals, host callback rollback, and adjacent input knots that must not
prematurely trigger a nearby sample hit.

GUI verification loaded Rate demo, observed the integral reach 0.375 at one
second, changed the transition period from 0.25 to 0.5 using Sample time,
observed the result reach 0.25, then undid the edit and observed 0.375 again.
The supported semantics and epsilon-relative event rule are in
[MULTIRATE.md](MULTIRATE.md). This is the numerical sample/hold subset of rate
crossings; asynchronous tasks, target-specific buffering, full sample-time
propagation, and additional Simulink Rate Transition policies remain gaps.

## Nonlinear control increment (2026-11-06)

Saturation, Dead Zone, and threshold Switch now execute on scalar/matrix
signals in Octave and generated C. The editor exposes all three, numeric
parameter validation, explicit Switch ports, and a Control demo. Saturation
and Dead Zone use ordered finite scalar bounds; Switch implements the
`u2 >= threshold` criterion, equal-shaped data inputs, and scalar or per-element
control. Both data branches remain active graph dependencies.

The new `test_ob_controls` suite checks analytical boundary values, equal
limits, threshold equality, port ordering, matrix feedback with all three
solvers, nested external input and multirate integration, finite/shape errors,
and direct dependency loops. C verification includes the same scalar/matrix
operations, feedback, and a signed-zero regression whose downstream `atan2`
would expose a changed sign.

`Launch-Blocks.ps1 -SelfTest` passed all seven Octave suites and all 56 C
compilation/API cases on the verified Windows/Octave/GCC toolchain. Every
channel from 50 compiled models matched its Octave reference (worst scaled
error 0). A dedicated Dead Zone overflow API harness also verified that failed
initialization and stepping preserve the existing context. Model-file tests
round-tripped all three new block types and retained integer parameter types.

GUI verification loaded Control demo and inspected both output curves. Editing
the Switch threshold from 2 to 3 moved the observed transition from two seconds
to three; Undo restored the transition to two seconds. A touching pair of demo
blocks was spaced apart after visual inspection.

See [CONTROLS.md](CONTROLS.md) for equations and the public MathWorks references.
These checks use analytical expected values and Octave/C comparisons, not a
running Simulink reference. General zero-crossing detection, other Switch
criteria, data-branch scalar expansion, dynamic limits, saturation status
ports, and Boolean/fixed-point semantics remain gaps. This increment does not
complete broader block/port coverage or the overall compatibility goal.

## Resumable engine foundation (2026-11-06)

The Octave scheduler now exposes `ob_runtime_init`, `ob_runtime_step`, and
`ob_runtime_outputs`. `ob_run` collects its samples through the same contexts.
Copies own their states, pending captures, input tables, clock origins/counters,
and cached outputs. MAT checkpoints preserve execution across a restart.
Failed stepping leaves the prior context unchanged, including after multiple
hidden clock hits or an accepted integration segment. Nested and numbered-port
output reads use the existing compiled signal map.

The new `test_ob_runtime` checks every supported solver across streamed runs,
independent branches, checkpoint roundtrips, nested multi-output reads,
invalid times/contexts/paths, empty diagrams, and failure/retry behavior.
It also exposed a preexisting adaptive endpoint issue: Octave ode45 can return
one ulp beyond a requested boundary. Endpoint validation now permits a bounded
rounding difference only after forward progress, and derivative stages at or
past the boundary use its left-limit input. A jump from 0.2 to 1e8 at the
endpoint is tested against its analytical integral with all three solvers.

The full launcher verification passed all eight Octave suites and all 56 C
compilation/API cases. All channels of 50 compiled models matched Octave
(worst scaled error 0 on the verified Windows toolchain).

This foundation is now used by the sampled conditional implementation below.
The broader conditional milestone remains unchecked. See [RUNTIME.md](RUNTIME.md).

## Conditional Octave execution increment (2026-11-06)

Subsystem execution settings now support sampled enabled, rising, falling,
and either modes. Each conditional instance initializes lazily, owns its child
state and trigger history, exposes numeric output proxies, and retains held
output buffers. Enabled state/output reset policies are independent. Parent
sample clocks can execute children between output requests; continuous parent
solvers read their held buffers during intermediate stages. Recursive contexts
preserve nested execution, matrix/multiple ports, internal stateful feedback,
and checkpoint/rollback behavior.

The editor configures these modes through selected-Subsystem Edit, displays
the last control pin, and supports conditional sample times. Converting back
to virtual removes the control wire and rate through an undoable edit. Scopes
inside atomic children use snapshots; samples before first execution become
gaps, and never-executed scopes are skipped in the GUI.

`test_ob_conditional` passed its analytical traces, zero-plateau rules,
hold/reset combinations, all parent solvers, hidden hits/offsets, nested
execution, matrix/multiple outputs, inactive invalid functions, stateful
feedback, variable-interval Euler behavior, model/runtime roundtrips, and
transactional error checks. The full launcher passed all nine Octave suites
and the existing 56 C compilation/API cases; all 50 compiled models still
matched Octave with worst scaled error 0 on the verified toolchain.

GUI verification used the conditional example with one-second samples. The
held-state output at re-enable (t=5) was 2; changing the Subsystem's state policy
to reset made it 0, and Undo restored 2 on the next run. The six-field settings
dialog, mode/control-pin label, and ordinary run flow were visually inspected.

MATLAB R2026b Update 1 was launched to attempt a Simulink comparison. The
recorded [probe](matlab-environment.json) confirms MATLAB runs but Simulink is
not installed and `load_system` is missing, despite a positive license test.
The reproducible [comparison harness](reference_ob_conditional.m) is retained;
no live Simulink trace agreement is claimed. REA 6.8.0 inspected the local
support directory, retaining [237 observed entries and its limitations](REFERENCE_EVIDENCE.md#rea-installation-inspection).
That installation scan does not establish runtime behavior.

Conditional C generation was added in the following increment. Continuous enabled
simulation and its C export were subsequently added, followed by independent
inner clocks in Octave. Their C export,
combined enable-and-trigger modes, general zero crossings, and data feedback
across atomic boundaries remain required compatibility work. See
[CONDITIONAL.md](CONDITIONAL.md).

## Conditional C generation and timing correction (2026-11-07)

Conditional exports now generate typed recursive child contexts with separate
private symbol namespaces. Children initialize only on execution and receive
packed current inputs directly, without storing pointers into parent or stack
memory. Root transactional copies include every child state, trigger history,
and held buffer. Output reads and RK4 stages do not execute children. Public
`ob_model_*` APIs and root input callbacks remain available. Static inference
checks data/control and initial-output shapes before replacing a source file.
Atomic cores have zero numeric channels; output proxies expose their held data.

Review found and fixed nested enabled Euler advancing through a disabled
ancestor. Inherited execution intervals now propagate to enabled descendants;
triggered Euler retains actual elapsed time. Fixed and irregular interval
regressions verify the distinction. Virtual interface edits also normalize
unused conditional metadata, and inactive-child output queries now validate
paths/ports before reporting that a child has not executed.

The final `Launch-Blocks.ps1 -SelfTest` passed all ten Octave suites and all
80 C compilation/API cases using strict C99 warnings as errors. Every numeric
channel of 72 compiled models matched Octave (worst scaled error 0). Eight C
API harnesses include nested host-input/domain failure rollback, successful
retry, independent instances, and an irregular enabled Euler pause. Conditional
fixtures cover all mode/policy combinations, zero plateaus, offsets, matrix
and multiple ports, nested triggers, inherited Rate Transition, matrix
Gain/Product, broadcasting, empty children, and continuous parent integration.

Native GUI verification clicked Export C on the conditional example. The exact
saved source compiled warning-clean and all 101 samples/four numeric channels
matched its Octave model with zero observed error.

The MATLAB numeric reference was produced by MATLAB R2026b Update 1: 26 native
builtin cases plus signed-zero atan2 and rounding ties. Its Octave comparison
suite passes independently of MATLAB being installed during routine tests.
Live Simulink execution comparison remains pending because its local engine
is absent. The comparison harness explicitly chooses a discrete clock and zero
initial trigger state; the separate first-evaluation compatibility policy is
still a gap. The overall conditional milestone and full compatibility goal
remain active, including inner rates, combined
variants, general events, and boundary feedthrough analysis.

## Code generation milestone verification (2026-11-06)

`ob_codegen` exports a self-contained C99 model with independent per-instance
state, static matrix dimensions, RK4/Step boundary behavior, simultaneous
discrete updates, flattened hierarchy and numbered-port metadata. Selected
actual builtin Function implementations map to C math/operators; arbitrary or
shadowed Octave functions are rejected. Unsupported models fail before file
replacement. C initialization/stepping commit only on successful finite output.

The initial `Test-Codegen.ps1` verification prepared 16 compilation cases:
14 executable models plus two
API harnesses. All compile using GCC with `-std=c99 -O2 -Wall -Wextra -Werror`.
Every signal channel is compared with its Octave reference. The verified cases
include scalar gains, nested continuous/discrete feedback, aligned/unaligned
Step transitions, mixed states, matrix integration/Euler/gains/products,
broadcasting, all supported math mappings, Function-driven dynamics, and
multiple subsystem ports. API harnesses verify independent contexts, invalid
times, domain failure, and preservation of state after an error. Rejection
checks include arbitrary/shadowed functions, adaptive solver selection, invalid
dimensions/types, mismatched state shapes, and algebraic loops.

GUI verification: Export C was used to write a model into a separately selected
folder; its success message and destination were inspected. That exact source
compiled and its 101 output samples matched the configured Time → Gain → Scope
model. The callable API and CSV runner are documented in [CODEGEN.md](CODEGEN.md).

This completes the initial C generation milestone, not full Simulink parity.
Current C limits include real full double arrays, static dimensions, the RK4
solver, selected builtin functions, compiled-constant parameters, an `ob_`
symbol namespace. Independent numerical clocks and root input APIs were added
in the milestones above. Arbitrary Octave translation, adaptive solver emission, configurable namespacing,
deployment targets, and model/toolbox compatibility remain required extensions.

## Subsystem milestone verification (2026-11-06)

Virtual subsystems now compile recursively to one execution graph before the
existing dependency sort and solver run. Edges support explicit source and
target ports, while legacy two-column edges keep their input order. Numbered
Inport/Outport blocks expose subsystem interfaces; boundaries may have multiple
inputs/outputs. The editor can add, enter, modify, and leave nested diagrams.

`test_ob_subsystems` covers continuous feedback through boundaries with all
three solvers, discrete feedback, deeper nesting, noncommutative port routing,
multiple outputs, branches to distinct ports on the same block, stable port
identities after disconnect, algebraic loops, invalid interfaces/connections,
nonmutating nested edits, and hierarchical file roundtrips.

GUI verification: loaded Nested demo, entered its first subsystem, edited the
inner Integrator initial condition from 1 to 2, ran from inside the subsystem,
and observed the root Scope oscillate with amplitude 2. Up returned to the
parent; Undo restored amplitude 1 on the next run. Port labels, path status,
and the new navigation controls were visually inspected.

These are virtual subsystem semantics: states use the root solver. Independent
inner-block rates and external root signals were added in the milestones above.
Sampled conditional execution and general multi-output Function calls were
subsequently added. Continuous enabled simulation was also added later.
Continuous enabled C export was subsequently added. Broader atomic variants and
hierarchy-wide structural editing tools remain gaps. Nesting is
bounded to 32 levels.

Each milestone must record its tested scope and remaining gaps. The original
REA installation scan does not establish implementation details; behavior must
be grounded in documented interfaces and reproducible numerical checks.
