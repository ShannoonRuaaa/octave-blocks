# 0.3.0 release validation

Release commit `7880a58` (`7880a5877e3229bf35e7417bed7c477bcbecc81b`) on
`main` was tested from fresh clones on the desktop test machine. This folder
is committed in the next commit, which adds only this folder and is tagged
`v0.3.0`.

**Windows** (Windows 11, GNU Octave 11.3.0 with its MinGW gcc 15.2.0,
PowerShell 7.7.0): `tests/Run-Tests.ps1` ran all 21 stages in one
uninterrupted run from a signed-in desktop session, 2026-11-24 05:28 to
06:20 UTC. Every stage exited 0, the source hashes were unchanged and the
manifest is `Complete`.

- `windows-manifest.json`: the runner's manifest. Absolute project paths are
  replaced with `<project>`; per-stage logs are not retained.
- `windows-source-hashes.json`: SHA-256 of the 306 tested `.m`/`.ps1`
  sources and package files. All 306 match the tagged tree.

**Linux** (WSL 2 Ubuntu 26.04.1, GNU Octave 11.3.0 built from the official
source with SUNDIALS 7.1.1, gcc 15.2.0): `tests/run-tests-linux.sh` ran the
20 non-editor stages, all exit 0, on 2026-11-26.

- `linux-summary.txt`: per-stage exit codes and durations.
- `linux-environment.txt`: revision, Octave, gcc and OS.

The reference suites assert their documented differences; passing stages do
not establish full Simulink parity. No speed figures were remeasured.
