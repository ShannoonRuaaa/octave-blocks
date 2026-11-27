# Octave Blocks

**Build block diagrams. Run ordinary Octave functions. Export C99.**

[![Stage: preview](https://img.shields.io/badge/stage-preview-e6a23c)](https://github.com/ShannoonRuaaa/octave-blocks/releases)
[![GNU Octave](https://img.shields.io/badge/GNU%20Octave-11.3.0-0790c0)](https://octave.org/)
[![License: GPL--3.0--or--later](https://img.shields.io/badge/license-GPL--3.0--or--later-2b8a65)](LICENSE)

**Development verification note:** the release preparation changes on this
branch are not fully tested and will be verified on another machine. See
the [proposal review and verification plan](doc/V1_PROPOSAL_REVIEW.md) for
accepted changes, corrections and outstanding checks. The released version
remains 0.3.0.

Octave Blocks is a visual modeling and simulation project built around GNU
Octave. Connect continuous and discrete blocks, place your own `.m` functions
in the diagram, and inspect scalar, vector or matrix signals in a Scope.

![Octave Blocks editor displaying the oscillator feedback model](doc/images/editor.png)

[Download the preview](https://github.com/ShannoonRuaaa/octave-blocks/releases)
· [User guide](doc/USER_GUIDE.md)
· [Examples](#try-an-example)
· [Roadmap](doc/ROADMAP.md)
· [Report a problem](https://github.com/ShannoonRuaaa/octave-blocks/issues/new/choose)

## Start in a minute

Install **GNU Octave with Qt**. Verified on Octave 11.3.0 on Windows.
Download and extract a source release, or clone this repository.
Octave is installed separately; the download is not a standalone application.

From the extracted folder, launch the editor with PowerShell 7:

```powershell
./Launch-Blocks.ps1
```

Or open Octave and run:

```octave
cd ('/path/to/octave-blocks');
ob_setup ();
octave_blocks ();
```

Click a block to select it, **Connect** to wire two blocks, **Edit** to change
parameters, and **Run** to plot the result. **Oscillator** loads the feedback
example shown above. Save and load diagrams as Octave Blocks `.mat` models.
See the [user guide](doc/USER_GUIDE.md) for input data and subsystem editing.

## Install as an Octave package

For a packaged release, use Octave's package manager:

```octave
pkg install '/path/to/octave-blocks-0.3.0.tar.gz';
pkg load octave-blocks;
octave_blocks();
```

The package archive is produced by `tools/Package-Release.ps1`; older preview
ZIPs use the source-checkout instructions above. Browse the installed API
with `pkg describe -verbose octave-blocks`. See [package layout](doc/PACKAGE_LAYOUT.md)
and the [documentation index](doc/README.md).

The Simulink-style [command API](doc/SIMULINK_API.md) (`new_system`,
`add_block`, `add_line`, `sim` and related commands) is opt-in. After
`pkg load`, enable it with:

```octave
pkg load octave-blocks;
ob_simulink_setup ();
new_system ('loop');
```

In a source checkout, `ob_setup ('simulink')` does the same. The wrappers
deliberately take precedence over same-named functions on the path.

## What you can build

| Capability | Available on `main` |
| --- | --- |
| Visual modeling | Selection and dragging, numbered ports, nested diagrams, undo/redo and persistence |
| Simulation | RK4, Octave `ode45` and `ode15s`, explicit periods and offsets |
| Octave functions | Ordinary `.m` functions on the Octave path, including multiple outputs |
| Controls and hierarchy | Enabled/triggered subsystems, state/output policies, Saturation, Dead Zone, Switch and registered zero crossings |
| Linear systems | Continuous state-space and proper SISO transfer-function builders |
| C export | Static real-double C99 subset with RK4 and flat-model adaptive ode45, supported events and transactional APIs |
| Acceleration | Cached compiled MEX simulation for supported flat and conditional models; explicit fallback outside the subset |
| Additional blocks | PID and discrete-system builders, lookup tables, Transport Delay and Limited Integrator within the documented subsets |
| Library builders | Backlash, Quantizer, MinMax, Saturation/Dead Zone Dynamic, Sign, Coulomb & Viscous Friction, Relational and Logical Operators, Mux/Demux, Multiport Switch, Pulse Generator, Chirp, second-order integrator and Rate Transition modes, built from exportable primitives |
| Analysis | `ob_linearize` (linmod), `ob_findop` (trim), `ob_bode` (frequency response and margins) and `ob_stepinfo` |
| Programmatic modeling | Simulink-style construction, parameter and simulation commands (including `Dataset`-style outputs) with recorded reference comparisons |

This is an experimental independent project. Simulink `.slx`/`.mdl` file
interchange and full Simulink compatibility are unfinished. Arbitrary `.m`
functions run in Octave; export supports a documented subset of Function blocks.
See [supported exports](doc/CODEGEN.md) and [compatibility gaps](doc/COMPATIBILITY_GAPS.md).

The [advanced feature guide](doc/ADVANCED_EXTENSIONS.md), [command API](doc/SIMULINK_API.md)
and [validation record](doc/VALIDATION.md) describe the supported combinations.
The broader compatibility goal remains incomplete.

## Try an example

Run an oscillator without opening the editor:

```octave
model = ob_oscillator ();
result = ob_run (model, 0:0.02:12);
plot (result.t, ob_scope_data (result, 4));
xlabel ('Time (s)'); ylabel ('Position');
```

![RK4 oscillator output overlapping its analytical cosine reference](doc/images/oscillator.png)

Explore `ob_subsystem_example()`, `ob_multirate_example()`,
`ob_continuous_control_example()` and `ob_linear_system_example()`.
Open any model with `octave_blocks(model)`.

Export the oscillator to C:

```octave
ob_codegen (model, 'oscillator.c', [0 12 0.02]);
```

Compile the optional CSV runner with a C99 compiler:

```sh
gcc -std=c99 -O2 -DOB_STANDALONE oscillator.c -lm -o oscillator
```

On Windows use `-o oscillator.exe`. A compiler is required for C export
verification, not for ordinary interpreted simulation.

## Documentation and verification

| Start here | Read more |
| --- | --- |
| [User guide](doc/USER_GUIDE.md) | Editor controls, model construction and examples |
| [Runtime](doc/RUNTIME.md) · [Events](doc/ZERO_CROSSINGS.md) | Resumable execution and event handling |
| [Subsystems](doc/CONDITIONAL.md) · [Multirate](doc/MULTIRATE.md) | State policies and scheduling |
| [C export](doc/CODEGEN.md) | Supported blocks, compilation and model APIs |
| [Validation](doc/VALIDATION.md) | Dated test evidence, reproduction and limits |
| [Contributing](CONTRIBUTING.md) · [Review guide](doc/REVIEW_GUIDE.md) | Development and code review |

`tests/Run-Tests.ps1` is the local gate. It runs 21 stages: 13 Octave test
stages (including the embedded BIST checks and the recorded Simulink
reference suites), six strict C99 export stages, the package check and the
Qt editor checks. Each run writes a `manifest.json` with the git revision,
per-stage logs and exit codes. Dated results are recorded in
[VALIDATION.md](doc/VALIDATION.md); they are not a GitHub CI badge or a
claim of complete compatibility. Run locally:

```powershell
./tests/Run-Tests.ps1
```

All suites, reference fixtures and runners live in [tests/](tests/README.md).
Generated C, executables and logs default to ignored `tests/.artifacts/`.
`./Launch-Blocks.ps1 -SelfTest` remains a shortcut to the same runner.
The editor checks require a desktop session and Qt. See
[VALIDATION.md](doc/VALIDATION.md) for the full environment.

## Releases and license

[Releases](https://github.com/ShannoonRuaaa/octave-blocks/releases) provide
versioned source ZIPs, SHA-256 checksums and feature notes. Preview releases
are intended for experimentation. See [NEWS](NEWS) and
[release instructions](doc/RELEASING.md).

The combined distribution is [GPL-3.0-or-later](COPYING), including adapted
Octave solver code. Original MIT copyright and permission notices are retained
in [LICENSES/MIT.txt](LICENSES/MIT.txt). Adaptive generated C includes GPL-derived
solver code; see [licensing and provenance](doc/LICENSING.md). GNU Octave is a separate dependency.
Octave Blocks is not affiliated with GNU Octave or MathWorks. MATLAB and
Simulink are trademarks of The MathWorks, Inc.
