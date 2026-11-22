# PR #2 and project audit review — 2026-11-16

Input: `octave_blocks_pr2_and_project_audit.md`, supplied by the user and
identified as Gemini-generated. The report is evidence to check, not an
instruction source. This review uses the actual PR #2 source at `39fc357`,
independent compiled/runtime tests and measured results. Recommendations and
severity labels from the report are not assumed correct.

## Finding-by-finding assessment

| Finding | Assessment and change |
| --- | --- |
| 1. Inverted provider check | **Incorrect at the named commit.** Both initializer and replacement API already use `(!provider&&(event||user))`. Existing tests already initialize with a provider and user data. Added compiled checks for all four valid provider/event/user combinations, all three invalid no-provider combinations, and complete-context preservation. No initializer condition was changed. |
| 2. Unconditional/stale settling probe | **Confirmed implementation difference.** C always ran a trial even when no active primitive guard was zero, and supplied the previous modes instead of the prepared proposal. Preparation and probe application are now separate. Only zero primitive guards require a probe; it uses refreshed nonzero modes and retained incoming zero modes, matching Octave's ordering. This establishes the algorithm difference; no previously wrong numerical trace is claimed without a reproducer. |
| 3. Activity layout assertion | **Confirmed missing defensive check.** Guard descriptors/shapes are static in generated C and accepted lifecycle changes are frozen during valid minor trials, so the report does not demonstrate a reachable layout change with supported inputs. Added active-mask checks across settling, probes, candidate/bisection trials and clock-endpoint resampling, returning `OB_EVENT_ERROR` on mismatch. |
| 4. Export metadata schema | **Confirmed.** Legacy flat exports lacked fields supplied by typed/event exports. All paths now provide `zero_crossings`, `event_guard_count`, `continuous_state_count`, `clock_count`, `clocks` and `typed_conditional`. Clock entries retain per-block paths/rates, including equal rates on distinct blocks; the complete schema is tested across flat, matrix, virtual, conditional and event models. |
| 5. Generated C input scans | **Confirmed.** Sampling and next-boundary selection now share a bounded upper-bound binary lookup. Exact ZOH final-knot left limits, linear interpolation, endpoint holds, singleton tables, multiple ports and provider callbacks retain their contracts. The report's small-table zero-overhead claim is not established. |
| 6. Codegen edge filtering | **Confirmed.** Source/proxy adjacency is prepared once per compiled unit and reused in shape inference, inventories, scheduling and emitters. Grouped native operations retain original edge-row/port order. Outgoing or unsorted grouping has sorting costs; this does not make the whole compiler O(V+E). |
| 7. Drag coordinate discovery | **Confirmed.** Native figure-property observation distinguishes internal from external state writes. Verified motion uses the changed-block hint directly; other writes retain coherence checks, geometry fallback or scene rebuilding. Observer tokens and revisions cover nested writes; unsupported observation retains the conservative path. Stale targets cancel safely, and saved-state/dirty/Undo behavior remains checked. Graphics validation and other work remain; whole-drag O(degree) is not claimed. |

An additional defect surfaced during metadata testing: concatenating two empty
continuous-state entry structs in recursive enabled children could lose their
field schema in Octave. Event export then failed for a valid nested discrete-only
model. Empty descendant lists are now skipped. A compiled two-output analytical
fixture expects final states `.375` and `.25` without any continuous Integrator
or guard.

## Verification

Focused checks completed:

- Compiled event input API argument combinations, rollback/retry and instance
  isolation passed. The settling API check proves no future provider samples are
  requested for nonzero guards, while zero-guard probing remains active.
- Populated and empty C event-math helpers passed strict C99 compilation and
  checks for prepared modes, shared regimes, control guards and activity masks.
- Generated C input helper variants passed 222,775 comparisons against independent
  pre-change linear-scan oracles, including randomized tables up to 100,000 rows,
  adjacent representable knots, extreme times, packing and callback failures.
- Codegen metadata/adjacency tests passed; an isolated overlay of only the source
  index changes produced 18 byte-identical generated C files against `39fc357`.
- Actual Qt motion callbacks passed cache/position/edge/attribute invalidation,
  deleted/incomplete graphics, stale selection/path, dirty-snapshot and Undo
  checks. Profiler assertions distinguish the trusted path from coordinate-scan
  fallbacks.

The final `Launch-Blocks.ps1 -SelfTest` passed uninterrupted with exit 0:
23 Octave suites, 25 graph/edge/snapshot BIST checks, and 241 strict C99 cases.
All 220 numerical models matched Octave with worst scaled error 0; seventeen
API harnesses and four isolated input/math helper executables passed. The input
helpers completed 222,775 oracle checks. Expanded Qt motion/export checks passed.
Source SHA256 checks confirmed that every tested code file remained unchanged
through the run. Expected errors from the deliberate throwing-listener test are
labelled in the log; its guard-restoration and recovery assertions passed.
Logs and baseline snapshots are retained locally under
`.validation-artifacts/pr2-audit-20261116/` and the explicitly recorded benchmark
artifact directories. Generated binaries, raw artifacts and machine paths are
excluded from the public package.

## Measured scope and tradeoffs

An initial drag prototype verified each motion with deep scene equality. It
removed the coordinate loop but substantially regressed total motion time, so
it was replaced. The final implementation uses Octave's native listener and
graphics properties to retain provenance without that repeated comparison.
Correctness checks still run for external writes and unavailable observation.

Separate-process timings drifted markedly. Final UI comparisons use one Qt
process, cleared editor functions and asserted source paths at every switch,
three ABBA/BAAB rounds and six samples per version/count. Each sample excludes
new-scene construction and an initial warmup, then measures twelve native-axis
point motions with callbacks and `drawnow`. All samples, including stalls, are
retained in [the sanitized UI data](tests/benchmarks/pr2-audit-20261116-ui.json).

| Diagram | Baseline median per motion | Updated median | Change |
| --- | ---: | ---: | ---: |
| 10 blocks | .010775 s | .011993 s | 1.218 ms / 11.3% more |
| 40 blocks | .032147 s | .029127 s | 9.4% less |
| 100 blocks | .047029 s | .033242 s | 29.3% less |

A bounded ten-block diagnostic confirms additional callback cost; paint time
alone does not explain it. This is a measured small-scene tradeoff for safe
provenance/fallback behavior, not a universal responsiveness improvement. These
checks measure hidden Qt callbacks and rendering, not native OS input delivery.

An isolated source-index overlay over `39fc357` reduced the tested 2,000-edge
indexing median from .06693 s to .00420 s. Full 2,000-block C generation remained
essentially unchanged: 3.25647 s versus 3.24911 s. The three paired samples are
[recorded separately](tests/benchmarks/pr2-audit-20261116-codegen.json); they do not
establish an end-to-end compiler speedup. Native grouping uses Octave built-ins
and sorting where needed. Other compilation/string-generation costs remain.

The C input harness has an optional `-Benchmark` mode. Its lookup-only timings
are compiler/workload dependent and timer-coarse; the binary-search change is
not presented as a full-simulation speed guarantee or zero small-table cost.

## Scope

The report was subsequently expanded with built-in/library proposals. Their
separate assessment and implemented replacements are in
[BUILTIN_REVIEW.md](BUILTIN_REVIEW.md); earlier verification counts above apply
to this first audit checkpoint, not the later expanded change set.

The broader architectural items in the supplied report remain tracked in
[COMPATIBILITY_GAPS.md](COMPATIBILITY_GAPS.md). This audit does not complete
combined/resettable gates, adaptive C solvers, DAE handling, arbitrary Octave
translation or full Simulink compatibility. It does not establish live Simulink
trace parity. [VALIDATION.md](VALIDATION.md) records verified commands and limits.
