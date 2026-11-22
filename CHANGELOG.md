# Changelog

## 0.2.1 (development)

- Adopt GNU Octave package layout and metadata for `pkg install` and `pkg load`.
- Group shared internals under `inst/private/`, public functions under `inst/`,
  and runnable examples under `inst/examples/`.
- Fold the compiler-only multiple-output shape helper into its caller.
- Move guides and project records into `doc/`, with a documentation index.
- Add installable `.tar.gz` archives alongside source ZIPs in release packaging.

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

See [VALIDATION.md](doc/VALIDATION.md) for recorded milestone evidence and
[COMPATIBILITY_GAPS.md](doc/COMPATIBILITY_GAPS.md) for remaining work.
