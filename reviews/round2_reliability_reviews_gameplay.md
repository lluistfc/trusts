# Round 2 — Reliability review of the gameplay proposal

Reviewer persona: skeptical senior Ashita/Lua reliability engineer.

Rating scale: **1 = reject**, **2 = major redesign required**, **3 = accept with safeguards**, **4 = strongly accept**, **5 = essential and implementation-ready**. Ratings judge not only gameplay value but whether the proposal can be implemented predictably with Ashita v4 data, bounded frame cost, graceful degradation, and deterministic tests.

## Executive response

The gameplay review correctly identifies the recommendation engine's semantic defects. I accept its central thesis: do not tune more name-specific numbers until the feature meanings, missing-data policy, and full-team objective are repaired. Its strongest proposals are splitting direct WS damage element from resulting SC/burst element, replacing greedy slot filling with cached whole-team evaluation, exposing uncertainty, and adding benchmark fixtures.

I do not accept every proposed fact as immediately observable. Equipped-weapon filtering, encounter detection, WS selection probabilities, and combat telemetry require explicit capability boundaries. They must be designed as optional adapters with manual fallbacks, not embedded assumptions inside the scorer. The pure evaluator must remain deterministic and must never touch Ashita memory, ImGui, files, or clocks.

## Review of critical proposals

### G1 — Split direct WS damage element from desired SC burst element

Rating: **5/5 — accept as essential**

Pros:

- Corrects a demonstrable contract violation: gold indicators and selected filters currently describe different domains.
- Produces types that can be validated: `damage_element` belongs to an action; `result_element` belongs to a directed SC result.
- Makes UI labels, scoring, and explanation fixtures straightforward.

Cons:

- Adds UI surface and requires migration of existing `team_builder.elements` settings.
- Existing generated records may ambiguously use `element` for affinity rather than damage, so conversion cannot be a blind rename.

Implementation/runtime risks:

- If both concepts continue to share loosely typed strings, the mismatch will return.
- A settings migration that maps old `elements` to one new field would silently guess user intent.

Reliability conditions:

1. Create separate schema fields and separate selected maps.
2. On migration, clear the old ambiguous selection and show a one-time explanation rather than guessing.
3. Add fixture tests proving a gold Fire burst indicator scores Fire-producing chains, while a Fire WS-damage selection scores only direct Fire/hybrid actions.

### G2 — Add confidence and role-neutral priors for missing behavior data

Rating: **4/5 — strongly accept, with a different scoring contract**

Pros:

- Avoids equating missing metadata with poor performance.
- Makes degraded recommendations visible instead of silently authoritative.
- Encourages provenance/schema work and prevents curated names from permanently monopolizing results.

Cons:

- A median role prior can overrate an unknown weak Trust.
- “Confidence” is itself subjective unless its derivation is standardized.

Implementation/runtime risks:

- Confidence multiplied directly into total score may systematically bury unknown Trusts again.
- Role medians computed from a sparse and biased curated sample are unstable.

Reliability conditions:

- Separate `estimated_value` from `confidence`; display an interval or warning instead of collapsing both into one opaque number.
- Use schema completeness plus per-field provenance to derive confidence deterministically.
- Unknown candidates should be returned in an “uncertain alternative” where appropriate, not falsely mixed into an exact ordinal ranking.
- Reject unversioned behavior records at validation time with a one-time diagnostic.

### G3 — Replace greedy role-order filling with bounded complete-team search

Rating: **5/5 — accept as essential, but never run it per frame**

Pros:

- Removes arbitrary role-order bias and permits symmetric synergy scoring.
- Makes the user's five-Trust benchmark feasible.
- Enables top alternatives and honest final-team category scores.

Cons:

- Naive combinations can grow quickly: choosing five from a large learned roster is not suitable for `d3d_present`.
- Candidate pruning can itself eliminate the globally best synergy team.

Implementation/runtime risks:

- Current `draw_team_builder` recomputes on every visible frame; dropping enumeration there would produce frame spikes.
- Unstable table iteration or floating comparisons can make results flicker across runs.
- A scorer with asymmetric “addition” bonuses cannot safely score an unordered completed team.

Reliability conditions:

1. Extract a pure symmetric `score_team(context, members)`.
2. Cache by a stable fingerprint of roster, WS/context, config, and data-schema version.
3. Compute only on invalidation, ideally in bounded chunks/tasks if profiling shows a hitch.
4. Use deterministic candidate ordering and explicit tie-breakers.
5. Begin with beam search or role-aware branch-and-bound; measure candidate counts and elapsed time.
6. Test against adversarial cases where pruning removes a low-individual/high-synergy member.

### G4 — Model per-WS AI policy and probabilistic chain execution

Rating: **3/5 — accept incrementally; reject invented precision**

Pros:

- Correctly separates capability from likely behavior.
- Product/multiplicative pair reliability is safer than the current maximum-of-either-member reliability.
- Can model competing closers and policy-incompatible directions.

Cons:

- FFXI Trust AI facts are incomplete, conditional, level-dependent, and difficult to calibrate.
- Numeric selection probabilities may look empirical when they are only editorial estimates.

Implementation/runtime risks:

- Schema explosion: action conditions become an ad hoc rules engine.
- Incorrect probabilities can create more confident-looking but less reliable recommendations.
- Exact timing depends on player cadence, latency, TP state, target behavior, and current level—many are not stable configuration inputs.

Reliability conditions:

- Phase 1 should use categorical policies (`never`, `free`, `prefers_open`, `prefers_close`, `holds_for_chain`, `exclusive_ws`) and confidence, not fake percentages.
- Add numeric telemetry-derived probabilities only when sample size and aggregation method are visible.
- Score only policy-compatible directions; use a conservative pair function such as the lower confidence/reliability, not `max`.
- Version and cite every curated behavioral fact.

## Review of high-priority proposals

### G5 — Filter player WS by equipped weapon and allow 1–3 pinned WS plus player SC policy

Rating: **4/5 — strongly accept manual pins; conditional accept for auto-detection**

Pros:

- Manual pinned WS and opener/closer preference provide a clear, testable input contract.
- Equipment filtering removes obviously unusable learned WS from Auto.

Cons:

- Determining usability is more than reading a weapon slot: skill type, off-hand/ranged interactions, level sync, quest unlocks, and resource mappings matter.
- Equipment may be changing during GearSwap-like actions; a transient snapshot should not churn the recommendation.

Implementation/runtime risks:

- Polling inventory/equipment every frame is unnecessary and may race zone/job transitions.
- Resource APIs can expose IDs but still require a maintained weapon-type-to-WS mapping.

Reliability conditions:

- Implement pinned WS first and make it authoritative.
- Put auto-detection behind a small `player_context` adapter with debounce and an explicit “detected” explanation.
- If detection is unavailable or ambiguous, fall back to `Auto (all learned)` with a visible low-specificity warning.
- Unit-test the pure mapping; integration-test job change, level sync, empty weapon slot, and ranged/off-hand cases in Ashita.

### G6 — Replace exclusive roles with multi-capability coverage thresholds

Rating: **4/5 — strongly accept**

Pros:

- Better represents hybrids and prevents redundant forced slots.
- Supports complete-team coverage scoring and clearer explanations.

Cons:

- Thresholds introduce another tuning layer.
- Fractional capability values can repeat the undocumented-scale problem.

Implementation/runtime risks:

- If capabilities are both eligibility constraints and additive bonuses, the same feature may be double-counted.
- A generic tank score cannot represent enmity, mitigation, recovery, and AoE control equally across contexts.

Reliability conditions:

- Use a documented normalized schema with separately named dimensions (`enmity`, `mitigation`, `single_heal`, `aoe_heal`, etc.).
- Derive display roles from capability bands; do not maintain a second role truth table.
- Validate all values in `[0,1]` and define thresholds per preset in one versioned file.
- Explain unmet/partial coverage to the user.

### G7 — Normalize heterogeneous numeric feature scales

Rating: **5/5 — accept as a prerequisite**

Pros:

- Prevents arbitrary constants from dominating unrelated categories.
- Enables sensitivity tests and understandable preset weights.
- Makes data schema validation mechanical.

Cons:

- Migrating current hand-tuned results will alter recommendations.
- A normalized scale does not itself make the estimates accurate.

Implementation/runtime risks:

- Silent clamping can hide invalid data; load should diagnose it.
- Floating-point scores can produce unstable near-ties unless tie policy is explicit.

Reliability conditions:

- Validate and reject/flag out-of-range facts; do not silently clamp curated source data.
- Keep raw facts/capabilities separate from preset weights.
- Round only for display, never during selection, and use deterministic secondary ordering.
- Add sensitivity fixtures showing small weight changes do not unexpectedly reorder unrelated teams.

### G8 — Add player role and encounter context; avoid claiming automatic detection

Rating: **4/5 — accept manual context; defer broad automatic detection**

Pros:

- Player role is essential to avoid recommending redundant tank/healer coverage.
- Explicit toggles make assumptions visible and reproducible.
- The gameplay reviewer correctly warns against overstating detection.

Cons:

- Too many toggles can overwhelm the interface.
- Job-derived defaults can be wrong for hybrid jobs or unconventional play.

Implementation/runtime risks:

- Enemy status/weakness/content detection is incomplete and can change per target; stale context would mislead.
- Reading target state every frame and rebuilding teams on every target change would be costly and noisy.

Reliability conditions:

- Start with a compact manual context and job-derived suggestion that the user can override.
- Label every value as `selected`, `detected`, or `unknown`.
- Do not recompute on target churn; require an explicit contextual refresh or debounce stable target/content state.
- Treat unavailable detection as unknown, never false.

### G9 — Expand party synergy and recompute final explanations

Rating: **4/5 — strongly accept final scoring; phase the synergy catalog**

Pros:

- Fixes misleading selection-time member scores.
- Category totals support debugging, user trust, and regression tests.
- Redundancy/overwrite/cap handling is vital for support-heavy teams.

Cons:

- Buff caps and overwrite rules add substantial domain complexity.
- Per-member attribution is ambiguous for pair/group synergies.

Implementation/runtime risks:

- Summing category explanations independently may not equal the final score if nonlinear constraints exist.
- Attribution can double-count one synergy on multiple members.

Reliability conditions:

- Return a structured score ledger from the exact scoring pass: stable rule ID, category, delta, members involved, confidence, explanation.
- The displayed total must equal the ledger sum within a tested tolerance.
- Attribute group synergy to the team, not arbitrarily to one member.
- Add rules incrementally with isolated fixtures and provenance.

## Review of the proposed architecture

### G10 — Canonical fact layer with stable ID, per-action conditions, provenance, and confidence

Rating: **5/5 — accept as foundational**

Pros:

- Stable resource/spell ID eliminates alias drift across profile and behavior tables.
- Per-field provenance lets maintainers distinguish facts from tuning.
- Versioning enables migrations and repeatable recommendations.

Cons:

- Retrofitting the generated ~198 KB data and supplements is substantial.
- Some Trust variants/Unity identities may not have one simple universal ID across sources.

Implementation/runtime risks:

- Loading a much richer table eagerly may increase startup allocation.
- A flexible condition representation can accidentally become executable data.

Reliability conditions:

- Keep data declarative; never execute expressions from scraped content.
- Validate offline during generation and minimally again at runtime.
- Emit generated indexes by stable ID/name so runtime does not repeatedly scan actions.
- Include schema version and generator/source metadata at file level.

### G11 — Context layer

Rating: **4/5 — accept with a strict typed boundary**

Pros:

- Makes recommendations reproducible: the result can state exactly which context generated it.
- Decouples Ashita state collection from scoring.

Cons:

- Context freshness and ownership need definition.
- Optional fields can cause combinatorial fallback behavior.

Implementation/runtime risks:

- Passing live memory objects into scoring would destroy purity and testability.
- Implicit defaults can change recommendation semantics across releases.

Reliability conditions:

- Context must be a plain immutable snapshot with explicit `unknown` values.
- Store schema/model version with exported recommendations.
- Centralize defaults and show them in explanations.

### G12 — Whole-team expected-value evaluator

Rating: **4/5 — accept the architecture, constrain claims**

Pros:

- Correct optimization unit and suitable home for redundancy/conflict penalties.
- Category decomposition supports top alternatives.

Cons:

- “Expected offense/survival” suggests numerical accuracy the available data cannot support.

Implementation/runtime risks:

- Estimated values may be mistaken for DPS/survival predictions.
- Nonlinear interaction rules can become hard to audit.

Reliability conditions:

- Call outputs comparative category ratings, not expected DPS/time-to-death unless measured.
- Keep every rule declarative or a small named pure function with fixtures.
- Expose model/data version and confidence.

### G13 — Return balanced, offense/SC, and safe alternatives

Rating: **4/5 — accept after whole-team scoring**

Pros:

- Avoids false precision of a single winner.
- Helps users select tradeoffs without changing many controls.

Cons:

- Three labels may still produce near-identical teams.
- More computation and UI content.

Implementation/runtime risks:

- If alternatives are merely different presets, they may violate the user's hard constraints.
- Diversity selection can lower quality too far.

Reliability conditions:

- Preserve hard constraints for every alternative.
- Apply an explicit, tested diversity rule and show sacrifice/category differences.
- Generate all alternatives from the same cached search result where possible.

### G14 — Optional combat-log telemetry for calibration

Rating: **2/5 now, 3/5 as a future opt-in module — defer**

Pros:

- Real observations could calibrate SC execution and expose incorrect hand-authored reliability.
- Per-user performance can reflect latency, cadence, and content better than wiki facts.

Cons:

- Combat logs are censored/confounded by target, buffs, gear, level, player behavior, and sample size.
- Storage, migration, reset, privacy expectations, and parser correctness become new product responsibilities.

Implementation/runtime risks:

- Packet/message parsing is version/localization-sensitive.
- Unbounded event history or per-action disk writes can harm performance.
- Learned rankings may create feedback loops: recommended Trusts are sampled more, so they appear more reliable.

Reliability conditions before acceptance:

- Separate opt-in module and bounded aggregate storage; no raw-log retention by default.
- Display sample counts and confidence; never replace factual AI rules automatically.
- Batch/debounce writes and version the telemetry schema.
- This must not block the semantic/scoring/test fixes.

## Review of benchmark scenarios

Rating: **5/5 — accept, with one wording correction**

Pros:

- The seven scenarios exercise semantic, player-role, unknown-data, AoE, healing, and SC/burst behavior.
- They turn user observation into regression protection.

Cons:

- Hard-coding one team as universally best risks overfitting.

Reliability correction:

- The Valaineral/Zeid II/Semih/Qultada/Apururu fixture should assert that the model identifies all documented synergies and places the team in a defined top tier under a fully specified context. It should not assert rank 1 without controlling player job, equipped/pinned WS, level, learned roster, and encounter assumptions.
- Each fixture must include complete input snapshots and expected score-ledger rule IDs, not only final names.

## Accepted points

- Accept the diagnosis of semantic mismatch, sparse-data bias, greedy search failure, theoretical-versus-behavioral SC confusion, exclusive-role weakness, heterogeneous scales, missing player/encounter context, and misleading incremental member scores.
- Accept the four-layer direction: facts, context, pure whole-team evaluation, and multiple alternatives.
- Accept provenance, confidence, stable IDs, and benchmark scenarios as first-class requirements.
- Accept the warning not to tune more base numbers before repairing the model contract.

## Rejected or deferred points

- Reject precise WS selection probabilities until supported by cited facts or sufficiently sampled opt-in telemetry. Begin with categorical policies and conservative confidence.
- Reject broad automatic encounter detection in the initial refactor. Start with manual explicit context and narrow, clearly labeled detected hints.
- Reject running combination search or context polling from ImGui render code.
- Reject calling comparative category scores “expected offense/survival” if they are not calibrated measurements.
- Defer telemetry until the pure scorer, schema validation, lifecycle, caching, and tests are stable.

## Proposed consensus priorities

1. **Define and validate a versioned canonical schema** keyed by stable Trust identity. Separate facts, editorial capability estimates, confidence, provenance, and preset weights.
2. **Correct the UI/model semantics** by splitting direct WS damage element from desired SC result/burst element; migrate ambiguous old settings by clearing them with notice.
3. **Extract a pure scorer and structured score ledger**, with no Ashita/UI/file dependencies. Normalize capability scales and use conservative categorical AI policy initially.
4. **Add deterministic fixtures before changing selection**, including the fully specified known-good lineup, pinned-WS direction, AoE avoidance, WHM player, status-heavy healing, missing data, semantic separation, and dependency degradation.
5. **Implement cached bounded whole-team search** with deterministic tie-breaking, hard constraints, pruning metrics, and recomputation only on explicit input invalidation.
6. **Replace exclusive roles with multi-capability coverage**, while keeping role labels only for display and using one canonical source of truth.
7. **Implement manual pinned WS/player policy and player-role/context inputs first.** Add equipped-weapon detection later through a debounced adapter with visible fallback/unknown state.
8. **Show multiple constrained alternatives and exact category/ledger explanations**, including uncertainty and data-degradation notices.
9. **Expand cited behavior coverage incrementally**, prioritizing competitive Trusts and categorical policy facts rather than fabricated probabilities.
10. **Only after the recommendation core is reliable**, consider optional bounded telemetry and narrow automatic encounter hints.

## Final reliability verdict

The gameplay proposal is strong and should drive the consensus, provided implementation proceeds as a testable model refactor rather than another expansion of `trusts.lua`. The decisive reliability requirement is separation: Ashita adapters collect snapshots, a validated canonical dataset supplies facts, a pure cached engine scores complete teams, and ImGui only renders results and records user choices. Without that separation, the proposed richer model will magnify the addon's current lifecycle, frame-time, and maintainability risks.
