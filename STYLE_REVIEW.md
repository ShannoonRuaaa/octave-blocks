# Documentation and style review

Review snapshot: 2026-11-10. This is a maintainability assessment of the current
worktree, not a claim that every implementation path has been audited for
correctness. Active changes and
line numbers may advance; function names below identify the review boundaries.

## Findings and recommended follow-ups

| Priority | Evidence | Why it matters | Bounded next change |
| --- | --- | --- | --- |
| High | [ob_emit_c_conditional.m:278](ob_emit_c_conditional.m#L278) (`emit_clocked_child`) and [line 445](ob_emit_c_conditional.m#L445) (`emit_clocked_root`) combine scheduler policy, C syntax, context layout, and API assembly. The file has 718 lines. | A reviewer must mentally execute both Octave generation logic and generated C while tracing lifecycle changes. Dense templates can conceal a misplaced mutation or inconsistent legacy/clocked behavior. | Extract emission by lifecycle boundary (clock masks/commits/captures, child lifecycle, root API, integration). Keep a typed/unit descriptor as the input; preserve exact generated-model/API regressions rather than rewriting the entire emitter at once. |
| Medium | Collision policy appears in `time_equal` in [private/ob_runtime_engine.m](private/ob_runtime_engine.m), [private/ob_clock_rebase.m:1](private/ob_clock_rebase.m#L1), [ob_c_schedule_lines.m:9](ob_c_schedule_lines.m#L9), and conditional C templates. | Clock tolerance has already needed large-origin and decimal-coincidence corrections. Repeating the policy across host/runtime/generated paths makes later drift easy. | Centralize policy constants/description and generate the C comparison from the same small policy helper where practical. Retain cross-implementation regression cases for ordinary offsets, decimal coincidence, large origins, and unrepresentable progress. |
| Medium | Guard descriptors are reconstructed by [private/ob_zc_snapshot.m](private/ob_zc_snapshot.m) and deeply compared during localization in [private/ob_integrate_events.m](private/ob_integrate_events.m). | After caching execution options, graph evaluation and guard comparisons remain measurable event-path costs. Layout can change when active children change or a function changes shape. | Profile a representative event workload before caching a fixed per-search inventory; preserve finite-value and layout/shape rejection plus newly active-child discovery. |
| Medium | [private/ob_flow_segment.m](private/ob_flow_segment.m) and the legacy path in [private/ob_runtime_integrate.m](private/ob_runtime_integrate.m) each pack nested states and propagate RK4/adaptive trajectories. | Event mode needs frozen regimes and local-time propagation; two implementations can drift as solver behavior evolves. Existing mode remains separate to preserve its verified generated-C behavior. | Extract common state packing and derivative traversal first, then consolidate propagation only with numerical/C comparisons and event regressions retained. Profile before optimizing canonical event-state reconstruction. |
| Medium | [Launch-Blocks.ps1](Launch-Blocks.ps1) and [Test-Codegen.ps1](Test-Codegen.ps1) duplicate Octave discovery/version sorting. | Fixes to discovery, installation layouts, or diagnostics can diverge between the editor launcher and C gate. | Extract a small shared resolver that accepts explicit `-OctaveHome`, returns paths, and keeps launch/test-specific behavior in the callers. Verify standard discovery and explicit-path use. |
| Medium | The nested `add_case` helper in [test_ob_codegen.m](test_ob_codegen.m) intentionally captures its registry/directory. An autonomous-model fixture initially reused its `source` name and accidentally shared that variable with the helper; the fixture now uses a distinct name. | Octave nested-function scope can turn a plausible local name into shared state and replace a model struct with a filename. | Keep parent fixture names distinct and consider extracting artifact preparation into a function that returns a registry entry. Preserve the existing model/API cases when moving it. |
| Low | Host Octave code and generated C use mixed quote/spacing styles, abbreviated emission-local names (`u`, `p`, `t`, `o`, `n`), and some multi-statement lines. Sixteen emitter lines exceed 160 columns; the maximum is 261. | Compact layout is useful for C templates but harder to scan when applied to host-language control flow. Large formatting-only diffs would also obscure active semantic work. | Expand newly touched host control flow and use named intermediate expressions for timing/ownership decisions. Keep template exceptions intentional; avoid a repository-wide formatting pass in the scheduler change. |

## Addressed during integration

The C interval-source argument formerly named `has_interval` encoded three
different timing sources. It is now an `ob_interval_kind` enum with
`OB_INTERVAL_ELAPSED`, `OB_INTERVAL_INHERITED`, and `OB_INTERVAL_PERIOD`.
Clocked-child timing uses an explicit switch in place of the nested ternary.
Separate inherited-union, configured-period, and ancestor-pause cases retain
the behavioral coverage. Scheduler extraction and centralized collision policy
remain follow-ups; this update does not treat every style finding as resolved.

Repeated conditional normalization/classification is now cached after validated
compilation. Input routing and loop membership are cached too. Dynamic data,
guard, derivative and output checks remain live; cache-free MAT resumes match
future contexts in regression coverage. Missing/unknown metadata falls back to
legacy evaluation, while same-version internal cache contents remain trusted.
Measured normalization calls fell 95–96% in enabled workloads; see
[RUNTIME_PERFORMANCE.md](RUNTIME_PERFORMANCE.md) for timing spread and limits.

Continuous-control dispatch now has explicit boundaries: gate-only lifecycle,
ordinary child clock execution, and outgoing-regime reconciliation. This keeps
zero-time control changes from committing clock state. The new helpers are
listed in [REVIEW_GUIDE.md](REVIEW_GUIDE.md); keep each boundary visible when
extracting or optimizing further.

## Existing strengths to preserve

- Public runtime wrappers are small; the engine and solver layers are separate
  from the editor. Value-context stepping makes rollback reviewable.
- Validation, model compilation, and public signal mapping are explicit. Legacy
  two-column edges and missing Function output metadata have defined behavior.
- C export validates/infer shapes before replacing a file; generated API tests
  check whole-context rollback and independent instances.
- Numerical comparisons retain sources and traces, and strict compiler warnings
  are part of the gate. Analytical cases complement C/Octave agreement.
- UI optimization now retains graphics for selection/drag instead of rebuilding
  the scene on each click. Its callback regression checks and local benchmark
  method are documented separately in [UI_PERFORMANCE.md](UI_PERFORMANCE.md).

## Documentation changes from this review

[REVIEW_GUIDE.md](REVIEW_GUIDE.md) provides setup commands, source entrypoints,
model/index conventions, execution invariants, and a review sequence. The main
README links it; timing documentation states the complete capped collision
rule and includes conditional Subsystems among eligible clock owners.

Feature claims remain separated from evidence. Consult
[ADVANCED_PLAN.md](ADVANCED_PLAN.md) for completed gate results and
[SIMULINK_REFERENCE.md](SIMULINK_REFERENCE.md) for MATLAB/Simulink/REA limits.
The C inner-clock extension has completed strict compilation, numeric, and API
checks, recorded in the milestone log. Additional model families and UI tests
must retain their own evidence rather than borrowing that narrower result.
