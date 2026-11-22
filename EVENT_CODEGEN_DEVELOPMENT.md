# C event runtime architecture and regression guide

`ob_codegen` selects the typed event runtime for RK4 exports with
`zero_crossings=true`, including models without conditional children. Declared
continuous controls require that option. The ordinary event-off path retains
its supported sampled behavior. [CODEGEN.md](CODEGEN.md) describes public use,
static-shape restrictions, return codes and metadata.

The registered milestone checks passed on `codex/event-c-integration`: 21
Octave suites, 25 BIST checks, 235 strict C99 cases, and the expanded Qt tests.
All 219 numeric C models matched Octave with worst scaled error 0; sixteen
API harnesses passed. Verification completed across the retained main run and
an explicit successful final-stage rerun. Consult
[VALIDATION.md](VALIDATION.md) and [ADVANCED_PLAN.md](ADVANCED_PLAN.md) for final
recorded status. These checks do not establish full Simulink compatibility.

## Run the public regression gates

```powershell
./tests/Test-EventCodegen.ps1
./tests/Test-EventCodegenEdges.ps1
./tests/Test-EventCodegenHierarchy.ps1
./tests/Test-Codegen.ps1
./tests/Test-Editor.ps1
./Launch-Blocks.ps1 -SelfTest
```

The event scripts prepare analytical Octave references, generate C through
`ob_codegen`, compile with `-std=c99 -O2 -Wall -Wextra -Werror`, execute model
runners/API harnesses and compare numeric channels at a scaled tolerance below
`2e-8`. Each prints a retained artifact directory. Use `-OutputDirectory` for a
stable destination and the main script's `-CasePattern` for a focused probe.
The optional `-ExperimentalTyped` switch remains an internal-generator diagnostic;
public acceptance must pass without it.

The main factory covers primitive guards, matrix/simultaneous transitions,
source jumps, equality/plateaus, bounded oscillation, state-free models,
enabled policies, triggers, clock coincidences and host input/chatter APIs.
The independent edge factory adds large/tiny times, dormant/lazily activated
guards and finite guard-subtraction overflow. The hierarchy factory exercises
multi-level lifecycle/clock behavior and accepted event metadata. Editor tests
exercise Export C callbacks; retain and compile their exact generated sources.
Gate results apply to the exercised cases, not every possible model.

## Runtime boundaries

`ob_codegen_conditional` normalizes options, inventories guards/clocks and
classifies units requiring continuous flow. The typed emitter selects:

- `ob_emit_c_event_root.m`: shared RK4 stages, raw guard snapshots, frozen-mode
  settling, root localization, accepted scheduling and transactional model APIs.
- `ob_emit_c_event_child.m`: accepted enable/trigger lifecycle, inherited and
  explicit samples, held/reset policies and recursive suspension.
- `ob_emit_c_event_math.m`: guard metadata, crossing predicates and proposals.
- `ob_c_event_inventory.m`: public/compiled paths and stable per-channel IDs.

The transient `ob_clock_frame` carries origin, due/tick arrays, frozen modes
and accepted/reconcile flags. No frame pointer is retained in a model context.
Frames carrying modes alone still have valid empty due/tick arrays. Trials use
complete context copies with acceptance disabled. Primitive outputs use frozen
incoming regimes while raw source signals determine guards.

An accepted continuous enable change is separate from an inherited sample.
Zero-time reconciliation skips unrelated captures, commits and clock advances.
An accepted trigger intentionally executes its body once, including inherited
capture. Unchanged control signs do not rearm a zero plateau. Enabled inherited
Euler intervals count active time across pauses; explicit clocks keep root
phase. Newly active bodies require fresh guard/source-boundary discovery before
further integration. A coincident scheduled clock is processed once.

## Event memory and failure contracts

Event-enabled contexts contain cumulative `event_count` and `last_event_time`;
the latter is meaningful when the count is nonzero. They have no unbounded
event log. Simultaneous guard records may increment the count at the same time.
At a plateau endpoint, the next advance can first establish an outgoing regime
and report a transition at the previous accepted stop. Test metadata against
sequential accepted `ob_runtime` contexts; a batch reference that has already
advanced beyond that stop can contain a later-discovered record.

Initialization, output evaluation, provider replacement and stepping preserve
the complete caller context on failure. Guard subtraction must stay finite
even when source and threshold are separately finite; overflow returns
`OB_NONFINITE`. Unresolved/chattering regimes and exhausted event-progress
limits return `OB_EVENT_ERROR=4`. Custom callback side effects remain outside
the context rollback guarantee. Provider replacement recomputes outputs without
advancing continuous state or replaying historical events.

## Search and compatibility limits

`maxstep` bounds searched RK4 segments; its default `Inf` adds no bound. Matching
endpoint signs can hide multiple crossings, and tangencies are not guaranteed.
The locator does not supply adaptive ODE error control or make a coarse nonlinear
RK4 trajectory exact. Unrepresentable time progress and nonsettling outgoing
modes fail explicitly. See [ZERO_CROSSINGS.md](ZERO_CROSSINGS.md) and
[CONTINUOUS_CONTROLS.md](CONTINUOUS_CONTROLS.md) for equality/initialization rules.

Adaptive C solver emission, general guard registration, combined/resettable
gate variants and other gaps remain open in
[COMPATIBILITY_GAPS.md](COMPATIBILITY_GAPS.md). Retained MATLAB/REA probes do not
establish live Simulink trajectory agreement; their exact limits are recorded
in [REFERENCE_EVIDENCE.md](REFERENCE_EVIDENCE.md).
