# Contributing

Bug reports, small reproducible models and focused fixes are welcome.
Include the Octave version, operating system, solver settings, expected
output and actual output. Attach a minimal model or `.m` script when possible.
For editor issues, describe the click target and steps. Remove private data.

## Develop a change

1. Create a focused branch from the intended target.
2. Read [REVIEW_GUIDE.md](doc/REVIEW_GUIDE.md) for engine/exporter architecture.
3. Run `ob_setup('tests')` (or add `tests/` to the Octave path) and run
   relevant `test_ob_*` suites; see [tests/README.md](tests/README.md).
   Exporter changes need compiled comparisons (`./tests/Test-Codegen.ps1`);
   editor changes need Qt interaction checks (`./tests/Test-Editor.ps1`).
4. Record actual commands, environment, results, skipped checks and limits.
5. Update documentation when behavior or limitations change, and add a line
   to [NEWS](NEWS), the single changelog, for user-visible changes.

The full Windows gate is `./tests/Run-Tests.ps1` with PowerShell 7,
GNU Octave with Qt, and a C99 compiler. Tests currently run locally;
there is no required GitHub CI status check yet.

Use Octave built-ins and maintained libraries where suitable. Preserve
independent instances, failure rollback, signal shapes, clocks and event order.
Keep formatting changes separate from behavior fixes.

`main` requires pull requests and resolved discussions, and disallows force
pushes and deletion. Draft PRs may contain work outside the released subset.
The source follows GNU Octave package conventions; see
[PACKAGE_LAYOUT.md](doc/PACKAGE_LAYOUT.md) for where new files belong.
