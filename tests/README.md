# Tests

All test suites, case builders, verification scripts and embedded regression
checks live here. `reference/` holds the MATLAB producer and recorded data.
Generated C, executables, CSV output and editor logs default to ignored
`.artifacts/` subdirectories. Each Octave suite temporarily redirects its
scratch environment to `.artifacts/scratch/` and restores it afterward.
Existing fixture cleanup continues to remove temporary models and files.

Run the complete Windows gate from the project root:

```powershell
./tests/Run-Tests.ps1
```

`./Launch-Blocks.ps1 -SelfTest` delegates to this same runner.
For a focused suite in Octave:

```octave
addpath('tests');
test_ob_run();
test_ob_editor_core();
```

Each suite temporarily adds the installed API in `inst/`, examples and private helpers it needs,
then restores the previous path. Normal application startup does not load tests.
Run a focused C gate with `./tests/Test-Codegen.ps1`, or the Qt gate with
`./tests/Test-Editor.ps1`. These resolve the production path from the script
location and do not require running from the repository root.

The `test_ob_*_bist.m` files contain the regression checks formerly embedded
in production files; their wrapper functions check that every case passed.
`test_ob_multi_function`, `test_ob_inner_clock_c_cases` and several codegen
case files are fixtures, not standalone test commands.

Set the environment variable `OB_SKIP_ACCELERATOR` to any non-empty value to
skip the accelerated comparisons in `test_ob_routing_builders` (for machines
where compiled MEX files cannot load, such as under Windows Smart App
Control). The suite prints each skipped case and counts fewer checks; a full
gate run must leave the variable unset.

The stage runner accepts `-Workers 1` through `-Workers 4` (default 2) and
optional `-Stages engine,api` for focused retries. Each run keeps a fresh
manifest, per-stage stdout/stderr, source hashes and exit codes under
`.artifacts/gate-*/`. Only a complete default run covers the full stage set;
focused retries have their own manifests. Concurrent checks do not produce
performance claims. The editor stage runs after other checks have finished.
