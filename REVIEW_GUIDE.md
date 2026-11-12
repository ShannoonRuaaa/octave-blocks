# Reviewer guide

Octave Blocks is an Octave-native block editor, simulation runtime, and C99
exporter. This guide explains how to review changes. It does not establish
full MATLAB or Simulink compatibility. The current tested scope and remaining
work are recorded in [ADVANCED_PLAN.md](ADVANCED_PLAN.md); behavior references
and the limits of the MATLAB/REA evidence are in
[SIMULINK_REFERENCE.md](SIMULINK_REFERENCE.md).

## Start and reproduce

Use GNU Octave with Qt for the editor. The verified Windows installation is
Octave 11.3.0; numerical tests also run through `octave-cli`. Generated C needs
a C99 compiler and the standard math library. The PowerShell scripts use
Octave's bundled GCC by default and place its runtime dependencies on PATH.

From this `octave-blocks` folder in PowerShell 7:

```powershell
./Launch-Blocks.ps1                  # Native editor
./Launch-Blocks.ps1 -SelfTest        # Octave, compiled C, then Qt graphics checks
./Test-Codegen.ps1                  # C generation/compilation/comparison only
```

Use `-OctaveHome 'C:\path\to\Octave-11.3.0'` when discovery cannot find the
installation. `Test-Codegen.ps1` also accepts `-Compiler` and
`-OutputDirectory`. Its reported artifact folder contains generated sources,
expected traces, executable output, and a manifest; retain it when reporting a
failure. A script that reaches source generation has not yet proved C parity:
the compiler, executables, API harnesses, and final comparison must also pass.

For a focused numerical review, add this folder to Octave's path:

```octave
addpath (pwd ());
test_ob_runtime ();
test_ob_enabled_continuous ();
test_ob_enabled_multirate ();
test_ob_algebraic ();
test_ob_zero_crossings ();
test_ob_continuous_controls ();
test_ob_runtime_metadata ();
```

Choose suites relevant to the change, then run the full gate before accepting
a scheduler or compiler change. Qt callback/graphics checks run in a separate
GUI-runtime process after CLI/C checks; see [UI_PERFORMANCE.md](UI_PERFORMANCE.md) for that harness and
its measured scope. A live editor opened before a code change may retain old
functions; use a fresh Octave process for reproducible UI checks.

## Read the execution path

| Area | Entry points | What to inspect |
| --- | --- | --- |
| Public Octave API | [ob_run.m](ob_run.m), [ob_runtime_init.m](ob_runtime_init.m), [ob_runtime_step.m](ob_runtime_step.m), [ob_runtime_outputs.m](ob_runtime_outputs.m) | Public inputs, value semantics, cached reads, result mapping. |
| Linear library | [ob_state_space.m](ob_state_space.m), [ob_transfer_function.m](ob_transfer_function.m), [LINEAR_SYSTEMS.md](LINEAR_SYSTEMS.md) | Equations, vector dimensions, autonomous sources, direct feedthrough, and realization-state convention; builders return editable virtual diagrams. |
| Model validation | [ob_validate_model.m](ob_validate_model.m), [ob_edges.m](ob_edges.m), [ob_block_ports.m](ob_block_ports.m), [ob_execution_options.m](ob_execution_options.m) | Draft versus complete diagrams, port cardinality/order, hierarchy and parameter contracts. |
| Compilation | [ob_compile_model.m](ob_compile_model.m), [ob_execution_order.m](ob_execution_order.m) | Virtual flattening, atomic/multiple-output proxies, dependency order, public-to-internal paths. |
| Scheduler | [private/ob_runtime_engine.m](private/ob_runtime_engine.m), [private/ob_nested_clocks.m](private/ob_nested_clocks.m), [private/ob_clock_rebase.m](private/ob_clock_rebase.m) | Pending commits, hidden events, global clock phase, lazy children and transaction boundaries. |
| Compiled runtime metadata | [private/ob_prepare_runtime_model.m](private/ob_prepare_runtime_model.m), [private/ob_runtime_execution.m](private/ob_runtime_execution.m), [private/ob_event_execution.m](private/ob_event_execution.m), [RUNTIME_PERFORMANCE.md](RUNTIME_PERFORMANCE.md) | Immutable routing/options versus dynamic data checks, trusted context metadata, cache-free checkpoint fallback and measured cost. |
| Flow and integration | [private/ob_runtime_eval.m](private/ob_runtime_eval.m), [private/ob_conditional_eval.m](private/ob_conditional_eval.m), [private/ob_conditional_flow.m](private/ob_conditional_flow.m), [private/ob_runtime_integrate.m](private/ob_runtime_integrate.m) | Major-hit mutation versus minor-stage flow, shared continuous state vector, left-limit endpoints. |
| Algebraic constraints | [private/ob_algebraic_solve.m](private/ob_algebraic_solve.m), [private/ob_direct_output.m](private/ob_direct_output.m), [ALGEBRAIC.md](ALGEBRAIC.md) | Simultaneous residuals, fixed shapes, per-context guesses, singularity and independent residual checks; no lifecycle operations inside iteration. |
| Zero-crossing events | [private/ob_zc_snapshot.m](private/ob_zc_snapshot.m), [private/ob_flow_segment.m](private/ob_flow_segment.m), [private/ob_integrate_events.m](private/ob_integrate_events.m), [ZERO_CROSSINGS.md](ZERO_CROSSINGS.md) | Frozen incoming regimes, accepted-step monitors, canonical event-state reconstruction, outgoing-mode settling and checkpointed boundary history; no extra discrete hits. |
| Continuous controls | [private/ob_conditional_control.m](private/ob_conditional_control.m), [private/ob_conditional_gate_flow.m](private/ob_conditional_gate_flow.m), [CONTINUOUS_CONTROLS.md](CONTINUOUS_CONTROLS.md) | Accepted gate lifecycle versus inherited captures, trigger arming, source/primitive transitions, coincidence ordering and zero-time clock isolation. |
| C export | [ob_codegen.m](ob_codegen.m), [ob_c_conditional_unit.m](ob_c_conditional_unit.m), [ob_codegen_conditional.m](ob_codegen_conditional.m), [ob_emit_c_conditional.m](ob_emit_c_conditional.m) | Static shape inference, actual builtin mappings, typed contexts, generated C and file replacement. |
| Clocked C extension | [ob_c_clock_inventory.m](ob_c_clock_inventory.m), clocked child/root emitters in [ob_emit_c_conditional.m](ob_emit_c_conditional.m) | Global clock IDs versus block IDs, transient event frames, disabled clocks, root-owned tick phase. Consult current C support status in [CODEGEN.md](CODEGEN.md). |
| Editor and persistence | [octave_blocks.m](octave_blocks.m), [ob_save_model.m](ob_save_model.m), [ob_load_model.m](ob_load_model.m) | Model/graphics separation, undo snapshots, nested editing, validation before persistence. |
| Evidence | [test_ob_codegen.m](test_ob_codegen.m), [verify_ob_codegen.m](verify_ob_codegen.m), the `test_ob_*.m` suites | Analytical expectations, generated-code comparisons, failure/rollback harnesses, rejection paths. |

## Model and index conventions

`model.blocks` is a struct array with `type`, `value`, `name`, `x`, and `y`.
Subsystem `value` holds a child model; interface block `value` holds a numbered
port. Function output count is the optional `outputs` field, independent of
the legacy `value` field. Optional block metadata must survive ordinary edits.

Canonical edge rows are `[source source_port target target_port]`. Legacy
two-column rows remain accepted and assign destination ports in row order.
All model block IDs, port numbers, and public hierarchy paths are one-based.
C array offsets are zero-based. Matrix components are packed in Octave column
order. Check these boundaries explicitly when reviewing routing or codegen.

Compiler-generated paths containing zero identify internal cores/proxies.
Some `flat_values` cells contain structured conditional contexts or multiple
returns. Use `ob_signal_values`, `ob_scope_data`, or `ob_runtime_outputs` for
public paths instead of assuming every flat cell is numeric. Root
`result.values` retains each block's first output for compatibility.

Sample times are per-level `[period offset]` rows. They are this project's
schema, not Simulink parameter encodings. Read [MULTIRATE.md](MULTIRATE.md),
[CONDITIONAL.md](CONDITIONAL.md), and [RUNTIME.md](RUNTIME.md) before changing
clock or conditional semantics. Saved diagrams are Octave Blocks MAT files;
runtime checkpoints are separate implementation-dependent contexts.

## Invariants to preserve

1. A failed Octave step leaves the caller's context unchanged. Generated C
   initialization, provider changes, and steps commit only on success. Include
   nested state, pending captures, tick counters, held outputs, and gate history
   in rollback checks. External Function/callback side effects are excluded.
2. Major hits may update gate history and discrete state. Minor solver stages
   evaluate flow using stage inputs and states; they do not sample clocks,
   trigger children, or change major-hit capture buffers.
3. Active continuous child states share the parent solve. Test coupled
   parent/child dynamics; integrating the child separately with previous inputs
   can pass simple ramps while producing incorrect feedback behavior.
4. Root-origin clocks advance while disabled descendants skip execution.
   Reenable/reset must not replay missed hits or rephase a clock. Explicit
   Euler uses its configured period; inherited execution follows its documented
   active-interval contract.
   [private/ob_suspend_enabled.m](private/ob_suspend_enabled.m) freezes active
   descendant interval metadata at an ancestor disable boundary without
   sampling state or resetting clock phase. Review its generated-C counterpart
   when changing pause/resume behavior.
5. Due Unit Delay/Euler state commits are simultaneous. Rate Transition samples
   in dependency order at a hit and does not itself break algebraic loops.
6. Integration ends on the left side of known discontinuities; major sampling
   uses the current/right-side source value. Verify sparse output requests as
   well as aligned and unaligned source transitions.
7. Validation and static C rejection happen before replacing the destination
   file. Temporary files belong beside the destination and are cleaned up on
   failure. An invalid export must preserve an existing source byte-for-byte.
8. Graphics handles belong to editor state, not models, MAT files, or undo
   snapshots. Selection/drag optimizations must preserve topology rebuilds,
   numbered wire endpoints, and one undo entry per logical edit.

For clocked C review, `ob_clock_frame` is temporary event data. Its pointers
may refer to the current stack/work context and must never be retained in a
model instance. The emitted `ob_interval_kind` enum distinguishes
`OB_INTERVAL_ELAPSED`, `OB_INTERVAL_INHERITED`, and `OB_INTERVAL_PERIOD`.
Review producers and consumers together: inherited time is bounded by the
child's elapsed time while configured periods retain a fixed step.

## Review a change

1. State the supported behavior and the affected public/model contracts. Link
   the exact reference or analytical equation. Identify unsupported cases before
   inspecting whether the existing tests happen to pass.
2. Follow one model through validation, compilation, ordering, runtime, result
   mapping, editor/persistence, and supported C emission. A new block requires
   more than an evaluator `switch` case.
3. Inspect at least one independent expected trace or closed-form solution.
   C-versus-Octave comparisons prove agreement between implementations for
   those cases; they do not prove that both match Simulink.
4. Check edge cases that distinguish the behavior: offsets, simultaneous hits,
   sparse requests, inactive initialization, pause/reset, matrices, nested
   boundaries, nonfinite/domain failures, and retry after failure.
5. Run relevant suites and the complete required gate. For UI changes, verify
   native Qt callbacks and visual behavior. For C, compile exact generated
   artifacts with warnings as errors and exercise the callable API.
6. Report the concrete change, evidence, and remaining limits. Update the
   feature documentation and milestone record together. Do not infer release
   readiness or full compatibility from a green numerical subset.

`git diff --check` does not inspect untracked files. If a working copy is still
untracked, inspect the exact files intended for review before relying on Git
diff output. Check licensing/distribution metadata separately before publishing;
the project is distributed under the [MIT license](LICENSE). Current verification is recorded in [VALIDATION.md](VALIDATION.md).

## Readability expectations

Use descriptive names at model/API boundaries and document units/index bases.
Prefer one state transition or host-language statement per line. Match the
surrounding Octave style (`endif`, `endfunction`, explicit continuations); do
not rewrite working Octave constructs just to imitate MATLAB syntax.

Keep generated-C text distinct from the Octave code that selects and assembles
it. Comments should explain timing, ownership, and compatibility decisions.
Avoid unrelated formatting in a behavior change: extract a bounded helper,
preserve regression evidence, then improve the next boundary. Concrete
follow-ups from this review are in [STYLE_REVIEW.md](STYLE_REVIEW.md).
