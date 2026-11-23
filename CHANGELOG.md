# Changelog

## 0.3.0 (development)

- Integrate advanced simulation into the Octave package layout.
- Add cached compiled acceleration, flat adaptive C export, delay and
  limited-state blocks, command APIs and recorded reference comparisons.
- Distribute the combined project under GPL-3.0-or-later, with solver
  attribution, generated-code notices and retained original MIT grants.
- Add writable-cache fallback and actionable accelerator-load diagnostics.
- Use neutral project branch names and current documentation references.
- Add Simulink library builders (Backlash, Quantizer, MinMax, Saturation and
  Dead Zone Dynamic, Sign, Coulomb & Viscous Friction, Relational and
  Logical Operators, Mux, Demux, Multiport Switch, Pulse Generator, Chirp
  Signal, Integrator Second-Order, Rate Transition modes, first-order
  filters) with recorded Simulink 26.2 comparisons, C export and
  accelerator checks.
- Add `ob_linearize`, `ob_findop`, `ob_bode` and `ob_stepinfo`.
- Map the new blocks in the command API and support `SaveFormat`
  `'Dataset'` (Dataset-like `yout` and `logsout`).
- Make the Qt editor test stage fail fast with an explanation instead of
  hanging in session 0 or behind Octave's first-run welcome wizard.

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
