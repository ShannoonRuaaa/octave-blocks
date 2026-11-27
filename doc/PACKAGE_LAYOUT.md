# Package layout and function organization

The layout follows GNU Octave's [package structure](https://docs.octave.org/latest/Creating-Packages.html).

| Location | Purpose |
| --- | --- |
| `DESCRIPTION`, `COPYING`, `INDEX`, `NEWS` | Package identity, license, categorized function list and user-visible changes (`NEWS` is the single changelog) |
| `LICENSE`, `NOTICE`, `LICENSES/` | A second copy of the GPLv3 text, the attribution notice and the retained original MIT grant ([LICENSING.md](LICENSING.md)) |
| `inst/` | Installed public `.m` functions, complete `Contents.m` catalog, and `PKG_ADD`/`PKG_DEL`; no test or benchmark runners |
| `inst/private/` | Shared runtime, compiler, scheduling and exporter implementation |
| `inst/examples/` | Runnable examples, added to the path by `PKG_ADD` when the package loads |
| `inst/simulink/` | Simulink-named command wrappers (`new_system`, `add_block`, `add_line`, `sim`, ...), added to the path only by `ob_simulink_setup ()` and removed by `PKG_DEL` |
| `doc/` | User guides, design notes, validation, licensing, roadmap and images |
| `tests/` | Suites, runners, reference producers/data, benchmarks and ignored artifacts |
| `tools/` | Release packaging, image generation and editor diagnostics |
| `ob_setup.m`, `Launch-Blocks.ps1` | Source-checkout setup and Windows launch shortcuts |
| `.github/` | Issue and pull request templates |

Installed `.m` code belongs in `inst/`; `pkg install` copies it into the
package's installation directory. Octave reserves `src/` for native code
that is compiled at install time. This project has no `src/` directory and
installs no compiled extension: `ob_accelerate` compiles generated C at run
time into a per-user cache, and C from `ob_codegen` is written only to the
requested output location.

## When to group functions

Keep a public function in its matching `.m` file so Octave can find it and
`help`/`which` work normally. Put helper routines used only by that function
in the same file as subfunctions. For example, the conditional unit compiler
(`inst/private/ob_c_conditional_unit.m`) includes its multiple-output
Function shape helper as a subfunction.
Use `inst/private/` when several implementation files share a helper.
The control-mode predicates `ob_is_combined_mode` and
`ob_is_resettable_mode` are private implementation details. The example
`ob_example` has one definition, in `inst/examples/`, and is available after
both `ob_setup ()` and `pkg load octave-blocks`.
See Octave's [subfunction](https://docs.octave.org/latest/Subfunctions.html)
and [private function](https://docs.octave.org/latest/Private-Functions.html)
guidance. This preserves separately callable APIs while hiding internals.

Keep `INDEX` and `inst/Contents.m` synchronized with the installed functions
in `inst/`, `inst/examples/` and `inst/simulink/`. Catalog the command wrappers
as opt-in functions. Every installed function needs a help comment immediately
after its function declaration, before executable statements; use Texinfo for
usage forms, arguments, results, examples and related functions when adding
or expanding help. Implementation comments should explain constraints and
decisions rather than repeat the code. `ob_atomic_feedthrough` is an
experimental diagnostic, not a scheduler contract.

Run `test_ob_package_layout` to check unique installed function names,
filename/signature agreement, reachable help and matching catalogs. This is
part of the audit stage on Windows and Linux. `Test-Package.ps1` also checks
that private helpers stay hidden after installation, the example resolves to
its single definition, and editor help is accessible.

### Verification on 2026-11-24

On Windows with GNU Octave 11.3.0, the focused layout check passed for all
93 installed functions (54 main APIs, 24 examples/signal functions and 15
opt-in command wrappers). Documentation checks passed for 377 UTF-8 files
and 466 relative links; `test_ob_editor_core` passed. An isolated archive
of the working package files installed and loaded successfully with `pkg`,
kept private functions hidden, ran the oscillator and combined-control
examples and a command-API model, listed the complete catalog with
`pkg describe -verbose`, and removed the package paths on unload. The
archive, installation and smoke script are local artifacts under
`tests/.artifacts/layout-dea1b337e3a94797b8cd9c726eda824e/`; the user's regular
package installation was not changed. This check did not rerun the full
numerical, generated-C or Qt interaction gates.

## Source checkout

```octave
cd('/path/to/octave-blocks');
ob_setup();
octave_blocks();
```

For development, use `ob_setup('tests')`. Test suites temporarily expose
private helpers for regression checks and restore the path afterward.
`ob_setup('simulink')` also adds the command wrappers in `inst/simulink/`.

## Installed package

```octave
pkg install '/path/to/octave-blocks-0.3.0.tar.gz';
pkg load octave-blocks;
octave_blocks();
```

Use a package archive produced by `tools/Package-Release.ps1`. Tests, tools
and the source-checkout launcher are not needed to run an installed package.
Use `pkg describe -verbose octave-blocks` to browse its public categories.
Call `ob_simulink_setup ()` after `pkg load` to use the Simulink-style
command API; `pkg unload octave-blocks` removes the wrappers again.
