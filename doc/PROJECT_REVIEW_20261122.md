# Reorganization review and next milestones — 2026-11-22

## Follow-up resolution

The implementation now uses the native Octave package layout from main.
The owner selected GPL-3.0-or-later distribution with original MIT notices
retained; solver provenance and generated-code terms are in LICENSING.md.
Default accelerator compilation succeeds with the desktop toolchain;
writable-cache fallback and load diagnostics are implemented. The new
revision-bound stage runner writes source hashes, per-stage logs and exit
codes under tests/.artifacts/. The earlier review below remains a dated
record; its branch labels use the current neutral naming.

## Assessment

This is a substantial engine and compatibility advance beyond the previously
verified advanced builders and sampled reset milestone. It is still a partial
Simulink implementation. Case counts measure selected scenarios, not a
percentage of the full product.

The review examined branch `feature/advanced-simulation`, HEAD `3089021`,
including its staged moves and unstaged/untracked implementation. The index
contains 212 file moves with no line changes; working files add the behavior.
Comparing only committed history would miss most of the new work. No source
or existing staged changes were changed by this review.

## What advanced

| Area | Previously verified | Current source and evidence |
| --- | --- | --- |
| Organization | Root-level source, tests and documentation | `inst/`, `inst/private/`, `tests/`, `doc/`, `examples/`, `reference/`, `benchmarks/`, `tools/`; `ob_setup` selects paths, with Simulink command wrappers opt-in. Launchers and test scripts use the new layout. |
| Blocks | PID/linear/lookup/sampled discontinuity builders and sampled reset modes | Transport Delay history and interpolation, Limited Integrator bounds and sampled reset including level variants; flat C support. |
| Programmatic modeling | Octave model structs | Simulink-style construction, parameters, wiring, simulation and inspection commands; recorded parameter/default comparisons. |
| Execution | Interpreted RK4/ode45/ode15s and RK4 C | Cached compiled MEX acceleration, flat adaptive ode45 C, callbacks to Octave for user Functions in flat accelerated models. |
| Conditional behavior | Enable/trigger combinations and nested state policy | Trigger initialization modes, per-output disabled policies, scalar output expansion, source-rate output buffers and new Simulink comparisons. |
| Evidence | Analytical tests; earlier direct Simulink checks unavailable | Checked-in Simulink 26.2 traces, producer scripts and replay tests. They supersede the earlier availability limitation for these recorded cases; MATLAB was not rerun during this review. |

## Fresh verification in this review

- Setup path BIST: 3/3 passed.
- Runtime fast-path regression suite: passed.
- Transport Delay and Limited Integrator: 65 analytical cases passed.
- Command API: 69 cases passed with an explicit writable accelerator cache.
- Recorded Simulink command-API comparison: 158 checks passed.
- Conditional reference replay: 304 matched, worst absolute error
  1.25011e-13, with no documented differences in that suite.
- Delay/Integrator Simulink replay: 22 cases agree, 29 documented
  differences reproduced. A successful test here preserves those
  differences; it does not mean all 51 cases match Simulink.
- Oscillator acceleration: RK4 and ode45 each matched interpreted scope
  values within 1e-10; both reused the compiled cache on the second call.
- Selected extended references: 10 agree; one diagnosed deterministic
  Rate Transition difference remains (maximum absolute discrepancy 2.5).
  Its alternate model reproduces the recorded Simulink trace exactly.
- Reorganized `tests/Test-Codegen.ps1`: all 222 strict C99 compilation/run
  cases passed; 209 numerical models compared against Octave, worst scaled
  error 3.33e-16. Includes adaptive ode45, Transport Delay overflow and
  rollback, callbacks, clocks, nested conditional states and failure retries.
  Artifacts: `.validation-artifacts/reorganization-review-codegen-20261122`
  (ignored local directory).

The first command-API run failed an assertion that acceleration was active,
after printing `Access is denied` with the default cache location. The direct
accelerator checks above used an explicit temporary cache and succeeded. An
API rerun with that temporary cache passed all 69 cases. This isolates the
observed failure to the default environment/cache path rather than the
tested simulation behavior; default-cache failure diagnostics merit review.

The full new GUI, C and accelerator suites were not all rerun here. Historical
results in `VALIDATION.md` are the other model's records, not fresh passes.
That report explicitly describes three nonzero job statuses and rewritten
logs; it does not establish one clean, revision-bound full gate. Performance
claims (2.74x interpreted, 66–261x accelerated on selected benchmarks) were
not remeasured. Current benchmark JSONs retain older optimization runs;
new timing evidence is described through originating temporary artifacts.

## Next work, in order

### 1. Make this tree reviewable and its validation reproducible

Freeze the complete working tree as a concrete revision, preserving moves,
new reference files and new implementation files. Run the reorganized
launcher end to end, keeping numerical, compiled and GUI exit codes separate
and propagating every failure. Record source hashes, commands, tool versions,
case counts, skipped cases and known differences in a machine-readable
manifest. Retain the raw new benchmark measurements with workload/settings
and source identifiers; repeat them on a quiet machine before restating speed
claims. Check documentation links and startup from a clean clone.

Acceptance: a clean checkout reproduces setup, all registered required gates
and GUI selection/run/export checks without relying on ignored temporary files.

Before publishing the solver additions, establish their source/license
provenance. `ob_dormand_prince.m` and `ob_c_ode45_lines.m` describe reproducing
or porting Octave source; the installed `ode45.m` carries GPL-3-or-later
notices, while the repository LICENSE is MIT. Determine derivation and
applicable notices/terms for both shipped and emitted code. This review has
not resolved that release question.

### 2. Close the measured scheduling and buffer gaps

Implement the recorded deterministic and integrity-off Rate Transition modes.
Probe inherited-rate expressions of slow states read by faster blocks, and
clocked blocks that drive no Outport before their first execution. Add exact
Simulink traces for offsets, first hits, disable/re-enable, reset and coincident
events. Separate intentional numerical conventions from unsupported semantics.

Acceptance: the three extended Rate Transition discrepancies become asserting
matches, with equivalent interpreted, C and accelerated behavior where supported.

### 3. Finish hybrid state semantics across execution backends

Support Limited Integrator and Transport Delay inside conditional bodies and
event-enabled runs, followed by typed C and accelerator support. Add continuous
resettable subsystems, event-located Integrator resets and conditional reset
descendants. Specify event priority, reset versus clock coincidence, accepted
history updates and rollback before extending emitters.

Acceptance: independent analytical trajectories plus recorded Simulink cases,
including sparse/dense outputs, boundaries, retries and nested inactive bodies.

### 4. Unify adaptive execution and compilation

Address solver history continuity between requested outputs. Extend adaptive
compilation to conditional/event models; select a maintained solver library for
stiff/DAE support after verifying headers, binaries and deployment requirements.
Keep support explicit for ode15s, algebraic loops and user Function callbacks.
Replace accelerator string/regular-expression patching of emitted C with
explicit emitter hooks for event records, step counts and callbacks.

Acceptance: event times, outputs and failures match the interpreter; rollback,
cache invalidation, delay capacity recovery and repeated model instances pass.
Add Linux/macOS gateway checks before claiming portability.

### 5. Expand interoperability after the core is stable

Add logging/dataset/SimulationOutput compatibility, model references and file
interchange in separately scoped milestones. Add function-call trigger and
continuous combined-control reference traces. Keep broader Stateflow,
Simscape and toolbox support explicitly outside completed milestones.

Recommended immediate milestone: **reviewable reorganization with a clean
validation manifest, then Rate Transition parity**. This closes a known
observable mismatch while strengthening the foundation for subsequent work.
