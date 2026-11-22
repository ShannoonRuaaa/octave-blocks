# Multiple Function outputs

Function blocks can expose several outputs from an ordinary Octave function.
In **Add Function** or **Edit Function**, enter the function name and a positive
integer output count. The block shows numbered pins. **Connect** prompts for a
source output port when there is more than one. Each evaluation calls the
function once with the declared number of returned values; its consumers then
read their selected ports.

```octave
model = ob_multioutput_example ();
result = ob_run (model, [0 1]);
values = ob_signal_values (result, 2, 1);
indices = ob_signal_values (result, 2, 2);
assert (isequal(values{end}, [3 8 -1]));
assert (isequal(indices{end}, [1 1 1]));
octave_blocks (model);
```

Programmatically, set `block.outputs`. Missing or empty values retain one
output. This field is independent of `block.value`, which remains ignored by
Function blocks for compatibility with older diagrams. A different output can
branch to several consumers or feed another input on the same consumer.
Reducing the count in the editor removes only wires from the deleted output
ports. Undo restores both the count and those wires.

Outputs may have different shapes. For example, the supplied
`ob_demo_multi_function` returns a scaled matrix, its transpose, and scalar
energy:

```octave
model.blocks(2).name = 'ob_demo_multi_function';
model.blocks(2).outputs = 3;
result = ob_run (model, 0);
energy = ob_signal_values (result, 2, 3);
assert (energy{1} == 88);
```

Input ports still supply arguments in destination-port order. The function
must implement the requested number of outputs. Invalid arity or user-code
failures stop simulation; failed resumable steps retain their previous state.
Consumer blocks retain their normal type/shape checks. Scope signals must keep
a fixed real numeric shape during a run. Functions should be deterministic
and free of external side effects because solvers also evaluate them at
intermediate stages.

## Hierarchy and persistence

Output counts, wires, and function names are saved with the model. Nested
virtual subsystems and conditional children preserve numbered function ports.
`ob_signal_values(result,path,port)`, `ob_scope_data(result,path,port)`, and
`ob_runtime_outputs(runtime,path,port)` read them by ordinary model paths.
`result.values` retains each root block's first output.

The compiler represents a multiple-output call as one nonnumeric core plus
numeric-capable output proxies. Internal paths contain zero. Use the signal
APIs instead of assuming every `result.flat_values` cell is numeric. Context
copies and MAT checkpoints retain the same mappings and all cached outputs.

## Generated C subset

C export currently supports one full finite real-double scalar/matrix input
and exactly two outputs for actual builtin `size`, `max`, and `min`:

| Function | Output 1 | Output 2 |
| --- | --- | --- |
| `size` | Row count | Column count |
| `max` | Default-dimension maximum | First-occurrence index, starting at 1 |
| `min` | Default-dimension minimum | First-occurrence index, starting at 1 |

Reductions use the first nonsingleton dimension. Rows and columns reduce to a
scalar; a matrix reduces each column to a row result. Strict comparisons keep
the first equal value, including its zero sign. Both results have fixed shapes.
The same operations work inside conditional children and stateful feedback.

Arbitrary Octave multi-output functions remain available in simulation but
cannot yet be translated to C. Other output counts, single-output reductions,
explicit reduction dimensions, additional signatures, N-D C arrays, and
shadowed implementations are rejected before replacing a source file. Existing
single-output C builtin mappings are documented in [CODEGEN.md](CODEGEN.md).

## Reference checks

The definitions are tracked against the public MATLAB references for
[size](https://www.mathworks.com/help/matlab/ref/double.size.html),
[max](https://www.mathworks.com/help/matlab/ref/double.max.html), and
[min](https://www.mathworks.com/help/matlab/ref/double.min.html).
MATLAB R2026b Update 1 produced 15 two-output cases covering scalars, rows,
columns, matrices, ties, and signed zero. Their retained values, indices,
dimensions, and zero-sign flags are checked by `test_ob_matlab_numeric`.
JSON input/output zero signs are recorded separately so serialization cannot
erase them. This proves measured agreement for those cases; it does not
establish agreement for every MATLAB signature or Simulink block.
