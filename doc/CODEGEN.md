# Standalone C generation

Adaptive ode45 exports include GPL-3.0-or-later solver code and retain upstream
attribution. See [licensing and provenance](LICENSING.md) before distributing
generated source or compiled output.

Event-runtime architecture and focused regression commands are described in
[EVENT_CODEGEN_DEVELOPMENT.md](EVENT_CODEGEN_DEVELOPMENT.md). Current verification
status is recorded in [VALIDATION.md](VALIDATION.md).

Use **Export C** in the editor or call the exporter directly in Octave:

```octave
info = ob_codegen (ob_subsystem_example (), 'model.c', [0 10 0.1]);
```

The export uses the whole root model, including nested subsystems, and requires
`rk4` in simulation settings, or `ode45` for flat models (see
[Adaptive ode45 export](#adaptive-ode45-export)); `ode15s` is interpreted only.
It produces one C99 source file with a callable
model API. Define `OB_STANDALONE` when compiling to add a CSV runner using the
requested start/stop/output interval. Source generation requires Octave;
compiling/running the exported model does not require the Octave interpreter
or Octave libraries. Existing output files are replaced only after successful
validation and source generation. The editor places export metadata in
`ob_last_export`.

## Supported models

| Feature | Generated behavior |
| --- | --- |
| Constant, Time, Step | Real numeric sources; Step transitions split continuous integration intervals. |
| Root Inport | Sampled root signals with declared matrix shapes, ZOH or linear interpolation, endpoint holds, or host C input providers. |
| Gain, Product | Scalar scaling and matrix multiplication with statically checked dimensions. |
| Sum | Addition with scalar, row, or column expansion using Octave's two-dimensional broadcasting rules. |
| Saturation, Dead Zone | Elementwise clamp or dead-zone excess with fixed scalar lower/upper limits; input shape preserved. |
| Switch | Input 1 where input 2 is greater than or equal to its scalar threshold, otherwise input 3; data shapes must match and control must be scalar or match them. |
| Unit Delay | Previous input on its explicit clock, or on requested output times when inherited. |
| Discrete Integrator | Forward Euler on its explicit clock, or using the next output interval when inherited. |
| Rate Transition | Samples its current input at its configured hit and holds it between hits; no extra Unit Delay. |
| Integrator | RK4 with all continuous states integrated together; discrete states held during intermediate stages. Flat models may use adaptive ode45 instead (Octave's own algorithm, [below](#adaptive-ode45-export)). |
| Limited Integrator | RK4 with saturation decided from each step's initial state, clamping, and sampled rising/falling/either/level/level hold resets (see [below](#transport-delay-and-limited-integrator)). |
| Transport Delay | Bounded input history reproducing `ob_run` exactly: left/right samples, cubic Hermite interpolation, delayed jumps as solver boundaries (see [below](#transport-delay-and-limited-integrator)). |
| Subsystem, Inport, Outport | Virtual boundaries are flattened; explicit ports, branches, hierarchy, and multiple subsystem outputs are retained in metadata. |
| Conditional Subsystem | Sampled or explicitly continuous enabled/rising/falling/either and combined enabled_rising/enabled_falling/enabled_either control with typed nested contexts and lazy initialization (see [combined controls](COMBINED_CONTROLS.md)). Enabled bodies support held/reset state/output policies, continuous states and inherited or independent inner clocks. Continuous controls require `zero_crossings=true`. |
| Registered zero crossings | With `zero_crossings=true`, localize Switch/Saturation/Dead Zone guards and declared continuous controls under RK4, including active enabled descendants. |
| Scope | Signals remain available as numeric channels in the API and CSV output. |
| Selected builtin Function blocks | Elementwise unary math and supported binary operations below, with statically checked arity and broadcasting. |
| Two-output Function calls | Actual builtin size, max, or min with one scalar/matrix input; dimensions or first-occurrence value/index pairs. |

Parameters and initial states must be full, finite, real `double` scalars,
vectors, or matrices. State inputs must have the same shape as their initial
conditions. Matrix elements use Octave's column order. Generated code uses
standard C `double` arithmetic and checks all block outputs for nonfinite
values. Different compilers/math libraries may produce small rounding changes;
cross-platform bit-for-bit equivalence is not promised.

Supported unary Function names: `sin`, `cos`, `tan`, `asin`, `acos`, `atan`,
`sinh`, `cosh`, `tanh`, `exp`, `log`, `log10`, `sqrt`, `abs`, `floor`, `ceil`,
`round`, `sign`, `uminus`.

Supported binary names: `power`, `atan2`, `hypot`, `plus`, `times`, `minus`,
`rdivide`. These are elementwise operations with scalar/row/column expansion.
For example, Function `times` is elementwise multiplication, while the Product
block uses matrix multiplication. Only the actual Octave builtin is mapped;
a user function shadowing that name is rejected.

Functions declared with two outputs also support one-input `size`, `max`, and
`min`. These use fixed shapes; reductions operate on the first nonsingleton
dimension and return the first matching index starting at 1. Other signatures
and arbitrary multi-output `.m` translation are not yet supported. See
[MULTIOUTPUT.md](MULTIOUTPUT.md) for the exact subset and MATLAB comparisons.

Enabled/triggered Subsystems use generated child contexts embedded by value.
Independent clocks inside enabled bodies share a root-owned clock inventory.
Ticks advance while disabled children skip execution. Child initialization
and reset preserve global phase; missed hits are not replayed. Explicit
control samples and inner hits dispatch separately, and inherited enabled
controls also sample at the union of descendant hits.
Inactive children are not initialized or evaluated. Discrete-only children
retain held output buffers between their hits; in event mode that includes
the reconciliations between them (input and Step boundaries, located
crossings, accepted control changes), as in the interpreter. Active enabled continuous bodies
share all four RK4 stages with their parent: each child receives current stage
inputs and exposes instantaneous outputs. Nested active Integrator states use
one shared derivative vector, with zero derivatives while an ancestor is
disabled. Stage copies preserve activation and discrete sample histories.
Separate major-hit value snapshots supply inherited Delay/Euler updates, so
minor-stage values cannot alter their timing. Nested Step transitions and root
input events split integration intervals with left-limit endpoint evaluation.

Each active event receives current data,
absolute time, and the inherited execution interval; nested enabled Euler state
therefore freezes across a disabled ancestor. Parent transaction copies include
child states and trigger history, so a nested failure preserves the entire
previous context. Child input buffers are passed directly without retained
pointers into parent or stack storage. See [CONDITIONAL.md](CONDITIONAL.md).

Conditional exports follow the same Outport rules as the interpreter:
per-port OutputWhenDisabled; scalar initial outputs expanded to the port
shape; and, in enabled bodies with inner clocks, Outports that update only
when one of their clocked sources executes, clocked blocks that share the
buffer of the Outport they drive, and per-port reset at the port's own clock
(CONDITIONAL.md; `private/ob_conditional_gating.m`,
`private/ob_conditional_c_gate.m`). In event mode an inherited enabled
control is also sampled at its body's inner clock hits (`ob_emit_c_event_root`).

See [CONTROLS.md](CONTROLS.md) for nonlinear block equations and solver limits.
Switch evaluates both data branches; it does not gate execution of upstream
blocks. Registered event behavior and search limits are described below;
arbitrary event registration is not supported.

Arbitrary `.m` Function blocks (except in accelerated builds, which call
Octave for them; see [Accelerated simulation](#accelerated-simulation)),
complex/integer/single/sparse/N-D parameters, `ode15s`, `ode45` with
conditional subsystems, multiple-output Functions or zero crossings, changing
signal shapes, and unsupported block types are rejected before replacing an
output file. Functions whose runtime inputs leave
their real finite domain (for example `power(-1, 0.5)` or division by zero)
produce an explicit C runtime error. Octave may represent some of these results
as complex values; generated code supports real finite signals only.

## Compile and verify

With a C99 compiler on PATH:

```sh
cc -std=c99 -O2 -DOB_STANDALONE model.c -lm -o model
./model > model.csv
```

On Windows, the verified toolchain is the GCC bundled with Octave 11.3.0. Its
`mingw64\bin` directory must be on the child process PATH so GCC can load its
support tools. `Test-Codegen.ps1` sets and restores that PATH automatically:

```powershell
./tests/Test-Codegen.ps1
./tests/Test-Codegen.ps1 -OctaveHome 'C:\path\to\Octave-11.3.0'
./tests/Test-Codegen.ps1 -Compiler 'C:\path\to\gcc.exe' -OutputDirectory './c-verification'
./tests/Test-EventCodegen.ps1
./tests/Test-EventCodegenEdges.ps1
./tests/Test-EventCodegenHierarchy.ps1
```

The script generates fixtures and Octave references, compiles with
`-std=c99 -O2 -Wall -Wextra -Werror`, runs each executable, and compares every
CSV signal channel against Octave (scaled error below 1e-11, or below the
case's manifest `tolerance`, 1e-9 for ode45 exports). It also exercises the
C API's independent instances and error handling. It retains sources,
binaries, references, CSVs, and a manifest in the reported artifact
directory. `Launch-Blocks.ps1 -SelfTest` includes these compiled-code checks
as well as the Octave test suites.

## Accelerated simulation

Like Simulink's Accelerator mode, a model can run as compiled C from Octave:

```octave
result = ob_run (model, 0:0.01:10, struct ('solver', 'rk4', 'accelerate', true));
[result, info] = ob_accelerate (model, 0:0.01:10);   % same, with build details
```

`ob_accelerate` exports the model with `ob_codegen` (without the CSV runner,
with Transport Delay histories sized for the requested times), appends a MEX
gateway and compiles it with `mkoctfile --mex` (flags `-O2
-ffp-contract=off`). The C code initializes at `t(1)`, steps through every
requested time exactly as `ob_run` does, and returns all values at once. The
result has the same fields, field order and value shapes as an interpreted
run: `t`, root `values`, `flat_values`, `integration_steps`, `sample_hits`
and `events`, plus the static fields (`order`, `signal_map`, `block_paths`,
`compiled_model`, `inputs`, `sample_times`) taken from an initialized
interpreted context. `test_ob_accelerate` (72 cases) checks every field and
value against the interpreted run for eight of the nine benchmark cases
(Mackey-Glass on shortened grids) and 46 further models (14 flat rk4, 9
ode45, 17 typed, 5 with user Functions, and a delay feedback model that needs
a capacity retry); the worst scaled error is 2.0e-16 (two ode45 models whose
state is a 2-by-2 matrix; see the arithmetic note below) and 0 everywhere else.

**Sample hits.** `sample_hits` is rebuilt from the root clock schedule
(`private/ob_accelerate_hits.m`), which is the same in both runs: explicit
root clocks hit at their ticks, inherited blocks at every output time, and
an inherited enabled Conditional Subsystem with sampled control also
whenever one of its inner clocks is due, as in `ob_run`. The schedule
replays the engine's rule that every clock whose tick lies within the clock
tolerance of an event is processed there, so a tick that nearly coincides
with an earlier tick of another clock (3*0.1 and 0.3) carries the earlier
time. The tick counts of explicit clocks are checked against the compiled
counters.

**Cache.** Compiled files are stored per user, never in the repository:
`$OB_ACCELERATOR_CACHE` if set, otherwise
`%LOCALAPPDATA%\octave-blocks\accelerator\<Octave version>-<platform>` on
Windows and `$XDG_CACHE_HOME` (or `~/.cache`)`/octave-blocks/accelerator/...`
elsewhere. Each build is named `ob_accel_<key>`, where the key is a SHA-1 of
the generated source, the gateway, the compiler flags and the Octave version,
so any change to the model, its parameters, inputs or settings, or to the
generator gives a new build, and repeated runs reuse it. The source is kept
next to the binary. Builds are compiled under a private name and renamed, so
concurrent sessions can share the cache. The cache directory is appended to
the end of the Octave path. Within a session, exports are also remembered by
a digest of the model, options, times and how each Function name currently
resolves (builtin or file), so a repeated run skips export and interpreted
initialization (`info.reused_export`; `clear ob_accelerate` forgets them).
Shadowing a C-mapped builtin with a user file, or removing that file, gives a
new export. A remembered export fixes the output shapes of user Functions; if
an edited function returns another shape, the export is regenerated once.
Delete the cache directory to remove all builds.

**Supported subset.**

| Model | Exporter | Solvers |
| --- | --- | --- |
| Flat models: the blocks in the table above, including Transport Delay and Limited Integrator, root inputs, explicit clocks and virtual subsystems | flat `ob_codegen` | `rk4`, `ode45` |
| Conditional subsystems (all modes and policies, nested, continuous bodies, inner clocks), multiple-output Functions, `zero_crossings=true`, continuous controls | typed `ob_codegen_conditional` | `rk4` |
| Function blocks whose function has no C mapping (user `.m` functions, shadowed builtins), in flat models only | flat, through `ob_external_call` | `rk4`, `ode45` |

`ode15s`, `ode45` with typed models or zero crossings (so `control_zc_ode45`
of the benchmark set), `ode45` with `reltol`, `abstol` or `maxstep` of a class
other than double (`ob_run` then runs Octave's `ode45` in that class), user
Functions anywhere in a typed model (inside or next to a conditional
subsystem, with `zero_crossings=true`, or as a multiple-output Function),
Transport Delays and Limited Integrators in typed models and algebraic loops raise
`octave_blocks:accelerate_unsupported` before anything is compiled; a
missing or failing compiler raises `octave_blocks:accelerate_unavailable`.

**Typed models.** The gateway drives the typed exporter's public root API
(`ob_model_init`, `ob_model_step`, `value`, `tick`) exactly like the flat one.
Two things `ob_run` reports are not kept by that exporter, so
`ob_accelerate` instruments its generated source (and rejects a source
whose shape it does not recognize): a root `integration_steps` counter,
incremented for every RK4 segment with active continuous states (the
`ob_shared_rhs` activity guards) and every accepted zero-crossing flow, and
an event log. Each record the C context counts is logged with `ob_run`'s
direction (sign of a continuous control's change, outgoing regime of a
plateau departure, sign of a located crossing), and `result.events` is
rebuilt from the exporter's guard inventory (`ob_c_event_inventory`: public
path, type, channel, side, boundary; `private/ob_accelerate_events.m`). The
generated crossing loop already applies `ob_run`'s `origin_departures` rule.
Each zero-crossing search step is numbered (a call at the start of each pass
of `ob_integrate_events`' loop), and every record carries its step: within
one step the C records continuous-control changes before plateau departures
while `ob_run` lists the departures first, so the records of each step are
ordered departures, changes, crossings, the crossings in time order (a
departure from zero at the search origin before another guard's crossing
bisected just after it; the C counts them in guard order and keeps the
latest time as `last_event_time`); records of different steps keep
their order (a change that ends one step stays before a departure that the
next step finds at the same instant). `test_ob_accelerate` has a model of
each kind. The C counters are never changed. Exporter hooks that would replace this
instrumentation are proposed for the conditional track. A `Multiple
Function` core in `flat_values` is the cell of its outputs, as in `ob_run`.
A `Conditional Subsystem` core is the interpreted child context in
`ob_run`; the compiled child context stays in C, so the accelerated core is
`struct ('outputs', {...})`, the held outputs (equal to the interpreted
context's `outputs`, and to the Conditional Output proxies).

**User Functions.** For a Function block without a C mapping the export
calls `ob_external_call (index, inputs, output)` (accelerated builds only;
standalone exports keep rejecting such blocks). Its output shape is the
block's value at `t(1)` in the initialized interpreted context, which must
be a real double matrix. Only Octave's main thread may evaluate Octave code,
so a model whose estimated stack need is at most 256 KB runs on the main
thread (a thread handshake per call cost several times the call itself);
larger models keep the simulation thread, which posts each call and waits.
The call goes straight to the function with `mexCallMATLAB` under the trap
flag; a failed call is repeated through `private/ob_accelerate_call.m`
(`feval` by name from the same folder as `ob_runtime_eval`), which returns
the error message. The result must be a real double matrix of the compiled
shape. An error inside the function fails the run with that message
(`OB_EXTERNAL_ERROR`, `octave_blocks:accelerate_runtime`, as `ob_run`
fails); a result of another class, a complex value or another shape
(`OB_EXTERNAL_SHAPE`), or one with a NaN or Inf element
(`OB_EXTERNAL_NONFINITE`: `ob_run` keeps such values, for example in a Scope,
but the compiled model stops on any nonfinite signal) raises
`octave_blocks:accelerate_unsupported`, so `accelerate='auto'` reruns it
interpreted. User Functions are accelerated in flat models only: the typed
exporter maps every Function to C math (`ob_c_function`), so a user Function
in a model that needs it is unsupported. An interrupt (Ctrl-C) inside the function
unwinds out of the MEX file; on the simulation-thread path the waiting
thread then stays blocked, harmlessly, until Octave exits.

Transport Delay histories have a fixed compiled capacity (see below). If a
run fills one (`OB_DELAY_OVERFLOW`), typically because delayed
discontinuities keep multiplying through feedback, `ob_accelerate` rebuilds
the model with every history doubled and runs it again, up to 8 times and
within the 256 MB export limit (`info.capacity_retries` counts the rebuilds;
the enlarged build is reused for later calls in the session). If the history
still overflows, it raises `octave_blocks:accelerate_capacity`.

With `accelerate='auto'`, `ob_run` falls back to interpretation for exactly
these three errors (unsupported, unavailable, capacity). Other failures of
the compiled model (`OB_NONFINITE`, `OB_DELAY_SEGMENTS`, `OB_STEP_FAILED`,
`OB_EVENT_ERROR`, `OB_EXTERNAL_ERROR`) raise
`octave_blocks:accelerate_runtime` in both modes; the segment limit uses
`ob_run`'s wording. Generated code rejects nonfinite signals, so a model
whose C-mapped blocks produce complex or infinite values (`sqrt(-1)`,
`log(0)`), which an interpreted run may pass to a Scope, fails when
accelerated, also with `'auto'`. Only nonfinite results of user Functions
fall back (see above).

`info` reports `mex`, `source`, `cache`, `cache_hit`, `reused_export`,
`exporter` (`flat` or `typed`), `external_functions`, `generate_time`
(export and hashing), `compile_time` (mkoctfile, about 2-5 s on first use),
`run_time` (the compiled simulation), `assemble_time`, `delay_capacity` and
`capacity_retries`. The context is heap-allocated (`mxMalloc`) and the
simulation runs on a worker thread with a 64 MB reserved stack, because
evaluation and the integrators keep value-sized arrays on the stack (small
models with user Functions run on the main thread, see above). The MEX gateway was
verified with the Octave 11.3.0 MinGW toolchain on Windows; other platforms
use POSIX threads and are untested.

`benchmarks/benchmark_ob_accelerator.m` times accelerated against
interpreted runs (interleaved) on the shared benchmark set, reports export
and compile time separately, and compares with the recorded Simulink times
and outputs when `simulink-benchmark-reference.json` exists;
`test_ob_simulink_benchmarks` also checks every accelerated case against
Simulink with the interpreted tolerances and diagnoses. On 2026-11-21
(`benchmark_ob_accelerator (5)`, repository interpreter of that day, a
lightly loaded machine; Simulink times recorded earlier with
`reference_ob_simulink_benchmarks`, so compare them only roughly):

| Case | Interpreted | Accelerated (warm) | C simulation | Export + first compile | Simulink `sim()` | Fast Restart |
| --- | --- | --- | --- | --- | --- | --- |
| `oscillator_rk4` | 3.87 s | 23 ms | 1.1 ms | 0.16 + 1.8 s | 112 ms | 44 ms |
| `oscillator_ode45` | 2.82 s | 11 ms | 1.2 ms | 0.15 + 1.8 s | 99 ms | 30 ms |
| `dde_rk4` | 3.00 s | 13 ms | 2.1 ms | 0.17 + 2.0 s | 105 ms | 30 ms |
| `dde_ode45` | 3.06 s | 13 ms | 2.1 ms | 0.16 + 2.1 s | 97 ms | 26 ms |
| `mackey_rk4` | 17.5 s | 266 ms | 242 ms | 0.18 + 2.0 s | 113 ms | 36 ms |
| `mackey_ode45` | 13.5 s | 197 ms | 185 ms | 0.16 + 2.3 s | 106 ms | 46 ms |
| `conditional_rk4` | 4.91 s | 23 ms | 1.2 ms | 0.28 + 1.7 s | 129 ms | 31 ms |
| `linear10_rk4` | 3.38 s | 27 ms | 2.5 ms | 0.18 + 1.8 s | 107 ms | 31 ms |

Eight of the nine cases are accelerated (`control_zc_ode45` needs zero
crossings with ode45) and equal their interpreted runs (scaled error 0):
66-261 times faster. Apart from Mackey-Glass, warm calls took 11-27 ms here,
below Simulink's recorded warm Normal-mode `sim()` (97-129 ms) and close to
its Fast Restart (26-44 ms); most of such a call is Octave-side work (export
digest, result assembly; a Conditional Subsystem's per-sample core structs
are built in one vectorized step). On a heavily shared machine the warm
calls of earlier runs were two to four times longer, so the comparison with
Simulink holds only at a similar load. The Mackey-Glass cases spend almost all their time in about 20000
evaluations of the user `.m` Function (`ob_bench_mackey_term`), about 10-25
us each in Octave, and are 66-68 times faster than interpreted but slower
than Simulink, whose model computes the term in a compiled block. Their
difference from Simulink is the documented delay interpolation difference
(`test_ob_simulink_benchmarks`). The first call adds 0.15-0.3 s of export
and about 2 s of compilation (3-4.5 s under heavy load). In the final gate of
2026-11-22, on a loaded machine, `test_ob_simulink_benchmarks` measured warm
accelerated calls at 0.14-0.30 times Simulink's recorded warm `sim()` time,
and the two Mackey-Glass cases at 1.7 and 2.8 times.

## C API

Compile without `OB_STANDALONE` and include the generated source in a host
translation unit:

```c
#include "model.c"

int main(void) {
    ob_model model;
    if (ob_model_init(&model, 0.0) != OB_OK) return 1;
    if (ob_model_step(&model, 0.1) != OB_OK) return 2;
    /* Read model.value[] using the metadata arrays below. */
    return 0;
}
```

Each `ob_model` owns its state and outputs. There is no mutable global state or
heap allocation, so independent instances can be advanced independently. Host
code controls the output schedule by passing a strictly increasing finite
`next_time` to `ob_model_step`. Every step applies the same continuous/discrete
timing as `ob_run` with the corresponding output times. A shortened final
interval is supported. `ob_model_outputs` recomputes outputs at the current time.

Return codes are `OB_OK=0`, `OB_BAD_ARGUMENT=1`, `OB_NONFINITE=2`, and
`OB_INPUT_ERROR=3`. Typed exports additionally define `OB_EVENT_ERROR=4` for
nonsettling/chattering event regimes or exhausted event-progress limits.
Exports with Transport Delay blocks define `OB_DELAY_OVERFLOW=5` for a full
delay history and `OB_DELAY_SEGMENTS=6` when a gap would need more than 1e6
integration segments (where `ob_run` raises an error). ode45 exports define
`OB_STEP_FAILED=7` (see [Adaptive ode45 export](#adaptive-ode45-export)).
Exports made by `ob_accelerate` for user Functions define
`OB_EXTERNAL_ERROR=8`, `OB_EXTERNAL_SHAPE=9` and `OB_EXTERNAL_NONFINITE=10`.
Initialization and stepping commit the context only on success; failures leave
the previous context intact. Initialize before using a context, and check every return code.
Large models use proportionally large context and stack scratch arrays; host
applications must provide sufficient memory. Without Transport Delays,
`ob_model_init_inputs`, `ob_model_set_input_provider` and `ob_model_step`
each keep one copy of `ob_model` on the stack for rollback. With Transport
Delays they roll back in place and need only `OB_DELAY_CORE_BYTES` (the
context without its histories) plus a few value arrays; the CSV runner keeps
its context in static storage.

`OB_BLOCK_COUNT`, `OB_VALUE_COUNT`, and `OB_STATE_COUNT` describe the root flat
graph and its numeric value/state arrays. Conditional child state lives in
separate embedded typed contexts and is not part of the root numeric state
array. For each flat block (zero-based C array index), `ob_block_path[]` identifies its
path, `ob_block_rows[]`/`ob_block_cols[]` describe its shape,
and `ob_block_offset[]` identifies its first element in `model.value[]`.
CSV headers follow the same order, e.g. `b1/2_e1` is element 1 of block 2 inside
subsystem 1. All numeric flat blocks are logged, including boundary ports and scopes.
Conditional and multiple-Function core entries have zero rows/columns and no numeric channel. Internal
core/proxy paths contain zero; `info.signal_map` maps ordinary positive model
paths and output ports to numeric proxies. Inner atomic leaf signals are not
included in the root C value array or CSV.

Octave's returned `info` contains the same paths/shapes/zero-based value offsets
plus `signal_map`, whose output entries are one-based flat block IDs. This maps
logical subsystem output ports to their flattened Outport blocks. Parameters
are compiled constants; regenerate the source after changing them. Exported
symbols currently use the `ob_` prefix, so multiple separately generated models
cannot yet be linked into one executable without namespacing their symbols.
Every export includes `info.typed_conditional`; it is true for conditional
children and false for flat, event-only or multi-output models without them.
Every path also includes `info.zero_crossings` and `info.event_guard_count`,
which are false and zero respectively for ordinary event-off exports.
Their private child symbols have separate generated namespaces; the public
root API retains the `ob_` prefix.
Exports with enabled inner clocks define `OB_CLOCK_COUNT`, `ob_clock_period`,
`ob_clock_offset`, and `ob_clock_path` for the explicit clock tree. Their root
context owns `clock_tick`; child resets do not reset it. Export metadata
provides `info.clock_count` and `info.clocks` with path/rate entries. Temporary
`ob_clock_frame` pointers are function arguments, never retained in a context.
Those metadata fields are also present for flat exports. With no explicit
clocks, the count is zero and the inventory is an empty path/rate struct.
Equal rates on different blocks retain separate entries; this is a per-block
inventory, not a count of distinct period/offset pairs.
All export paths report `info.continuous_state_count`, counting continuous
scalar components across the entire context tree. When continuous children
require a shared solve, generated `OB_CONTINUOUS_COUNT` gives that total;
`OB_STATE_COUNT` continues to describe only the root numeric state array.

## External root input API

Configure root input shapes and default sampled data in Octave before export;
see [INPUTS.md](INPUTS.md). The generated CSV runner and ordinary
`ob_model_init` use those compiled tables. Their ZOH, linear interpolation,
endpoint holds, and knot boundaries match `ob_run`. Root input port data is
packed in numbered-port order, with each port's matrix elements in column
order. `OB_INPUT_PORT_COUNT` and `OB_INPUT_VALUE_COUNT` give the number of root
ports and packed scalar values. The zero-based C arrays `ob_input_offset[]`,
`ob_input_rows[]`, and `ob_input_cols[]` describe each numbered input port.
Octave export `info` includes `input_shapes`, zero-based `input_offsets`, and
`input_value_count` as well.

A host application can replace the tables with a time-dependent provider:

```c
typedef int (*ob_input_provider)(double time, int left, double *values,
                                 size_t count, void *user);
typedef double (*ob_input_event)(double after, double before, void *user);

int ob_model_init_inputs(ob_model *model, double start_time,
                         ob_input_provider provider, ob_input_event event,
                         void *user);
int ob_model_set_input_provider(ob_model *model, ob_input_provider provider,
                                ob_input_event event, void *user);
```

The provider must fill every one of `count == OB_INPUT_VALUE_COUNT` packed
values and return `OB_OK`. It is evaluated at output times and intermediate
RK4 stages. If `left` is nonzero, return the left-hand value at an exact
discontinuity; return the ordinary value when the signal is continuous. All
values must be real finite doubles. Callback errors map to `OB_INPUT_ERROR`;
nonfinite or unfilled entries produce `OB_NONFINITE`.

For discontinuous inputs, the optional event callback must return the earliest
boundary in `(after, before]`, or `before` when there is no earlier boundary.
It must return a finite value strictly greater than `after` and no greater
than `before`; otherwise stepping returns `OB_INPUT_ERROR`. This lets RK4 stop
at host signal discontinuities while preserving the requested output schedule.
The default tables automatically split at all their knots. A custom provider
with a NULL event callback is assumed continuous between caller output times;
the caller may also place every discontinuity on an output time explicitly.

For example, a smooth scalar forcing input `u(t) = t` can be supplied as:

```c
static int forcing(double time, int left, double *values,
                   size_t count, void *user) {
    (void)left; (void)user;
    if (count != 1) return 1;
    values[0] = time;
    return OB_OK;
}

/* After exporting a model with one scalar root Inport: */
/* ob_model_init_inputs(&model, 0.0, forcing, NULL, NULL); */
```

`ob_model_set_input_provider` changes an initialized model's provider and
recomputes its outputs at the current time without advancing state. Passing
`NULL, NULL, NULL` restores the compiled tables. Initialization, provider
changes, and steps commit the context only on success. Callbacks must be
deterministic and avoid side effects: they can run several times per interval,
and changes to caller-owned `user` data cannot be rolled back on failure.
Each instance has its own callback pointers and user pointer; host code is
responsible for the lifetime and thread safety of any shared user data.

Additional generation targets, implicit (ode15s) and typed adaptive solvers,
parameter tuning, arbitrary Octave-to-C compilation, and deployment
integration remain part of the advanced compatibility work.

Octave simulation can solve selected smooth algebraic loops, but C generation
continues to reject cyclic direct-feedthrough components before replacing an
output file. This restriction also appears in MathWorks' documented algebraic
loop limitations. See [ALGEBRAIC.md](ALGEBRAIC.md) for the supported simulation
scope and reference comparison.

## Transport Delay and Limited Integrator

Both blocks export on the flat path, with rk4 or ode45 (models without
conditional subsystems, multiple-output Functions or zero crossings). Inside a
conditional subsystem, with `zero_crossings=true`, or alongside blocks that
need the typed conditional/event exporter, export fails before replacing the
output file, as simulation does for the first two cases. The C gate compares
34 such models with `ob_run` (30 rk4, worst scaled error 0; 4 ode45, within
the ode45 tolerance below) and checks history overflow and byte-exact
rollback through the C API.

**Transport Delay.** Each delay keeps a ring buffer of accepted input samples
and reproduces `private/ob_transport_delay.m` and the delay segment loop of
`private/ob_runtime_integrate.m` operation by operation:

- Accepted hits record the right limit of the input; the end of every
  integration segment records the left limit, and an interior segment start
  records the right limit. A discontinuity is two samples at one time.
  Samples a few ulps apart (`same_instant`, the engine's time tolerance with
  the delay as spacing) merge into one instant.
- The output is the initial value before `start + T` and at its left limit,
  where `start` is the first recorded time (kept when old samples are
  pruned). Otherwise it is a cubic Hermite interpolation of the history at
  `t - T`, with slopes from the quadratic through each sample and its
  neighbours, never across a stored jump. A query at a sample's shifted time
  reads that sample exactly, including left limits.
- Samples older than `t - T` are pruned, except the two at or before it that
  interpolation needs.
- At the start of each scheduled interval, stored jumps plus `T` and
  `start + T` become segment boundaries, unless they are the same instant as
  an existing boundary (an output or clock time, a Step time, an input knot,
  another delayed jump). Every gap is then divided into equal segments no
  longer than the shortest delay, so RK4 stages only read recorded history.
  More than 1e6 segments in one gap return `OB_DELAY_SEGMENTS`, where
  `ob_run` raises an error.
- A scalar initial output is broadcast to the input's shape from the first
  sample; a scalar input is expanded to a matrix initial output's shape. As
  in `ob_run`, a scalar-initial delay learns its shape while every such delay
  still outputs its scalar initial value; a later change of shape is
  rejected at export.

Scalar `x^2` in the Hermite weights uses `pow()` with an opaque exponent:
Octave evaluates it with `pow`, and a compiler would otherwise substitute
`x*x`, which rounds differently with MinGW's `pow`.

**History capacity and rollback.** Histories are the last members of
`ob_model`. `ob_model_step` works on the context in place. It saves the
context without its histories (`OB_DELAY_CORE_BYTES`, which includes each
history's head and count) and the last two samples of each history, the only
stored samples a step can change in place. Within one step, appends never
reuse a slot that was live when the step began, and unused slots are kept
zero. A failed step is therefore undone byte for byte: the saved part is
restored and the appended slots are cleared. A successful step clears the
slots it pruned. Stack use and per-step cost do not grow with the capacity.
The remaining per-step cost grows with the live history, because each
scheduled interval scans it for delayed jumps, as `ob_run` does.

Capacity is fixed at generation time. It covers one delay window of samples
plus everything one host step records, estimated from the delay, the output
grid (the export `[start stop step]` grid, or the actual times for
`ob_accelerate`) and its longest step, explicit clocks, Step times, input
knots and the shortest delay, with one delayed discontinuity per instant. The
result is rounded up to a power of two (at least 64 samples).
`ob_delay_time[]` and `ob_delay_capacity[]` give each delay's time and
capacity.

The estimate is not a bound. Delayed jumps that feed back through delays,
for example `y = u + a y(t - 1) + b y(t - sqrt(2))`, keep multiplying. A host
whose steps are much finer, or much longer, than the export grid's can also
need more. A record that would overflow returns `OB_DELAY_OVERFLOW` and
leaves the context unchanged. Export with the host's own time grid, or use
`ob_accelerate`, which retries with doubled capacities. Exports whose
histories would need more than 256 MB are rejected.

**Limited Integrator.** The state starts at the initial condition clipped to
the limits, and the output is `min (max (x, lower), upper)` with Octave's tie
and signed-zero choices. Each RK4 step decides saturation from its initial
state: a component at its upper (lower) limit does not integrate upward
(downward), inward motion resumes at once, and the result is clamped.
Infinite limits export as `HUGE_VAL`. Resets are sampled at accepted hits
(output times and clock hits), from one side-effect-free evaluation after
pending discrete updates commit: `rising`, `falling` and `either` compare
the sign of the signal with its previous sample, `level hold` resets while
the signal is nonzero, and fixed-step `level` also resets at the first hit
after the signal returns to zero, as Simulink ode4 does. A nonzero `level`
or `level hold` signal holds the state during the step. The reset signal must
be scalar.

## Adaptive ode45 export

```octave
options = struct ('solver', 'ode45', 'reltol', 1e-8, 'abstol', 1e-10);
info = ob_codegen (ob_oscillator (), 'oscillator.c', [0 20 0.1], options);
```

Flat models (no conditional subsystems, multiple-output Functions or zero
crossings) export with an adaptive Dormand-Prince 5(4) integrator
(`ob_c_ode45_lines.m`) that ports Octave's own `ode45` as `ob_run` calls it,
so a compiled run follows the interpreted one step for step:

- **Segments.** Each scheduled interval (output times and clock hits) is
  split at Step times and input knots, and with Transport Delays also at
  delayed jumps and into pieces no longer than the shortest delay, exactly as
  for RK4. Every segment is one `ode45` call over `[begin, end]` with
  `MaxStep = min (maxstep, end - begin)`, `Refine = 1` and the model's
  `RelTol`/`AbsTol`; stages at or past the segment end are evaluated at the
  end with left limits (`adaptive_segment`/`adaptive_rhs`).
- **Algorithm.** `starting_stepsize` (norms of `y0`, `f(t0, y0)` and a
  difference quotient after one Euler step), Kahan-summed step times (the
  compensation is updated by rejected steps too, as in Octave), the
  `AbsRel_norm` error norm `max |y5 - y4| / max (AbsTol, RelTol max (|y|,
  |y_old|))`, acceptance at `err <= 1`, the step factor `min (1.5, max (0.8,
  0.38^(1/6) (1/(err + eps))^(1/6)))`, `MaxStep`, the `eps (t)` step floor,
  the clipped last step, first-same-as-last stage reuse and the 5000
  consecutive-rejection limit.
- **Arithmetic.** Stage sums `K (h a_k)'` are BLAS products in Octave. The
  generated sums use the order of Octave's OpenBLAS for up to three
  continuous states (one state: `ddot`, left to right; two or three: the
  generic `dgemv` kernel, which adds column pairs), so those models round
  identically. With four or more states OpenBLAS uses CPU-specific FMA
  kernels; the generated plain left-to-right sums agree to rounding.
- **Delays.** Every accepted interior point is kept in the context's
  `ode_t`/`ode_y` scratch, and after the whole segment evaluated and recorded
  (right limits, in order) into the delay histories, as `ob_run` records
  them. A segment with more accepted points than the history capacity
  returns `OB_DELAY_OVERFLOW`. Histories start four times larger than for
  RK4 (several accepted points per output interval at tight tolerances).
- **Limited Integrators** saturate on each evaluation's output and are
  clamped at accepted points; a `level` reset fires only while its signal is
  nonzero (the fixed-step rule that also resets when the signal returns to
  zero applies to `rk4` only), as in `ob_run`.
- **Failure.** If the step size underflows or 5000 consecutive steps are
  rejected before a segment end, `ob_model_step` returns `OB_STEP_FAILED=7`
  and leaves the context unchanged, where `ob_run` raises "ode45 failed to
  reach time ... with finite states".
- `integration_steps` (accelerated builds) counts accepted steps, as
  `ob_run` does; `info.solver` is `'ode45'`.

`ode15s` (implicit, variable order, Jacobian updates) is rejected before an
output file is replaced, as are `ode45` exports of typed models (the
conditional/event exporter is RK4 only) and `ode45` exports whose `reltol`,
`abstol` or `maxstep` is not a double (for example `single (1e-5)`): `ob_run`
takes its Dormand-Prince path, which the C port reproduces, only for double
settings, and otherwise runs Octave's `ode45` in the settings' class.

The C gate (`test_ob_codegen`, `verify_ob_codegen`) compiles ten ode45
models (oscillator with and without `MaxStep`, unaligned Step, root inputs,
explicit clocks, a tenth-order system, `x' = -x(t - 1)`, a delayed Step and
both Limited Integrator reset kinds) and compares them with `ob_run` at a
documented scaled tolerance of 1e-9, looser than RK4's 1e-11 because a
rounding difference that flipped one accept/reject decision would change
the trajectory at the level of the solver's local error (the cases use
tight tolerances to bound that). On the verified toolchain (Octave 11.3.0,
OpenBLAS 0.3.31 Haswell kernels, its GCC with `-O2`) the measured worst
scaled error is 0 for up to three states and 3.3e-16 for the tenth-order
system (the other 199 compared models in the same gate: 0; final gate of
2026-11-22, 222 compiled cases, 209 compared). The `api_ode45` harness checks
`OB_STEP_FAILED` and rollback for a blow-up `x' = x^2`.

## Event-enabled RK4 export

Pass the same event options used for Octave simulation:

```octave
options = struct ('solver', 'rk4', 'zero_crossings', true, 'maxstep', .1);
info = ob_codegen (ob_zero_crossing_example (), 'events.c', [0 1 1], options);
```

The public exporter selects the typed event runtime even for a model without
conditional children. Its metadata reports `info.zero_crossings=true` and
`info.event_guard_count`, the static registered-guard inventory size. Inactive
descendants may own inventory entries without contributing active guards.
`typed_conditional` describes conditional children, not whether events are on.

Trial RK4 stages freeze the incoming Switch/Saturation/Dead Zone regimes while
guards use raw source values. Located crossings settle outgoing modes before
continuing. Accepted continuous gates dispatch lifecycle changes separately
from clock hits; trials cannot commit child state or trigger history. Known
Step/input boundaries and explicit clocks split integration. Coincident clocks
execute once; primitive events do not consume unrelated inherited captures.

`maxstep` bounds searched RK4 segments independently of requested output times.
The default `Inf` does not add a bound. Sign-based detection cannot guarantee
all crossings or tangencies between samples; choose a bound appropriate to the
control frequency and dynamics. Localization does not make a coarse nonlinear
RK4 trajectory exact. See [ZERO_CROSSINGS.md](ZERO_CROSSINGS.md) for the model's
registered guards and [CONTINUOUS_CONTROLS.md](CONTINUOUS_CONTROLS.md) for gate
initialization, equality and plateau rules.

Event-enabled `ob_model` contexts contain cumulative `event_count` and
`last_event_time`; the latter is meaningful only when the count is nonzero.
Simultaneous guard records can increase the count more than once at one time.
There is no unbounded C event log and these fields do not replace the detailed
Octave `result.events` records. At a zero plateau ending on a requested stop,
the following advance may first establish and report the outgoing transition
at that previous stop. `ob_model_outputs` does not perform that forward search.

Event failures return `OB_EVENT_ERROR`; finite guard-subtraction overflow returns
`OB_NONFINITE`. Initialization, output evaluation, provider replacement and
steps preserve the complete caller context on failure, including nested states,
clocks and event memory. Callback effects outside the context cannot be rolled
back. A successful provider change recomputes current outputs without advancing
state or replaying past events.

A model declaring `execution.control='continuous'` requires
`zero_crossings=true`; omitting or disabling it fails before file replacement.
Adaptive (ode45) C solver selection is also rejected before replacement for
these typed exports; flat models may use it. Disabling
events on a model with only sampled controls selects ordinary RK4 behavior;
it does not assert equality with an event-enabled trajectory. General events,
adaptive solvers for typed exports and the broader gaps in
[COMPATIBILITY_GAPS.md](COMPATIBILITY_GAPS.md) remain unfinished.

## Independent sample clocks

Generated models preserve the per-block periods/offsets in `model.sample_times`.
Unit Delay and Discrete Integrator use pending simultaneous state commits;
Rate Transition samples in dependency order at its destination clock. An
explicit clock is independent of the CSV output interval or host step spacing.
Rows `[0 0]` retain caller-output scheduling. See [MULTIRATE.md](MULTIRATE.md)
for the exact first-hit, offset, collision, and held-state rules.

`ob_model_step` processes hidden sample hits before reaching the requested
time, splitting continuous integration as necessary. Input-only knots do not
trigger clock hits. Integer tick counters, pending states, and the clock origin
belong to each model instance and are rolled back if a step fails. C metadata
`ob_sample_period[]` and `ob_sample_offset[]` describes each flat block's
schedule. Export `info.sample_times` contains the same rows.

The kernel and C use the same epsilon-relative collision rule, including the
simulation origin to account for cancellation across zero. C returns
`OB_BAD_ARGUMENT` when a period/offset cannot make representable forward
progress, or a tick counter would lose integer precision. Sample periods are
compiled constants. This is deterministic, single-thread numerical scheduling;
multitasking data-integrity buffers, hardware scheduling, and the full Simulink
Rate Transition latency policies are not yet generated.
