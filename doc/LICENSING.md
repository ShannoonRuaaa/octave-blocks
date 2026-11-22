# Licensing and solver provenance

The combined Octave Blocks distribution is licensed under the GNU General
Public License, version 3 or (at your option) any later version. `COPYING`
and `LICENSE` contain the complete GPLv3 text. The package DESCRIPTION
declares `GPL-3.0-or-later`.

The original Octave Blocks code was published under MIT. Its copyright and
permission notice are preserved verbatim in [LICENSES/MIT.txt](LICENSES/MIT.txt).
Those original grants are retained; the combined distribution containing
the adapted solver components is distributed under GPL-3.0-or-later.
Earlier MIT-only release tags retain their original terms.

## Adapted solver components

`inst/private/ob_dormand_prince.m` reproduces the supported Octave 11.3.0
ode45 path with prevalidated settings and a project monitor interface.
`inst/private/ob_c_ode45_lines.m` ports that path into generated C, adding
project state packing, delay-history recording and limited-state handling.
These files are GPL-3.0-or-later and retain upstream attribution to The
Octave Project Developers and the modifications attribution to Shannon Ruan.

The relevant GNU Octave 11.3.0 source routines are `ode45.m`,
`private/starting_stepsize.m`, `private/integrate_adaptive.m`,
`private/runge_kutta_45_dorpri.m` and `private/AbsRel_norm.m` under `m/ode/`.
Upstream sources: [GNU Octave release-11-3-0](https://github.com/gnu-octave/octave/tree/release-11-3-0/scripts/ode).
Their headers identify The Octave Project Developers (2006–2026 for ode45,
2013–2026 for the listed private routines), under GPL version 3 or later.
Upstream author information is recorded in the
[Octave copyright record](https://octave.org/copyright/).

## Generated code and compiled acceleration

Adaptive ode45 C output contains the adapted GPL solver implementation.
The emitter includes an SPDX license identifier, upstream attribution,
modification attribution and redistribution notice in the generated source.
Retain these notices and supply the GPL text and corresponding source when
redistributing derivative binaries, including accelerator builds. This
release does not provide an exemption that makes that solver output MIT.
Other generated code retains its applicable source notices; check the
specific output and linked dependencies before redistribution.

GNU Octave itself is a separate dependency, not bundled in source releases.
The native MEX accelerator is compiled locally using the user's Octave
toolchain; the project ships its gateway and generated-source machinery.
