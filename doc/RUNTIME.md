# Resumable Octave execution

The Octave engine exposes an independent execution context. `ob_run` uses this
same scheduler to collect a sequence of output samples. A host can instead
request one output at a time, copy a context to explore another continuation,
or save and restore it between steps.

```octave
runtime = ob_runtime_init (ob_multirate_example (), 0);
runtime = ob_runtime_step (runtime, 0.1);
checkpoint = runtime;
runtime = ob_runtime_step (runtime, 1);
assert (abs (ob_runtime_outputs(runtime, 4) - 0.375) < 1e-12);

branch = ob_runtime_step (checkpoint, 0.5);
assert (abs (ob_runtime_outputs(branch, 4) - 0.0625) < 1e-12);
assert (checkpoint.time == 0.1);
```

| Operation | Behavior |
| --- | --- |
| `ob_runtime_init(model, start_time=0, options=struct())` | Validate and compile the model, initialize all states/clocks, and evaluate the first output. Supports the same solver options as `ob_run`. |
| `ob_runtime_step(runtime, next_time)` | Return a new context at a finite time strictly after the current one, processing every hidden clock hit and integration boundary along the way. |
| `ob_runtime_outputs(runtime)` | Return a row cell array containing the first output of each root block. |
| `ob_runtime_outputs(runtime, path, port=1)` | Return one scalar/matrix signal at a hierarchical block path and numbered output port. |

Always assign the returned step context. Contexts use Octave value semantics;
stepping one copy does not change another. An error leaves the caller's
previous context intact, including its time, states, pending discrete updates,
clock counters, and cached outputs. Reads of `ob_runtime_outputs` return the
cached sample and do not execute Function blocks or advance sample hits.

The public diagnostic fields are `time`, `start_time`, `integration_steps`,
`sample_hits`, `signal_map`, and `block_paths`. `current` contains one cached
value per compiled leaf block. Other fields are implementation details; do not
edit context fields to change model parameters, input data, states, or clocks.
Initialize a new context when changing the model or its settings.

## Save and resume

```octave
save ('-mat7-binary', 'checkpoint.mat', 'runtime');
restored = load ('checkpoint.mat');
runtime = ob_runtime_step (restored.runtime, 2);
```

Checkpoints contain the compiled model, fixed external-input tables, solver
settings, numerical state, and scheduling information. Restoring a checkpoint
requires a compatible Octave Blocks implementation and the same custom `.m`
Function implementations on Octave's path. It does not save function source,
external files, or mutable global state. The current context schema is
`octave-blocks-runtime-v1`; future schema migration is not yet provided.

For equivalent results to `ob_run`, request the same output-time sequence.
Output times determine inherited discrete updates and RK4 integration
intervals. Adding output requests can therefore change the numerical solution
or inherited-clock behavior; explicit clocks keep their original start-time
origin and period across checkpoints. Adaptive solvers restart at each
requested output, hidden discrete hit, or known source boundary while retaining
their continuous state.

Failed Octave evaluation cannot roll back side effects performed by a custom
Function block. As with ordinary simulation, functions must be deterministic
and avoid external side effects. There is no concurrency or shared-state
guarantee for external resources used by such functions.

The generated C model already provides its own per-instance initialization,
stepping, and output API; see [CODEGEN.md](CODEGEN.md). Octave MAT checkpoints
are not a C memory-image format.

Supported algebraic feedback is solved at scheduled evaluations and continuous
solver stages. Accepted numeric solutions are stored as per-context guesses;
trial iterations never consume discrete hits or change trigger history. Cached
output reads do not solve the constraints again. See [ALGEBRAIC.md](ALGEBRAIC.md)
for supported blocks, matrix guesses, convergence checks, and failure behavior.

With `options.zero_crossings = true`, `runtime.events` and `result.events`
contain accepted control-guard events using public block paths and column-major
channel indices. `runtime.event_memory` retains incoming regimes and guard
history at a boundary. Copies and MAT checkpoints preserve this history, and
failed steps preserve the caller's original event list and memory. A plateau
departure at the requested stop may be recognized on the next advance with
that previous stop's timestamp. These internal integration boundaries do not
consume unrelated inherited discrete updates. Conditional gates default to
sampled timing; explicit continuous controls dispatch at accepted events. See
[ZERO_CROSSINGS.md](ZERO_CROSSINGS.md) for the supported scope.

The `execution.control='continuous'` setting separates enable transitions from
inherited child captures, while triggered execution intentionally advances its
own body clock. Primitive-to-gate changes may use an accepted zero-time outgoing
regime reconciliation; that frame skips all ordinary clock rebasing/hits.
See [CONTINUOUS_CONTROLS.md](CONTINUOUS_CONTROLS.md) for timing and initialization.

`model.runtime_info` caches immutable compiled routing, loop membership and
conditional descriptors. Missing/unknown-version metadata falls back to the
legacy path; compatible same-version cache contents are trusted implementation
data. Value/shape checks remain dynamic. See
[RUNTIME_PERFORMANCE.md](RUNTIME_PERFORMANCE.md) for measurements and cache tests.

Conditional children now use these contexts for sampled enable/trigger
execution. Active enabled continuous child states participate in the root
solver vector; their stage evaluations preserve major-hit execution histories.
Reads still return cached outputs without advancing the model.
Root contexts also keep the global clock inventory for enabled descendants,
discovered without executing lazy children. Disabled descendants skip their
events while the root clock phase advances. Nested contexts and checkpoints
retain pending captures; resuming executes the next global hit rather than
catching up through inactive time. Inner `sample_hits` list executed hits;
cached child scheduler fields may remain at their last active sample while the
root inventory continues to advance.
See [CONDITIONAL.md](CONDITIONAL.md) for retained/reset state,
hierarchical snapshots, and the remaining milestone gaps.
