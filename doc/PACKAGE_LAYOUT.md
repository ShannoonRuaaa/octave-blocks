# Package layout and function organization

The layout follows GNU Octave's [package structure](https://docs.octave.org/latest/Creating-Packages.html).

| Location | Purpose |
| --- | --- |
| `DESCRIPTION`, `COPYING`, `INDEX`, `NEWS` | Package identity, license, categorized function list and user-visible changes (`NEWS` is the single changelog) |
| `LICENSE`, `NOTICE`, `LICENSES/` | A second copy of the GPLv3 text, the attribution notice and the retained original MIT grant ([LICENSING.md](LICENSING.md)) |
| `inst/` | Installed public `.m` functions, `Contents.m`, and `PKG_ADD`/`PKG_DEL`; no test or benchmark runners |
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
See Octave's [subfunction](https://docs.octave.org/latest/Subfunctions.html)
and [private function](https://docs.octave.org/latest/Private-Functions.html)
guidance. This preserves separately callable APIs while hiding internals.

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
