# Octave Blocks

**Build block diagrams. Run ordinary Octave functions. Export C99.**

[![Stage: preview](https://img.shields.io/badge/stage-preview-e6a23c)](https://github.com/ShannoonRuaaa/octave-blocks/releases)
[![GNU Octave](https://img.shields.io/badge/GNU%20Octave-11.3.0-0790c0)](https://octave.org/)
[![License: MIT](https://img.shields.io/badge/license-MIT-2b8a65)](LICENSE)

Octave Blocks is a visual modeling and simulation project built around GNU
Octave. Connect continuous and discrete blocks, place your own `.m` functions
in the diagram, and inspect scalar, vector or matrix signals in a Scope.

![Octave Blocks editor displaying the oscillator feedback model](docs/images/editor.png)

[Download the preview](https://github.com/ShannoonRuaaa/octave-blocks/releases)
· [User guide](docs/USER_GUIDE.md)
· [Examples](#try-an-example)
· [Roadmap](COMPATIBILITY_GAPS.md)
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
addpath (pwd ());
octave_blocks ();
```

Click a block to select it, **Connect** to wire two blocks, **Edit** to change
parameters, and **Run** to plot the result. **Oscillator** loads the feedback
example shown above. Save and load diagrams as Octave Blocks `.mat` models.
See the [user guide](docs/USER_GUIDE.md) for input data and subsystem editing.

## What you can build

| Capability | Available on `main` |
| --- | --- |
| Visual modeling | Selection and dragging, numbered ports, nested diagrams, undo/redo and persistence |
| Simulation | RK4, Octave `ode45` and `ode15s`, explicit periods and offsets |
| Octave functions | Ordinary `.m` functions on the Octave path, including multiple outputs |
| Controls and hierarchy | Enabled/triggered subsystems, state/output policies, Saturation, Dead Zone, Switch and registered zero crossings |
| Linear systems | Continuous state-space and proper SISO transfer-function builders |
| C export | Static real-double C99 subset with RK4, supported events, input callbacks and transactional model contexts |

This is an experimental independent project. Simulink `.slx`/`.mdl` file
interchange and full Simulink compatibility are unfinished. Arbitrary `.m`
functions run in Octave; export supports a documented subset of Function blocks.
See [supported exports](CODEGEN.md) and [compatibility gaps](COMPATIBILITY_GAPS.md).

The newer accelerator, adaptive C export, Transport Delay, Limited Integrator
and reorganized source layout are under review in
[draft PR #4](https://github.com/ShannoonRuaaa/octave-blocks/pull/4).
They are not included in the `main` preview release.

## Try an example

Run an oscillator without opening the editor:

```octave
model = ob_oscillator ();
result = ob_run (model, 0:0.02:12);
plot (result.t, ob_scope_data (result, 4));
xlabel ('Time (s)'); ylabel ('Position');
```

![RK4 oscillator output overlapping its analytical cosine reference](docs/images/oscillator.png)

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
| [User guide](docs/USER_GUIDE.md) | Editor controls, model construction and examples |
| [Runtime](RUNTIME.md) · [Events](ZERO_CROSSINGS.md) | Resumable execution and event handling |
| [Subsystems](CONDITIONAL.md) · [Multirate](MULTIRATE.md) | State policies and scheduling |
| [C export](CODEGEN.md) | Supported blocks, compilation and model APIs |
| [Validation](VALIDATION.md) | Dated test evidence, reproduction and limits |
| [Contributing](CONTRIBUTING.md) · [Review guide](REVIEW_GUIDE.md) | Development and code review |

The merged event-export milestone records 26 Octave suites, 25 BIST checks
and 242 strict C99 cases. These are recorded results for that milestone,
not a GitHub CI badge or a claim of complete compatibility. Run locally:

```powershell
./Launch-Blocks.ps1 -SelfTest
```

The editor checks require a desktop session and Qt. See
[VALIDATION.md](VALIDATION.md) for the full environment.

## Releases and license

[Releases](https://github.com/ShannoonRuaaa/octave-blocks/releases) provide
versioned source ZIPs, SHA-256 checksums and feature notes. Preview releases
are intended for experimentation. See [CHANGELOG.md](CHANGELOG.md) and
[release instructions](docs/RELEASING.md).

Distributed under the [MIT license](LICENSE). GNU Octave is a separate dependency.
Octave Blocks is not affiliated with GNU Octave or MathWorks. MATLAB and
Simulink are trademarks of The MathWorks, Inc.
