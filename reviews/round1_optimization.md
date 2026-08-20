# Round 1 — Quantitative ranking and optimization review

Reviewer persona: **ranking/optimization engineer**  
Scope: `trusts.lua`, generated Trust profiles, curated behavior metadata, team construction, skillchain math, calibration, explainability, and evaluation.  
Verdict: the refactor has a promising architecture, but its scores are currently **heuristic labels rather than calibrated estimates**, and the greedy selector can return a materially inferior team. The output should be described as a suggestion until the objective, data coverage, and evaluation harness are strengthened.

## Executive assessment

The strongest design choice is the separation between action-derived capabilities, curated AI behavior, player fit, and team-addition synergy. This creates clean seams for improvement. Directed skillchain lookup is also a meaningful improvement over property intersection.

The largest validity problem is coverage: there are 112 generated Trust profiles but only 25 curated behavior records (22.3%). The remaining 87 Trusts receive the same `base = 50` fallback and almost no situation value. The optimizer therefore compares rich, manually favored records against an undifferentiated long tail. It is not yet a full-roster ranker in a statistical sense.

The largest algorithmic problem is sequential greedy construction under ordered role quotas. It makes irreversible early choices and never swaps a selected Trust when a later combination is better. This is particularly harmful because several modeled benefits are conditional or pairwise (healer dependencies, support scaling, and skillchains).

The largest skillchain problem is loss of action identity. All properties from all of a Trust's weapon skills are flattened into one set. The ranker can consequently score a theoretical pairing even when the relevant WS is rarely selected, level-gated, mutually exclusive with another WS, or inconsistent with the Trust's AI policy.

## What is good

1. **Explicit feature layers.** `collect_trust_builder_capabilities`, `score_builder_trust`, and `score_team_addition` separate extraction, individual utility, and team context (`trusts.lua:1122-1263`). This is substantially easier to test than one monolithic recommendation function.
2. **Direction is represented.** `directed_chain_result(opening, closing)` correctly rejects combinations absent from the directional table (`trusts.lua:1168-1182`). This is better than treating properties as unordered tags.
3. **AI reliability is acknowledged.** The `sc_policy` and `sc_reliability` fields recognize that availability is not execution (`trusts.lua:1211-1217`; `data/trust_behavior.lua`).
4. **Conditional and group value exists.** The model attempts healer dependencies and support scaling (`trusts.lua:1240-1261`). This correctly moves the unit of recommendation from isolated Trusts toward teams.
5. **Hard constraints are supported.** Maximum party size and requested role quotas are explicit (`trusts.lua:1280-1315`).
6. **Unknown elemental damage is filtered.** Physical WS properties are not automatically treated as elemental damage (`trusts.lua:1127-1137`).
7. **Deterministic tie-breaking.** Alphabetical tie-breaking makes repeated results stable (`trusts.lua:1287-1289`), useful for debugging.

## Findings and counterexamples

### P0 — Greedy selection does not optimize the team objective

`build_custom_team` chooses the best current addition and never backtracks (`trusts.lua:1281-1315`). Greedy selection is only guaranteed for narrow objective classes; this objective contains dependencies, role constraints, and pair synergies.

Counterexample: suppose damage dealer A has individual score 130 and no useful chain with the selected party. B and C each score 110 but form a reliable level-3 chain worth 30 per member under a Skillchain preset. Greedy selects A first. It may then select B, producing 240 plus weak synergy, while B+C produces 220+60. No later step can replace A.

The problem is amplified by quota order. Roles are processed in fixed UI order: Tank, Healer, Support, Melee, Ranged, Caster, Special (`trusts.lua:1006-1014`, `1304-1311`). If quotas exceed `max_trusts`, later requested roles are not merely deprioritized; they are impossible. The UI warns that only the "first" slots are filled (`trusts.lua:1755-1756`), but this is an implementation artifact, not an optimization policy.

Pros of current approach:

- Very fast and deterministic.
- Easy to understand mechanically.
- Marginal scoring allows some context sensitivity.

Cons:

- Order-dependent results.
- Cannot discover combinations whose components are mediocre alone.
- Cannot repair a poor early selection.
- Role order silently acts as priority.
- `team_score` is an insertion-time marginal score, not a comparable final Trust contribution.

Recommendation: use a bounded beam search over partial teams (for example width 64–128), enforce role constraints at completion, and evaluate a canonical whole-team objective. For small owned rosters, exact combination enumeration up to five Trusts is also feasible after role-aware candidate pruning. Always compare the final team, not the sequence of additions.

### P0 — Behavior coverage creates severe selection bias

`get_trust_behavior` returns an empty table when no curated record exists (`trusts.lua:1048-1051`). `score_builder_trust` then assigns `base = 50` (`trusts.lua:1185-1193`). Curated bases range roughly from 72 to 102 and also receive situation features. Thus missing metadata is treated as evidence of mediocrity, not uncertainty.

Measured local coverage:

- Generated Trust profiles: 112
- Curated behavior entries: 25 (22.3%)
- Uncurated profiles: 87 (77.7%)
- Total actions: 916
- Weapon skills: 385
- Fields explicitly marked `Question`: 43

This is a classic missing-not-at-random bias: famous/useful Trusts were curated first, so curation status is correlated with expected strength. The addon will reinforce the curator's initial beliefs.

Counterexample: an uncurated Trust with excellent real-world AI starts 48–52 points below Semih or Monberaux before situation features or synergy. A selected skillchain property (+32) may still leave it behind a curated Trust with no selected property.

Recommendation:

- Add `data_confidence` and `provenance` to every feature.
- Derive conservative priors by role/job/action data rather than a universal 50.
- Do not rank high-uncertainty Trusts as definitively worse. Show confidence or an “insufficient behavior data” badge.
- Reach broad behavior coverage before presenting the system as full-roster optimization.

### P0 — Skillchain feasibility is overstated

`collect_trust_builder_capabilities` flattens every WS property into `skillchains[property] = true` (`trusts.lua:1127-1146`). `chain_pair_score` then takes the best possible result across the Cartesian product of those sets (`trusts.lua:1172-1182`). This computes an optimistic upper bound, not expected chain value.

Lost information includes:

- Which properties belong to the same WS.
- Primary/secondary/tertiary property priority.
- WS selection priority and TP threshold.
- Level availability.
- Opener/closer timing and whether another Trust competes for the window.
- Range/position and target restrictions.
- Whether a Trust uses the relevant WS at all under the current condition.

The team score further uses `max(forward, backward)` and `max` reliability (`trusts.lua:1234-1237`). If one member is reliable and the other random, `max(reliability)` exaggerates the pair. A successful two-actor sequence is bounded by the weaker actor; a first approximation should use a product or directional initiator/closer probability.

Counterexample: Trust A has six WS and only one supplies Fragmentation, selected randomly. Trust B reliably closes Fusion into Light. The current set model gives the pair the same property feasibility as an A that exclusively uses the needed opener. With reliabilities 0.25 and 1.0, `max` treats the pair as 1.0 rather than approximately 0.25.

Recommendation: preserve a list of WS records per actor and score directed paths:

`P(opener WS used) × P(closer responds | opener) × chain level value × timing/TP readiness × target validity`.

For a player-selected WS, use exactly that WS's ordered properties. For Auto, weight usable WS by equipped weapon and a user-editable usage profile. For Trusts, encode WS policy and priority explicitly.

### P1 — Player fit is based on learned WS, not current combat intent

`collect_character_ws_fit` iterates the complete collected WS list in Auto mode (`trusts.lua:1060-1067`). Property frequency adds up to five points (`1084`), even though learning five WS with the same property does not make the player five times more likely to use it. If this list spans weapon categories, Auto can highlight a “best fit” unavailable to the equipped weapon.

The calculation also merges both directions while producing one best-fit indicator (`1075-1088`). A player who wants Trusts to close their chosen opener has different needs from a player who wants a Trust opener.

Recommendation: detect main/sub/ranged weapon skill type, filter WS to currently usable weapon families, and expose intent: `Trust opens`, `Trust closes`, or `Either`. Prefer an explicit primary WS over frequency of learned WS. Auto should be a defensible fallback, not an aggregation of the character's entire history.

### P1 — Feature scales are arbitrary and selection-count dependent

The score mixes values from incompatible informal scales:

- Curated base: 50 fallback versus 72–102 curated.
- Situation fields: numeric values roughly 8–48 multiplied by weights 0.2–1.0.
- Boolean situation feature: forcibly converted to 20 (`trusts.lua:1190-1192`).
- Each selected element: +28 (`1198-1201`).
- Each selected SC property: +32 (`1203-1206`).
- Skillchain pair: 12, 24, or 36 times reliability (`1178`).
- Avoid-AoE penalty: -65 (`1194-1195`).
- Healer dependency: +38 or -55 (`1240-1246`).
- Physical support: `physicalCount × physical_support × 10` (`1249-1257`).

There is no common interpretation for one point. Selecting more element or SC checkboxes mechanically increases the total opportunity for bonuses, and broad-action Trusts benefit more than reliable specialists. Situation weights cannot be meaningfully tuned because feature magnitudes differ.

Recommendation: normalize every feature to [0,1] with documented semantics, then assign preset weights that sum to 1 (or present a clear 0–100 utility). Treat selected criteria as a set whose total budget is divided among selections, not +28/+32 for each checkbox. Separate hard requirements from preferences.

### P1 — Pairwise synergy double-counts possibility and rewards redundant closers

Every selected pair can add its best chain value (`trusts.lua:1227-1238`). A five-Trust team has ten pairs, so pairwise SC bonuses can dominate individual utility. Yet combat cannot necessarily realize all ten best pairings, and multiple autonomous closers may compete for the same opening.

This creates superlinear “property breadth” rewards: a Trust with many properties pairs with almost everybody. It also fails to penalize closure collision, despite that being a known practical failure mode.

Recommendation: score a small number of executable chain plans rather than all pairs. Select a primary path and perhaps one fallback. Add collision penalties when multiple `closer` policies target the same likely opener and timing window. Discount redundant coverage with diminishing returns.

### P1 — Roles are categorical when Trusts are multi-role

`normalize_builder_role` reduces each Trust to one role (`trusts.lua:1016-1025`). A Valaineral-like tank with healing and AoE utility can only satisfy Tank; a hybrid cannot partially cover Support or Healer. Conversely, the `healer` behavior flag and profile role can disagree, causing constraint and synergy logic to use different concepts.

Recommendation: model role capability as a vector (tank 1.0, healing 0.25, support 0.35, damage 0.4) and make quotas coverage thresholds. Keep a primary display role, but optimize using continuous coverage.

### P1 — Explainability is descriptive, not causal

`behavior_summary` lists flags (`trusts.lua:1692-1704`) and the UI states broad inputs (`1715`). It does not show why the chosen Trust beat the runner-up, how much each feature contributed, what uncertainty exists, or which SC path is expected. The stored `team_score` is the score at insertion time and depends on selection order.

Recommendation: return a score breakdown from every component and show:

- Individual utility by situation.
- Role coverage supplied.
- Exact directed WS path(s), direction, and estimated reliability.
- Synergy/dependency bonuses and redundancy penalties.
- Data confidence.
- Best excluded alternative and the reason it lost.

### P2 — “Best fit” only marks exact maxima

`best_set` marks values only when exactly equal to the maximum (`trusts.lua:1097-1110`). Near-equivalent paths receive no visual indication, while ties caused by coarse integer scoring all look equally optimal.

Recommendation: use tiers, e.g. Best (>=95% of max), Good (>=80%), Possible (>0), with directional tooltips.

### P2 — The objective ignores encounter and observed performance variables

Situation presets are broad labels. They do not incorporate enemy resistances, level/content, number of targets, incoming damage type, dangerous status effects, player job/role, party buffs already supplied by the player, Trust availability conditions, or actual combat outcomes. `main_job_name` is exported but not used in scoring (`trusts.lua:1351-1387`).

Recommendation: introduce an encounter context object and initially populate it from user choices. Later, learn from local combat logs without claiming universal causality.

## Prioritized redesign

### Phase 1 — Make the current result honest and testable

1. Define a single pure `evaluate_team(team, context)` function returning total plus a structured breakdown.
2. Add confidence/provenance and distinguish unknown from zero.
3. Preserve per-WS properties and encode primary order, use policy, TP behavior, availability, AoE, and conditional rules.
4. Filter player WS by equipped weapon and add opener/closer intent.
5. Normalize feature scales and cap category budgets.
6. Replace “full-roster score” language with confidence-aware wording until coverage improves.

### Phase 2 — Replace greedy construction

1. Generate role-feasible candidates using vector coverage.
2. Use beam search or exact enumeration with branch-and-bound for up to five slots.
3. Evaluate complete teams using the same order-independent objective.
4. Return the top 3–5 distinct teams, not one brittle winner.
5. Encourage diversity among alternatives (different tank/healer/SC plan), so results are useful rather than near-duplicates.

Suggested whole-team utility:

```text
U(team, context) =
    survival_coverage
  + damage_value
  + support_value_after_caps
  + executable_skillchain_plan_value
  + encounter_counter_value
  + dependency_value
  - role_gap_penalties
  - buff_redundancy
  - closer_collision_risk
  - AoE/positioning risk
  - uncertainty_penalty (optional, user-selectable)
```

All terms should be normalized and exposed in the explanation.

### Phase 3 — Calibrate and validate

Build a deterministic offline harness with fixture rosters, player WS, and contexts. Required tests:

1. **Known lineup regression:** Valaineral + Zeid II + Semih Lafihna + Qultada + Apururu should be near the top for general physical/leveling when five Trusts are allowed, with explicit credit for healer dependency, rolls, SC closing, and tanking.
2. **Permutation invariance:** reordering roles or candidates must not change the optimum.
3. **Dependency test:** Zeid II's value should rise when a capable healer is present, without requiring healer-first selection.
4. **SC direction test:** reversing opener/closer must change the result when the directed table says so.
5. **Random-versus-exclusive WS test:** an exclusive reliable closer must outrank a Trust that only theoretically has the property among many random WS.
6. **Collision test:** two competing closers must not receive the sum of two independently perfect paths.
7. **Missing-data test:** lack of metadata must appear as uncertainty rather than an automatic low rank.
8. **Quota feasibility test:** all requested role constraints are solved together; excess quotas require explicit priority input or are rejected.
9. **Scale invariance:** selecting more preferred properties must divide the preference budget rather than inflate all candidate totals.
10. **Golden score breakdowns:** every recommended team should have a stable, inspectable explanation.

For empirical evaluation, record per encounter (locally and opt-in): uptime, deaths, cures, status-removal latency, successful SC paths, interrupted chains, WS frequency, buffs, debuffs, and fight duration. Compare recommendations using matched contexts rather than raw aggregate damage. Avoid online self-training until enough samples exist; sparse personal logs will otherwise overfit.

## Proposed acceptance criteria

- At least 90% of summonable profiles have behavior data or an explicit role-derived prior with confidence.
- Team output is invariant to role display order and Trust input order.
- The solver can show at least one exact executable SC path for every SC bonus it awards.
- No score component depends on the number of selected checkboxes except through a normalized preference allocation.
- The UI explains the winner versus the closest excluded alternative.
- The known strong lineup appears as a top candidate in appropriate contexts without name-specific bonuses.
- Unit fixtures cover every dependency, direction, and penalty rule.

## Bottom line

Keep the layered capability/behavior/team architecture and directed lookup. Replace flattened possibility sets, uncalibrated additive constants, and ordered greedy selection. The next engineering milestone should not be more hand-tuned base scores; it should be a pure full-team evaluator, preserved per-WS behavior, confidence-aware priors, and a search/evaluation harness. Once those exist, curated knowledge and observed combat data can improve the model without turning it into an opaque list of favored names.
