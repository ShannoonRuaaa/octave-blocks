# First release

This is the completed first-release record. Further work is tracked in
[ADVANCED_PLAN.md](ADVANCED_PLAN.md).

The release target is a usable Octave-native block simulator with a visual
editor. It supports the existing block library, fixed-step continuous and
discrete simulation, Octave functions, scopes, and portable model files.

Completed release work:

- [x] Validate models and settings before loading or simulating; preserve the
  current diagram when a file is invalid.
- [x] Add a blank diagram command and undo/redo for diagram edits.
- [x] Provide a direct launcher and a reproducible smoke check.
- [x] Verify the final editor in Octave and document limitations and examples.

Verification on 2026-11-06 with GNU Octave 11.3.0 on Windows:

- `Launch-Blocks.ps1 -SelfTest`: engine, model editing, matrix scopes, file
  roundtrip, invalid file/settings rejection, and preservation after an invalid save.
- Numerical checks: continuous oscillator against cos(t), integration across
  aligned and unaligned Step jumps, vector integration, ordered matrix product,
  Unit Delay feedback, discrete integration, and an ordinary custom .m function.
- GUI checks: standalone startup, blank diagram, undo/redo, dragging and undo
  of a move, unsaved title marker, status layout, oscillator loading and Scope plot.
- Earlier GUI verification: parameter editing and running the modified gain.

Advanced features outside this release: variable-step solvers, algebraic-loop
solving, multirate execution, subsystems, code generation, and Simulink file
compatibility.
