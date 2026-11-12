# Standalone C generation

Use **Export C** in the editor or call the exporter directly in Octave:

```octave
info = ob_codegen (ob_subsystem_example (), 'model.c', [0 10 0.1]);
```

The export uses the whole root model, including nested subsystems, and requires
`rk4` in simulation settings. It produces one C99 source file with a callable
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
| Integrator | RK4 with all continuous states integrated together; discrete states held during intermediate stages. |
| Subsystem, Inport, Outport | Virtual boundaries are flattened; explicit ports, branches, hierarchy, and multiple subsystem outputs are retained in metadata. |
| Conditional Subsystem | Sampled enabled/rising/falling/either execution with typed nested contexts, lazy initialization, and held/reset policies. Enabled bodies may contain continuous states and inherited or independent inner clocks. |
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
retain held output buffers between events. Active enabled continuous bodies
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

See [CONTROLS.md](CONTROLS.md) for nonlinear block equations and solver limits.
Switch evaluates both data branches; it does not gate execution of upstream
blocks. General zero-crossing events are not generated.

Arbitrary `.m` Function blocks, complex/integer/single/sparse/N-D parameters,
adaptive solver code, changing signal shapes, and unsupported block types are
rejected before replacing an output file. Functions whose runtime inputs leave
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
./Test-Codegen.ps1
./Test-Codegen.ps1 -OctaveHome 'C:\path\to\Octave-11.3.0'
./Test-Codegen.ps1 -Compiler 'C:\path\to\gcc.exe' -OutputDirectory './c-verification'
```

The script generates fixtures and Octave references, compiles with
`-std=c99 -O2 -Wall -Wextra -Werror`, runs each executable, and compares every
CSV signal channel against Octave. It also exercises the C API's independent
instances and error handling. It retains sources, binaries, references, CSVs,
and a manifest in the reported artifact directory. `Launch-Blocks.ps1 -SelfTest`
includes these compiled-code checks as well as the Octave test suites.

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

Return codes are `OB_OK`, `OB_BAD_ARGUMENT`, `OB_NONFINITE`, and `OB_INPUT_ERROR`. Initialization
and stepping commit the context only on success; failures leave the previous
context intact. Initialize before using a context, and check every return code.
Large models use proportionally large context and stack scratch arrays; host
applications must provide sufficient memory.

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
Exports containing conditional children also set `info.typed_conditional=true`;
exports using only multi-output functions set it to false.
Their private child symbols have separate generated namespaces; the public
root API retains the `ob_` prefix.
Exports with enabled inner clocks define `OB_CLOCK_COUNT`, `ob_clock_period`,
`ob_clock_offset`, and `ob_clock_path` for the explicit clock tree. Their root
context owns `clock_tick`; child resets do not reset it. Export metadata
provides `info.clock_count` and `info.clocks` with path/rate entries. Temporary
`ob_clock_frame` pointers are function arguments, never retained in a context.
Typed exports also report `info.continuous_state_count`, counting continuous
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

Additional generation targets, adaptive solvers, parameter tuning,
arbitrary Octave-to-C compilation, and deployment integration remain
part of the advanced compatibility work.

Octave simulation can solve selected smooth algebraic loops, but C generation
continues to reject cyclic direct-feedthrough components before replacing an
output file. This restriction also appears in MathWorks' documented algebraic
loop limitations. See [ALGEBRAIC.md](ALGEBRAIC.md) for the supported simulation
scope and reference comparison.

The simulation option `zero_crossings = true` is also rejected before output
replacement. The generated RK4 kernel currently evaluates control primitives
at its ordinary stages; it does not emit the event-localizing kernel described
in [ZERO_CROSSINGS.md](ZERO_CROSSINGS.md). Disable the option to export the
existing fixed-step behavior. This restriction is specific to the current
Octave Blocks exporter; it is not a Simulink code-generation restriction.

Models declaring `execution.control='continuous'` are also rejected, even when
`zero_crossings` is omitted or false. Turning off the event option cannot
silently reinterpret a declared continuous gate as sampled. See
[CONTINUOUS_CONTROLS.md](CONTINUOUS_CONTROLS.md).

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
