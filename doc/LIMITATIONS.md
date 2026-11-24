# Limitations and workarounds

**These development changes are not fully tested and will be verified on
another machine.** The current released package is 0.3.0. This branch adds
release preparation work; it does not establish a verified 1.0 release.
Detailed feature gaps remain in [COMPATIBILITY_GAPS.md](COMPATIBILITY_GAPS.md).

## Platforms and numerical assumptions

| Platform | Evidence and remaining work |
| --- | --- |
| Windows x86_64 | Earlier 0.3.0 gates are recorded in [VALIDATION.md](VALIDATION.md). This branch has only the focused checks listed in [V1_PROPOSAL_REVIEW.md](V1_PROPOSAL_REVIEW.md); another-machine verification is pending. |
| Linux x86_64 | Earlier Octave 11.3.0/SUNDIALS gates are recorded in VALIDATION.md. New CI uses an official Octave 11.3.0 image; its result must be checked separately from prior results. |
| macOS | Unverified. No new platform claim is made. |

The package depends on GNU Octave 11.3.0 or newer. The bundled optimized
Dormand-Prince implementation is selected only on the exact version it
reproduces, 11.3.0, and for supported double settings. Other versions use
the host `ode45`. Removing that guard would require numerical comparisons
on each added version; this branch retains it. `ode15s` also needs SUNDIALS
IDA in the host Octave build. The editor requires a desktop Qt session.

## C export and acceleration

`ob_codegen` supports real-double static-shape models: RK4 for flat and
supported conditional/event models, and adaptive `ode45` for flat models.
It rejects `ode15s`, adaptive conditional/event models, algebraic loops,
arbitrary user `.m` Functions and single-input MinMax reduction.

The accelerator covers flat RK4/ode45 models, supported typed RK4 models
and user `.m` callbacks on its flat path. Typed ode45, algebraic loops,
and Transport Delay/Limited Integrator inside conditional/event exports
remain gaps. `accelerate='auto'` can fall back on unsupported/unavailable
builds or exhausted delay capacity. C-mapped nonfinite results still fail;
nonfinite user Function results can fall back. Raw `ob_run` does not add a
fallback-reason result field; command-API simulation records fallback
diagnostics in `SimulationMetadata.ExecutionInfo`.

`smoke_release` checks only a small installed model set. Skipping MEX with
`OB_SKIP_ACCELERATOR` is reported as a skip, not a tested fallback or a full
backend pass. See [CODEGEN.md](CODEGEN.md) for the detailed supported subsets.

## Other gaps and workarounds

| Feature | Current behavior and workaround |
| --- | --- |
| Simulink `.slx`/`.mdl` files | Unsupported; use Octave Blocks MAT models. |
| Buses and broader signal types | Full bus/type support is absent; use explicit numeric signals and Mux/Demux where appropriate. Relational/logical builders produce double 0/1. |
| Fixed-step `ode1`/`ode2`/`ode3` | Rejected. Use `ode4` (RK4) or supported adaptive solvers. |
| Other solver names | `ode23`/`ode113` map to `ode45`, `ode23s`/`ode23t`/`ode23tb` to `ode15s`, and `FixedStepAuto` to RK4. The proposed identified substitution warning is still absent. |
| Rate Transition modes | Require explicit input/output rates through the builder or API extension. Integrity-off continuous consumers still see an output-rate hold. |
| Function-call and broader subsystem families | Not implemented; sampled/continuous enable, trigger and supported reset modes cover only their documented cases. |
| General inline MATLAB code | Unsupported; use `.m` Functions on the Octave path, with exporter limitations. |
| Unconnected required inputs | Rejected; connect an explicit input such as a Constant. |
| Dataset-like results in MAT files | Function handles must be removed and rebuilt with `ob_simulink('dataset', s)`, or use Octave binary/text serialization. |
| Historical model compatibility | Synthetic legacy cases are covered; real model fixtures from every old release and future 1.x guarantees remain unverified. |

Proposed stability and deprecation rules are in [API.md](API.md). Remaining
release criteria are tracked in [ROADMAP.md](ROADMAP.md).
