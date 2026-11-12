# Sample times and rate transitions

`model.sample_times` assigns a period and offset to each block in that diagram.
Each row is `[period offset]`; its position matches the block-array position.
Omitting the field or using `[0 0]` retains the existing output-schedule behavior.
Only Unit Delay, Discrete Integrator, and Rate Transition blocks may have a
positive period. Other block rows must be `[0 0]`.

```octave
model = ob_example ();
model.blocks(2).type = 'Unit Delay';
model.blocks(2).value = -1;
model.sample_times = [0 0; 0.25 0; 0 0];
result = ob_run (model, [0 0.1 0.6 1]);
plot (result.t, ob_scope_data (result, 3));
```

The Time source is sampled by the delay every 0.25 seconds, independently of
the irregular requested output times. Its delayed output is -1 initially,
0 after the hit at 0.25, 0.25 after 0.5, and so on. Adding output timestamps does
not change the trajectory of blocks whose periods are explicit.

## Periods, offsets, and hits

Periods must be finite and positive. Offsets must be finite, nonnegative, and
strictly smaller than their period. They are relative to the simulation start:

```text
hit(k) = start_time + offset + k * period, k = 0, 1, 2, ...
```

The scheduler computes times from integer ticks, rather than repeatedly adding
the period. A model starting at 10 with period 0.3 and offset 0.1 has its first
hit at 10.1, then 10.4, 10.7, and so on. Before the first hit, the block emits
its initial condition. A `[0 0]` row has no independent clock and participates
at requested output times instead. `[0 nonzero]`, negative periods, invalid
offsets, nonfinite values, and metadata with the wrong number of rows are
rejected when validating the model.

Nominal clock/output collisions are grouped within
`8*eps(1)*max(realmin, abs(start_time), abs(a), abs(b))`. Including the origin
handles cancellation across time zero; avoiding an absolute one-second floor
keeps very small offsets near zero distinct. Positive offsets are never sampled
at initialization. Output timestamps are retained exactly as requested.

## Discrete state behavior

At an explicit Unit Delay or Discrete Integrator's first hit, its initial
condition remains the visible output. It samples its input to prepare the
next hit:

| Block | Value prepared for the next hit |
| --- | --- |
| Unit Delay | Current input. |
| Discrete Integrator | Current state plus `period * current_input` (forward Euler). |

At the next hit, the previously prepared value becomes visible, and the block
captures another value for its following hit. Output-only timestamps do not
change these explicit states. All due state changes commit simultaneously,
including when several periods coincide or an explicit hit coincides with an
output-schedule state update. This avoids block-array execution order changing
feedback behavior.

Unit Delay and Discrete Integrator blocks with `[0 0]` preserve their original
behavior: at each requested output time, they emit the previous interval's
prepared state, then capture the next state. The inherited Euler interval is
the distance to the next output time; the explicit Euler interval is its
configured period. Mixing explicit and inherited schedules is supported, but
changing the output grid still changes inherited state updates.

## Rate Transition

A Rate Transition block samples its current input at a hit and holds that
value until its next hit. It introduces no additional Unit Delay. Set its
`value` to the initial held value and its sample-time row to the destination
period/offset. With `[0 0]`, it samples at output times.

At a hit, the Rate Transition is evaluated in signal dependency order, so a
downstream Rate Transition sees an upstream Rate Transition's newly sampled
value when both hit together. It is direct feedthrough at hits and therefore
does not break an algebraic loop. A Unit Delay or stateful Integrator is still
needed to break direct signal feedback.

For example, Time → Rate Transition with period 0.25 emits 0, 0.25, 0.5, ... at
its hits. Time → Unit Delay with the same period emits its initial condition,
0, 0.25, ... instead.

## Continuous integration and input jumps

The continuous solver splits integration at scheduled sample hits, Step
transitions, and external-input knots. Discrete outputs remain held during
intermediate RK4 or adaptive-solver stages. Integration ending at a hit uses
the previous held value; after the hit the solver uses the new held value.
Output queries at a hit show the new state/sampled value.

External ZOH inputs and Step sources use their right-side value when sampled
at the same time as a hit. An external input knot between rate hits changes
the source signal but does not update the rate-controlled block.

For Time → Rate Transition (period 0.25) → continuous Integrator, the state at
time 1 is exactly `0.25*(0 + 0.25 + 0.5 + 0.75) = 0.375`, independent of whether
the requested output grid includes the intermediate hits. This hold behavior
is shared by `rk4`, `ode45`, and `ode15s`.

## Hierarchy, persistence, and scope

Each subsystem's child model stores its own `sample_times` rows. Virtual
subsystem boundaries preserve those periods and offsets when compiling the
hierarchy. Virtual Subsystem blocks have no own clock; configure their
inner state/transition blocks instead. Child offsets are relative to the root
simulation start, matching their flattened execution schedule.

Sample-time metadata is saved with the model. Older files without it retain
their output-schedule behavior. `result.compiled_model.sample_times` exposes the
flattened schedule used during execution.
`result.sample_hits` records hit times for each flat block, with
`result.block_paths` identifying its hierarchy path. Algebraic and continuous
blocks have no discrete hit list.

In the editor, **Rate Transition** adds the sampled hold block. Select a Unit
Delay, Discrete Integrator, or Rate Transition and click **Sample time** to edit
its period/offset. **Edit** changes its initial state. These edits participate
in undo/redo. **Rate demo** loads Time → Rate Transition (0.25 seconds) →
Integrator → Scope and sets the run configuration to `[0 1 0.1]`.

This implements deterministic numerical rate crossings with sample-and-hold
semantics. It does not yet implement asynchronous tasks, thread scheduling,
real-time deadlines, or Simulink's complete set of Rate
Transition block data-integrity and transfer-delay modes.

Run `test_ob_multirate` in Octave for explicit/legacy schedules, simultaneous
hits, offsets, held integration, nested models, validation, and persistence.
Generated-code timing is verified through the compiled C tests described in
[CODEGEN.md](CODEGEN.md).

Enabled bodies now support independent inner clocks in Octave simulation,
including skipped inactive hits and globally aligned phase on resume. Their
enclosing clock samples the enable control. Inherited controls additionally
sample at inner-clock hits. Triggered bodies retain inherited-only execution,
and C export supports the same enabled inner clocks. See
[CONDITIONAL.md](CONDITIONAL.md) and `test_ob_enabled_multirate`.

Hit comparisons allow floating-point coincidence within a bound
capped by one sixteenth of the shortest configured
period. This avoids merging whole hits merely because the absolute start time
is large. The Octave scheduler and both C emitters use the same comparison for
their supported schedules. Periods that cannot advance representable time are
rejected explicitly.
