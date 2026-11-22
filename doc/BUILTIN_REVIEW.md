# Expanded report: built-in and library recommendations

Reviewed against `03090f4` and installed GNU Octave 11.3.0 on 2026-11-16.
The supplied report was revised after the first audit. Its new sections 5–6
were checked separately; the earlier seven findings remain in
[PR2_AUDIT.md](PR2_AUDIT.md). Report examples are proposals, not trusted fixes.

## Core function replacements

| Recommendation | Evidence and action |
| --- | --- |
| Saturation via min/max | Already implemented. The claim that this path still used indexed clamp assignments is stale. Frozen-mode evaluation has a separate incoming-regime contract. |
| Switch via ifelse | Valid for matrix selection after the existing validation. Implemented; retained the scalar branch fast path. Extreme finite values, signed zero, full-double conversion, frozen modes, shapes and errors have focused coverage. |
| Dead Zone via eager max/min | Not shown to improve this path. Both subtraction arrays are evaluated; unused overflow may be clamped harmlessly, so overflow alone is not a proven wrong-value example. Retained selective arithmetic, including frozen modes. No invented bug claim or unmeasured speedup. |
| deconv and compan | Companion reuse is valid: `rot90(compan(den),2)` preserves the documented state order and is now used. Existing code did not perform polynomial long division, so deconv removes no such algorithm. Properness, normalization, direct term, initial-state ordering and uncancelled factors remain explicit. Installed `compan.m` is a script, disproving the blanket compiled-C++ claim. |
| SCC via dmperm | Implemented native decomposition with canonical component IDs/members; existing FIFO DAG ordering is retained. 1,320 comparisons against the previous implementation preserve all outputs and errors for four-/two-column edges, mixed block types, isolates, duplicates and cycles. Existing 9/9 BIST passed. `accumarray` indegrees were already present. |
| fsolve finite differences/Broyden | The option exists, but the proposed direct switch failed the existing `x=x^2`, initial guess .1 test: status 0 despite a tiny residual. Added library-managed updates with one bounded retry from the original guess using the original checked Jacobian. Both attempts must satisfy successful status, fresh residual and conditioning checks; no acceptance tolerance was relaxed. Existing algebraic regression passes. |
| lookup or interp1 everywhere | Large double tables already use lookup. The small-table cutoff is measured; unconditional dispatch is not an established improvement. Mixed numeric comparisons and endpoint/left-limit contracts require the existing fallback. interp1's extrapolation and extra interpolation modes are not drop-in endpoint holds or a complete scheduling/C-export feature. No change. |
| Vectorized numeric formatting | Implemented shared vectorized sprintf and regex suffixing. The simple array example emits `-0`, losing its floating sign on C conversion; scalar helpers must also retain floating division. Large `%.17g` values use exponent notation (e.g. 2^63 becomes `9.2233720368547758e+18`), so a separately rejected huge integer literal does not prove that exact snippet fails compilation. 4,123 finite doubles match previous formatting exactly and pass compiled bitwise round-trip checks, including subnormals and extreme values. |
| String-target shape cellfun | Incorrect for these cells, which contain dimension vectors. `prodofsize([2 3])` returns 2, not 6; its size is 1-by-2, not 2-by-3. All three proposed substitutions produce wrong metadata. Left correct calculations unchanged. |

## Libraries and solver backends

| Proposal | Verified status |
| --- | --- |
| Singular-mass ode15s / DASRT / DASPK | Legitimate DAE facilities, but not a drop-in rewrite of stage-local algebraic solving. Residual formulation, consistent initial conditions, index restrictions, clocks, resets, event modes and rollback need a separate acceptance milestone. The runtime already calls native ode45/ode15s. |
| Bundled SUNDIALS adaptive C target | IDA 7.5.0, KLU, development headers/import libraries and IDA initialization/rootfinding exports are present. CVODE and ARKODE are absent from this installation and its installed-component metadata. Therefore the claim that all named backends are already bundled is false. IDA remains a viable optional future target, not an implementation of ode45 or automatic completion of adaptive emission. |
| control package | control 4.2.1 is installed and requires loading. Smoke checks for tf, ss, minreal, c2d(zoh) and descriptor construction passed. Optional adapters are feasible; replacing the editable state-space diagram builder would change its state, dependency and codegen contracts. No automatic model cancellation or state-basis change was introduced. |
| Bundled OpenBLAS CBLAS | False for this binary: OpenBLAS 0.3.31 declares NO_CBLAS=1; its cblas.h and dgemm/dgemv CBLAS exports are absent. A separate GSL compatibility header exists, but does not add those exports to OpenBLAS. Fortran BLAS symbols exist. The report's CBLAS macro cannot link this DLL as stated. An optional BLAS target needs a verified ABI/dependency design. |
| Standard bsearch for intervals | Valid with an adapter, now implemented. Only rows-1 interval starts are searched, so `t[1]` cannot read beyond the final knot. Empty/singleton tables, endpoints and non-comparable queries are handled before searching; the matched pointer is converted to an upper-bound rank. Both generated variants pass the existing 222,775 independent oracle checks. This replaces the custom binary-search loop while retaining portable C99 and left limits. |

These proposals should guide future backend work, not be presented as already
delivered functionality. No packages or DLLs were installed to make the report's
availability claims appear true. See [COMPATIBILITY_GAPS.md](COMPATIBILITY_GAPS.md).

## Measured scope and verification

Focused results, not whole-application guarantees:

- Matrix Switch selection, 30 operations on 1000-by-1000 arrays: .351–.355 s
  for indexed assignment versus .180–.189 s for ifelse, three trials.
- 10,000-node cycle ordering: native dmperm median .08055 s versus .52312 s
  for the historical traversal, three trials.
- 10,000 integer tokens: safe shared formatting median .02888 s versus
  .24268 s, about 8.4 times faster. This does not establish the report's
  50–100-times claim or total codegen performance.

The final uninterrupted full gate passed with exit 0: 26 Octave suites,
25 graph/edge/snapshot BIST checks and 242 strict C99 cases. All 220 numerical
C models matched Octave with worst scaled error 0; seventeen API harnesses and
five isolated helpers passed. This includes 222,775 input-lookup checks and
4,123 formatter bitwise checks. Source hashes remained unchanged during the run.
Local evidence is in `.validation-artifacts/builtin-audit-20261116/`:
`full-gate.log`, `full-gate-result.json`, `source-hashes.json`, the initial
Broyden failure and successful fallback regression, plus the focused bsearch
check. The earlier run was superseded to include the final library adapter;
its log is retained separately. No success is claimed for that interrupted run.

## Primary references

- [Octave fsolve options](https://docs.octave.org/latest/Solvers.html): Broyden
  updates attempt to reduce Jacobian evaluations; convergence is not guaranteed.
- [Octave companion convention](https://docs.octave.org/latest/Finding-Roots.html).
- [Octave dmperm](https://docs.octave.org/latest/Mathematical-Considerations.html).
- [Octave ODE/DAE solvers](https://docs.octave.org/latest/Matlab_002dcompatible-solvers.html)
  and [DAE interfaces](https://docs.octave.org/latest/Differential_002dAlgebraic-Equations.html).
- [SUNDIALS IDA](https://sundials.readthedocs.io/en/latest/ida/Introduction_link.html).
- [Octave control package](https://gnu-octave.github.io/pkg-control/).
- [OpenBLAS manual](https://www.openmathlib.org/OpenBLAS/doc/user_manual/).
