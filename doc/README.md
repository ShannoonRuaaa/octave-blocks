# Documentation

## Using Octave Blocks

- [User guide](USER_GUIDE.md): editor, diagrams, inputs and examples.
- [Runtime](RUNTIME.md): simulation and resumable state.
- [Inputs](INPUTS.md), [controls](CONTROLS.md), [linear systems](LINEAR_SYSTEMS.md).
- [Subsystems](CONDITIONAL.md), [continuous controls](CONTINUOUS_CONTROLS.md),
  [combined enable and trigger controls](COMBINED_CONTROLS.md),
  [multirate scheduling](MULTIRATE.md), [multiple outputs](MULTIOUTPUT.md).
- [Events](ZERO_CROSSINGS.md), [algebraic systems](ALGEBRAIC.md),
  [C export](CODEGEN.md).
- [Advanced builders](ADVANCED_EXTENSIONS.md): PID, linear systems, the 0.3.0
  Simulink library builders and the
  [linearization and analysis functions](ADVANCED_EXTENSIONS.md#linearization-and-analysis).
- [Simulink-style command API](SIMULINK_API.md), including
  [Dataset output](SIMULINK_API.md#dataset-output).
- [Simulink cross-reference](SIMULINK_REFERENCE.md): Simulink concepts and
  their Octave Blocks status.

## Developing and reviewing

- [Licensing and solver provenance](LICENSING.md): GPL distribution and retained MIT notices.
- [Package layout](PACKAGE_LAYOUT.md): where code belongs and why.
- [Review guide](REVIEW_GUIDE.md), [validation](VALIDATION.md),
  [release packaging](RELEASING.md).
- [Road to 1.0](ROADMAP.md): release criteria, intermediate releases and scope.
- [Compatibility gaps](COMPATIBILITY_GAPS.md) and [advanced plan](ADVANCED_PLAN.md).
- [C event runtime architecture](EVENT_CODEGEN_DEVELOPMENT.md): the typed
  event runtime behind `ob_codegen` and its regression guide.
- [Runtime performance](RUNTIME_PERFORMANCE.md), [UI performance](UI_PERFORMANCE.md),
  [benchmark reproduction](../tests/benchmarks/README.md).
- Historical reviews: [optimization audit](OPTIMIZATION_AUDIT.md),
  [PR2 audit](PR2_AUDIT.md), [built-ins](BUILTIN_REVIEW.md),
  [reference evidence](REFERENCE_EVIDENCE.md),
  [style review](STYLE_REVIEW.md) (2026-11-10),
  [reorganization review](PROJECT_REVIEW_20261122.md) (2026-11-22),
  [first release record](RELEASE_PLAN.md).
