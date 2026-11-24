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
`test_ob_docs` (in the `audit` stage) checks that the README, CONTRIBUTING.md,
NEWS, DESCRIPTION, INDEX and Markdown docs are valid UTF-8, that their relative
Markdown links resolve, and that `doc/README.md` links every `doc/*.md` file.
`test_ob_package_layout` (also in `audit`) checks unique installed function
names, matching filenames and declarations, reachable help, and agreement
between `inst/`, its examples and opt-in wrappers, `INDEX` and `Contents.m`.

Set the environment variable `OB_SKIP_ACCELERATOR` to any non-empty value to
skip the accelerated comparisons in `test_ob_routing_builders` (for machines
where compiled MEX files cannot load, such as under Windows Smart App
Control). The suite prints each skipped case and counts fewer checks; a full
gate run must leave the variable unset.

## Release preparation checks

`test_ob_model_format` and `test_ob_api_contract` run in the
`release-contract` stage. They check versioned and legacy model loading,
failed-save preservation, invalid/future version rejection, the documented
API inventory and result fields, and the Qt preflight in a headless session.
`tests/Test-Launcher.ps1` checks launcher syntax and Windows argument quoting
without opening the editor; run it with PowerShell 7 and Windows PowerShell
5.1 on Windows.

Run the installed-package smoke check in a fresh Octave process, with GCC
and mkoctfile on PATH, without `ob_setup` or an existing loaded package:

```octave
addpath ('tests');
report = smoke_release ('/absolute/path/octave-blocks-0.3.0.tar.gz');
```

It isolates the package prefix and both package registries, compares RK4
and ode45 simulation, checks schema persistence and command-API Dataset
output, compiles standalone C99 and compares every exported numeric column,
checks MEX cache reuse/model edits, and verifies unload/uninstall. A JSON
report and generated files remain in a new `tests/.artifacts/` directory
(or a new explicit directory passed as the second argument).
`OB_SKIP_ACCELERATOR` skips MEX checks without claiming fallback was tested.
A successful smoke check with skips is not a full backend pass. The complete
release gates and another-machine run remain required before a release claim;
see [the review plan](../doc/V1_PROPOSAL_REVIEW.md).

On Linux, `tests/run-tests-linux.sh REPO OUTDIR [JOBS] [STAGE...]` runs the
same Octave stages, ports the strict C99 stages and the package check to
bash, and skips the Qt editor stage. It needs `octave-cli`, `mkoctfile`, `gcc`
and `git`; `ode15s` needs an Octave built with SUNDIALS IDA. Ubuntu 26.04's
`octave` package lacks it. To build Octave from source with SUNDIALS there,
install `libsundials-dev`, `libsuitesparse-dev` and `mpi-default-dev`
(Ubuntu's SUNDIALS headers include `<mpi.h>`), then run configure with
`CPPFLAGS=-I/usr/lib/x86_64-linux-gnu/openmpi/include`. Its summary must list
the SUNDIALS IDA, NVECTOR and SUNLINSOL KLU libraries. Put that Octave's
`bin` first on `PATH` when running the script.

The stage runner accepts `-Workers 1` through `-Workers 4` (default 2) and
optional `-Stages engine,api` for focused retries. Each run keeps a fresh
manifest, per-stage stdout/stderr, source hashes and exit codes under
`.artifacts/gate-*/`. Only a complete default run covers the full stage set;
focused retries have their own manifests. Concurrent checks do not produce
performance claims. The editor stage runs after other checks have finished.

The editor stage (`Test-Editor.ps1`) opens the Octave Qt GUI, so it needs a
signed-in desktop session. It fails at once with an explanation when started
in session 0 (over SSH or as a service), where the GUI would wait forever.
After a fresh Octave installation, open the Octave GUI once (the
GNU Octave (GUI) Start menu entry, or `octave-gui.exe --gui`) and finish its
"Welcome to GNU Octave" wizard, which saves `%APPDATA%\octave\octave-gui.ini`.
Until that file exists the stage stops before launching Octave with that
instruction; if the English wizard still opens during the stage, the runner
closes Octave and fails the same way instead of waiting for a click.
