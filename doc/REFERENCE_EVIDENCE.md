# Reference evidence

These records describe the evidence used during development. They do not prove
full MATLAB or Simulink compatibility. Behavioral references and the implemented
subset are described in [SIMULINK_REFERENCE.md](SIMULINK_REFERENCE.md).

## REA installation inspection

Two bounded, read-only Reverse Engineer Anything scans inspected the installed
support directory at `<MATLAB_ROOT>/toolbox/simulink`. The later scan used REA
6.8.0. The raw local bundles are excluded from this repository because they
contain machine-specific filesystem metadata; this is their sanitized summary.

| Field | Recorded value |
| --- | --- |
| Operation | `inspect_desktop_application` |
| Provider | `rea-artifact-graph`, version 1 |
| Authority / confidence | Shipped artifact / observed |
| Entry limit | 1,200 in the first scan; 1,500 in the conditional scan |
| Probe-byte limit | 8,388,608 |
| Entries examined | 237 in each scan |
| Files probed / payload bytes read | 0 / 0 |
| Runtime candidates / components | 0 / 0 |
| Coverage status | `complete-within-scan` |

The retained metadata digest in both scans was
`da561178dd037cdb2b1541d2f09be0dd19f48db6df82995021e2525aa5fe042c`.
It identifies retained paths and observed metadata, not the complete contents
of every file. These scans did not establish a loaded engine, runtime execution,
simulation algorithms, or source/build correspondence. No proprietary file
payload was read by these scans. The implementation is original Octave code.

## Recorded MATLAB numeric comparisons

[matlab-numeric-reference.json](../tests/reference/matlab-numeric-reference.json) records results
from MATLAB R2026b Update 1: 26 single-output builtin mappings, 15 two-output
cases, signed-zero checks, and rounding ties. The generator is
[reference_ob_matlab_numeric.m](../tests/reference/reference_ob_matlab_numeric.m). Routine Octave
tests compare against this retained reference; they do not rerun MATLAB.

<a id="live-simulink-references-2026-11-21"></a>

## Live Simulink references

[matlab-environment.json](../tests/reference/matlab-environment.json) is written by
[reference_ob_environment.m](../tests/reference/reference_ob_environment.m). It records MATLAB
R2026b Update 1 with Simulink 26.2 installed, a successful license checkout,
`load_system` available, and a small unsaved model that simulates to within
8.1e-11 of its analytic result. An earlier hand-made record reported no
Simulink. It relied on a license test alone, and the conditional harnesses
could not run anyway: R2026b rejects their From Workspace configuration until
`OutputAfterFinalValue` is set to `'Holding final value'`.

Each JSON file below is written by its producer in MATLAB, with Simulink
except for `reference_ob_dde.m` (MATLAB `dde23` only, no model), and compared
by an Octave test that does not run MATLAB. To regenerate a file, run its
producer with `reference/` as MATLAB's current folder, so the output replaces
the file the tests read; a bare or default file name is written to the current
folder. Every Simulink producer builds
unsaved temporary models and closes them without saving. On the evening of
2026-11-21 (local time; 2026-11-22 UTC) the 13 producers other than
`reference_ob_simulink_benchmarks.m` (the other eleven below, plus
`reference_ob_environment.m` and `reference_ob_matlab_numeric.m`) were rerun
in one MATLAB R2026b Update 1 session (26.2.0.3433840). Every
regenerated file was identical to the checked-in one except wall-clock timing
fields. `simulink-benchmark-reference.json` is kept from its own producer run,
because its timings need a quiet machine.

| Producer | Reference | Octave check |
| --- | --- | --- |
| [reference_ob_conditional.m](../tests/reference/reference_ob_conditional.m) | [simulink-conditional-reference.json](../tests/reference/simulink-conditional-reference.json) | `test_ob_simulink_conditional` |
| [reference_ob_combined.m](../tests/reference/reference_ob_combined.m) | [simulink-combined-reference.json](../tests/reference/simulink-combined-reference.json) | `test_ob_simulink_conditional` |
| [reference_ob_nested_reset.m](../tests/reference/reference_ob_nested_reset.m) | [simulink-nested-reset-reference.json](../tests/reference/simulink-nested-reset-reference.json) | `test_ob_simulink_conditional` |
| [reference_ob_conditional_probes.m](../tests/reference/reference_ob_conditional_probes.m) | [simulink-conditional-probes-reference.json](../tests/reference/simulink-conditional-probes-reference.json) (182 records, plus the Trigger block's InitialTriggerSignalState values) | `test_ob_simulink_conditional` |
| [reference_ob_conditional_outputs.m](../tests/reference/reference_ob_conditional_outputs.m) | [simulink-conditional-outputs-reference.json](../tests/reference/simulink-conditional-outputs-reference.json) (7 traces, 27 parameter probes) | `test_ob_simulink_extended`, `test_ob_simulink_api_reference` |
| [reference_ob_simulink_continuous.m](../tests/reference/reference_ob_simulink_continuous.m) | [simulink-continuous-reference.json](../tests/reference/simulink-continuous-reference.json) (50 cases, ode45/ode15s) | `test_ob_simulink_extended` |
| [reference_ob_simulink_multioutput.m](../tests/reference/reference_ob_simulink_multioutput.m) | [simulink-multioutput-reference.json](../tests/reference/simulink-multioutput-reference.json) (11 cases) | `test_ob_simulink_extended` |
| [reference_ob_simulink_inner_clocks.m](../tests/reference/reference_ob_simulink_inner_clocks.m) | [simulink-inner-clocks-reference.json](../tests/reference/simulink-inner-clocks-reference.json) (10 cases) | `test_ob_simulink_extended` |
| [reference_ob_simulink_delay_integrator.m](../tests/reference/reference_ob_simulink_delay_integrator.m) | [simulink-delay-integrator-reference.json](../tests/reference/simulink-delay-integrator-reference.json) (51 traces, plus dde23) | `test_ob_simulink_delay_integrator` |
| [reference_ob_simulink_api.m](../tests/reference/reference_ob_simulink_api.m) | [simulink-api-reference.json](../tests/reference/simulink-api-reference.json) | `test_ob_simulink_api_reference` |
| [reference_ob_dde.m](../tests/reference/reference_ob_dde.m) | [matlab-dde-reference.json](../tests/reference/matlab-dde-reference.json) (MATLAB `dde23`) | `test_ob_delay_matlab` |
| [reference_ob_simulink_benchmarks.m](../tests/reference/reference_ob_simulink_benchmarks.m) | [simulink-benchmark-reference.json](../tests/reference/simulink-benchmark-reference.json) (the nine shared benchmark cases: outputs and timings) | `test_ob_simulink_benchmarks` |

The comparisons and their results (final gate, 2026-11-22):

- **Conditional files:** `test_ob_simulink_conditional` matches all 304 cases
  with no documented differences: discrete traces exactly, ode45 within
  1.25e-13. That includes the trigger-only `compatibility` records, now run
  as `initial_control = 'compatibility'`, edge flags kept across ancestor
  resets, and 24 continuous triggers located by ode45.
- **Extended references:** `test_ob_simulink_extended` compares 78 cases; 75
  agree and 3 are documented differences. The 50 continuous cases (continuous
  Enable and trigger controls, and Switch, Saturation and Dead Zone crossings
  feeding Integrators, under ode45 and ode15s) agree within 1.3e-7 (the
  primitive crossings within 2e-8), and the crossing times Simulink locates
  match `result.events`. The 7 Outport-timing traces agree exactly, and
  the 11 multiple-output cases within the 1e-12 tolerance (8 exactly; the
  largest error, 1.8e-15, is in `virtual_three_ode4`), including per-port
  OutputWhenDisabled, scalar InitialOutput expansion and the Outport buffer
  shared by faster readers. Of the 10 inner-clock cases, 7 agree; the 3
  differences are Rate Transition transfer modes ([MULTIRATE.md](MULTIRATE.md)):
  deterministic slow-to-fast transfer, and data integrity off under ode4 and
  ode45.
- **Delay and integrator:** 22 cases agree, and 29 documented differences are
  asserted on both sides ([ADVANCED_EXTENSIONS.md](ADVANCED_EXTENSIONS.md#comparison-with-simulink)).
- **Command API:** 158 checks, covering library paths, BlockType/MaskType,
  Ports, parameter names and defaults (including the `built-in/<BlockType>`
  defaults), Outport and Enable parameter probes, error, solver-name and
  sim-output probes, and scenario outputs.
- **Benchmarks:** `test_ob_simulink_benchmarks` finds 4 of the 9 cases in
  agreement and 5 documented differences, in interpreted and in accelerated
  runs: Simulink's linear Transport Delay history interpolation (two
  delay-equation cases), the same difference amplified by chaos in
  Mackey-Glass after t = 17 (two cases), and Simulink ode4's on-grid Step
  rule in `linear10_rk4`. In the delay-equation and Step cases Octave Blocks
  is closer to the exact solution. Simulink's warm `sim()` takes 0.10–0.14 s on these cases (Fast
  Restart 0.026–0.046 s). The interpreter is roughly 25–165 times slower than
  warm `sim()` (32–165 in the final gate, 25–142 in
  [RUNTIME_PERFORMANCE.md](RUNTIME_PERFORMANCE.md) run D); warm accelerated calls take 0.14–0.30 times its time, except
  Mackey-Glass, whose `.m` Function is called back into Octave (about 2.2
  times).

Only the recorded scenarios are covered; see
[COMPATIBILITY_GAPS.md](COMPATIBILITY_GAPS.md) for the remaining evidence gaps.

## Verification artifacts

Historical artifact names in the roadmap and performance report use
`<TEMP>/...` to denote the originating machine's temporary directory. They
are provenance references, not files shipped with this repository. Test scripts
print fresh artifact directories when run; see [VALIDATION.md](VALIDATION.md).
