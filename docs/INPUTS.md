# External root inputs

Root Inport blocks receive supplied signals. Their positive, consecutive port
numbers select entries in the root model's `inputs` cell array. Nested Inports
continue to receive signals from their enclosing subsystem wires. Input data
belongs to the root model and is saved with it.

## Configure a sampled signal

```octave
model = ob_example ();
model.blocks(1).type = 'Inport';
model.blocks(1).value = 1;
model.inputs = {ob_input_signal ([0 0.5 1], [0; 1; 0], [1 1], 'zoh')};
result = ob_run (model, 0:0.1:1);
plot (result.t, ob_scope_data (result, 3));
```

`ob_input_signal(times, values, shape, method)` validates and normalizes a
dataset. The result has `t`, `values`, `shape`, and `method` fields. Times become
a column vector; each row of `values` contains one complete signal sample.
There must be one row per time and `prod(shape)` columns per row. Times must be
finite and strictly increasing. Samples must be full, finite, real doubles.
`shape` is a two-element positive-integer vector `[rows cols]`; it defaults to
`[1 columns(values)]`. The default method is `zoh`.
The constructor also accepts a scalar struct with `t` and `values` fields and
optional `shape`/`method` fields; it applies the same defaults and rejects
unknown fields. Simulation normalizes the input data without modifying the
supplied model, and records the normalized tables in `result.inputs`.

For a matrix signal, flatten each sample in Octave column order. This supplies
`[1 2; 3 4]` at time 0 and `[2 4; 6 8]` at time 1:

```octave
matrix_input = ob_input_signal ([0 1], [1 3 2 4; 2 6 4 8], [2 2], 'linear');
model.inputs{1} = matrix_input;
```

The downstream blocks must accept that matrix shape. In particular, an
Integrator's initial condition must have the same shape as its derivative.
Use `zeros(2,2)` for a two-by-two integrated state. A single sample specifies a
constant input for all simulation times.

Dataset positions follow port numbers, not block-array order. If a root Inport
with `value = 2` appears before the Inport with `value = 1`, it still receives
`model.inputs{2}`.

## Timing and interpolation

| Method | Between samples | At an input knot |
| --- | --- | --- |
| `zoh` | Holds the preceding sample. | Uses the new sample for outputs and discrete sampling. Continuous integration ending at the knot uses the previous sample's left limit. |
| `linear` | Interpolates each matrix component between adjacent rows. | Uses the supplied sample continuously. |

Before the first supplied time and after the last supplied time, the first or
last sample is held. Input coverage does not have to match the simulation
interval. Input shapes remain fixed throughout a run.

RK4, ode45, and ode15s split continuous integration intervals at input knots.
This preserves jumps even when an input changes between requested output
times. The extra internal boundaries do not update Unit Delay or Discrete
Integrator blocks. Explicit sample-time rows control their own clocks;
inherited `[0 0]` rows retain the requested-output schedule. See
[MULTIRATE.md](MULTIRATE.md).
For example, a held input that jumps at 0.35 seconds is integrated from exactly
that time even if outputs are requested only at 0, 0.3, 0.6, and 1 seconds.

`ob_input_value(signal, time)` evaluates a dataset directly. Its optional third
argument requests the left limit at that time, which is useful for inspecting
ZOH transitions. The simulation engine applies this rule at integration
segment endpoints automatically.

## Editor and persistence

Add numbered **Inport** blocks at the root, then use **Inputs** to configure
each root port. The dialog accepts Octave expressions for sample times, sample
rows, and shape, plus `zoh` or `linear` as the method. Expressions are evaluated
in the Octave base workspace when submitted. **Inputs** always configures root
data, including when the editor is displaying a subsystem's contents.

The editor stages all port datasets and applies them together. Cancellation or
an invalid entry leaves the previous configuration intact. The edits participate
in Undo/Redo and the unsaved-change marker. **Input demo** loads a model with a
sampled input feeding an Integrator and Scope.

Models may be saved before input data is configured. Simulation and C export
require a valid dataset for every root port. Extra datasets, malformed samples,
or input data attached to a nested subsystem are rejected. After changing root
port numbers or counts, update the input configuration to match.

```octave
model = ob_input_example ();
ob_save_model ('input-model.mat', model, [0 1 0.1]);
[model, settings, options] = ob_load_model ('input-model.mat');
result = ob_run (model, ob_time_grid(settings(1), settings(2), settings(3)), options);
```

## Generated C

Supported input tables, shapes, and interpolation are included in generated C
for standalone runs. A C host can supply replacement signals through the
generated input-provider API, including input-event boundaries for jumps.
The sampled-data and host input behavior, packing order, return codes, and
examples are documented in [CODEGEN.md](CODEGEN.md).

External sampled inputs do not trigger block sample hits themselves. Independent
sample times are configured through `model.sample_times`; a general event
system, broader data types, and arbitrary Octave callback inputs remain
compatibility work.

Run `test_ob_inputs` in Octave for scalar/matrix signal, interpolation,
discontinuity, discrete-timing, hierarchy, validation, and persistence checks.
