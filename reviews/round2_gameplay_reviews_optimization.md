# Round 2 — Gameplay Review of the Optimization Proposal

Reviewer perspective: FFXI Trust gameplay-systems designer.  
Reviewed document: `round1_optimization.md`.

## Overall verdict

The optimization review is excellent at identifying why the current output is not a mathematical optimum: sparse metadata, greedy construction, flattened WS data, uncalibrated weights, and weak explanations. I accept its central diagnosis and most of its proposed architecture.

Its main weakness is that a more sophisticated optimizer does not automatically create a more truthful gameplay model. Several proposed quantities—role vectors, WS probabilities, expected damage, and empirical calibration—remain difficult to define in FFXI and can give false precision. The next version needs a fact model and explicit uncertainty before it needs a highly tuned numeric model.

Rating scale: 1 = reject, 2 = major revision, 3 = useful with caveats, 4 = accept, 5 = strongly accept.

## Proposal ratings

### 1. Replace greedy construction with bounded beam search or exact enumeration

**Rating: 5/5 — Strongly accept.**

Pros:

- Fixes fixed role-order bias and irreversible early choices.
- Allows healer dependencies, support amplification, and SC plans to be evaluated as properties of a completed party.
- Makes it possible to compare the user's five-member benchmark against genuine alternatives.
- Supports several distinct recommendations instead of one brittle result.

Cons and constraints:

- Candidate pruning by “top N per role” can discard the exact hybrids that become valuable only in combination.
- Exact enumeration grows quickly for large owned rosters; evaluation must be cached and run only when inputs change, not every render frame.
- A beam can still miss the optimum if the partial-team heuristic undervalues delayed synergy.

Gameplay correction: enforce hard necessities at completion, but do not make every role quota a hard categorical constraint. A solo tank player may need no tank Trust, and Valaineral can contribute tanking, cures, and AoE damage simultaneously. Search is necessary, but its objective and constraints must remain context-sensitive.

### 2. Create a pure, order-independent whole-team evaluator

**Rating: 5/5 — Strongly accept.**

Pros:

- Establishes one source of truth for ranking and explanation.
- Enables permutation-invariance tests and reliable comparison of alternatives.
- Corrects insertion-time `team_score`, which is not a final contribution score.
- Makes tradeoffs visible by category.

Cons and constraints:

- “Contribution per member” is not uniquely defined when value is joint. Qultada plus three physical attackers produces synergy that cannot be assigned causally to only one participant.
- A single total can conceal fatal coverage gaps. A party with enormous offense but no adequate sustain should not win by compensation.

Gameplay correction: return both hard/threshold checks and normalized soft scores. Report joint synergy at team level rather than pretending every point belongs to one Trust.

### 3. Add data confidence and provenance; treat unknown as uncertainty

**Rating: 5/5 — Strongly accept.**

Pros:

- Corrects the current curation-status bias.
- Separates documented behavior from judgment and tuning.
- Makes future wiki changes auditable.
- Prevents an unmapped Trust from being silently treated as mediocre.

Cons and constraints:

- A role-derived prior can itself fabricate confidence if a job label is mistaken for Trust AI behavior.
- Source quality varies: BG Wiki observations, official resource facts, and player testing should not have identical confidence.

Gameplay correction: confidence should attach to individual facts, not only the Trust record. “Uses Ground Strike” may be certain while “closes reliably” is observational. Unknown behavior should generate a range or warning, not necessarily an uncertainty penalty; penalizing uncertainty repeats the bias under a new name.

### 4. Preserve per-WS properties and model WS policy/probability

**Rating: 5/5 — Strongly accept, with a mechanical correction.**

Pros:

- Eliminates impossible “best property from every WS” combinations.
- Can distinguish Zeid II's narrow, deliberate behavior from a Trust with many opportunistic WS.
- Enables level gating, TP thresholds, AoE risk, and conditional action rules.

Cons and constraints:

- Reliable probability estimates will rarely be available from wiki text alone.
- Trust choices are conditional on TP, distance, target state, party TP, and AI rules; one global WS probability is misleading.
- Maintaining level-specific WS availability across all Trusts is a substantial research burden.

Incorrect/unclear assumption: the skillchain properties attached to one WS are not generally alternative properties randomly selected by the actor. The actor selects a WS; the game resolves its ordered skillchain properties against the existing chain. The probability belongs primarily to **which WS is used and when**, followed by deterministic/ordered compatibility rules, not to an arbitrary property choice.

Gameplay correction: encode `ws_choice_policy`, conditions, TP threshold, and ordered SC properties. Begin with qualitative reliability tiers when measured probabilities are unavailable.

### 5. Use multiplicative directional SC reliability rather than maximum reliability

**Rating: 4/5 — Accept with revision.**

Pros:

- Correctly rejects the current optimistic use of `max(reliabilityA, reliabilityB)`.
- Makes opener/closer direction and timing relevant.
- Supports collision and redundancy penalties.

Cons and constraints:

- A naive product assumes independent events. Trust closing behavior is conditional on observing an opener, so the terms are not independent.
- Trust-to-player, player-to-Trust, and Trust-to-Trust paths have very different controllability.
- TP readiness and the skillchain timing window can dominate nominal policy reliability.

Gameplay correction: use conditional factors: opener availability × closer response given the opener × TP/timing readiness × target continuity. Give user-controlled player paths a different controllability weight from autonomous Trust-to-Trust paths. Prefer qualitative Low/Medium/High until telemetry supports numeric estimates.

### 6. Filter player WS by equipped weapon and add opener/closer intent

**Rating: 5/5 — Strongly accept.**

Pros:

- Removes irrelevant learned WS from Auto mode.
- Makes BEST FIT correspond to the current combat plan.
- Separates “Trust opens” from “Trust closes,” which is critical for practical SC play.

Cons and constraints:

- Usability depends on more than weapon family: main/sub/ranged slot, level sync, skill, equipment-granted WS, quest unlocks, and sometimes current status.
- Players may weapon-swap, so equipped weapon is a strong default rather than an absolute truth.

Gameplay correction: allow 1–3 pinned player WS and treat equipped-weapon detection as Auto. Show why a WS was included or excluded.

### 7. Normalize all features and divide selection budgets

**Rating: 4/5 — Accept with revision.**

Pros:

- Stops checkbox count from inflating total utility.
- Makes preset weights interpretable.
- Reduces accidental domination by arbitrary constants.

Cons and constraints:

- Normalization does not make subjective features objective.
- Some gameplay requirements are thresholds, not weighted preferences: adequate tanking, sustain, or required dispel cannot always be averaged against damage.
- A 0–100 display can imply more precision than the evidence warrants.

Gameplay correction: use hard requirements/coverage thresholds first, capped category utilities second, and confidence labels alongside the score. Prefer score bands over decimal rankings when teams are effectively tied.

### 8. Replace exclusive roles with continuous role-capability vectors

**Rating: 4/5 — Accept concept, revise implementation.**

Pros:

- Properly recognizes hybrids such as Valaineral, Selh'teus, and Qultada.
- Avoids wasting slots to satisfy labels already covered by secondary capabilities.
- Better represents the actual question: what functions does the party cover?

Cons and constraints:

- Linear partial coverage can be nonsensical. Two “0.5 healers” may not equal one healer if neither responds reliably to emergencies.
- Capability depends on encounter intensity and player role.
- A single vector cannot represent trigger behavior, MP sustainability, or response latency.

Gameplay correction: use named capabilities with thresholds and conditional descriptors, e.g. emergency healing, sustained healing, AoE recovery, status removal, primary tank, backup enmity. Keep primary role labels only for navigation.

### 9. Score executable SC plans and penalize competing closers

**Rating: 5/5 — Strongly accept.**

Pros:

- Reflects what parties can execute rather than the sum of all theoretical pairs.
- Directly addresses the user's experience: fewer combos can outperform broad but chaotic coverage.
- Makes expected chain and burst elements explainable.

Cons and constraints:

- Collision risk varies with TP generation and player cadence.
- More than one closer can be valuable as fallback when one is out of range or lacks TP.
- Multi-step chains need stricter timing/readiness modeling than two-step chains.

Gameplay correction: choose one primary plan and one discounted fallback. Penalize simultaneous closer competition, but retain a smaller resilience bonus for a backup closer.

### 10. Return top 3–5 diverse alternatives with causal explanations

**Rating: 5/5 — Strongly accept.**

Pros:

- Better matches uncertainty and player preference than claiming one universal best team.
- Lets users choose between offense, safety, SC control, and low-AoE options.
- A runner-up comparison exposes why the model made its choice.

Cons and constraints:

- Near-duplicate results add noise unless diversity is enforced.
- Explanations can become overwhelming if every heuristic is shown.

Gameplay correction: provide three named alternatives—Balanced, Aggressive/SC, Safe/Counter—and one sentence of sacrifice for each. Put detailed score evidence behind an expandable section.

### 11. Add encounter context and later calibrate from combat logs

**Rating: 4/5 for explicit context; 3/5 for telemetry calibration.**

Pros:

- Player role, enemy count, damage resistance, statuses, and required utility are decisive.
- Local observations can reveal actual WS usage, successful closures, healing latency, and deaths.
- Matched-context evaluation is far better than raw DPS ranking.

Cons and constraints:

- Automatic detection cannot reliably infer encounter intent or future mechanics from the current target alone.
- Personal telemetry is strongly confounded by player gear, job, level sync, target, buffs, positioning, and player behavior.
- Rare emergency value is poorly learned from average fight statistics.
- Parser-style optimization can underrate prevention, safety, and controllability.

Gameplay correction: start with explicit user context and deterministic facts. Make telemetry opt-in, local, contextual, and explanatory. Use it to adjust qualitative reliability or flag mismatches, not to self-train universal Trust rankings.

### 12. Require 90% behavior coverage before full-roster claims

**Rating: 3/5 — Accept intent, reject rigid threshold.**

Pros:

- Establishes a measurable quality gate.
- Discourages pretending sparse curated data is comprehensive.

Cons and constraints:

- Ninety percent shallow coverage can be worse than well-sourced deep coverage of relevant Trusts.
- Many Trusts are niche or obsolete, while the competitive/useful subset matters more initially.
- “Role-derived prior” should not count as factual behavior coverage.

Gameplay correction: report coverage by field and confidence tier. Prioritize all commonly used and strategically distinct Trusts, then expand. Allow full-roster enumeration immediately, but label low-confidence candidates and avoid definitive ordering.

## Important omission in the optimization review

The document does not identify the current **element-domain mismatch**:

- Gold BEST FIT element indicators are derived from elements associated with the resulting skillchain (`trusts.lua:1080-1087`).
- Selected elemental preferences are scored against direct magical/hybrid Trust WS damage elements (`trusts.lua:1127-1138`, `1198-1201`).

This is a user-facing correctness defect, not merely a scoring refinement. Selecting a gold Fire indicator does not currently request Trusts that produce a Fire-burstable chain; it requests Trusts with Fire-elemental weapon-skill damage.

**Rating for fixing this omission: 5/5 and first priority.** Split the concepts into `Direct WS damage element` and `Desired skillchain/burst element`, and compute indicators within the same domain as their control.

## Other missing gameplay constraints

1. **Level and level sync:** Trust action availability and effectiveness change with level. A documented endgame WS should not drive a leveling recommendation before it exists.
2. **Player role redundancy:** the main job is read but unused. A tank, healer, or support player changes required coverage dramatically.
3. **Buff caps and overwrite behavior:** Haste sources, songs, rolls, Refresh, and debuffs do not stack as generic additive “support.”
4. **Qultada behavior:** roll selection and practical value depend on party composition and activity. `physical_support=2.0` is too coarse to represent roll choice, lucky/unlucky outcomes, or whether XP-oriented behavior is useful.
5. **Positioning and range:** ranged Trusts offer uptime and safety but may be outside AoE healing/buff range; melee Trusts can feed TP or suffer dangerous AoE.
6. **Enemy TP feed:** extra melee participants can materially increase enemy TP-move frequency in some contexts; “more physical attackers” is not always free value.
7. **AoE targeting discipline:** AoE risk is not a simple Trust-wide boolean. It can depend on WS policy, TP, target grouping, and level.
8. **Unity constraints and variants:** ownership detection helps, but variant identity and Unity availability must remain canonical so behavior data is not applied to the wrong version.
9. **Trust survivability scaling:** player level, item level, and content accuracy/evasion affect uptime and therefore all downstream utility.
10. **Magic-burst execution:** possessing magic and constructing the right SC element are insufficient; the caster must actually burst the window with an appropriate spell and have MP/readiness.

## Acceptance/rejection summary

### Accept

- Pure complete-team evaluator.
- Non-greedy bounded search.
- Confidence and per-fact provenance.
- Per-WS action identity and policy.
- Equipped-weapon-aware player fit plus explicit SC intent.
- Executable primary/fallback chain plans.
- Collision and redundancy penalties.
- Diverse alternative teams and causal explanations.
- Deterministic fixture harness and permutation-invariance tests.

### Accept with modification

- Multiplicative reliability: use conditional direction/readiness factors, not naive independence.
- Normalized scoring: preserve hard thresholds and uncertainty bands.
- Role vectors: use nonlinear functional coverage, not additive fractional roles alone.
- Telemetry: local, opt-in, contextual, and advisory only.
- Coverage target: measure depth and confidence, not a rigid 90% headline.
- Candidate pruning: preserve hybrids and unusual synergy candidates.

### Reject

- Any implication that algorithmic optimality can compensate for missing factual behavior.
- Any universal uncertainty penalty that automatically pushes unknown Trusts down.
- Treating role-derived priors as equivalent to researched behavior.
- Treating WS properties as probabilistic alternatives after a WS has already been selected.
- Treating the known five-Trust lineup as universally optimal independent of player role and encounter. It is a strong conditional benchmark, not a name-specific answer key.

## Proposed consensus priorities

1. **Correct semantic truth first:** split direct WS damage element from desired SC/burst element; align each visual indicator with the criterion it scores.
2. **Build one pure final-team evaluator:** include hard coverage checks, capped category scores, team-level synergy, risk, and confidence.
3. **Fix player intent:** equipped-weapon Auto, pinned WS choices, player role, and Trust-opens/Trust-closes/Either selection.
4. **Preserve executable action identity:** per-WS ordered properties, level, TP/AI policy, conditions, and qualitative reliability.
5. **Replace greedy selection:** bounded complete-team search with role/function feasibility, hybrid-safe pruning, and cached evaluation.
6. **Make missing data honest:** per-fact provenance/confidence and neutral role-informed ranges, never silent `base=50` punishment.
7. **Model one primary SC plan plus fallback:** conditional reliability, player controllability, burst follow-through, and closer-collision penalties.
8. **Return three distinct recommendations:** Balanced, Aggressive/SC, and Safe/Counter, each with sacrifices and confidence.
9. **Validate against context-aware fixtures:** include the user's Valaineral / Zeid II / Semih Lafihna / Qultada / Apururu party for an appropriate physical five-slot context, alongside cases where it should lose.
10. **Expand research before fine tuning:** prioritize strategically distinct/common Trusts, cite each behavior fact, and defer broad numeric calibration or telemetry learning until the fact model is stable.

## Round-2 consensus position

The optimization reviewer and gameplay reviewer agree on the central redesign: stop tuning additive name scores, preserve action behavior, evaluate complete teams, expose uncertainty, and test against real scenarios. Gameplay adds one immediate correctness fix—the element-domain mismatch—and cautions that role coverage, SC reliability, and telemetry are nonlinear and context-dependent. The credible path is therefore: semantic correction → factual schema → pure evaluator → bounded search → explanations and fixtures → cautious calibration.
