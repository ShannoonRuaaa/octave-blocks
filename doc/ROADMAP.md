# Road to 1.0

Status: **draft**, reviewed 2026-11-24. Current version: 0.3.0 (tagged
`v0.3.0`; earlier tags are `v0.2.0-preview.1` and `v0.2.1-preview.1`).

The reviewed [release preparation proposal](V1_PROPOSAL_REVIEW.md) adds a
schema guard, API inventory and verification helpers. Those development
changes are not fully tested and will be verified on another machine;
milestones below still require their complete acceptance evidence.

1.0 is a stable, installable and honestly documented release of the
capability subset that exists today, plus a few thin mappings onto
primitives that are already verified. It promises:

- **Stable interfaces.** The public functions, the model-file schema and the
  result structures users script against are documented and frozen, with a
  deprecation rule.
- **Readable models.** A model saved by 1.0 loads in every later 1.x release,
  and files from 0.2.x and 0.3.0 load through a tested migration.
- **Stable results.** Within 1.x, the default results of a supported model
  change only for a documented bug fix named in [NEWS](../NEWS). New numerical
  behaviour ships as an opt-in.
- **Agreeing backends.** Within the documented subset, the interpreter, the
  accelerator and strict C99 export agree within stated tolerances, or refuse
  with an identified error. Nothing is silently substituted.
- **Verified platforms.** Windows and Linux are verified. macOS is either
  verified or labelled unverified.
- **Recorded evidence.** One all-pass gate manifest, bound to the commit just
  before the tag, is committed in the release tree.

1.0 does **not** mean full Simulink parity, and it adds no new simulation
semantics. Every remaining gap stays in
[COMPATIBILITY_GAPS.md](COMPATIBILITY_GAPS.md), the detailed ledger, and on
one user-facing limitations page.

**Current evidence.** On 2026-11-22 all 21 stages of `tests/Run-Tests.ps1`
passed on the Windows 11 desktop test machine at commit `b54eddc`, but across
three separate runs, and that evidence is not committed. The committed
[tests/validation/pr4/README.md](../tests/validation/pr4/README.md) covers 20
stages across two runs. The 0.3.0 entries in [VALIDATION.md](VALIDATION.md)
were run in `octave-cli` rather than through a full `Run-Tests.ps1` run.

## Release criteria

In this first draft, `[x]` means implemented, with the implementing document
or file linked; the 0.3.0 gate manifest re-confirms each one with run
evidence. `[ ]` items in this section block the release. Each has an
acceptance criterion and a size (S/M/L/XL).

### Validation and evidence

- [x] Stage runner. `tests/Run-Tests.ps1` writes `manifest.json` with the git
  revision, the Octave and PowerShell versions, SHA-256 hashes of the `.m` and
  `.ps1` sources, per-stage logs and exit codes. It marks a run complete only
  when every exit code is 0 and the hashes are unchanged. A clean tree is
  enforced only by the package stage.
- [x] Simulink 26.2 / R2026b reference traces and their MATLAB producer
  scripts are committed under `tests/reference`. The reference suites assert
  the documented differences instead of claiming parity
  ([COMPATIBILITY_GAPS.md](COMPATIBILITY_GAPS.md)).
- [ ] One uninterrupted all-pass gate on the release candidate commit.
  Acceptance:
  - `Run-Tests.ps1` also records the compiler version (`gcc --version`) and
    the `OB_SKIP_ACCELERATOR` value, refuses to run when that variable is set,
    and hashes `tests/reference/*.json`.
  - Every test added for a release criterion in this file, except the
    portable smoke test, runs in a `Run-Tests.ps1` stage.
  - The gate runs on commit R, where `DESCRIPTION` already says 1.0.0, from a
    fresh clone on the desktop test machine in a signed-in desktop session
    (the editor stage refuses session 0). The manifest has `Complete=true` and
    every stage exit 0. It is committed as R+1 under
    `tests/validation/v1.0.0/`, `git diff --name-only R R+1` lists only that
    directory, and the tag `v1.0.0` points at R+1. The manifest's revision
    equals R, and its source hashes equal the tagged tree.
  - A failed stage means fix, commit and rerun every stage. Partial reruns do
    not count.

  **M**
- [ ] Performance claims. Acceptance: every speed or timing figure in
  [CODEGEN.md](CODEGEN.md), [VALIDATION.md](VALIDATION.md) and
  [RUNTIME_PERFORMANCE.md](RUNTIME_PERFORMANCE.md) (for example 2.74x
  interpreted, 66–261x accelerated, the warm-call timings) is remeasured with
  the committed benchmark scripts, at least 5 repetitions with the median
  reported and the CPU, OS, Octave and compiler recorded in JSON under
  `tests/benchmarks`. Otherwise it is removed, or the file moves to
  `doc/archive/`. **S**

### Platforms

- [ ] Octave version policy. Acceptance: the interpreter always uses the
  ported Dormand–Prince `ode45` path, removing the exact
  `strcmp (OCTAVE_VERSION, '11.3.0')` gate in
  `inst/private/ob_dormand_prince.m`. [VALIDATION.md](VALIDATION.md) gains a
  "Tested Octave versions" table listing at least 11.3.0 (Windows) and the
  Linux smoke-test version. Each listed version passes an interpreted/C
  `ode45` agreement test, plus accelerated where the accelerator is supported
  on that platform, and the `DESCRIPTION` `Depends` lower bound equals the
  oldest listed version. **M**
- [ ] Portable smoke test. Acceptance: `tests/smoke_release.m`, which needs
  no PowerShell, passes on Windows and on Linux with the tested Octave
  version(s), on Linux from a pinned container image or build named in
  [VALIDATION.md](VALIDATION.md). It covers:
  - `pkg install` of a tarball given as an argument (the release tarball, or
    in CI a `git archive` tarball matching what `tools/Package-Release.ps1`
    builds)
  - `ob_oscillator` under rk4 and `ode45`
  - a 3-block command-API model built with `add_block`/`add_line` and run
    with `sim`
  - `ob_codegen` compiled with `-std=c99 -Wall -Wextra -Werror` and compared
    against the interpreter
  - `ob_run` with `accelerate` `'on'` wherever the accelerator is supported,
    compared against the interpreter; elsewhere `'on'` raises the identified
    error and `'auto'` records the interpreter fallback in the result
  - where the accelerator is supported, a model edit that must cause an
    accelerator cache miss (no stale binary)
  - `pkg unload` and `pkg uninstall`, leaving no API on the path

  The Linux run (distro, Octave and compiler versions) is recorded in
  [VALIDATION.md](VALIDATION.md). **M**
- [ ] Linux accelerator. Acceptance: the POSIX-threads gateway branch in
  `inst/private/ob_accelerate_gateway.m` compiles, loads and matches
  interpreted runs in the smoke test's `accelerate` `'on'` step. If it cannot, `ob_accelerate` raises an
  identified error off Windows, `'auto'` falls back, and the limitations page
  says the accelerator is Windows-only. **M**
- [ ] Continuous integration. Acceptance: a `.github/workflows/` job on
  Ubuntu, with the Octave version pinned as in the smoke test, runs
  `tests/smoke_release.m` and the headless api and builders suites on every
  pull request to main. `OB_SKIP_ACCELERATOR` is set unless the Linux
  accelerator criterion passed, and every suite in those stages honours it
  (today only `test_ob_routing_builders` reads it; `test_ob_nonlinear_builders`
  and `test_ob_simulink_api` run accelerated cases unconditionally). A passing run on the 0.9.0 and 1.0.0 tag
  commits is linked from [VALIDATION.md](VALIDATION.md); making it a required
  check is recommended. Today `.github/` holds only issue and pull request
  templates. **M–L**
- [ ] macOS decision. Acceptance: a recorded passing smoke run on macOS, or
  `DESCRIPTION` `SystemRequirements`, the README and the limitations page
  state "macOS: unverified". **S**
- [ ] Launcher and runner requirements. Acceptance: `Launch-Blocks.ps1` works
  on Windows PowerShell 5.1 (today it uses `ProcessStartInfo.ArgumentList`),
  or a `.cmd` launcher ships. `tests/*.ps1` and `tools/*.ps1` start with
  `#Requires -Version 7`. The launcher result is recorded in
  [VALIDATION.md](VALIDATION.md). **S**

### Install and first run

- [x] Reproducible package build. `tools/Package-Release.ps1` refuses a dirty
  tree and builds the archives from an exact commit with `git archive`, with
  `SHA256SUMS.txt` ([RELEASING.md](RELEASING.md)).
- [x] Installed-package test. `tests/Test-Package.ps1` installs into an
  isolated prefix, checks that test and private helpers are hidden, runs a
  model, C export, the accelerator and `ob_simulink_setup` with
  `new_system`, unloads, and checks that the API is gone.
- [x] Accelerator diagnostics. Writable-cache fallback and actionable load
  errors are implemented
  ([PROJECT_REVIEW_20261122.md](PROJECT_REVIEW_20261122.md), follow-up
  resolution).
- [x] Editor-stage preflight. `tests/Test-Editor.ps1` fails with an
  explanation in session 0 or before Octave's first-run wizard instead of
  hanging ([tests/README.md](../tests/README.md)).
- [x] Command API documented for installed use. The README,
  [SIMULINK_API.md](SIMULINK_API.md) and [USER_GUIDE.md](USER_GUIDE.md) show
  `ob_simulink_setup ()` after `pkg load`, and `Test-Package.ps1` builds and
  simulates a 3-block `add_block`/`add_line`/`sim` model after `pkg install`
  ([VALIDATION.md](VALIDATION.md), 2026-11-23 entry).
- [ ] Qt check. Acceptance: `octave_blocks` raises an identified error with
  remediation text when Qt graphics are not available, and a headless
  `octave-cli` test asserts the identifier. **S**

### Stability contracts

- [x] Models are validated before loading or saving. An invalid file leaves
  the current diagram intact, and saving writes a temporary file and renames
  it ([RELEASE_PLAN.md](RELEASE_PLAN.md); `inst/ob_save_model.m`).
- [ ] Versioned model files. Acceptance:
  - `ob_save_model` writes `format_version`. `ob_load_model` migrates files
    without the field and rejects newer ones with an identified error.
  - Fixtures under `tests/fixtures/models/`: editor models saved by
    `v0.2.0-preview.1`; editor, conditional, multirate and `ode45` models saved
    by `v0.2.1-preview.1`; the same set plus command-API models (via
    `save_system`) saved by 0.3.0; and a set saved by the 0.9.0 release
    candidate covering every shipped 1.0 target, a discrete-only model, an
    `ode15s` model and command-API solver settings that substitute a solver,
    re-saved by 1.0.0 as the reference for 1.x.
  - Each fixture stores the outputs its saving release computed. A test
    reloads every fixture with the current release and compares the maximum
    elementwise difference against 1e-12·max(1,|y|) for rk4 and discrete
    models, or ten times the solver's RelTol·max(1,|y|) for adaptive solvers,
    listing any documented intentional change. This same test enforces the
    readable-models and stable-results promises.
  - The schema is documented in `doc/MODEL_FORMAT.md`.

  **M**
- [ ] Frozen public API. Acceptance:
  - `doc/API.md` marks every function in `inst/`, `inst/simulink/` and
    `inst/examples/` as stable or experimental.
  - It documents the model struct, the `ob_run` result struct, the `sim`
    output struct (including the Dataset-like `yout`/`logsout` layout) and the
    `ob_scope_data` output, and a semver deprecation rule: removals only in a
    major release, after at least one minor release of identified warnings.
  - Package organization completed on 2026-11-24: `ob_is_combined_mode` and
    `ob_is_resettable_mode` are in `inst/private`, `ob_atomic_feedthrough` is
    marked experimental, and the duplicate `inst/ob_example.m` is removed.
  - Tests assert that `inst/`, `INDEX`, `inst/Contents.m` and `doc/API.md`
    list the same functions, and that the documented result fields exist.

  **M**
- [ ] Help text. Acceptance: every stable function returns at least a usage
  line, inputs, outputs and one example from `help`, and a test enforces it.
  `ob_run` documents every option and result field. The 2026-11-24 package
  cleanup filled the missing help blocks and made `octave_blocks` help
  reachable; `test_ob_package_layout` now checks that all installed functions
  have help. Complete argument/result/example coverage for the stable API
  remains part of this milestone. **M**
- [ ] No silent substitutions. Acceptance: when the command API runs `ode23`,
  `ode113`, `ode23s`, `ode23t` or `ode23tb` with another solver, or
  `FixedStepAuto` with RK4, it raises the identified warning
  `ob_simulink:SolverSubstituted` naming the substitute (`ode1`, `ode2` and
  `ode3` stay rejected). The fallback under `accelerate` `'auto'` is recorded
  in the result. A nonfinite C-mapped signal in an accelerated run raises
  `octave_blocks:accelerate_runtime`, also under `'auto'` (this already
  holds); a nonfinite user Function result falls back under `'auto'` by
  design, and that fallback is recorded as above. Tests assert all three.
  **S**
- [ ] Identified rejections. Acceptance: errors for unsupported library
  paths, unsupported parameters and backend-subset refusals carry identifiers
  listed in `doc/API.md`, including the known per-backend gap (MinMax
  `Inputs` 1 runs in Octave and the accelerator but is not exported by
  `ob_codegen`). A static test fails on unidentified errors in
  `inst/private/ob_require_runtime_support.m`, the `ob_codegen` subset checks,
  `inst/ob_accelerate.m` and the `add_block`/`set_param`/`sim` parameter
  handling in `inst/ob_simulink.m`. A full sweep of every error is not
  required. **M**
- [ ] Validation errors name the block. Acceptance: model-validation errors
  (`ob_validate_model`, unconnected inputs, dimension mismatches,
  algebraic-loop rejection) name the block and port, and a test asserts the
  name appears. **S–M**

### Documentation

- [x] Command API reference. [SIMULINK_API.md](SIMULINK_API.md) gives a
  library-path table with BlockType, parameters and defaults, the Dataset
  layout, and the differences from Simulink, including installed-use setup.
- [x] Licensing and provenance. The project is GPL-3.0-or-later, with the
  Octave `ode45` derivation documented and the original MIT grant kept
  ([LICENSING.md](LICENSING.md), [NOTICE](../NOTICE)). `Test-Package.ps1`
  asserts the SPDX header in generated adaptive C.
- [ ] One user-facing limitations page. Acceptance: `doc/LIMITATIONS.md`
  states:
  - the platform matrix and the Octave-version policy for `ode45`
  - the C export and accelerator subsets (accelerated `ode45` only for flat
    models; MinMax element reduction not exported to C; nonfinite C-mapped
    signals fail accelerated runs, while nonfinite user Function results fall
    back under `'auto'`)
  - each major unsupported Simulink feature with a workaround: buses,
    non-double types, logical and relational outputs as double 0/1, `ode1` to
    `ode3`, Fcn expressions and the MATLAB Function block,
    function-call/atomic/If/Switch Case subsystems, `.slx`/`.mdl`, unconnected
    inputs, non-finite signals, and options rejected on existing blocks
  - editor limits: no zoom or pan, builder and library blocks script-only
    unless library insertion lands, no re-editing of builder parameters
  - saving Dataset results: MAT files need the handles removed and
    `ob_simulink ('dataset', s)` to rebuild them

  Function-call triggers are listed as not implemented:
  `inst/private/ob_execution_mode.m` has no such mode, while
  [COMPATIBILITY_GAPS.md](COMPATIBILITY_GAPS.md) lists them only as a missing
  trace. **M**
- [x] Contradictions and stale text fixed, with a lint test. Fixed: the
  `ode45` C export statements in [USER_GUIDE.md](USER_GUIDE.md), the Rate
  Transition `Integrity`/`Deterministic` entries in
  [SIMULINK_API.md](SIMULINK_API.md), the README gate counts, the stale
  versions in RELEASING.md and PACKAGE_LAYOUT.md, the `inst/` statement in
  PACKAGE_LAYOUT.md, the reorganization note in CONTRIBUTING.md and the
  `0x92` byte in README.md. `tests/test_ob_docs.m` (audit stage) checks that
  tracked text files are valid UTF-8, that relative links resolve, and that
  [doc/README.md](README.md) links every doc
  ([VALIDATION.md](VALIDATION.md), 2026-11-23 entry).
- [ ] Structured user guide. Acceptance:
  - [USER_GUIDE.md](USER_GUIDE.md) has sections for install (Windows, Linux),
    first model (editor), first model (script), results (including saving
    Dataset output), C export, the accelerator, upgrade and uninstall
    (`pkg install` over an older version, the model migration note,
    `pkg uninstall`, and where the accelerator cache lives and how to delete
    it), and troubleshooting (the first-run wizard, Qt, the compiler, Smart
    App Control, the cache).
  - A tutorial example in `inst/examples/` is run by a test.
  - Developer material moves to [tests/README.md](../tests/README.md).
  - Dated audits and plans move to `doc/archive/` and are excluded from the
    package with `.gitattributes` `export-ignore`.

  **M**

### Release mechanics

- [ ] Versioning and changelog. Acceptance:
  - [NEWS](../NEWS) is the single changelog, with CHANGELOG.md folded in and
    its labels corrected (the 0.2.1 entry becomes `0.2.1-preview.1`, which
    is tagged, not "development").
  - Every release is tagged and published with `SHA256SUMS.txt`.
  - The README install instructions name a released file.
  - [RELEASING.md](RELEASING.md) states the semver and stable-results
    policies.

  **S**

## 1.0 targets

These add user value on primitives that are already verified, with no engine
change. They are planned for 1.0 but do not block it: anything unfinished at
the 0.9.0 release candidate moves to After 1.0 and gets a line on the
limitations page.

- [ ] Zero-Order Hold, Memory and Delay (N samples, with InitialCondition).
  Acceptance:
  - `add_block` maps them onto a Rate Transition with an explicit period, an
    inherited-rate Unit Delay and a Unit Delay chain.
  - Zero-Order Hold with `SampleTime` -1 and Memory driven by a continuous
    signal raise identified errors, listed in
    [SIMULINK_API.md](SIMULINK_API.md); Memory is accepted only in discrete
    contexts. Other unsupported options also raise identified errors.
  - Each block is checked against at least 3 recorded Simulink cases (from the
    licensed MATLAB machine) or, if it is unavailable, a closed-form
    difference equation with the gap noted, in interpreted, accelerated and C
    runs.
  - Each block has a row in the SIMULINK_API.md library table.

  **M**
- [ ] External input data. Acceptance: `sim` accepts `LoadExternalInput` and
  `ExternalInput` (an `[t u]` matrix or a struct with time), and From
  Workspace is accepted with `VariableName`, `SampleTime` 0, `Interpolate` on
  and `OutputAfterFinalValue` "Holding final value" or "Extrapolation"; other
  parameters raise identified errors. Both map onto root Inports fed by
  `ob_input_signal` ([INPUTS.md](INPUTS.md)), whose interpolation is
  documented in SIMULINK_API.md. API tests match an equivalent
  `ob_input_signal` model at zero tolerance. **M**
- [ ] Editor library insertion. Acceptance: an "Add library block..." action
  lists the `add_block` library paths, prompts for parameters with their
  defaults, and inserts the block through the builder code that `ob_simulink`
  uses. An editor test covers Transfer Fcn, PID Controller and Sum `'+-'`
  against the same models built with `add_block`. **M**

## Intermediate releases

The release candidate is numbered 0.9.x so that plain version comparison
orders it before 1.0.0. Full gates run on the desktop test machine only.

1. **0.3.0: release what exists.** Fix the stale and contradictory docs and
   the README encoding. Document `ob_simulink_setup` and extend
   `Test-Package.ps1` to a 3-block `add_block`/`add_line`/`sim` model.
   Reconcile NEWS and
   CHANGELOG. Record one full gate manifest, then tag and publish `v0.3.0`.
   This also produces the 0.3.0 model fixtures.
2. **0.4.0: stability contracts.**
   - model `format_version`, migration and fixtures
   - `doc/API.md`, the index and result-field tests, and help text
   - solver-substitution warnings, identified rejections and block-naming
     validation errors
   - removing the 11.3.0 `ode45` gate
   - the gate-runner changes: compiler version and `OB_SKIP_ACCELERATOR`
     recorded in the manifest, refusal when that variable is set, and hashes
     of `tests/reference/*.json`
   - the Qt check and the launcher and runner requirements
3. **0.5.0: platforms, targets and docs.**
   - the portable smoke test with a Linux run, the tested-Octave-versions
     table and the `Depends` bound, the Linux accelerator check or its
     fallback, CI, and the macOS decision
   - the 1.0 targets: Zero-Order Hold, Memory, Delay, external input and
     editor library insertion
   - LIMITATIONS.md, the user guide restructure, the doc archive and
     `export-ignore`
   - the performance claims, remeasured or removed
4. **0.9.0: release candidate.** Code freeze, with only bug and doc fixes
   accepted. Unfinished 1.0 targets move to After 1.0. Run the full gate from
   a fresh clone on the desktop test machine, run `tests/smoke_release.m` on
   Windows and Linux against the candidate tarball, re-run the fixture loads,
   and save the 0.9.0 fixture set.
5. **1.0.0.** Bump the version and write the NEWS heading. Run the gate at
   the commit just before the tag and commit its manifest under
   `tests/validation/v1.0.0/`, as in the gate criterion. Build the release
   tarball with `tools/Package-Release.ps1`, run the package and smoke tests
   against it, re-save the fixtures as the 1.x reference set, then tag and
   publish it with `SHA256SUMS.txt`.

## After 1.0

The "Next acceptance milestones" in [COMPATIBILITY_GAPS.md](COMPATIBILITY_GAPS.md)
and sections 2–5 of "Next work" in
[PROJECT_REVIEW_20261122.md](PROJECT_REVIEW_20261122.md) continue as post-1.0
tracks. All items below are additive in a 1.x release unless noted.

- Further library mappings: Discrete Filter, Discrete Zero-Pole, Transfer Fcn
  First Order and Lead or Lag, Discrete FIR, Moving Average, Discrete
  Derivative, Bias, Unary Minus, Rounding, Compare To Constant/Zero, Sum and
  Product of Elements, and extra Math Function operators. Each needs its own
  traces.
- Sources: Random Number, Band-Limited White Noise, Repeating Sequence, Signal
  Generator, Derivative, Digital Clock and sample-based Sine Wave. Some depend
  on solver step semantics.
- Option gaps in existing blocks: Relational `isInf`/`isNaN`/`isFinite`,
  Logical Operator `Inputs` 1, vector Backlash widths, Multiport Switch
  `DiagnosticForDefault`/"Specify indices"/NaN controls, Integrator
  Second-Order options and its Limited variant, zero or per-element Transport
  Delay times, and signal-width inference. Most are rejected today, mostly
  without error identifiers (identifiers are a 1.0 criterion). Multiport
  Switch `DiagnosticForDefault` Warning/Error is accepted but not enforced,
  and signal widths are declared rather than inferred: `sim` reports a
  mismatch.
- Fixed-step `ode1`/`ode2`/`ode3` with a matching `FixedStepAuto`. They need
  implementing in the interpreter, C and the accelerator; 1.0 keeps rejecting
  them and warns when `FixedStepAuto` runs RK4.
- Discrete `SampleTime` on Constant, Step and Sine, full sample-time
  propagation and algebraic-block rate propagation. This is a scheduling
  redesign; discrete source sample times are rejected today
  ([SIMULINK_API.md](SIMULINK_API.md#differences-from-simulink)).
- Rate Transition Integrity/Deterministic parity for inherited and
  discrete-to-continuous rates, and the unprobed buffer cases. These remain
  asserted documented differences ([VALIDATION.md](VALIDATION.md)). Any
  change of default ships as an opt-in.
- Limited Integrator limits and ExternalReset located at events instead of at
  samples, and Transport Delay and Limited Integrator inside conditional
  bodies or zero-crossing runs (rejected today by
  `ob_require_runtime_support`). Both need an event-priority specification
  first.
- General zero crossings for Abs, Relational and Function outputs, and
  multiple or tangential crossing policies. These would change the results of
  existing models, so they ship as opt-ins.
- Adaptive solver continuity, Refine output, `ode15s` C export and adaptive
  conditional/event C. The current restart-at-output behaviour is documented
  and deterministic.
- Accelerator and C coverage: `ode15s` acceleration; `ode45`, user-Function
  callbacks, Transport Delay and Limited Integrator in models that need the
  typed exporter; broader Function and multi-output signatures in C; build
  system integration. `'auto'` falls back for these today.
- Function-call subsystems, atomic subsystems with feedthrough scheduling and
  state-broken feedback across atomic boundaries, continuous and nested
  resettable subsystems, vector enable/trigger controls, and If/Switch
  Case/For Each/Merge. All are new execution semantics.
- Algebraic loops: broader loop blocks, atomic hierarchy analysis,
  sparse/analytic Jacobians and large-loop performance. The current smooth
  fixed-shape solver and its diagnostics are the 1.x contract.
- Fcn expressions (`u^2+3*u`) and an inline MATLAB Function block. These need
  an expression parser and a C translation story; the workaround is a `.m`
  Function block.
- Editor usability: palette, re-editing builder parameters, names and values
  on block faces, zoom and pan, choice widgets, per-scope windows, structural
  subsystem editing (create from selection, port reordering), and settings
  carried through `open_system`. The file format is covered by 1.0, so the UI
  can change freely.
- Error messages that name blocks by path everywhere, and a full sweep of
  error identifiers.
- Unconnected inputs fed 0 with a warning, and Inf/NaN propagation. The
  current fail-fast behaviour is safe and documented.
- Simulink.SimulationOutput, Dataset and timeseries classes, To Workspace
  Timeseries, signal logging names, per-signal logging rates, and
  SaveState/LoadInitialState. The struct outputs are usable and can be
  layered on later.
- Linearization of discrete, delay and conditional states, operating-point
  specifications, linearization I/O points, and trim's "as close as possible"
  targets and DX0/IDX. Discrete states raise `ob_linearize:unsupported`
  today.
- Codegen symbol namespacing, tunable parameters, algebraic loops in C, and
  emitter hooks in place of the regex patching in `ob_accelerate.m`.
- A full Windows gate in CI, the editor stage under xvfb, other Octave
  versions, and clang/MSVC compiles, once the Linux smoke path exists.
- Texinfo help and `%!` BIST blocks in `inst/`. Plain help text meets the 1.0
  bar.
- Evidence gaps that need the licensed MATLAB machine or extra toolboxes:
  live traces for variable-step combined or nested continuous controls and
  resettable subsystems; multirate traces for offsets, first hits,
  disable/re-enable, reset and coincident events; MATLAB
  bode/margin/stepinfo comparisons (Control System Toolbox not installed).
- Research: the Octave control package and CBLAS.

## Out of scope

- Full Simulink parity. It is unreachable for this project, and 1.0 is a
  documented subset.
- Simulink `.slx`/`.mdl` load and save. These are proprietary, versioned
  formats, and the native `.mat` format is the 1.x contract.
- Buses, non-double data types (boolean, integer, single, fixed-point) and
  complex signals. These change the real-double signal model that every block
  and the C emitter assume, so they are a 2.x line.
- Stateflow, Simscape, toolbox libraries, model reference and variant
  subsystems. These are separate products.
- Implicit DAEs and mass matrices in 1.x. A stiff/DAE solver library backend
  (for example SUNDIALS) needs its own licensing review and is at most a
  research item; `ode15s` on explicit ODEs is the 1.x ceiling.
- Multitasking, asynchronous scheduling and preemption. Deterministic
  single-tasking execution is a design property.
- Deployment targets, SIL/PIL/external modes, Rapid Accelerator, standalone
  executables and Simulink Coder parity. Strict C99 source and the MEX
  accelerator are the deliverables.
- Bit-for-bit equality across compilers, platforms and Octave versions.
  [CODEGEN.md](CODEGEN.md) disclaims it, and the contract is agreement within
  tolerance.
- Arbitrary translation of Octave `.m` code to C. It is open-ended; user
  Functions stay interpreted, or are called back from the accelerator.

## How to update this file

From 0.3.0 onward, tick a box only in the same change that adds the
supporting evidence (a dated [VALIDATION.md](VALIDATION.md) entry naming the
revision, or a committed manifest) and link it in the note. Moving an item between Release criteria,
1.0 targets, After 1.0 and Out of scope needs a one-line reason in the pull
request. Keep detailed per-area status in
[COMPATIBILITY_GAPS.md](COMPATIBILITY_GAPS.md), not here.
