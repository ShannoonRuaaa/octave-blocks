# Experimental C event runtime

This is developer work on `codex/event-c-export`. The public `ob_codegen` entry
point still rejects zero-crossing and continuous-control export. The published
baseline and [VALIDATION.md](VALIDATION.md) describe the supported event-off C
path. Do not treat internal generation or a focused check as production parity.

## Run the integration probe

```powershell
./Test-EventCodegen.ps1 -ExperimentalTyped
```

The explicit switch calls `ob_codegen_conditional` internally with event
options. Omitting it preserves the public exporter and its protective rejection.
The probe prepares 43 analytical Octave fixtures, generates their C, compiles
with `-std=c99 -O2 -Wall -Wextra -Werror`, runs the models and two API harnesses,
and compares every numeric channel at a scaled tolerance below `2e-8`.

Use `-CasePattern` for a focused probe and `-OutputDirectory` for a stable
artifact directory. Existing supported exports are checked separately with
`./Test-Codegen.ps1`. The edge factory `test_ob_event_codegen_edges()` contains
six additional analytical specifications and a guard-overflow API harness; its
analytical pass alone does not establish compiled behavior.

## Runtime boundaries

`ob_codegen_conditional` normalizes solver options, inventories guards/clocks
and classifies units requiring continuous flow. The existing typed emitter
selects separate event helpers only for the explicit internal event path:

- `ob_emit_c_event_root.m`: shared RK4 stages, raw guard snapshots, frozen-mode
  settling, root localization, accepted scheduling and transactional model APIs.
- `ob_emit_c_event_child.m`: accepted enable/trigger lifecycle, inherited and
  explicit samples, held/reset state/output policies and recursive suspension.
- `ob_emit_c_event_math.m`: guard metadata, crossing predicates and mode proposals.
- `ob_c_event_inventory.m`: public/compiled paths and stable per-channel IDs.

The transient `ob_clock_frame` carries origin, due/tick arrays, a frozen-mode
pointer, and accepted/reconcile flags. No pointer from this frame may be retained
in a model context. A frame carrying modes alone still needs valid empty
due/tick arrays. Trials use complete context copies with acceptance disabled;
raw source signals determine guards even when primitive outputs use frozen modes.

An accepted continuous enable change is separate from an inherited sample.
Zero-time reconciliation skips unrelated commits, captures and clock advances.
An accepted trigger edge intentionally executes its body once, including that
body's inherited capture. Unchanged control signs must not rearm zero plateaus.
Enabled inherited Euler intervals count active time across pauses, while explicit
clocks retain the root phase. Newly active bodies require fresh guard and source
boundary discovery before further integration.

Generated experimental contexts contain cumulative `event_count` and
`last_event_time`; the latter is meaningful when the count is nonzero. They do
not contain an unbounded event log. Guard subtraction must remain finite, even
when each input and boundary is separately finite. Public output evaluation,
initialization, provider changes and steps must preserve the complete caller
context on failure. Custom callback side effects remain outside this guarantee.

## Before enabling public export

Complete the main and edge compiled comparisons, coincidence and rollback
checks, and the supported-export regression gate. Check active descendants,
source jumps, outgoing equality regimes, plateau memory, chattering, stateless
models and representable progress at small/large times. Replace the former
public event-rejection regression expectations with positive integration checks
while retaining protected-file checks for genuinely unsupported/invalid exports.
Update the public support table and run the full application gate before
removing `ob_codegen`'s protective checks.

The current checkpoint results and remaining failures belong in
[ADVANCED_PLAN.md](ADVANCED_PLAN.md). Full compatibility, adaptive C solver
generation and the other advanced requirements remain unfinished.
