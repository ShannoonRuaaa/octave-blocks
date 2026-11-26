# Editor responsiveness

The editor retains its diagram graphics between interactions. Selection changes
the old and new block highlights. Dragging moves the selected block, label,
numbered ports, and incident wires in place. Mouse-up without movement does not
repaint the diagram. Structural or parameter changes and hierarchy navigation
rebuild the scene; deleted graphics also invalidate the cache.

Block faces, labels, port markers, and port numbers now share explicit block
ownership and the same selection callback. Signal lines and arrows are not
pickable, so they cannot intercept a block click. A figure-level canvas
fallback supplies five pixels of tolerance around block edges. Owned parts
keep their own dispatch path; the fallback skips them to avoid handling one
click twice in Connect mode.

These changes remove the former full `cla`/object recreation on selection,
every drag event, and mouse-up. A click previously rebuilt the whole diagram
twice. A drag still records one Undo entry, and moving back to the saved
position clears the dirty marker when the drag finishes. Graphics handles stay
in editor state and are excluded from model files and Undo/Redo snapshots.

## Wire routing (2026-11-26)

Wires are routed as horizontal and vertical segments by
`inst/private/ob_route_wires.m`, so that wires of different signals never
share a segment. Routes are display data in the retained scene (`routes` in
the graphics cache), never part of the model, Undo/Redo snapshots or files.

- A scene rebuild (load, demo buttons, Connect/Disconnect, edits, Undo/Redo,
  navigation) routes every wire.
- A drag motion reroutes only the moved block's wires, around the unchanged
  routes of the others, with the shortest detour lanes. The line and arrow
  objects are kept and only changed routes are written.
- The drop (mouse-up after a move) routes the whole diagram again and writes
  the wires whose routes changed. The settled layout therefore depends only on
  the diagram, whatever path the drag took.
- A wire with a port inside another block (blocks drawn over each other, as
  newly added blocks are) cannot avoid that block. It takes its plain shape
  without a lane search, which keeps such crowded scenes cheap.

![Editor demos before (left) and after (right) wire routing: Oscillator,
Nested demo, Rate demo, Control demo and Input demo](images/wire-routing.png)

In the oscillator the two feedback wires shared their top segment, and
Position -> Scope ran under the Velocity block; in the Rate demo the loopback
ran on top of Time -> Rate Transition. After routing, each signal has its own
lane. These canvases were printed offscreen from the editor figures of
`v0.3.0` and of this change on the Windows test desktop.

Router cost alone, in `octave-cli` on the laptop used for development (median
of repeated calls):

| Diagram | Full routing | Drag reroute |
| --- | ---: | ---: |
| Oscillator (4 wires) | 8.8 ms | |
| Control demo (7 wires) | 8.0 ms | |
| 10-block benchmark chain | 4–6 ms | 3.0 ms |
| 40-block benchmark chain | 28–49 ms | 3–5.5 ms |

In the editor, hidden Qt figures on the Windows test desktop, `v0.3.0` and
this change alternating in fresh GUI processes, three rounds each (medians;
`benchmark_ob_editor_drag ([10 40], 12, 5)` for motion, then mouse-up after
one motion for the drop):

| Callback | Diagram | Before | After | Change |
| --- | --- | ---: | ---: | ---: |
| Drag motion | 10-block chain | 27.9 ms | 36.6 ms | +8.7 ms |
| Drag motion | 40-block chain | 27.0 ms | 37.6 ms | +10.6 ms |
| Drop | Oscillator | 12.1 ms | 40.5 ms | +28 ms |
| Drop | Control demo | 15.1 ms | 36.0 ms | +21 ms |
| Drop | 10-block chain | 16.5 ms | 29.5 ms | +13 ms |
| Drop | 40-block chain | 31.1 ms | 96.5 ms | +65 ms |

That desktop was locked and noisy during these runs (its callback times are
three to four times those in the audits below, and repeated scene builds of
one model varied by up to 2x). Selection clicks and scene builds do not run
the router on their own; an earlier round of the same protocol measured them
equal within noise (10-block click 99.9 vs 117.7 ms, 40-block 275.5 vs
275.1 ms). Routing adds roughly 10 ms to each drag motion and a one-time
cost on the drop that grows with the diagram. The benchmark chains are a
stress case: their blocks overlap, so every in-row wire has a buried port.

## Drag audit (2026-11-16)

Ordinary motion now uses a changed-block hint when native `guidata` write
observation proves that the cached scene is current. Internal writes use a
per-window token; external and reentrant writes invalidate trust. Missing
observation, other coordinate changes, changed attributes/edges and lost
graphics retain equality checks, coordinate discovery or rebuilding. Undo,
dirty markers, stale selection/path cancellation and incident wires are tested.
Graphics validation and other costs remain; the whole drag is not O(degree).

Six same-process interleaved samples per version/count against `39fc357`, with
warmups and twelve actual axis-point motions/callbacks plus `drawnow`, gave:

| Blocks | Before per motion | After | Change |
| --- | ---: | ---: | ---: |
| 10 | .010775 s | .011993 s | 1.218 ms / 11.3% more |
| 40 | .032147 s | .029127 s | 9.4% less |
| 100 | .047029 s | .033242 s | 29.3% less |

Every sample, including early stalls, was retained. A bounded small-scene
diagnostic confirms extra callback work; no universal speedup is claimed.
An earlier deep-equality prototype was discarded after measured regressions.
These are callback/render timings, not OS input latency. See
[PR2_AUDIT.md](PR2_AUDIT.md) and its raw-data links for protocol and limits.

## Earlier audited changes (2026-11-13)

Pure selection now skips model reinstallation and content-history comparison.
A coherency key includes current and saved snapshots before reusing dirty/scene
classification, preserving external model/settings/saved-state invalidation.
Incident-wire indexes avoid scanning every edge to select wires for a drag;
graphics validity and block-position work remain, so the entire drag is not
constant-time or O(degree).

Six interleaved samples per version used the same hidden Qt callback benchmark,
with twelve clicks plus `drawnow` per sample:

| Diagram | Before | After | Change |
| --- | ---: | ---: | ---: |
| 10 blocks | .02623 s/click | .02450 s/click | 6.6% lower |
| 40 blocks | .08498 s/click | .07838 s/click | 7.8% lower |

The expanded Qt regression passed external model/settings/saved-state changes,
dirty markers, deleted graphics, nonincident-wire stability, ordinary selection,
drag/Undo and Run. These timings measure callbacks/rendering, not OS mouse-event
delivery. See [OPTIMIZATION_AUDIT.md](OPTIMIZATION_AUDIT.md) and
[benchmarks/README.md](../tests/benchmarks/README.md) for samples, protocol and limits.

## Earlier retained-graphics measurements

On Windows with GNU Octave 11.3.0's Qt runtime, six selection-plus-mouse-up
cycles were timed for each hidden test figure:

| Diagram | Before | After | Relative improvement |
| --- | ---: | ---: | ---: |
| 10 blocks | 0.519 s/click | 0.039 s/click | about 13× |
| 40 blocks | 2.137 s/click | 0.102–0.112 s/click | about 19–21× |

The harness uses the actual callbacks and includes callback lookup and
`drawnow`. Initial scene construction is excluded. These are local relative
measurements; OS input delivery, display rendering, simulations, and source
generation have separate costs. Large diagrams still pay for a full rebuild
after structural edits, and a Run remains synchronous while simulation runs.

An independent fresh-process rerun of the same six-cycle harness measured
0.026 s/click for 10 blocks and 0.085 s/click for 40 blocks. The baseline and
after measurements use the same callback path; these ranges reflect local
timing variation, rather than a fixed speed guarantee for every machine.

Existing open editors can retain callbacks loaded before an update. Save work
and open the updated editor in a fresh Octave process to apply this version.

## Verify or reproduce

From PowerShell in the repository root:

```powershell
.\tests\Test-Editor.ps1
.\tests\Test-Editor.ps1 -Benchmark
```

The script launches the installed Qt GUI runtime with hidden test figures and
reports a retained log directory. It does not close or modify existing editors.
`octave-cli.exe` lacks Qt in the tested Windows installation, so this check is
run as a separate process after the CLI/C phases of `Launch-Blocks.ps1 -SelfTest`.

In the Octave GUI, from the repository root, the equivalent calls are:

```octave
addpath (pwd ());
ob_setup ('tests');
test_ob_editor_graphics ();
benchmark_ob_editor_ui ([10 40], 6);
```

The graphics regression suite verifies every block part's ownership, picking
properties and selection callback, selection without graphics recreation,
multi-output block movement and numbered wire endpoints, loopback rerouting,
one history entry
per drag, Undo/Redo, interface changes, recovery after external graphics removal,
and Enter/Up navigation. It also checks that the drawn wires of every editor
demo match a fresh routing and that no two signals share a segment or pass
through a block: on load, after each demo button, during and after a drag, and
after Disconnect and Connect. `test_ob_editor_core` checks the same routing
geometry without a GUI. Test figures are deleted after each run.

Native mouse verification also exercised block faces, labels, port circles,
port numbers, and an edge click that previously missed. A traced drag selected
the Time block under the pointer, moved only that block, and ended its drag
state on mouse-up. One Undo restored its position and cleared the dirty marker.

For diagnosing a mouse-picking report in a fresh editor (the helper is in
`tools/`, which `ob_setup ('tests')` adds):

```octave
[fig, tracefile] = ob_trace_editor_clicks ();
% Click or drag in that window, then inspect:
trace = load (tracefile);
trace.records
```

This optional helper preserves the editor's original callbacks and writes a
local MAT log after mouse-down/up. Records include the picked graphics owner,
axes coordinates, selected block, drag state, and block positions. It adds disk
logging overhead and is not part of the selection benchmark. It does not
modify an already-open editor or save a model file.

## Selection repaint fix (2026-11-21)

A click on a block updated the selection and the status line, but the
orange highlight could stay on the previously selected block. The
selection-only path changes just two patch face colors. Octave's Qt GUI
pushes axes changes made inside a callback to the screen only at the next
graphics flush, and no other event triggered one. The status line is a Qt
widget, so it updated anyway.

`ob_draw` now ends with `drawnow` (via `ob_flush_canvas`), after the editor
state is stored, so a callback that runs during the flush sees consistent
state. All callers return right after `ob_draw`. With the existing Qt
benchmark (which already flushed after each motion), dragging measured 8.2
ms per motion for 10 blocks and 7.0 ms for 40, with no regression. Scripted
editor tests read graphics properties, which were always correct, so they
could not detect this. It was found in a real-window capture whose status
line and highlight disagreed.
