# Source releases

Release a reviewed commit on `main`. A release tag and notes must describe
that commit's code, not a draft PR. Keep unresolved dependency/license
changes out of releases.

1. Run relevant numerical, C and Qt gates; record revision and environment.
2. Update `CHANGELOG.md`; use a preview version for experimental subsets.
3. Build with `tools/Package-Release.ps1`. It rejects a dirty tree and
   packages tracked files from an exact Git revision.
4. Extract the ZIP and verify startup, examples and the included license.
5. Publish a GitHub prerelease with the source ZIP, installable `.tar.gz`
   and `SHA256SUMS.txt`. Use the version in `DESCRIPTION` for package releases.

```powershell
./tools/Package-Release.ps1 -Version '0.2.1' -Revision HEAD
```

No Octave installation, compiler, cache or ignored validation artifact ships.
Verify downloads with `Get-FileHash -Algorithm SHA256`. GitHub also provides
automatically generated source archives alongside the uploaded ZIP.

## Refresh images

From a Qt-enabled Octave session in the repository root:

```octave
addpath(pwd()); addpath('tools'); capture_readme_images();
```

This refreshes the simulation plot and writes an `editor-canvas.png` preview.
Octave's `getframe` omits toolbar controls; capture the actual application
window separately as `doc/images/editor.png` for the full editor image.
The simulation plot uses
`ob_run` and checks oscillator error against cosine is below 1e-6.
Inspect images before committing; they illustrate the application and do
not establish correctness of the entire engine.
