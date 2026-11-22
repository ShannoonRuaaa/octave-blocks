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

Each suite temporarily adds the production root and private helpers it needs,
then restores the previous path. Normal application startup does not load tests.
Run a focused C gate with `./tests/Test-Codegen.ps1`, or the Qt gate with
`./tests/Test-Editor.ps1`. These resolve the production path from the script
location and do not require running from the repository root.

The `test_ob_*_bist.m` files contain the regression checks formerly embedded
in production files; their wrapper functions check that every case passed.
`test_ob_multi_function`, `test_ob_inner_clock_c_cases` and several codegen
case files are fixtures, not standalone test commands.
