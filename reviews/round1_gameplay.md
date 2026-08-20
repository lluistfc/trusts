# Round 1 — Gameplay Systems Review

Perspective: FFXI Trust party-composition and combat-systems designer.

Scope: `trusts.lua`, `data/trust_behavior.lua`, and `data/trust_profile_supplements.lua`. This review evaluates recommendation quality, not UI implementation or Lua runtime safety.

## Executive assessment

The refactor is directionally good: it considers the complete learned roster, separates situation presets, models directed skillchain combinations, exposes a preferred player WS, and adds party-level bonuses. It can now explain why Valaineral, Zeid II, Semih Lafihna, Qultada, and Apururu work well together.

However, its recommendations are not yet trustworthy enough to be called “best teams.” The largest problem is not tuning; it is model semantics. Several values presented as gameplay facts are hand-authored scores without provenance, coverage is sparse, and the team builder optimizes one slot at a time. It therefore rewards the best theoretical property set, not the most likely behavior in combat.

The observed five-Trust party should be retained as a benchmark fixture. Any General Physical or Leveling evaluation that ranks a materially weaker party above it should be treated as a model regression unless the player role or encounter constraints justify the difference.

## What the current model does well

1. **It no longer restricts recommendations to a tiny name list.** `build_custom_team` constructs candidates from every learned Trust (`trusts.lua:1266-1276`). This is a major improvement over name-based selection.
2. **Skillchains are evaluated directionally.** `DIRECTED_SKILLCHAINS` is queried as opener then closer (`trusts.lua:1168-1182`), and player-to-Trust versus Trust-to-player paths are separated (`trusts.lua:1209-1217`). This is substantially better than set intersection.
3. **Known behavior is represented explicitly.** The curated entries distinguish opener/closer policy, reliability, healer dependencies, ranged behavior, AoE risk, status removal, and support (`trust_behavior.lua:4-31`). Those are the right categories to model.
4. **Some party interactions are rewarded.** Zeid II's healer dependency and physical-support scaling are recognized (`trusts.lua:1221-1263`). This is exactly the sort of whole-party logic the addon needs.
5. **Situation presets are understandable.** The eight presets cover common solo contexts and translate cleanly to weighted features (`trusts.lua:1028-1041`).
6. **The player can select a preferred WS.** This provides a useful escape hatch from the noisy “all learned WS” default (`trusts.lua:1054-1119`, UI at `trusts.lua:1726-1782`).

## Critical findings

### P0 — “Best WS element” and the selectable element filter describe different things

`collect_character_ws_fit` derives `elementScores` from the **elements of the resulting skillchain** (`trusts.lua:1080-1087`). Those scores drive the gold BEST FIT indicators (`trusts.lua:1114-1118`, `1775`). In contrast, `collect_trust_builder_capabilities` records elements only for a Trust WS that deals magical/hybrid/explicit elemental damage (`trusts.lua:1122-1148`), and `score_builder_trust` rewards selected elements against that damage-element set (`trusts.lua:1198-1201`).

Thus a gold “Fire” indicator means “the player's WS can participate in a skillchain whose resulting element includes Fire,” but selecting Fire means “choose Trusts possessing a Fire magical/hybrid WS.” The UI implies one coherent feature while scoring two unrelated features.

**Gameplay impact:** the player can follow the visual recommendation and make the team score worse for their actual goal. Physical Trusts such as Zeid II and Semih may be excluded even when they are excellent at creating a Fire-aligned Light/Fusion chain.

**Recommendation:** split this into two controls:

- `WS damage element` — direct magical/hybrid WS damage element.
- `Desired SC burst element` — resulting skillchain element, evaluated through directed opener/closer paths.

Gold indicators must be calculated using the same domain that the selected control scores.

Pros: eliminates misleading advice; makes Magic Burst composition meaningful.  
Cons: adds one more UI concept and requires clear tooltips.

### P0 — Sparse behavior data creates a large name-based prior

Only a small curated subset has behavior metadata (`trust_behavior.lua:4-31`). Every unmapped Trust receives an empty behavior and a base score of 50 (`trusts.lua:1048-1052`, `1185-1188`), while curated entries commonly start around 80–102 before situational bonuses. This makes the system “full roster” in enumeration but not in competitive evaluation.

The old `TRUST_ROLE_PRIORITY` table also remains authoritative for nine names (`trusts.lua:129-138`, `613-625`), so role quality is still partly maintained in a second hand-authored name table.

**Gameplay impact:** an undocumented but excellent Trust often cannot beat a documented average Trust. Recommendations will converge on the same curated names across situations, creating false confidence.

**Recommendation:** add explicit `data_confidence` and refuse to interpret missing data as poor performance. Until coverage is broad, use role-relative neutral priors (for example the median known score for the role), apply a confidence band, and label results “insufficient behavior data.” Merge role and behavior metadata into one canonical profile.

Pros: fairer roster comparison; transparent uncertainty.  
Cons: neutral priors can temporarily overrate weak unknown Trusts.

### P0 — Greedy slot filling cannot find the best party

The algorithm fills requested roles in fixed UI order—tank, healer, support, melee, ranged, caster, special—then fills remaining slots greedily (`trusts.lua:1007-1015`, `1281-1316`). Each selection is permanent. It never revisits an earlier choice after later synergies become known.

With default maximum 3 and default quotas of one tank, healer, and support, damage dealers and SC specialists cannot appear at all. When quotas exceed the maximum, earlier roles always win. This is a hidden policy decision, not optimization.

**Gameplay impact:** it misses combinations whose value is collective. A slightly lower individual healer might enable a much stronger support/DD pair; a closer chosen early may conflict with a better closer selected later. The user's proven five-member lineup is impossible under the default max of 3.

**Recommendation:** enumerate feasible teams from a pruned candidate pool and score the complete set. With at most five Trusts, retaining the top 5–8 candidates per role makes bounded combination search practical. Treat role counts as constraints, not an ordering. Return the top three distinct teams, not only one.

Pros: real team optimization; exposes meaningful alternatives.  
Cons: needs caching and candidate pruning to avoid frame-time spikes.

### P0 — Skillchain possibility is being scored as skillchain reliability

Each Trust's complete set of WS properties is collapsed into a set (`trusts.lua:1122-1155`). `chain_pair_score` takes the single best theoretical pair (`trusts.lua:1172-1182`). Team scoring then chooses either direction and uses the **maximum** reliability of the two Trusts (`trusts.lua:1233-1238`).

This loses the facts that determine whether the chain actually happens:

- WS selection priority and conditions.
- TP hold threshold.
- opener versus closer behavior.
- range and engagement behavior.
- level-scaled WS availability.
- competing closers firing on the same window.
- whether a Trust uses only one WS or chooses among many.
- player cadence and intended opener/closer role.

Using `max(reliabilityA, reliabilityB)` overstates a pair: a reliable closer paired with a random opener is not a fully reliable pair. Taking `max(forward, backward)` also rewards a direction neither AI policy is likely to execute.

**Recommendation:** model each WS as an action with `priority`, `min_level`, `tp_policy`, `sc_properties`, `usage_conditions`, and estimated selection probability. Score only policy-compatible directions. Pair reliability should resemble `opener_probability * closer_probability * timing_factor`, not max reliability. Penalize multiple autonomous closers competing for the same player opener.

Pros: recommendations align with observed combat.  
Cons: behavior data is expensive to research and will need versioned provenance.

## High-priority findings

### P1 — Learned WS is not the player's current usable WS set

`collect_weapon_skills` includes every learned WS (`trusts.lua:961-986`). Auto mode treats them all as current options (`trusts.lua:1054-1068`). It does not inspect the equipped weapon, weapon type, current level sync, or the player's intended WS rotation.

**Impact:** BEST FIT can be driven by a weapon the player is not using. Property frequency (`propertyCounts`) mildly favors properties repeated across the account-wide learned set, which has no combat meaning.

**Improve:** detect main/sub/ranged weapon skills available for current equipment and level. Default Auto to main-hand-valid WS only. Let the user pin 1–3 preferred WS and specify whether the player opens, closes, or either.

### P1 — Roles are exclusive, but Trust functions are not

Each Trust receives one normalized role (`trusts.lua:1016-1027`, `1150-1155`). Valaineral is a tank with AoE damage and cures; Selh'teus is special/support/healing; Qultada is support plus ranged DD. Single-role quotas fail to credit these hybrids as coverage.

**Impact:** teams can be forced to spend a slot on redundant formal coverage even when a hybrid already provides enough practical coverage.

**Improve:** replace `role` with scored capabilities such as `tank=0.9`, `healing=0.3`, `physical_support=0.8`, `ranged_damage=0.4`. Define minimum party coverage thresholds rather than exact category counts. Keep familiar role labels for display only.

### P1 — Numeric feature scales are undocumented and heterogeneous

The same record mixes `base` near 100, situational values near 10–48, booleans converted to 20, reliability from 0–1, and `physical_support=2.0` (`trusts.lua:1185-1205`; `trust_behavior.lua:4-31`). There is no schema or calibration source.

**Impact:** a small tuning change can dominate unrelated mechanics. For example, a matching selected SC property adds 32, comparable to major healer survival differentiation, regardless of whether that WS is ever used.

**Improve:** define a documented 0–1 capability schema and keep user-facing weights separate. Add tests that assert expected ordering for benchmark scenarios.

### P1 — Situation presets omit decisive player and encounter context

The model reads the player's job name but does not use it for scoring (`trusts.lua:1351-1388`). It does not know whether the player is tanking, healing, meleeing, nuking, or cleaving. Enemy target data is not considered: level, resistances, damage weaknesses, dispel needs, status effects, dangerous AoE, or content mechanics.

**Impact:** “Boss Survival” and “Status Heavy” are manual labels with static weights, not detection. A healer recommendation may be redundant for a WHM player; a tank may be unnecessary for a tank player; Qultada's value changes with physical party composition and activity goals.

**Improve:** add a Player Role selector with job-derived default, plus encounter toggles: need tank, need dispel, silence/paralyze risk, enemy count, AoE forbidden, physical/magic resistance, and XP/CP content. Do not claim automatic situation detection until target/content signals exist.

### P1 — Party synergy bonuses are too narrow and sometimes asymmetric

Current synergy covers healer dependency, physical support, Haste, and any theoretical Trust-to-Trust chain (`trusts.lua:1221-1263`). It misses roll/song/spell overwrite rules, haste caps, Refresh demand, ranged positioning, debuff duplication, magic-burst follow-through, tank-healer compatibility, AoE healing demand, and MP sustain.

The incremental `team_score` shown for a member is also selection-time marginal value (`trusts.lua:1294-1298`, displayed at `1800-1803`), not that member's contribution in the final team. Earlier members never receive later synergy in the displayed number.

**Improve:** compute a final team score and explain contributions after the complete team is built. Break explanation into role coverage, offense, survival, SC likelihood, burst follow-up, and penalties.

## Data-quality review

### Strengths

- Supplemental Apururu and Yoran-Oran profiles prevent total omission (`trust_profile_supplements.lua:1-45`).
- Action profiles preserve spell, ability, WS, damage-type, and SC-property detail.
- Runtime name normalization and aliases handle common resource/wiki name differences (`trusts.lua:185-227`).

### Weaknesses and risks

- Curated behavior claims have no per-field source URL, retrieval date, evidence note, or confidence rating (`trust_behavior.lua:1-32`). Future maintainers cannot distinguish verified AI behavior from subjective tuning.
- Supplement actions use aggregated pseudo-actions such as “Cure I - VI” and “-na Spells.” These are useful for display but cannot support level-specific availability or precise scoring (`trust_profile_supplements.lua:9-20`, `29-39`).
- Behavior and profile identity can drift across aliases. The alias table maps action profiles, while behavior relies on separate normalized names (`trusts.lua:199-227`, `1044-1052`). One canonical Trust ID should join all data.
- `load_skillchains_data` silently returns nil on missing/broken Skillchains data (`trusts.lua:229-248`). Recommendations then degrade without warning.
- The generated action data describes what a Trust can do, not what its AI will choose. Capability must not be used as behavior probability without an explicit confidence penalty.

## Proposed gameplay model

### 1. Canonical fact layer

For each Trust, store:

- stable spell/resource ID and aliases;
- jobs, role capabilities, positioning;
- per-action level requirement and conditions;
- WS selection order/probability and TP policy;
- opener/closer behavior and timing reliability;
- buffs/debuffs with overwrite group and target logic;
- healing triggers, status-removal priority, MP recovery;
- AoE footprint and risk;
- dependencies and exclusions;
- source URL, retrieval date, and confidence per fact.

### 2. Context layer

Inputs should include:

- maximum Trusts;
- player role and equipped weapon;
- preferred WS set and player SC policy;
- content intent (leveling, farming, boss, survival, burst);
- enemy count and AoE tolerance;
- healing/status/dispel requirements;
- desired damage type, SC result, and burst element.

### 3. Whole-team evaluator

Score completed teams using:

`coverage + expected offense + expected survival + SC execution + burst follow-up + support amplification - redundancy - behavioral conflicts - encounter risks`

Use expected values and confidence, not only additive name scores. Surface separate category scores so users can see why a team wins.

### 4. Recommendations as alternatives

Return at least:

- Best balanced team.
- Best offense/SC team.
- Best safe team.

Also state what each team sacrifices. A single ordinal list falsely suggests precision the underlying data does not have.

## Benchmark scenarios and acceptance criteria

1. **General physical player, five Trust slots:** Valaineral / Zeid II / Semih Lafihna / Qultada / Apururu should be a top-tier result, with explicit credit for physical-roll scaling, healer-enabled Zeid II, SC closers, ranged uptime, and sustain.
2. **Same scenario, Avoid AoE:** Semih and Valaineral should incur visible AoE-risk penalties; safe alternatives should rise.
3. **Player is WHM:** dedicated healer value should decrease unless the user explicitly requests one.
4. **Player uses a single pinned WS:** only directed chains involving that WS should count.
5. **Magic Burst:** the team must include both a plausible chain execution and a burster for the resulting element; owning a matching elemental WS alone must not qualify.
6. **Status-heavy/silence encounter:** medicine-based or silence-safe healing should gain value over spell-only healing.
7. **Unknown behavior data:** the UI must disclose low confidence rather than silently assigning a losing base score of 50.

## Prioritized implementation plan

1. Fix the element/skillchain semantic mismatch and rename controls.
2. Add equipped-weapon filtering and player opener/closer preference.
3. Replace greedy selection with bounded complete-team search.
4. Add confidence-aware role-neutral priors for missing behavior data.
5. Convert exclusive roles into multi-capability coverage.
6. Add WS-level AI policies for the most competitive 20–30 Trusts.
7. Add final-team category scoring and explanations.
8. Add benchmark fixtures, starting with the user's proven five-Trust party.
9. Expand factual coverage with cited, dated behavior data.
10. Later, add optional combat-log telemetry to calibrate reliability and performance without treating parser DPS as the only definition of value.

## Overall pros, cons, and risk rating

**Pros**

- Strong architectural direction compared with fixed-name recommendations.
- Correct recognition that AI policy and team synergy matter.
- Useful manual controls and understandable presets.
- Directed SC graph provides a good foundation.

**Cons**

- Sparse curated metadata dominates the complete roster.
- Greedy construction cannot optimize whole teams.
- UI conflates direct WS elements with resulting SC elements.
- Theoretical WS availability is mistaken for execution likelihood.
- Player and encounter context are mostly absent.

**Risk rating: High for recommendation accuracy, low for destructive impact.** The addon is safe as advisory tooling, but its wording should avoid “best” until semantic fixes, confidence reporting, and benchmark tests are in place.

## Round-1 position

Do not spend the next iteration tuning individual base numbers. First correct the feature meanings, selection algorithm, and missing-data policy. Once the model can represent the actual decision, factual behavior research and numeric calibration will produce durable improvements instead of increasingly precise-looking heuristics.
