# Optimization measurements

`optimization-20261113.json` contains the recorded timing samples, analytical
checksums, CPU times, integration steps and event counts used in
[OPTIMIZATION_AUDIT.md](../OPTIMIZATION_AUDIT.md). Version 1 is baseline `8aeec48`;
version 2 is the optimized source. The baseline's benchmarked runtime, graph,
input and editor files also match the published `2ae43f3` release. Use that public
commit as the reproduction baseline; `8aeec48` identifies the original local
measurement checkout. The optimized production files on `codex/optimized-release`
are identical to the measured development version.

Three rounds alternate A/B/B/A and B/A/A/B, giving six samples for each version
and workload. The comparison scripts clear functions and assert the loaded
source path between versions. Runtime cases warm up before every timed run.
UI cases warm up both versions initially, create fresh hidden figures, and
exclude initial figure creation/drawing from each twelve-click measurement.

Use a fresh Octave process and two source directories. For example, in Octave:

```octave
baseline_source = '/path/to/baseline';
optimized_source = '/path/to/optimized';
output_directory = fullfile (optimized_source, 'validation-out');
run (fullfile (optimized_source, 'benchmarks', 'compare_runtime.m'));
```

Run `compare_ui.m` the same way under Octave's Qt GUI runtime. The figures are
hidden and cleaned up. For a focused runtime check, set `comparison_cases` to
a subset such as `{'sampled','input100000'}` before running the script.

For simpler measurements in separate processes, use
`benchmark_ob_optimizations(source, output_json, repetitions)` from the optimized
source directory. Separate-process wall times showed substantial drift on the
test machine, so the final report uses the interleaved measurements instead.
Avoid concurrent tests or benchmarks. Small differences and these few models
do not establish universal speed guarantees.
