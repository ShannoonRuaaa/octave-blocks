# Review of the v1 release preparation ZIP

**Not fully tested. These changes will be verified on another machine before
release readiness is assessed.** The package version remains 0.3.0. This
branch includes the package organization cleanup and reviewed portions of
`octave_blocks_v1_release_push.zip`, supplied on 2026-11-24.

The ZIP's Python applicator was inspected as a proposal, not run against the
repository. It contains instructions to overwrite files and remove a solver
guard; those instructions do not substitute for review or test evidence.
The integration preserves the existing package layout and Texinfo help.

## Findings and disposition

| Proposal | Assessment and integrated change |
| --- | --- |
| Versioned MAT models | Valid additive design. Save marker 1, accept unversioned files as source version 0, reject malformed/newer markers, preserve the first three loader outputs and selective variable loading. The supplied help incorrectly said legacy files return version 1; corrected. |
| Atomic save guarantee | Too strong. Retain validation, sibling temporary save and replacement, but document that `movefile` does not prove cross-platform/filesystem atomicity or crash durability. |
| Qt preflight and editor help | Useful. Existing help was already fixed by package cleanup; add the identified no-Qt diagnostic without overwriting that help. Desktop interaction still needs another-machine verification. |
| Remove the exact Octave solver guard | Deferred. The guard selects an optimized reproduction of 11.3.0's solver; other versions use their host `ode45`. The supplied unconditional-availability assertion would erase this numerical assumption. Keep the guard and test its actual contract. |
| PowerShell 5.1 launcher | Useful compatibility change. Keep the quoting logic, correct empty arguments, and delegate `-SelfTest` to PowerShell 7 when invoked from 5.1. Focused syntax/quoting tests do not prove a live editor launch. |
| Portable release smoke | Substantial correction needed. Oscillator Scope is block 4, not 5; standalone compilation needs `-DOB_STANDALONE`; `accelerate='on'` is invalid (use logical true or `ob_accelerate`). Isolate both package registries as well as the prefix. Restore both prefixes, registry paths, Octave path and cache environment. Compare all C output rows/columns and test actual MEX cache reuse/model edits. |
| Accelerator skip/fallback | Original skip branch still attempted compilation through `auto` and labelled it fallback. A skip now skips MEX explicitly, records that fact, and makes no fallback claim. |
| GitHub CI | Default Ubuntu's Octave may fail the declared >=11.3.0 dependency. Use the [official GNU Octave image](https://github.com/gnu-octave/docker), pinned to 11.3.0 and its amd64 digest, plus focused source/installed checks and Windows launcher checks. A workflow definition is not an observed CI pass. |
| API stability document | Useful inventory, premature guarantee. Inventory all 93 installed functions and mark proposed stable APIs as candidates; examples and the structural diagnostic stay experimental. Correct raw-run fallback and result representations. No 1.x interface/numerical stability promise is declared complete. |
| Limitations document | Retain the documented backend limits and workarounds, remove unverified 1.0/platform assertions, and distinguish earlier 0.3.0 gates from this branch. Solver substitution warnings and raw-run fallback reason fields are still absent. |
| Supplied format/API tests | Correct the Scope index, apply the standard test setup, avoid requiring private functions as public APIs, and add malformed/future version, legacy-default and failed-save preservation checks. Historical-release fixtures remain missing. |

## Focused local verification

The working environment is Windows with GNU Octave 11.3.0. Launcher syntax
and six quoting cases passed under PowerShell 7.6 and Windows PowerShell
5.1. Model-format roundtrip, legacy normalization, failed-save preservation
and malformed/future schema guards passed. API inventory/result fields,
reachable help, headless Qt rejection, all 93 installed function catalog
entries and editor core checks passed. Documentation checks passed for
386 UTF-8 files and 487 relative links. The initial help check needed the
bundled `perl` on PATH and permission for its MSYS runtime to initialize;
the successful run used both `mingw64/bin` and `usr/bin` outside the sandbox.

The installed smoke check compiled standalone C99 with GCC using
`-std=c99 -O2 -Wall -Wextra -Werror -DOB_STANDALONE`; every numeric CSV
column agreed with interpreted RK4 within 1e-11. RK4/ode45 oscillator,
schema roundtrip, command-API Dataset output, MEX compilation, repeated-cache
reuse and model-edit invalidation checks passed. The first cleanup attempt
revealed that `pkg` mlocks itself and its registry setter creates absent
files. Cleanup now unlocks/resets `pkg` before restoring settings and reports
whether registry paths and prefixes were actually restored.

The final cleanup verification passed with `registry_restored=true`, clean
unload/uninstall and no registry-restoration warning. That retry explicitly
skipped MEX comparisons, which passed in the preceding run; the skip remains
in its JSON report. Local artifacts are under
`tests/.artifacts/v1-smoke-587106f1d08c4822aeabbcf86d4924b8/`
(`result-fixed` for the MEX comparisons, `result-restoration` for final
cleanup). The archive tested the working package files; it was not an
official release artifact. No full numerical, C, Qt, historical-fixture or
cross-version gate is claimed by these focused checks.

## Verification on another machine

Use a clean checkout of this branch's exact commit and GNU Octave >=11.3.0.
Record OS, architecture, Octave/build features, compiler, PowerShell (on
Windows), commit and whether any checks were skipped. Install Octave's
development toolchain so GCC and mkoctfile are on PATH.

1. Build an archive of the commit, rather than a changed working tree:

   ```sh
   git archive --format=tar.gz --prefix=octave-blocks/ -o octave-blocks-verification.tar.gz HEAD
   ```

2. In a fresh process, add only `tests/` and run:

   ```octave
   addpath ('tests');
   report = smoke_release ('/absolute/path/octave-blocks-verification.tar.gz');
   ```

   Keep the report and generated C/CSV files. Leave `OB_SKIP_ACCELERATOR`
   unset to verify MEX compilation, reuse and invalidation. A skip must
   remain visible in the report.

3. Run the focused source checks:

   ```octave
   ob_setup ('tests');
   test_ob_model_format ();
   test_ob_api_contract ();
   test_ob_package_layout ();
   test_ob_docs ();
   ```

4. On Windows, run `tests/Test-Launcher.ps1` under both PowerShell 7 and
   Windows PowerShell 5.1, then launch the actual editor from a directory
   containing spaces. Verify editing, save/reload and unload. Test
   `Launch-Blocks.ps1 -SelfTest` delegation with PowerShell 7 installed.

5. For release readiness, run the full platform gate from
   [tests/README.md](../tests/README.md). Preserve revision-bound logs and
   skips. Add real historical model fixtures, failure-path cleanup cases
   for the new smoke helper, another Octave version, and filesystem-specific
   save replacement checks before expanding compatibility claims.

CI provides a Linux smoke environment and Windows launcher checks. It does
not replace testing on the user's other machine, a live Qt desktop gate,
or the remaining [roadmap criteria](ROADMAP.md).
