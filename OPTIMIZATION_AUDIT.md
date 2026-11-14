# Optimization report audit — 2026-11-13

Status: optimization implementation, full regression verification and measured
comparison are complete. The publication branch is `codex/optimized-release`,
based on published release `2ae43f3`. It contains the optimization changes without
the separate experimental C event runtime from the local development branch.

The input was `octave_blocks_optimization_report.md`, supplied from Downloads.
Its proposed installer and nineteen replacement files were not supplied or run.
The changes here were implemented independently against local checkpoint
`8aeec48`, then isolated onto the published release. All optimized production
files match the measured development version. The public export guard remains.

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
| The proposed replacements preserve all contracts and improve performance | Not established by the supplied report, which explicitly says Octave execution/timing was unavailable. The independent implementation here passed the complete gate and the measured comparisons below. This supports the tested cases, not every possible model or a universal speed guarantee. |

Twenty-one implementation files changed, including an additional cache-descriptor
compatibility helper and legacy edge expansion. New category fields remain optional in v1 metadata.
Category-less old v1 contexts, absent/unknown metadata and malformed optional
categories with structurally invalid indices retain fallback behavior. Valid
same-version metadata remains trusted implementation data, not a general
corruption-repair format. Initialization rebuilds metadata; callers
still reinitialize after model edits. No public context-mutation API was added.

Final measurements exposed costs that the original report missed. Interpreted
cache-tag/shape comparisons initially offset the intended runtime savings; these
now use exact builtin checks and lazy child-only metadata preparation. The
legacy two-column edge converter also recounted earlier wires quadratically;
grouped counting now preserves original port order without storage proportional
to the largest block ID.

Binary lookup needed two correctness fixes beyond the report: mixed `single`
or large `uint64` queries can compare differently after lookup conversion, so
they keep the original search. Exact-last-knot left limits remain unchanged.
The binary/endpoint fast path is restricted to double tables/queries longer
than 4,096 entries, avoiding most small-table overhead. This is a conservative
measured cutoff, not a claim of a universally optimal threshold.

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

The final `Launch-Blocks.ps1 -SelfTest` completed with exit 0:

- All 21 Octave suites passed, including the three registered performance suites.
- Graph BIST passed 9/9, edge expansion 4/4, and snapshot BIST 12/12.
- All 167 strict C99 compilation/execution cases passed: 157 numeric models
  matched every channel against Octave with worst scaled error 0; all ten model
  API harnesses passed.
- The expanded Qt editor regression passed.

The isolated `codex/optimized-release` publication branch subsequently passed
the same complete gate with exit 0, including the 167 supported C cases and Qt
checks, without the experimental C event-runtime changes. Its local log is
`.validation-artifacts/optimization-publication-full-gate.log`; details are in
[VALIDATION.md](VALIDATION.md).

Tests additionally cover 49 exact shape-equivalence cases, accepted numeric
query types above the binary-search cutoff, sparse large-table boundary queries,
and large graph/legacy-edge ordering. The public event-export guard is intact.

## Final measured results

Separate-process wall measurements showed substantial drift, including an
initial apparent regression. Final comparisons therefore use one process with
function definitions cleared and source paths asserted between versions.
Three ABBA/BAAB rounds give six samples per version/case, with warm-ups and
analytical/checksum/step/event checks. Qt measurements use twelve actual
selection callbacks plus `drawnow` per sample, excluding scene creation.

| Workload | Before median | After median | Measured change |
| --- | ---: | ---: | ---: |
| Sampled enabled, 101 outputs | 1.0361 s | .7414 s | 28.4% lower |
| Continuous enabled/events, 101 outputs | 2.2869 s | 1.7563 s | 23.2% lower |
| Primitive event, two outputs | .1828 s | .1642 s | 10.2% lower |
| Graph ordering, 1,000 blocks | .03498 s | .01388 s | 60.3% lower |
| Graph ordering, 10,000 blocks | .46164 s | .12999 s | 71.8% lower |
| 500 input queries, 100,000-row table | .03300 s | .02242 s | 32.1% lower |
| Selection, ten blocks | .02623 s/click | .02450 s/click | 6.6% lower |
| Selection, forty blocks | .08498 s/click | .07838 s/click | 7.8% lower |

The 16- and 1,000-row input cases were 3.6% and 2.7% slower: approximately
.0006/.0005 extra seconds per 500 queries, with unchanged median CPU-time
resolution. Small cases are roughly unchanged with a small dispatch overhead;
they are not presented as wins. Runtime outputs, integration steps and event
counts matched. These few local workloads do not predict every model's speed.

[Recorded samples](benchmarks/optimization-20261113.json) and
[reproduction instructions](benchmarks/README.md) are checked in. Runtime
CPU-time medians corroborated the direction of the three runtime improvements.
The baseline's benchmarked files also match published release `2ae43f3`.

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
numbers are not improvements. They are retained for provenance; the final
interleaved comparison above supersedes that preliminary timing method.

The final full-gate and explicit BIST logs are `full-gate.log` and `bist.log`
in that artifact directory. Interleaved timing logs/data and profiling snapshots
are also retained there. Final C artifacts are under
`<TEMP>/octave-blocks-codegen-a7307632e8f0436e9225ce7e064e689e`; final Qt log:
`<TEMP>/octave-blocks-editor-fc58d1bebb2f48548702f9e0439b0918/editor.log`.
Artifact directories are ignored by Git and are not part of the public package.

## Reproduce and scope

Run `./Launch-Blocks.ps1 -SelfTest` for the complete registered gate. Use
`benchmark_ob_optimizations` for simple fresh-process measurements, or the
interleaved scripts in `benchmarks/` for the comparison protocol above.
The advanced compatibility goal and full experimental C event parity remain
separate unfinished work. Full structural redraws, synchronous Run, layout
changes and canonical graph sorting retain costs; those are not hidden by
claims that every path is constant-time or that all comparisons were removed.
