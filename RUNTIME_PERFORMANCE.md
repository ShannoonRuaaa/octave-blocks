# Runtime metadata and measured performance

Runtime initialization now prepares immutable graph metadata after validation
and flattening. The cache contains input-source indices in port order, algebraic
loop membership, normalized conditional options, interface indices and flow/clock
classification. Evaluation reuses these descriptors instead of repeatedly
normalizing the same child configuration and searching the edge table.

The cache does not contain input values, state, guard values, candidate outputs
or dynamic signal shapes. Finite-value, derivative-shape, conditional output
shape and control checks still run. New initialization rebuilds metadata from
the validated graph. Reinitialize after model/parameter/settings changes;
mutating a runtime's implementation fields is not a public editing API.

Missing or unknown-version metadata uses the legacy validation/classification
path. Same-version cache contents are trusted implementation data, not a
general corruption-repair format. Compatible checkpoints preserve the cache as
ordinary structs/cells; no persistent/global process cache is used. The
metadata regression strips caches recursively, saves/loads the legacy context,
and compares complete future contexts after removing metadata from both sides.
Internal input-table isolation tests also retain finite/shape failure rollback.
See [RUNTIME.md](RUNTIME.md) for the public context contract.

## Measurements

Matched Windows/Octave 11.3 CLI measurements used one warm-up and the median of
three unprofiled runs for each model. All runs checked analytical outputs and
retained their integration-step/event counts. The final rerun measured:

| Model | Before cache integration | Final median | Final three runs |
| --- | ---: | ---: | --- |
| Sampled enabled, 101 outputs | 2.938 s | .903 s | .897, .924, .903 s |
| Continuous enabled with events, 101 outputs | 6.035 s | 2.221 s | 2.092, 2.221, 2.255 s |
| Primitive Switch event, two outputs | .318 s | .258 s | .231, .258, .281 s |

The outputs were 2, 2 and 1.25 respectively; accepted integration steps were
72, 102 and 2, with 0, 0 and 1 event records. Local system load and timing spread
matter. An earlier matched post-cache run measured 1.110, 2.850 and .344 s;
the small primitive case did not improve in that run. These are representative
local measurements, not a speed guarantee or an isolated attribution of every
gain to one code edit. Editor input/rendering has a separate benchmark in
[UI_PERFORMANCE.md](UI_PERFORMANCE.md).

Three profiled runs were used separately to identify costs, not as wall-time
speed measurements. In the sampled enabled model, execution-option normalization
calls fell from 4,986 to 252 and their self-time share from 17.4% to 2.0%.
For continuous enabled execution they fell from 9,015 to 342, with self-time
share changing from 15.9% to 1.2%. RHS evaluation counts stayed unchanged.

Retained reports:

- `<TEMP>/ob-runtime-cache-profile-e8977bdfa9c04b048f26df0a79590008.txt`
- `<TEMP>/ob-runtime-cache-final-97bb3c98046644db9041a9a94be18b64.txt`

The next measured candidates are guard-descriptor reconstruction/deep comparison
and remaining evaluator/graphics snapshot work. Any further caching must retain
guard layout-change detection, input/value validation, external graphics
invalidation and checkpoint compatibility. The numerical/C and Qt regression
gates remain required when changing those boundaries.
