# Optimization report audit — 2026-11-13

Status: saved and paused at the user's request. The source changes and focused
regressions are complete; full application verification and matched after-change
measurements are pending. No speedup is claimed yet. Nothing from this audit
has been pushed to GitHub.

The input was `octave_blocks_optimization_report.md`, supplied from Downloads.
Its proposed installer and nineteen replacement files were not supplied or run.
The changes here were implemented independently against local checkpoint
`8aeec48`, preserving the unfinished experimental C work and public export guard.

## Findings

| Report claim | Assessment and action |
| --- | --- |
| Repeated graph scans, execution-option normalization and derivative edge searches | Confirmed. Added optional category indexes, reused source/conditional descriptors, hoisted immutable derivative routing outside solver stages, and removed duplicate initialization normalization. |
| Repeated state-vector growth | Confirmed. Packing now collects/preallocates components rather than repeatedly extending vectors. Dynamic derivative/value/shape checks remain live. |
| Guard-descriptor construction and interpreted shape/count loops | Confirmed. Added scalar/vectorized descriptor construction and builtin cell operations, preserving matrix order, empty shapes and the exact N-D fallback. |
| Quadratic matching in reconciliation memory and boundary departures | Confirmed. Matching layouts take a linear correspondence path; changing layouts keep descriptor matching. This does not make every event operation constant-time or linear. |
| Scheduler/output/conditional helper repetition | Confirmed. Added guarded direct output-map routes, cached options/port counts, one-per-advance clock spacing and reduced redundant refresh/clock discovery. Public validation and internal finite/shape checks remain. |
| Quadratic queue shifts and repeated edge scans in graph ordering | Confirmed. Traversal now uses indexed queues, adjacency and bounded DFS storage, preserving historical ordering. Canonical edge sorting, DAG uniqueness and component ordering still have sorting costs; the whole operation is not guaranteed O(V+E). |
| Linear input-table searches | Confirmed. Large tables use builtin lookup. The suggested unconditional ZOH final-endpoint shortcut was unsafe: exact-final-knot left-limit queries must return the previous sample. That behavior is retained. |
| Algebraic error-label formatting on every nonlinear iteration | Overstated. Labels were constructed once per solve invocation, not each fsolve iteration. Formatting is now deferred to failure paths; initial-vector allocation and source lookups were also improved. |
| Three repeated model comparisons during ordinary selection, plus full-edge drag scans | Confirmed. Pure selection skips content installation/history comparison. Drawing reuses dirty/scene classification only after a coherency comparison including current and saved snapshots, so external changes remain visible. Cached incident-wire adjacency replaces full-edge membership scans. Position/graphics checks remain; the whole drag is not O(degree). |
| The proposed replacements preserve all contracts and improve performance | Not established by the supplied report, which explicitly says Octave execution/timing was unavailable. Focused checks below support the independent changes; the complete gate and matched timing comparison remain required. |

Twenty implementation files changed, including an additional cache-descriptor
compatibility helper. New category fields remain optional in v1 metadata.
Category-less old v1 contexts, absent/unknown metadata and malformed optional
categories retain fallback behavior. Initialization rebuilds metadata; callers
still reinitialize after model edits. No public context-mutation API was added.

## Completed verification

- Existing runtime, runtime-metadata, adaptive-solver, external-input,
  algebraic-loop and zero-crossing suites passed.
- `test_ob_performance_graph`: 480 randomized graph/reference comparisons,
  exact historical ordering/errors, long-table and left/right input boundaries.
  Graph BIST passed 7/7; compiler outputs/maps/paths matched seven baseline
  hierarchy fixtures.
- `test_ob_performance_metadata`: optional/old/missing/unknown metadata replay,
  invalid-category/descriptor fallbacks, matrix state packing and failure rollback.
- `test_ob_performance_events`: cached/legacy snapshot equality, descriptor order,
  nested clock/output routes, finite/shape rejection and legacy replay.
  Snapshot BIST passed 12/12.
- Expanded `Test-Editor.ps1` passed. It checks existing selection/drag/Undo/Run
  behavior plus external model/settings/saved-state invalidation, dirty markers,
  deleted graphics and unchanged nonincident wires during branch-consumer drag.
- Whitespace checks passed before checkpointing.

These are focused checks, not a new complete application-gate result. The three
new regression suites are not yet registered in `Launch-Blocks.ps1`.

## Baseline evidence saved

Local artifacts are under `.validation-artifacts/performance-audit-20261113/`:

- `baseline.zip` and `baseline/`: exact pre-audit source from commit `8aeec48`.
- `benchmark_audit_snapshot.m`: runtime, graph and input benchmark driver.
- `baseline-runtime.json`: one warm-up and three timed runs with analytical
  checks; runtime step/event counts retained.
- `baseline-ui.json` and `baseline-ui.log`: Qt selection callback timings with
  a warm-up and three measurements per diagram size.

Preliminary runtime medians were 1.458 s sampled enabled, 3.424 s continuous
enabled, and .373 s primitive event. Outputs were 2, 2, and 1.25; step counts
72, 102, and 2; event counts 0, 0, and 1. Preliminary Qt medians were .0452
s/click for ten blocks and .1445 s/click for forty blocks. These baseline-only
numbers are not improvements. Timing spread/load requires a fresh serial paired
comparison before interpreting an after-change result.

The expanded Qt regression log was retained at
`<TEMP>/octave-blocks-editor-cd6f44ec8ac444eb97aaf519c00e4b0b/editor.log`.
Artifact directories are ignored by Git and are not part of the public package.

## Resume work

1. Register/run the three performance regressions, graph/snapshot BIST and the
   complete `Launch-Blocks.ps1 -SelfTest` gate, including strict compiled C parity
   and Qt checks. Preserve the experimental event-export protection.
2. Run fresh baseline and optimized benchmarks serially in separate processes,
   with identical models/queries, warm-up and repetitions. Compare values,
   integration steps and events as well as timings. Investigate regressions
   rather than asserting that every micro-optimization is faster.
3. Profile remaining costs if necessary, then update the runtime/UI performance
   documents with measured evidence and this report's corrected qualifications.
4. Review the complete diff before publishing. The advanced compatibility goal
   and full experimental C event parity remain separate unfinished work.
