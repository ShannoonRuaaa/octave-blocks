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

## Additional audited changes (2026-11-13)

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
[benchmarks/README.md](benchmarks/README.md) for samples, protocol and limits.

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

From PowerShell in this folder:

```powershell
.\Test-Editor.ps1
.\Test-Editor.ps1 -Benchmark
```

The script launches the installed Qt GUI runtime with hidden test figures and
reports a retained log directory. It does not close or modify existing editors.
`octave-cli.exe` lacks Qt in the tested Windows installation, so this check is
run as a separate process after the CLI/C phases of `Launch-Blocks.ps1 -SelfTest`.

In the Octave GUI, the equivalent calls are:

```octave
test_ob_editor_graphics ();
benchmark_ob_editor_ui ([10 40], 6);
```

The graphics regression suite verifies every block part's ownership, picking
properties and selection callback, selection without graphics recreation,
multi-output block movement and numbered wire endpoints, loopback rerouting,
one history entry
per drag, Undo/Redo, interface changes, recovery after external graphics removal,
and Enter/Up navigation. Test figures are deleted after each run.

Native mouse verification also exercised block faces, labels, port circles,
port numbers, and an edge click that previously missed. A traced drag selected
the Time block under the pointer, moved only that block, and ended its drag
state on mouse-up. One Undo restored its position and cleared the dirty marker.

For diagnosing a mouse-picking report in a fresh editor:

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
