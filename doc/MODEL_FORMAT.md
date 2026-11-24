# Model file format

**Development schema; not fully tested. Verification on another machine is
pending.** Octave Blocks saves MATLAB v7 binary MAT files with
`ob_save_model` or the command API's `save_system`.

## Top-level variables

| Variable | Meaning |
| --- | --- |
| `format_version` | New saves write numeric scalar `1`. Absence identifies a legacy unversioned file. |
| `model` | Required model struct, checked by model validation. See [API.md](API.md). |
| `config` | Optional `[start stop output_interval]`, normalized and validated; default `[0 10 0.1]`. |
| `options` | Optional solver-options struct, normalized by the runtime; default RK4 settings. |

Options include `solver` (`rk4`, `ode45`, `ode15s`), `reltol`, `abstol`,
`maxstep`, `zero_crossings` and `accelerate` (`false`, `true`, `'auto'`).
The schema marker is independent of the package version; these changes do
not increment the current 0.3.0 release metadata or establish a 1.0 release.

## Loading and legacy normalization

`[model, config, options, version] = ob_load_model(file)` reports the source
file's marker as its optional fourth output. It returns `version = 0` for
an unversioned file and `version = 1` for a current file. Existing callers
that request up to three outputs keep their interface.

Legacy files are validated and missing settings are filled in memory. The
loader never rewrites the source. Re-saving the returned model and settings
writes marker 1. Files with malformed markers are rejected with
`ob_load_model:InvalidFormatVersion`. Markers greater than 1 are rejected
with `ob_load_model:UnsupportedFormatVersion` before the model is inspected.

This is a guarded loader, not a complete migration framework: historical
fixtures saved by every prior release, command-API settings roundtrips,
and future 1.x compatibility still need the roadmap's validation.

## Save replacement and limits

Model, configuration and options validation precedes writing. The saver
creates a temporary MAT file beside the destination, then replaces the
destination with `movefile(..., 'f')` after a successful save. A failed
replacement raises `ob_save_model:WriteFailed`; temporary files are cleaned
up. Validation failure preserves an existing destination.

This design does not establish atomic replacement or crash durability on
every operating system or filesystem, including network and synchronized
folders. MAT files containing arbitrary result objects or function handles
are outside this model-file schema. Dataset result serialization has its
own [limits](SIMULINK_API.md#dataset-output).
