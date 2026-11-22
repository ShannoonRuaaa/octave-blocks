# Package layout and function organization

The layout follows GNU Octave's [package structure](https://docs.octave.org/latest/Creating-Packages.html).

| Location | Purpose |
| --- | --- |
| `DESCRIPTION`, `COPYING`, `INDEX`, `NEWS` | Package identity, license, categorized function list and user-visible changes |
| `inst/` | Installed public `.m` functions; no test or benchmark runners |
| `inst/private/` | Shared runtime, compiler, scheduling and exporter implementation |
| `inst/examples/` | Runnable examples, also available after loading the package |
| `doc/` | User guides, design notes, validation and images |
| `tests/` | Suites, runners, reference producers/data, benchmarks and ignored artifacts |
| `tools/` | Release packaging, image generation and editor diagnostics |
| `ob_setup.m`, `Launch-Blocks.ps1` | Source-checkout setup and Windows launch shortcuts |

Pure Octave code belongs in `inst/`. Octave reserves `inst/` for native code
that must be built; this project currently has no native extension build to
install. Runtime-generated C is written only to the requested output location.

## When to group functions

Keep a public function in its matching `.m` file so Octave can find it and
`help`/`which` work normally. Put helper routines used only by that function
in the same file as subfunctions. For example, the conditional unit compiler
now includes its multiple-output Function shape helper as a subfunction.
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

## Installed package

```octave
pkg install '/path/to/octave-blocks-0.2.1.tar.gz';
pkg load octave-blocks;
octave_blocks();
```

Use a package archive produced by `tools/Package-Release.ps1`. Tests, tools
and the source-checkout launcher are not needed to run an installed package.
Use `pkg describe -verbose octave-blocks` to browse its public categories.
