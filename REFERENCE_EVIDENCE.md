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

[matlab-numeric-reference.json](matlab-numeric-reference.json) records results
from MATLAB R2026b Update 1: 26 single-output builtin mappings, 15 two-output
cases, signed-zero checks, and rounding ties. The generator is
[reference_ob_matlab_numeric.m](reference_ob_matlab_numeric.m). Routine Octave
tests compare against this retained reference; they do not rerun MATLAB.

[matlab-environment.json](matlab-environment.json) records that MATLAB ran but
Simulink and `load_system` were absent. A positive feature-license test did not
establish an installed engine. The live subsystem comparison harness,
[reference_ob_conditional.m](reference_ob_conditional.m), remains unverified
against Simulink in this environment.

## Verification artifacts

Historical artifact names in the roadmap and performance report use
`<TEMP>/...` to denote the originating machine's temporary directory. They
are provenance references, not files shipped with this repository. Test scripts
print fresh artifact directories when run; see [VALIDATION.md](VALIDATION.md).
