# PR 4 validation evidence

`results.json` records twenty required stages with successful exit codes.
`source-hashes.json` identifies the final tested production/test code.
`transcripts.zip` retains both runs' stage specifications, logs and manifests;
absolute project paths in transcripts are replaced with `<project>`.

Baseline revision `84c458e` completed all twenty stages with seventeen passing.
The API, accelerator and installed-package stages failed because Windows'
MEX linker split temporary paths containing spaces. The only source changes
to revision `7cc42c7` were `inst/ob_accelerate.m` and
`tests/test_ob_accelerate.m`: relative compiler scratch paths, restoration of
the environment/current directory, and the corresponding regression.

The four affected stages (API, accelerator, installed package and shared
accelerated reference benchmarks) were rerun on `7cc42c7` and passed.
Both runs completed with unchanged source hashes. All other production/test
hashes are identical between revisions. This is complete stage coverage
across two runs, not one uninterrupted all-pass gate. The original failed
exit codes and linker diagnostics remain in the retained transcripts.

The reference suites assert their documented differences; a successful stage
does not establish full Simulink parity. No speed claims were remeasured.
Use `tests/Run-Tests.ps1` to reproduce the complete stage set with a supported
Octave/Qt/C99 toolchain. Test artifacts remain ignored under `.artifacts/`.
