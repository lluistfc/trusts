# Round 2 — Optimization review of the reliability proposal

Reviewer persona: **quantitative ranking/optimization engineer**  
Document reviewed: `round1_reliability.md`  
Rating scale: **1 = reject / little value, 3 = useful with revisions, 5 = accept as a priority**.

## Overall judgment

The reliability review is strong and unusually aligned with ranking validity. Its most important observation is not a Lua detail: scoring must be extracted into a pure, deterministic whole-team evaluator before further tuning. That is the correct foundation for calibration, counterexamples, and regression tests.

I accept nearly all findings. I would change the ordering in two ways:

1. Correct direct user-facing defects immediately, but treat them as a short stabilization pass rather than the centerpiece of the recommendation redesign.
2. Combine scorer extraction, complete-team evaluation, cache design, schema validation, and tests into one architectural milestone. Implementing caching around the current flattened, greedy model risks preserving invalid assumptions behind a faster interface.

## Proposal ratings

### R1 — Fix main-window close propagation

**Rating: 5/5 — Accept immediately.**

Pros:

- The evidence is direct and the fix is local.
- Removes a deterministic UI defect with negligible implementation risk.
- A small mocked-ImGui test can prevent recurrence.

Cons:

- No material effect on ranking validity.
- Persistence of visibility is a separate product choice and should not be bundled into the bug fix.

Scoring validity: neutral.  
Performance: neutral.  
Testability: positive; creates a clean, small regression fixture.

Decision: accept exactly as proposed. Copy the mutable close flag after `Begin` regardless of content visibility.

### R2 — Remove obsolete automatic summoning

**Rating: 5/5 — Accept immediately.**

Pros:

- Matches the user's explicit decision to summon manually.
- Removes unverified asynchronous state and a known-failing workflow.
- Reduces the state space that lifecycle tests must cover.

Cons:

- Existing command-line users, if any, lose compatibility.
- A future verified queue would need to be designed anew.

Scoring validity: neutral, though failed summoning can make a valid recommendation appear invalid in practice.  
Performance: mildly positive.  
Testability: strongly positive through state-space reduction.

Decision: accept. If command compatibility is a concern, commands should print that sequential summoning was removed and direct users to individual buttons; they must not call the broken queue.

### R3 — Move activation export/scoring out of `d3d_present`

**Rating: 5/5 — Accept, with one refinement.**

Pros:

- Prevents render-time I/O and duplicate recommendation builds.
- Separates lifecycle readiness from model evaluation and export.
- Makes recommendation timing observable and benchmarkable.

Cons:

- Ashita scheduling adds lifecycle complexity if introduced before a state model exists.
- An asynchronous implementation can create stale-snapshot races unless revisions are explicit.

Scoring validity: positive if snapshot versioning prevents stale results.  
Performance: strongly positive for frame-time tails.  
Testability: strongly positive after pure extraction.

Decision: accept. Refinement: represent inputs with a monotonically increasing `model_revision`; any scheduled calculation/export must carry that revision, and stale results must not overwrite a newer snapshot.

### R4 — Cache capabilities and Team Builder results

**Rating: 4/5 — Accept after scorer extraction.**

Pros:

- Static profile actions should not be rescanned every frame.
- A config-keyed cache enables repeatable performance tests.
- Separating capability compilation from team search is architecturally correct.

Cons:

- Premature caching can hide invalidation bugs.
- Caching current `team_score` would preserve an order-dependent insertion score that is not a valid team contribution.
- Equipment, roster, selected WS, and dependency data need explicit revision keys.

Scoring validity: neutral if implemented carefully; negative if stale.  
Performance: strongly positive.  
Testability: positive when cache keys are pure values.

Decision: accept with sequencing constraints. First define pure `compile_capabilities` and `evaluate_team`; then cache outputs by `(data_version, roster_revision, equipment_revision, config_revision)`. Verify cached and uncached outputs are identical.

### R5 — Validate dependencies and schemas; stop silent degradation

**Rating: 5/5 — Accept as a scoring prerequisite.**

Pros:

- Silent missing Skillchains data changes rankings without telling the user.
- Schema validation prevents malformed properties from quietly altering search results.
- Versioned data contracts make golden fixtures meaningful.

Cons:

- Strict validation can make the addon unavailable because of one nonessential bad record.
- Copying Skillchains data creates update/ownership concerns.

Scoring validity: critical positive.  
Performance: small one-time load cost.  
Testability: critical positive.

Decision: accept, but validate per record and distinguish fatal graph errors from recoverable profile errors. Quarantine invalid records, report counts, attach a degraded/confidence state to recommendations, and avoid pretending missing features are zero. A shared versioned data module/API is preferable to duplicated tables.

### R6 — Add versioned settings migration and reduce saves

**Rating: 5/5 — Accept.**

Pros:

- Invalid enums or stale preferred WS can create an empty player-fit vector and misleading ranking.
- Clamped, typed configuration makes the optimization domain well-defined.
- Versioned migration allows reproducible fixtures.

Cons:

- Resetting invalid preferences without an explanation can surprise users.
- Debounced saves require a small dirty-state lifecycle.

Scoring validity: strongly positive.  
Performance: positive through fewer writes.  
Testability: strongly positive.

Decision: accept. Preserve old/invalid values in a diagnostic field long enough to display a one-time migration notice. Role quotas exceeding capacity should be rejected or require explicit quota priorities; fixed role order is not a valid implicit policy.

### R7 — Make exports atomic and errors explicit

**Rating: 4/5 — Accept, but lower priority for ranking work.**

Pros:

- Prevents mixed-generation diagnostics, which otherwise invalidate offline comparisons.
- Makes export failures observable instead of falsely reporting success.
- Atomic snapshots are useful inputs for model evaluation.

Cons:

- Cross-file atomicity on Windows is nontrivial; a manifest/generation directory may be simpler than group rename.
- Does not improve the recommendation algorithm itself.

Scoring validity: indirectly positive for evaluation provenance.  
Performance: neutral to mildly negative only during explicit export.  
Testability: positive through fault injection.

Decision: accept. Add a manifest with model/data/config revision and write a complete generation before switching the manifest pointer. Do not retry permanent I/O errors on unrelated game packets.

### R8 — Introduce a lifecycle state machine with zoning tolerance

**Rating: 4/5 — Accept.**

Pros:

- Prevents repeated clearing/recomputation and stale snapshots.
- Gives cache invalidation a well-defined source.
- Makes equipment/job/roster changes explicit model events.

Cons:

- Incorrect packet assumptions can be worse than conservative polling.
- Too many states can overcomplicate a small addon.

Scoring validity: positive because inputs stay current.  
Performance: positive through reduced recomputation.  
Testability: strongly positive with event/state tables.

Decision: accept a minimal state machine. Use state plus debounced evidence rather than one packet as absolute truth. Model validity should be separate from UI visibility: `character_ready`, `data_ready`, and `model_revision` may be clearer than a large monolithic enum.

### R9 — Replace greedy role ordering with bounded complete-team search

**Rating: 5/5 — Highest optimization priority.**

Pros:

- Removes input/role-order bias.
- Correctly evaluates dependencies and pair/team interactions.
- Enables meaningful total scores and runner-up comparisons.

Cons:

- Naive enumeration scales poorly with roster size.
- A complete search over an invalid objective merely finds the wrong answer more accurately.
- Beam search is approximate and needs a quality bound or exact tests on small fixtures.

Scoring validity: critical positive after objective repair.  
Performance: controllable with pruning/beam search and cached capabilities.  
Testability: critical positive.

Decision: accept. Use a canonical, order-independent `evaluate_team`. For the owned roster, first apply safe feasibility pruning (availability and role constraints), not score-based pruning. Exact-search small fixtures to validate a beam implementation. Return several diverse top teams, not just one winner.

### R10 — Remove dead paths and split the monolith

**Rating: 5/5 — Accept as part of extraction.**

Pros:

- One canonical schema prevents old role priority and behavior data from disagreeing.
- Pure modules permit headless scoring tests.
- Dead `chain_mode`, automatic summon code, and obsolete score/note fields currently imply capabilities that are not real.

Cons:

- A large mechanical split risks regressions if performed without characterization tests.
- Excessive module granularity can obscure data flow.

Scoring validity: strongly positive through one source of truth.  
Performance: neutral to positive.  
Testability: critical positive.

Decision: accept incrementally. First add characterization tests around current normalization/data loading; then extract `data_adapter`, `skillchain_graph`, `capability_compiler`, and `team_optimizer`. UI/lifecycle splitting can follow.

### R11 — Add automated validation and regression fixtures

**Rating: 5/5 — Non-negotiable.**

Pros:

- Every proposed scorer change needs comparative evidence.
- The user's strong lineup supplies an excellent golden scenario.
- Schema, direction, settings, lifecycle, and I/O faults are deterministic test targets.

Cons:

- A single “expected winner” fixture can encode anecdotal bias.
- Golden total scores become brittle if they test implementation constants rather than rankings/invariants.

Scoring validity: critical positive.  
Performance: enables benchmarks and budgets.  
Testability: foundational.

Decision: accept with a broader methodology. The known lineup should rank near the top under a clearly specified context, but tests should also include adversarial scenarios where it should lose (Avoid AoE, specialized status pressure, magic-burst composition, or lower slot count). Assert invariants and score breakdowns, not only exact totals.

## Important points missing from the reliability review

The reliability paper correctly identifies greedy selection but largely accepts the current scoring primitives. Before whole-team search, four model errors must be fixed:

1. **Coverage bias:** only 25 of 112 generated profiles have curated behavior metadata. The 87 missing records receive a universal base 50 and almost no situational signal. Unknown is being scored as bad.
2. **Flattened WS possibility:** all properties across all Trust WS are merged into one set. The graph then rewards the best theoretical chain regardless of WS policy, priority, level, or frequency.
3. **Reliability aggregation:** pair synergy uses the maximum actor reliability. A two-actor sequence should be limited by both actors and direction; a product/conditional probability is a better starting approximation.
4. **Unnormalized features:** base, booleans converted to 20, per-checkbox +28/+32 bonuses, dependencies, and pairwise chain values have no common unit. Selecting more checkboxes inflates score opportunities.

These are not optional tuning details. A beam search should not be built until the evaluator preserves per-WS actions, distinguishes missingness, and returns normalized contributions.

## Review of the reliability proposal's priority order

I agree with priorities 1 and 2 as a rapid stabilization batch. I would merge and reorder the remaining work:

1. User-facing stabilization: close propagation, delete obsolete auto-summon, remove render-time export.
2. Characterization layer: schema/settings validation, data diagnostics, and tests around current behavior.
3. Pure model extraction: capability compiler, directed skillchain paths, context, and full-team evaluator with breakdown.
4. Model correction: per-WS policy, confidence-aware priors, normalized features, role vectors, redundancy/collision penalties.
5. Solver replacement: bounded exact/beam search, order invariance, multiple diverse outputs.
6. Revision-based caching and lifecycle invalidation.
7. Atomic diagnostic exports and module cleanup.

Caching is intentionally after the pure model shape is known; lifecycle design can be developed concurrently but should invalidate versioned inputs rather than directly trigger writes.

## Proposed consensus priorities

### Consensus P0 — Stabilize what users directly touch

- Fix ImGui close-state propagation.
- Remove automatic summoning commands/state and retain manual per-Trust summon buttons.
- Stop export and duplicate scoring from the render callback.

### Consensus P0 — Establish trustworthy model boundaries

- Extract a pure capability compiler and `evaluate_team(team, context)`.
- Validate/version settings and data at boundaries.
- Represent unknown feature values with confidence rather than zero/default inferiority.
- Return a decomposed explanation and model/data/config revisions with every result.

### Consensus P0 — Correct optimization semantics

- Preserve individual WS records, ordered properties, use policy, and directional opener/closer intent.
- Normalize category features and preference budgets.
- Replace `max` reliability and all-pairs optimistic SC bonuses with executable-path estimates and collision/redundancy handling.
- Replace ordered greedy selection with bounded whole-team search and enforce all quotas jointly.

### Consensus P1 — Prove behavior

- Add golden, adversarial, permutation-invariance, dependency, direction, missing-data, and settings fixtures.
- Verify beam results against exact enumeration on small rosters.
- Add a frame-time budget and ensure cached/uncached model results are identical.
- Show top alternatives and why they differ.

### Consensus P1 — Harden operation

- Add revision-based caches and lifecycle invalidation with zoning tolerance.
- Produce atomic, revisioned exports with actionable failure reporting.
- Split the monolith after characterization tests and remove obsolete sources of truth.

## Consensus conclusion

The reliability reviewer and optimization reviewer agree on the architectural center: **pure deterministic scoring, complete-team evaluation, explicit data contracts, and regression fixtures must precede further hand-tuning**. The immediate UI/summoning/render fixes are accepted. The only substantive qualification is that bounded search and caching must not fossilize the present evaluator: per-WS feasibility, uncertainty, normalized scales, and conditional reliability need correction first or in the same milestone.
