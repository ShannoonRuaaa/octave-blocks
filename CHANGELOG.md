# Changelog

## 0.2.0-preview.1

Source preview of the merged event-export milestone.

- Public C99 RK4 export for supported primitive and continuous-control events.
- Shared parent/child continuous stages, clocks and input callbacks.
- Transactional C APIs with failure and rollback checks.
- Input lookup, graph, numeric formatting and editor improvements.
- README images, analytical oscillator example, contribution guide and
  source-release packaging.

Requires a separate GNU Octave installation; verified on Octave 11.3.0 on
Windows. Does not include the accelerator or reorganization in draft PR #4.
Adaptive C solvers, arbitrary Octave-to-C translation and Simulink file
interchange remain outside this release.

See [VALIDATION.md](VALIDATION.md) for recorded milestone evidence and
[COMPATIBILITY_GAPS.md](COMPATIBILITY_GAPS.md) for remaining work.
